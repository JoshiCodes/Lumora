import AVFoundation
import AppKit

/// Borderless window that sits on the desktop layer, below the Finder icons.
final class DesktopWindow: NSWindow {
    convenience init() {
        self.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = PlayerView()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var playerView: PlayerView? { contentView as? PlayerView }

    func show(_ player: AVPlayer?, animated: Bool) {
        playerView?.show(player, animated: animated)
    }

    var videoGravity: AVLayerVideoGravity {
        get { playerView?.videoGravity ?? .resizeAspectFill }
        set { playerView?.videoGravity = newValue }
    }
}

/// Shows a player and cross-fades to the next one once its first frame is ready,
/// so switching wallpapers never flashes black.
final class PlayerView: NSView {
    private var current: AVPlayerLayer?
    private var readyObservation: NSKeyValueObservation?

    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet {
            layer?.sublayers?.compactMap { $0 as? AVPlayerLayer }.forEach { $0.videoGravity = videoGravity }
        }
    }

    init(player: AVPlayer? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        // Everything on screen comes from the player layers, so AppKit never needs to redraw.
        layerContentsRedrawPolicy = .never
        show(player, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }

    func show(_ player: AVPlayer?, animated: Bool) {
        guard current?.player !== player else { return }

        // Drop anything left over from a fade that was interrupted by another switch.
        readyObservation = nil
        layer?.sublayers?.filter { $0 !== current }.forEach { $0.removeFromSuperlayer() }

        let previous = current
        guard let player else {
            current = nil
            fadeOut(previous)
            return
        }

        let next = AVPlayerLayer(player: player)
        next.videoGravity = videoGravity
        next.backgroundColor = NSColor.clear.cgColor
        next.frame = bounds
        next.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        next.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        next.opacity = animated && previous != nil ? 0 : 1
        layer?.addSublayer(next)
        current = next

        guard next.opacity == 0 else {
            previous?.removeFromSuperlayer()
            return
        }

        readyObservation = next.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                self?.crossfade(to: layer, from: previous)
            }
        }
    }

    private func crossfade(to next: AVPlayerLayer, from previous: AVPlayerLayer?) {
        guard next === current, next.opacity == 0 else { return }
        readyObservation = nil
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.9)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { previous?.removeFromSuperlayer() }
        next.opacity = 1
        CATransaction.commit()
    }

    private func fadeOut(_ layer: AVPlayerLayer?) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.opacity = 0
        CATransaction.commit()
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
