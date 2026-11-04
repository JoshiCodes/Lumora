import AVFoundation
import ScreenSaver

@objc(LumoraSaverView)
final class LumoraSaverView: ScreenSaverView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var stopObserver: NSObjectProtocol?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    deinit {
        if let stopObserver {
            DistributedNotificationCenter.default().removeObserver(stopObserver)
        }
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    override func startAnimation() {
        super.startAnimation()
        player?.play()
    }

    override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    override func animateOneFrame() {}

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard player == nil else { return }

        let message = "Choose videos for the screen saver in Lumora."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: isPreview ? 11 : 20, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let size = message.size(withAttributes: attributes)
        message.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                     withAttributes: attributes)
    }

    private func setUp() {
        animationTimeInterval = 1
        wantsLayer = true
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)

        guard let source = Self.loadManifest(),
              let fileName = source.manifest.clips.randomElement()
        else { return }
        let manifest = source.manifest
        let folder = source.folder

        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player,
                                templateItem: AVPlayerItem(url: folder.appendingPathComponent(fileName)))
        playerLayer.videoGravity = manifest.fillsScreen ? .resizeAspectFill : .resizeAspect
        playerLayer.player = player
        self.player = player

        if !isPreview {
            // Since Sonoma the host process often outlives the screen saver and keeps
            // decoding in the background. Quit it ourselves once the saver is dismissed.
            stopObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main
            ) { [weak player] _ in
                player?.pause()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
            }
        }
    }

    private static func loadManifest() -> (manifest: SaverManifest, folder: URL)? {
        let fileManager = FileManager.default
        var candidates = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .map { $0.appendingPathComponent(SaverManifest.folderName, isDirectory: true) }
        let containerSupport = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(SaverManifest.hostBundleID)/Data/Library/Application Support/\(SaverManifest.folderName)",
                                    isDirectory: true)
        candidates.append(containerSupport)

        for folder in candidates {
            let url = folder.appendingPathComponent(SaverManifest.fileName)
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(SaverManifest.self, from: data),
                  !manifest.clips.isEmpty
            else { continue }
            return (manifest, folder)
        }
        return nil
    }
}
