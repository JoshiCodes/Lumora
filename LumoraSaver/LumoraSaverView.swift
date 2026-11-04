import AVFoundation
import ScreenSaver

/// One player for every screen. macOS creates a separate view per display inside the same
/// host process, so sharing keeps it to a single decoder and the screens stay in sync.
@MainActor
private enum SharedPlayback {
    private static var player: AVQueuePlayer?
    private static var looper: AVPlayerLooper?
    private static var fillsScreen = true
    private static var isWatchingForStop = false

    static func player(fillsScreen fills: inout Bool) -> AVQueuePlayer? {
        if let player {
            fills = fillsScreen
            return player
        }
        guard let source = loadManifest(), let fileName = source.manifest.clips.randomElement() else { return nil }

        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        looper = AVPlayerLooper(player: player,
                                templateItem: AVPlayerItem(url: source.folder.appendingPathComponent(fileName)))
        self.player = player
        fillsScreen = source.manifest.fillsScreen
        fills = fillsScreen
        return player
    }

    static func play() { player?.play() }
    static func pause() { player?.pause() }

    static func shutDown() {
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        player = nil
    }

    /// Since Sonoma the host process often outlives the screen saver and keeps decoding in the
    /// background, which makes the Mac sluggish right after unlocking. Stop everything the moment
    /// the saver is dismissed and quit the process; macOS starts a fresh one next time.
    static func watchForStop() {
        guard !isWatchingForStop else { return }
        isWatchingForStop = true

        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.willstop", "com.apple.screenIsUnlocked"] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    shutDown()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
                }
            }
        }
    }

    private static func loadManifest() -> (manifest: SaverManifest, folder: URL)? {
        guard let resources = Bundle(for: LumoraSaverView.self).resourceURL else { return nil }
        let folder = resources.appendingPathComponent(SaverManifest.folderName, isDirectory: true)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(SaverManifest.fileName)),
              let manifest = try? JSONDecoder().decode(SaverManifest.self, from: data),
              !manifest.clips.isEmpty
        else { return nil }
        return (manifest, folder)
    }
}

@objc(LumoraSaverView)
final class LumoraSaverView: ScreenSaverView {
    private let rootLayer = CALayer()
    private let playerLayer = AVPlayerLayer()
    private let messageLayer = CATextLayer()

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    override func startAnimation() {
        super.startAnimation()
        SharedPlayback.play()
    }

    override func stopAnimation() {
        super.stopAnimation()
        SharedPlayback.pause()
    }

    override func animateOneFrame() {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Some macOS versions never call startAnimation on secondary displays.
        if window != nil { SharedPlayback.play() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        layoutMessage()
        CATransaction.commit()
    }

    private func setUp() {
        // Host our own layer tree, so it exists right away on every display.
        rootLayer.backgroundColor = NSColor.black.cgColor
        layer = rootLayer
        wantsLayer = true
        animationTimeInterval = 1

        playerLayer.frame = bounds
        playerLayer.backgroundColor = NSColor.black.cgColor
        rootLayer.addSublayer(playerLayer)

        var fills = true
        if let player = SharedPlayback.player(fillsScreen: &fills) {
            playerLayer.videoGravity = fills ? .resizeAspectFill : .resizeAspect
            playerLayer.player = player
        } else {
            showMessage("Choose videos for the screen saver in Lumora.")
        }

        if !isPreview {
            SharedPlayback.watchForStop()
        }
    }

    private func showMessage(_ text: String) {
        messageLayer.string = text
        messageLayer.font = NSFont.systemFont(ofSize: 0, weight: .medium)
        messageLayer.fontSize = isPreview ? 11 : 20
        messageLayer.foregroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
        messageLayer.alignmentMode = .center
        messageLayer.contentsScale = window?.backingScaleFactor ?? 2
        rootLayer.addSublayer(messageLayer)
        layoutMessage()
    }

    private func layoutMessage() {
        let height = messageLayer.fontSize * 1.5
        messageLayer.frame = CGRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height)
    }
}
