import AVFoundation
import AppKit
import CoreImage

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

    var scaling: Scaling = .fill {
        didSet {
            playerView?.videoGravity = scaling.videoGravity
            playerView?.showsBlurredEdges = scaling.showsBlurredEdges
        }
    }
}

/// Shows a player and cross-fades to the next one once its first frame is ready,
/// so switching wallpapers never flashes black.
///
/// Each player gets a slot: the video itself, plus an optional blurred copy behind it that fills
/// the edges when the video is fitted onto a screen with a different shape, like an ultrawide.
/// Both layers show the same player, so nothing is decoded twice.
final class PlayerView: NSView {
    private final class Slot {
        let container = CALayer()
        let video: AVPlayerLayer
        let backdrop: AVPlayerLayer

        init(player: AVPlayer) {
            video = AVPlayerLayer(player: player)
            backdrop = AVPlayerLayer(player: player)
            let noAnimations: [String: CAAction] = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
                                                     "contentsScale": NSNull(), "hidden": NSNull()]
            for layer in [container, video, backdrop] {
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer.actions = noAnimations
            }
            backdrop.videoGravity = .resizeAspectFill
            backdrop.filters = [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 50])].compactMap { $0 }
            backdrop.opacity = 0.75
            container.addSublayer(backdrop)
            container.addSublayer(video)
        }

        var player: AVPlayer? { video.player }

        func apply(gravity: AVLayerVideoGravity, blurredEdges: Bool, scale: CGFloat, frame: CGRect) {
            video.videoGravity = gravity
            backdrop.isHidden = !blurredEdges
            for layer in [container, video, backdrop] {
                layer.contentsScale = scale
            }
            container.frame = frame
            video.frame = container.bounds
            // Slightly larger than the screen so the blur doesn't fade out at the edges.
            backdrop.frame = container.bounds.insetBy(dx: -80, dy: -80)
        }
    }

    private var current: Slot?
    private var slots: [Slot] = []
    private var readyObservation: NSKeyValueObservation?

    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet { applyAppearance() }
    }

    var showsBlurredEdges = false {
        didSet { applyAppearance() }
    }

    init(player: AVPlayer? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layerUsesCoreImageFilters = true
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

    /// Layers we create ourselves don't follow the screen's scale factor on their own. Without
    /// this the video renders at half resolution on Retina and HiDPI displays.
    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyAppearance()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyAppearance()
    }

    private func applyAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for slot in slots {
            slot.apply(gravity: videoGravity, blurredEdges: showsBlurredEdges, scale: backingScale, frame: bounds)
        }
        CATransaction.commit()
    }

    func show(_ player: AVPlayer?, animated: Bool) {
        guard current?.player !== player else { return }

        // Drop anything left over from a fade that was interrupted by another switch.
        readyObservation = nil
        for slot in slots where slot !== current {
            slot.container.removeFromSuperlayer()
        }
        slots = current.map { [$0] } ?? []

        let previous = current
        guard let player else {
            current = nil
            fadeOut(previous)
            return
        }

        let next = Slot(player: player)
        slots.append(next)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        next.apply(gravity: videoGravity, blurredEdges: showsBlurredEdges, scale: backingScale, frame: bounds)
        next.container.opacity = animated && previous != nil ? 0 : 1
        layer?.addSublayer(next.container)
        CATransaction.commit()
        current = next

        guard next.container.opacity == 0 else {
            remove(previous)
            return
        }

        readyObservation = next.video.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self, weak next] layer, _ in
            guard layer.isReadyForDisplay, let next else { return }
            DispatchQueue.main.async {
                self?.crossfade(to: next, from: previous)
            }
        }
    }

    private func crossfade(to next: Slot, from previous: Slot?) {
        guard next === current, next.container.opacity == 0 else { return }
        readyObservation = nil
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.9)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { [weak self] in self?.remove(previous) }
        next.container.opacity = 1
        CATransaction.commit()
    }

    private func fadeOut(_ slot: Slot?) {
        guard let slot else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        CATransaction.setCompletionBlock { [weak self] in self?.remove(slot) }
        slot.container.opacity = 0
        CATransaction.commit()
    }

    private func remove(_ slot: Slot?) {
        guard let slot else { return }
        slot.container.removeFromSuperlayer()
        slots.removeAll { $0 === slot }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Every connected display in physical pixels.
    @MainActor
    static var pixelSizes: [CGSize] {
        let sizes = screens.map { CGSize(width: $0.frame.width * $0.backingScaleFactor,
                                         height: $0.frame.height * $0.backingScaleFactor) }
        return sizes.isEmpty ? [CGSize(width: 2560, height: 1440)] : sizes
    }

    /// How wide a video with the given aspect ratio has to be to fill every display without
    /// being stretched. On an ultrawide that's decided by the height, not the width.
    @MainActor
    static func requiredVideoWidth(aspectRatio: CGFloat) -> Int {
        let ratio = aspectRatio > 0 ? aspectRatio : 16 / 9
        let widths = pixelSizes.map { max($0.width, $0.height * ratio) }
        return Int((widths.max() ?? 2560).rounded(.up))
    }

    /// Width a typical 16:9 video needs to look sharp on every display.
    @MainActor
    static var widestPixelWidth: Int {
        requiredVideoWidth(aspectRatio: 16 / 9)
    }

    /// Survives reboots, unlike `displayID`.
    var persistentID: String {
        let id = displayID
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
}
