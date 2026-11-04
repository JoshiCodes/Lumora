import AppKit
import Combine

@MainActor
final class ScreenSaverManager: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var hostIsReady = false
    @Published private(set) var selection: Set<UUID>
    @Published var errorMessage: String?

    private let library: VideoLibrary
    private let preferences: Preferences
    private let fileManager = FileManager.default
    private var subscriptions = Set<AnyCancellable>()
    private static let selectionKey = "screenSaverClips"

    init(library: VideoLibrary, preferences: Preferences) {
        self.library = library
        self.preferences = preferences
        let stored = UserDefaults.standard.stringArray(forKey: Self.selectionKey) ?? []
        selection = Set(stored.compactMap(UUID.init(uuidString:)))
    }

    func start() {
        refreshStatus()
        if isInstalled, installedVersion != bundledVersion {
            try? install()
        }

        library.$clips
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] clips in
                guard let self else { return }
                let ids = Set(clips.map(\.id))
                if !selection.isSubset(of: ids) {
                    setSelection(selection.intersection(ids))
                }
            }
            .store(in: &subscriptions)

        preferences.$scaling
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshStatus()
                self?.sync()
            }
            .store(in: &subscriptions)

        sync()
    }

    // MARK: - Selection

    func contains(_ clip: Clip) -> Bool {
        selection.contains(clip.id)
    }

    func toggle(_ clip: Clip) {
        var updated = selection
        if updated.contains(clip.id) {
            updated.remove(clip.id)
        } else {
            updated.insert(clip.id)
        }
        setSelection(updated)
    }

    private func setSelection(_ ids: Set<UUID>) {
        selection = ids
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: Self.selectionKey)
        sync()
    }

    // MARK: - Installation

    private var installURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers/Lumora.saver", isDirectory: true)
    }

    private var bundledURL: URL? {
        Bundle.main.url(forResource: "Lumora", withExtension: "saver")
    }

    private var bundledVersion: String? {
        bundledURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String }
    }

    private var installedVersion: String? {
        Bundle(url: installURL)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    func install() throws {
        guard let bundledURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fileManager.createDirectory(at: installURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: installURL.path) {
            try fileManager.removeItem(at: installURL)
        }
        try fileManager.copyItem(at: bundledURL, to: installURL)
        run("/usr/bin/xattr", "-dr", "com.apple.quarantine", installURL.path)
        restartHost()
        refreshStatus()
        sync()
    }

    func uninstall() {
        try? fileManager.removeItem(at: installURL)
        restartHost()
        refreshStatus()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The host process caches loaded savers; it starts again on demand.
    private func restartHost() {
        run("/usr/bin/killall", "legacyScreenSaver")
    }

    private func run(_ tool: String, _ arguments: String...) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func refreshStatus() {
        isInstalled = fileManager.fileExists(atPath: installURL.path)
        hostIsReady = fileManager.fileExists(atPath: hostContainerURL.path)
    }

    // MARK: - Sync

    private var hostContainerURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(SaverManifest.hostBundleID)", isDirectory: true)
    }

    private var hostSupportURL: URL {
        hostContainerURL.appendingPathComponent("Data/Library/Application Support/\(SaverManifest.folderName)", isDirectory: true)
    }

    /// Mirrors the selected clips into the screen saver's sandbox. Hard links cost no extra disk space.
    func sync() {
        // The container only exists once macOS has run a third-party saver.
        // Creating it ourselves would leave it without the metadata macOS expects.
        guard isInstalled, hostIsReady else { return }

        let folder = hostSupportURL
        let wanted = library.clips.filter { selection.contains($0.id) }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

            let wantedNames = Set(wanted.map(\.fileName))
            for existing in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            where existing != SaverManifest.fileName && !wantedNames.contains(existing) {
                try? fileManager.removeItem(at: folder.appendingPathComponent(existing))
            }

            for clip in wanted {
                let target = folder.appendingPathComponent(clip.fileName)
                guard !fileManager.fileExists(atPath: target.path) else { continue }
                let source = library.videoURL(for: clip)
                do {
                    try fileManager.linkItem(at: source, to: target)
                } catch {
                    try fileManager.copyItem(at: source, to: target)
                }
            }

            let manifest = SaverManifest(clips: wanted.map(\.fileName), fillsScreen: preferences.scaling == .fill)
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: folder.appendingPathComponent(SaverManifest.fileName), options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't prepare the screen saver: \(error.localizedDescription)"
        }
    }
}
