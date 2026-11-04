import AVFoundation
import AppKit
import Combine

@MainActor
final class WallpaperController: ObservableObject {
    @Published private(set) var isUserPaused = false
    @Published private(set) var isPlaying = false
    @Published private(set) var pauseReason: String?
    @Published private(set) var isHeldForMeasurement = false

    private let library: VideoLibrary
    private let preferences: Preferences
    private let conditions = PlaybackConditions()

    /// Shared by every desktop window and the in-app preview, so the video is only decoded once.
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var loadedClipID: UUID?
    private var loadGeneration = 0
    private var windows: [CGDirectDisplayID: DesktopWindow] = [:]
    private var subscriptions = Set<AnyCancellable>()

    private let savedPicturesKey = "originalDesktopPictures"

    init(library: VideoLibrary, preferences: Preferences) {
        self.library = library
        self.preferences = preferences
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
    }

    func start() {
        library.$activeClipID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadActiveClip() }
            .store(in: &subscriptions)

        preferences.$scaling
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scaling in
                guard let self else { return }
                windows.values.forEach { $0.videoGravity = scaling.videoGravity }
                if preferences.matchDesktopPicture { applyDesktopPicture() }
            }
            .store(in: &subscriptions)

        preferences.$matchDesktopPicture
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled { self?.applyDesktopPicture() } else { self?.restoreDesktopPictures() }
            }
            .store(in: &subscriptions)

        Publishers.MergeMany(
            conditions.$isOnBattery,
            conditions.$isLowPowerMode,
            conditions.$isAsleep,
            conditions.$isLocked,
            conditions.$isSessionInactive,
            conditions.$isScreenSaverRunning,
            preferences.$pauseOnBattery,
            preferences.$pauseInLowPowerMode,
            preferences.$pauseWhenCovered
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.updatePlayback() }
        .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)
            .filter { $0.object is DesktopWindow }
            .sink { [weak self] _ in self?.updatePlayback() }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.syncWindows() }
            .store(in: &subscriptions)
    }

    func togglePause() {
        isUserPaused.toggle()
        updatePlayback()
    }

    func stop() {
        library.activeClipID = nil
    }

    /// Lets the performance monitor measure the system without Lumora playing.
    func holdForMeasurement(_ hold: Bool) {
        isHeldForMeasurement = hold
        updatePlayback()
    }

    var hasClipLoaded: Bool { looper != nil }

    // MARK: - Playback

    private func loadActiveClip() {
        guard let clip = library.activeClip else {
            tearDown()
            restoreDesktopPictures()
            return
        }
        guard clip.id != loadedClipID else { return }

        loadedClipID = clip.id
        loadGeneration += 1
        let generation = loadGeneration
        let url = library.videoURL(for: clip)

        Task {
            let asset = await Self.silentAsset(for: url)
            guard generation == loadGeneration else { return }

            looper?.disableLooping()
            player.removeAllItems()
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
            isUserPaused = false

            syncWindows()
            if preferences.matchDesktopPicture { applyDesktopPicture() }
            updatePlayback()
        }
    }

    /// A muted player still decodes audio. Dropping the track saves that work entirely.
    private nonisolated static func silentAsset(for url: URL) async -> AVAsset {
        let asset = AVURLAsset(url: url)
        do {
            let audio = try await asset.loadTracks(withMediaType: .audio)
            guard !audio.isEmpty, let video = try await asset.loadTracks(withMediaType: .video).first else {
                return asset
            }
            let (range, transform) = try await video.load(.timeRange, .preferredTransform)

            let composition = AVMutableComposition()
            guard let track = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid)
            else { return asset }
            try track.insertTimeRange(range, of: video, at: .zero)
            track.preferredTransform = transform
            return composition
        } catch {
            return asset
        }
    }

    private func tearDown() {
        loadGeneration += 1
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.removeAllItems()
        loadedClipID = nil
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
        isPlaying = false
    }

    private var isDesktopVisible: Bool {
        windows.values.contains { $0.occlusionState.contains(.visible) }
    }

    private func updatePlayback() {
        let reason: String? = if loadedClipID == nil || looper == nil {
            nil
        } else if isHeldForMeasurement {
            "Paused for a measurement"
        } else if isUserPaused {
            "Paused"
        } else if conditions.isAsleep || conditions.isLocked || conditions.isSessionInactive {
            "Paused while the screen is off"
        } else if conditions.isScreenSaverRunning {
            "Paused while the screen saver runs"
        } else if preferences.pauseOnBattery && conditions.isOnBattery {
            "Paused on battery power"
        } else if preferences.pauseInLowPowerMode && conditions.isLowPowerMode {
            "Paused in Low Power Mode"
        } else if preferences.pauseWhenCovered && !isDesktopVisible {
            "Paused while the desktop is hidden"
        } else {
            nil
        }

        let shouldPlay = looper != nil && reason == nil
        if shouldPlay {
            player.play()
        } else {
            player.pause()
        }
        isPlaying = shouldPlay
        pauseReason = reason
    }

    // MARK: - Windows

    private func syncWindows() {
        guard looper != nil else { return }

        let screens = NSScreen.screens
        let connected = Set(screens.map(\.displayID))
        for (id, window) in windows where !connected.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }

        for screen in screens {
            let window = windows[screen.displayID] ?? DesktopWindow(player: player)
            window.videoGravity = preferences.scaling.videoGravity
            window.setFrame(screen.frame, display: true)
            window.orderFront(nil)
            windows[screen.displayID] = window
        }
        updatePlayback()
    }

    // MARK: - Desktop picture

    /// Sets the clip's first frame as the regular desktop picture, so Mission Control,
    /// the lock screen and the time before Lumora launches all match the video.
    private func applyDesktopPicture() {
        guard let clip = library.activeClip else { return }
        let url = library.stillURL(for: clip)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        rememberDesktopPictures()
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
            .allowClipping: preferences.scaling == .fill,
        ]
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    private func rememberDesktopPictures() {
        var saved = UserDefaults.standard.dictionary(forKey: savedPicturesKey) as? [String: String] ?? [:]
        for screen in NSScreen.screens where saved[screen.persistentID] == nil {
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  !url.path.hasPrefix(library.root.path)
            else { continue }
            saved[screen.persistentID] = url.path
        }
        UserDefaults.standard.set(saved, forKey: savedPicturesKey)
    }

    private func restoreDesktopPictures() {
        guard let saved = UserDefaults.standard.dictionary(forKey: savedPicturesKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            guard let path = saved[screen.persistentID] else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
        UserDefaults.standard.removeObject(forKey: savedPicturesKey)
    }
}
