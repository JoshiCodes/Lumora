import AVFoundation
import AppKit

/// Borderless window that sits on the desktop layer, below the Finder icons.
final class DesktopWindow: NSWindow {
    convenience init(player: AVPlayer) {
        self.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = PlayerView(player: player)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var videoGravity: AVLayerVideoGravity {
        get { (contentView as? PlayerView)?.videoGravity ?? .resizeAspectFill }
        set { (contentView as? PlayerView)?.videoGravity = newValue }
    }
}

final class PlayerView: NSView {
    private let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        wantsLayer = true
        // Everything on screen comes from the player layer, so AppKit never needs to redraw.
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        playerLayer
    }

    var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Widest connected display in physical pixels, capped at 4K.
    @MainActor
    static var widestPixelWidth: Int {
        let widest = screens.map { $0.frame.width * $0.backingScaleFactor }.max() ?? 2560
        return min(Int(widest), 3840)
    }

    /// Survives reboots, unlike `displayID`.
    var persistentID: String {
        let id = displayID
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
}
