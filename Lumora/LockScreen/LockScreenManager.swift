import AVFoundation
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
        static let installedSize = "lockScreenSize"
    }

    /// macOS 27 and later keep Aerials in the user's own Library.
    static var userAerialsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials", isDirectory: true)
    }

    /// Sonoma and Sequoia keep them in a system folder owned by root.
    static let systemAerialsRoot = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer", isDirectory: true)

    private let library: VideoLibrary
    private let preferences: Preferences
    private let fileManager = FileManager.default
    private var subscriptions = Set<AnyCancellable>()
    private var updateTask: Task<Void, Never>?
    /// Wallpaper changes wait a moment, so clicking through several clips only updates once.
    private var debounceTask: Task<Void, Never>?
    /// Only one install runs at a time. A request that comes in meanwhile replaces this one.
    private var pendingClipID: UUID?
    private var installLoop: Task<Void, Never>?

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
        var names: [String: String] = [:]
        for catalog in catalogFiles() {
            guard let data = try? Data(contentsOf: catalog),
                  let parsed = try? JSONDecoder().decode(Catalog.self, from: data)
            else { continue }
            for asset in parsed.assets where names[asset.id.uppercased()] == nil {
                names[asset.id.uppercased()] = asset.accessibilityLabel
            }
        }

        var found: [Aerial] = []
        for file in movieFiles() {
            let id = file.deletingPathExtension().lastPathComponent
            guard !found.contains(where: { $0.id == id }) else { continue }
            found.append(Aerial(id: id, name: names[id.uppercased()] ?? "Aerial \(id.prefix(8))", url: file))
        }
        aerials = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        if targetID == nil || target == nil {
            targetID = aerials.first?.id
        }
        checkInstalledFile()
    }

    /// Video files of downloaded Aerials, newest location first.
    private func movieFiles() -> [URL] {
        var folders = [Self.userAerialsRoot.appendingPathComponent("videos", isDirectory: true)]
        let legacy = (try? fileManager.contentsOfDirectory(at: Self.systemAerialsRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        folders += legacy.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        return folders.flatMap { folder in
            ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "mov" }
        }
    }

    /// Apple's catalog with the Aerials' names. Its exact place has moved between releases.
    private func catalogFiles() -> [URL] {
        var files: [URL] = []
        if let enumerator = fileManager.enumerator(at: Self.userAerialsRoot, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if url.pathComponents.count - Self.userAerialsRoot.pathComponents.count > 3 {
                    enumerator.skipDescendants()
                    continue
                }
                if url.lastPathComponent == "entries.json" { files.append(url) }
            }
        }
        files.append(Self.systemAerialsRoot.appendingPathComponent("entries.json"))
        return files
    }

    /// macOS replaces the file when it updates or re-downloads an Aerial. Files in the user's
    /// Library can simply be swapped again; system files need the password once more.
    private func checkInstalledFile() {
        guard isEnabled, let target else {
            needsSetupAgain = false
            return
        }
        let expected = UserDefaults.standard.object(forKey: Key.installedSize) as? Int
        let actual = (try? target.url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let wasReplaced = expected != nil && actual != expected

        if !fileManager.isWritableFile(atPath: target.url.path) {
            needsSetupAgain = true
        } else if wasReplaced, let clip = library.activeClip {
            needsSetupAgain = false
            requestInstall(clip)
        } else {
            needsSetupAgain = false
            repairIfBroken(target)
        }
    }

    /// Checks that the lock screen file actually plays. A broken or half-written file shows up
    /// as a black lock screen, so put the wallpaper back in place when that happens.
    private func repairIfBroken(_ target: Aerial) {
        guard installLoop == nil, installedClipID != nil else { return }
        Task {
            guard !(await Self.isPlayable(target.url)), installLoop == nil,
                  let clip = library.activeClip
            else { return }
            UserDefaults.standard.removeObject(forKey: Key.installedFile)
            requestInstall(clip)
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
        requestInstall(clip)
    }

    func restoreOriginal() {
        guard let target else { return }
        let backup = backupURL(for: target)
        isEnabled = false
        installedClipID = nil
        debounceTask?.cancel()
        pendingClipID = nil
        UserDefaults.standard.removeObject(forKey: Key.installedFile)
        UserDefaults.standard.removeObject(forKey: Key.installedSize)

        guard fileManager.fileExists(atPath: backup.path) else {
            state = .idle
            return
        }
        state = .working("Restoring Apple's video…")
        let running = installLoop
        updateTask = Task {
            // Let a running install finish first, so the two writes can't interleave.
            await running?.value
            do {
                try await Self.write(backup, to: target.url)
                try? fileManager.removeItem(at: backup)
                clearCache()
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

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let current = library.activeClip else { return }
            requestInstall(current)
        }
    }

    private func requestInstall(_ clip: Clip) {
        pendingClipID = clip.id
        guard installLoop == nil else { return }

        installLoop = Task {
            while let id = pendingClipID {
                pendingClipID = nil
                guard isEnabled, let target, let clip = library.clip(withID: id) else { continue }
                await install(clip, into: target)
            }
            installLoop = nil
        }
    }

    private func install(_ clip: Clip, into target: Aerial) async {
        state = .working("Preparing “\(clip.name)” for the lock screen…")
        let source = library.videoURL(for: clip)
        let screens = NSScreen.pixelSizes
        let cache = cacheURL(for: clip)

        do {
            let prepared = try await Self.lockScreenFile(from: source, cache: cache, screens: screens)
            // A newer wallpaper is already waiting. Skip writing this one.
            if pendingClipID != nil { return }

            state = .working("Updating the lock screen…")
            var attempts = 0
            repeat {
                attempts += 1
                try await Self.write(prepared, to: target.url)
            } while !(await Self.isPlayable(target.url)) && attempts < 2

            guard await Self.isPlayable(target.url) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            installedClipID = clip.id
            UserDefaults.standard.set(clip.fileName, forKey: Key.installedFile)
            let size = (try? target.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            UserDefaults.standard.set(size, forKey: Key.installedSize)
            trimCache(keeping: cache)
            restartWallpaperAgent()
            state = .idle
        } catch {
            // Never leave a broken file behind: a black lock screen is worse than Apple's video.
            let backup = backupURL(for: target)
            if !(await Self.isPlayable(target.url)), fileManager.fileExists(atPath: backup.path) {
                try? await Self.write(backup, to: target.url)
                restartWallpaperAgent()
                installedClipID = nil
                UserDefaults.standard.removeObject(forKey: Key.installedFile)
                state = .failed("Couldn't put “\(clip.name)” on the lock screen, so Apple's video is back for now. \(error.localizedDescription)")
            } else {
                state = .failed("Couldn't update the lock screen: \(error.localizedDescription)")
            }
        }
    }

    /// Aerials are HEVC QuickTime movies. Clips that already are one go in as they are,
    /// everything else is converted once and kept in a small cache.
    private nonisolated static func lockScreenFile(from source: URL, cache: URL, screens: [CGSize]) async throws -> URL {
        if FileManager.default.fileExists(atPath: cache.path), await isPlayable(cache) {
            return cache
        }
        guard let plan = await VideoLibrary.plan(for: source, screens: screens) else {
            throw ImportError.unsupported(source.lastPathComponent)
        }
        if plan.isHEVC, !plan.isWorthIt, source.pathExtension.lowercased() == "mov" {
            return source
        }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = cache.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).mov")
        do {
            try await VideoLibrary.encode(from: source, to: partial, plan: plan)
            _ = try? FileManager.default.removeItem(at: cache)
            try FileManager.default.moveItem(at: partial, to: cache)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        return cache
    }

    private nonisolated static func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let loaded = try? await asset.load(.isPlayable, .duration),
              loaded.0, loaded.1.seconds > 0.5,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty
        else { return false }
        return true
    }

    // MARK: - Cache

    private var cacheFolder: URL {
        library.root.appendingPathComponent("Lock Screen Cache", isDirectory: true)
    }

    private func cacheURL(for clip: Clip) -> URL {
        cacheFolder.appendingPathComponent("\((clip.fileName as NSString).deletingPathExtension).mov")
    }

    /// Keeps the last few converted clips, so switching back and forth is instant.
    private func trimCache(keeping current: URL, limit: Int = 3) {
        let files = (try? fileManager.contentsOfDirectory(at: cacheFolder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                          options: [.skipsHiddenFiles])) ?? []
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: current.path)
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for file in sorted.dropFirst(limit) where file != current {
            try? fileManager.removeItem(at: file)
        }
    }

    private func clearCache() {
        try? fileManager.removeItem(at: cacheFolder)
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

    /// Puts `source` in place of `target` without macOS ever seeing a half-written file.
    /// Where Lumora owns the folder (macOS 27 and later), the new file is written next to the old
    /// one and swapped in with a single rename. In the system folder of older releases Lumora only
    /// owns the file itself, so it's rewritten in place.
    private nonisolated static func write(_ source: URL, to target: URL) async throws {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let folder = target.deletingLastPathComponent()

            if fileManager.isWritableFile(atPath: folder.path) {
                let staging = folder.appendingPathComponent(".lumora-\(UUID().uuidString).mov")
                do {
                    try fileManager.copyItem(at: source, to: staging)
                    _ = try fileManager.replaceItemAt(target, withItemAt: staging)
                } catch {
                    try? fileManager.removeItem(at: staging)
                    throw error
                }
                return
            }

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
        }.value
    }

    // MARK: - System

    /// The wallpaper agent and the Aerials extension keep the old video open. Both restart on their own.
    private func restartWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent", "WallpaperAerialsExtension"]
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
