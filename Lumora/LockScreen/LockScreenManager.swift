import AppKit
import Combine

/// Puts a library clip on the lock screen by swapping the video file of one of Apple's Aerial
/// wallpapers. macOS animates Aerials on the lock screen, and there is no public API for anything else.
///
/// The Aerial files belong to the system, so setting up asks for an administrator password once and
/// hands that single file to the current user. After that Lumora can refresh it without asking again.
@MainActor
final class LockScreenManager: ObservableObject {
    struct Aerial: Identifiable, Hashable {
        let id: String
        let name: String
        let url: URL
    }

    enum State: Equatable {
        case idle
        case working(String)
        case failed(String)
    }

    @Published private(set) var aerials: [Aerial] = []
    @Published var targetID: String? {
        didSet { UserDefaults.standard.set(targetID, forKey: Key.target) }
    }
    @Published private(set) var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Key.enabled) }
    }
    @Published private(set) var installedClipID: UUID? {
        didSet { UserDefaults.standard.set(installedClipID?.uuidString, forKey: Key.installedClip) }
    }
    @Published private(set) var needsSetupAgain = false
    @Published private(set) var state: State = .idle

    private enum Key {
        static let target = "lockScreenAerial"
        static let enabled = "lockScreenEnabled"
        static let installedClip = "lockScreenClip"
        static let installedFile = "lockScreenFile"
    }

    static let aerialsRoot = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer", isDirectory: true)

    private let library: VideoLibrary
    private let preferences: Preferences
    private let fileManager = FileManager.default
    private var subscriptions = Set<AnyCancellable>()
    private var updateTask: Task<Void, Never>?

    init(library: VideoLibrary, preferences: Preferences) {
        self.library = library
        self.preferences = preferences
        let defaults = UserDefaults.standard
        targetID = defaults.string(forKey: Key.target)
        isEnabled = defaults.bool(forKey: Key.enabled)
        installedClipID = defaults.string(forKey: Key.installedClip).flatMap(UUID.init(uuidString:))
    }

    func start() {
        refresh()

        library.$activeClipID
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.followWallpaper() }
            .store(in: &subscriptions)

        // Optimizing changes the file behind a clip.
        library.$clips
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.followWallpaper() }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    var target: Aerial? { aerials.first { $0.id == targetID } }
    var installedClip: Clip? { installedClipID.flatMap(library.clip(withID:)) }
    var isBusy: Bool { if case .working = state { true } else { false } }

    // MARK: - Discovery

    /// Lists the Aerials macOS has downloaded. Names come from Apple's catalog next to them.
    func refresh() {
        let root = Self.aerialsRoot
        var names: [String: String] = [:]
        if let data = try? Data(contentsOf: root.appendingPathComponent("entries.json")),
           let catalog = try? JSONDecoder().decode(Catalog.self, from: data) {
            for asset in catalog.assets {
                names[asset.id.uppercased()] = asset.accessibilityLabel
            }
        }

        var found: [Aerial] = []
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension.lowercased() == "mov" {
                let id = file.deletingPathExtension().lastPathComponent
                guard !found.contains(where: { $0.id == id }) else { continue }
                found.append(Aerial(id: id, name: names[id.uppercased()] ?? "Aerial \(id.prefix(8))", url: file))
            }
        }
        aerials = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        if targetID == nil || target == nil {
            targetID = aerials.first?.id
        }
        if isEnabled, let target {
            // macOS hands the file back to the system when it updates or re-downloads an Aerial.
            needsSetupAgain = !fileManager.isWritableFile(atPath: target.url.path)
        } else {
            needsSetupAgain = false
        }
    }

    // MARK: - Setup

    func setUp() {
        guard let target, let clip = library.activeClip, !isBusy else { return }

        let path = target.url.path
        if !fileManager.isWritableFile(atPath: path) {
            state = .working("Waiting for your password…")
            let user = NSUserName()
            let command = "chown \(Self.shellQuoted(user)) \(Self.shellQuoted(path)) && chmod 644 \(Self.shellQuoted(path))"
            guard runAsAdministrator(command) else {
                if isBusy { state = .idle }
                return
            }
        }

        do {
            try backUpOriginal(of: target)
        } catch {
            state = .failed("Couldn't back up the original Aerial: \(error.localizedDescription)")
            return
        }

        // A still desktop picture would replace the Aerial wallpaper and with it the animation.
        if preferences.matchDesktopPicture {
            preferences.matchDesktopPicture = false
        }
        isEnabled = true
        needsSetupAgain = false
        install(clip, into: target)
    }

    func restoreOriginal() {
        guard let target, !isBusy else { return }
        let backup = backupURL(for: target)
        isEnabled = false
        installedClipID = nil
        UserDefaults.standard.removeObject(forKey: Key.installedFile)

        guard fileManager.fileExists(atPath: backup.path) else {
            state = .idle
            return
        }
        state = .working("Restoring Apple's video…")
        updateTask = Task {
            do {
                try await Task.detached(priority: .utility) {
                    try Self.overwrite(target.url, with: backup)
                }.value
                try? fileManager.removeItem(at: backup)
                restartWallpaperAgent()
                state = .idle
            } catch {
                state = .failed("Couldn't restore the original: \(error.localizedDescription)")
            }
        }
    }

    func openWallpaperSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Installing

    private func followWallpaper() {
        guard isEnabled, !needsSetupAgain, let target, let clip = library.activeClip,
              clip.fileName != UserDefaults.standard.string(forKey: Key.installedFile)
        else { return }
        guard fileManager.isWritableFile(atPath: target.url.path) else {
            needsSetupAgain = true
            return
        }
        install(clip, into: target)
    }

    private func install(_ clip: Clip, into target: Aerial) {
        updateTask?.cancel()
        state = .working("Preparing “\(clip.name)” for the lock screen…")

        let source = library.videoURL(for: clip)
        let width = NSScreen.widestPixelWidth
        updateTask = Task {
            do {
                let prepared = try await Self.lockScreenFile(from: source, targetWidth: width)
                guard !Task.isCancelled else { return }
                state = .working("Updating the lock screen…")
                try await Task.detached(priority: .utility) {
                    try Self.overwrite(target.url, with: prepared.url)
                }.value
                if prepared.isTemporary { try? FileManager.default.removeItem(at: prepared.url) }

                installedClipID = clip.id
                UserDefaults.standard.set(clip.fileName, forKey: Key.installedFile)
                restartWallpaperAgent()
                state = .idle
            } catch is CancellationError {
                return
            } catch {
                state = .failed("Couldn't update the lock screen: \(error.localizedDescription)")
            }
        }
    }

    /// Aerials are HEVC QuickTime movies. Clips that already are one go in as they are,
    /// everything else is converted first.
    private nonisolated static func lockScreenFile(from source: URL, targetWidth: Int) async throws -> (url: URL, isTemporary: Bool) {
        guard let plan = await VideoLibrary.plan(for: source, targetWidth: targetWidth) else {
            throw ImportError.unsupported(source.lastPathComponent)
        }
        if plan.isHEVC, !plan.isWorthIt, source.pathExtension.lowercased() == "mov" {
            return (source, false)
        }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumora-lockscreen-\(UUID().uuidString).mov")
        try await VideoLibrary.encode(from: source, to: temporary, plan: plan)
        return (temporary, true)
    }

    // MARK: - Files

    private var backupFolder: URL {
        library.root.appendingPathComponent("Lock Screen Backup", isDirectory: true)
    }

    private func backupURL(for aerial: Aerial) -> URL {
        backupFolder.appendingPathComponent("\(aerial.id).mov")
    }

    private func backUpOriginal(of aerial: Aerial) throws {
        let backup = backupURL(for: aerial)
        guard !fileManager.fileExists(atPath: backup.path) else { return }
        try fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        try fileManager.copyItem(at: aerial.url, to: backup)
    }

    /// Writes into the existing file instead of replacing it. Lumora owns the file but not the
    /// folder, and keeping the same file also keeps whatever macOS knows about it.
    private nonisolated static func overwrite(_ target: URL, with source: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: target)
        defer {
            try? input.close()
            try? output.close()
        }
        try output.truncate(atOffset: 0)
        while let chunk = try input.read(upToCount: 8 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
    }

    // MARK: - System

    private func restartWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func runAsAdministrator(_ command: String) -> Bool {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with prompt \"Lumora needs your password to put your video on the lock screen.\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {
            state = .failed(error[NSAppleScript.errorMessage] as? String ?? "The system didn't allow the change.")
        }
        return error == nil
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private struct Catalog: Decodable {
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let id: String
        let accessibilityLabel: String?
    }
}
