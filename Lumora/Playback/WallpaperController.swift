import AVFoundation
import AppKit
import Combine

@MainActor
final class WallpaperController: ObservableObject {
    @Published private(set) var isUserPaused = false
    @Published private(set) var isPlaying = false
    @Published private(set) var pauseReason: String?
    @Published private(set) var isHeldForMeasurement = false
    /// The player for the current clip. Desktop windows and the in-app preview share it,
    /// so the video is only decoded once. Each clip gets a fresh player so the views can cross-fade.
    @Published private(set) var player: AVQueuePlayer?
    @Published private(set) var nextRotation: Date?

    private let library: VideoLibrary
    private let preferences: Preferences
    private let conditions = PlaybackConditions()

    private var looper: AVPlayerLooper?
    private var rotationTimer: Timer?
    private var loadedClipID: UUID?
    private var loadedFileName: String?
    private var loadGeneration = 0
    private var windows: [CGDirectDisplayID: DesktopWindow] = [:]
    private var subscriptions = Set<AnyCancellable>()

    private let savedPicturesKey = "originalDesktopPictures"

    init(library: VideoLibrary, preferences: Preferences) {
        self.library = library
        self.preferences = preferences
    }

    private static func makePlayer() -> AVQueuePlayer {
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        return player
    }

    func start() {
        library.$activeClipID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadActiveClip() }
            .store(in: &subscriptions)

        // Picks up a re-encoded file after "Optimize".
        library.$clips
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                loadActiveClip()
                if rotationTimer == nil { scheduleRotation() }
            }
            .store(in: &subscriptions)

        preferences.$rotationMinutes
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRotation() }
            .store(in: &subscriptions)

        preferences.$scaling
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scaling in
                guard let self else { return }
                windows.values.forEach { $0.scaling = scaling }
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
            conditions.$isUserIdle,
            conditions.$isOverheating,
            conditions.$prefersReducedMotion,
            preferences.$respectReduceMotion,
            preferences.$pauseWhenHot,
            preferences.$pauseOnBattery,
            preferences.$pauseInLowPowerMode,
            preferences.$pauseWhenCovered
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.updatePlayback() }
        .store(in: &subscriptions)

        preferences.$pauseWhenIdle
            .combineLatest(preferences.$idleMinutes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, minutes in
                self?.conditions.idleThreshold = enabled ? TimeInterval(minutes * 60) : 0
            }
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

    var canSkip: Bool { library.clips.count > 1 }

    /// Switches to another clip, at random or in library order depending on the rotation setting.
    func next() {
        let clips = library.clips
        guard clips.count > 1 else { return }
        let currentIndex = clips.firstIndex { $0.id == library.activeClipID }

        let pick: Clip?
        if preferences.rotationShuffle || currentIndex == nil {
            pick = clips.filter { $0.id != library.activeClipID }.randomElement()
        } else {
            pick = clips[(currentIndex! + 1) % clips.count]
        }
        if let pick { library.activeClipID = pick.id }
    }

    private func scheduleRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        nextRotation = nil

        let minutes = preferences.rotationMinutes
        guard minutes > 0, loadedClipID != nil, library.clips.count > 1 else { return }

        let interval = TimeInterval(minutes * 60)
        nextRotation = Date().addingTimeInterval(interval)
        rotationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
        rotationTimer?.tolerance = min(60, interval * 0.1)
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
            if loadedClipID != nil || player != nil {
                tearDown()
            }
            restoreDesktopPictures()
            return
        }
        let isNewClip = clip.id != loadedClipID
        guard isNewClip || clip.fileName != loadedFileName else { return }

        loadedClipID = clip.id
        loadedFileName = clip.fileName
        loadGeneration += 1
        let generation = loadGeneration
        let url = library.videoURL(for: clip)

        Task {
            let asset = await Self.silentAsset(for: url)
            guard generation == loadGeneration else { return }

            let newPlayer = Self.makePlayer()
            let newLooper = AVPlayerLooper(player: newPlayer, templateItem: AVPlayerItem(asset: asset))
            let oldPlayer = player
            let oldLooper = looper
            player = newPlayer
            looper = newLooper

            if isNewClip {
                isUserPaused = false
                scheduleRotation()
            }
            syncWindows(animated: oldPlayer != nil)
            if preferences.matchDesktopPicture { applyDesktopPicture() }
            updatePlayback()

            // Keep the old player running until the cross-fade is over, then let it go.
            if let oldPlayer {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    oldLooper?.disableLooping()
                    oldPlayer.pause()
                    oldPlayer.removeAllItems()
                }
            }
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
        player?.pause()
        player?.removeAllItems()
        player = nil
        rotationTimer?.invalidate()
        rotationTimer = nil
        nextRotation = nil
        loadedClipID = nil
        loadedFileName = nil
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
        } else if conditions.isUserIdle {
            "Paused while you're away"
        } else if preferences.respectReduceMotion && conditions.prefersReducedMotion {
            "Paused because Reduce Motion is on"
        } else if preferences.pauseWhenHot && conditions.isOverheating {
            "Paused while your Mac cools down"
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
            player?.play()
        } else {
            player?.pause()
        }
        isPlaying = shouldPlay
        pauseReason = reason
    }

    // MARK: - Windows

    private func syncWindows(animated: Bool = false) {
        guard let player else { return }

        let screens = NSScreen.screens
        let connected = Set(screens.map(\.displayID))
        for (id, window) in windows where !connected.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }

        var addedScreen = false
        for screen in screens {
            let window: DesktopWindow
            if let existing = windows[screen.displayID] {
                window = existing
            } else {
                window = DesktopWindow()
                addedScreen = true
            }
            window.scaling = preferences.scaling
            window.show(player, animated: animated)
            window.setFrame(screen.frame, display: true)
            window.orderFront(nil)
            windows[screen.displayID] = window
        }

        // A newly connected display should get the matching still picture too.
        if addedScreen, !animated, preferences.matchDesktopPicture {
            applyDesktopPicture()
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
