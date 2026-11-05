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

    var scaling: Scaling {
        get { playerView?.scaling ?? .fill }
        set { playerView?.scaling = newValue }
    }

    var videoSize: CGSize? {
        get { playerView?.videoSize }
        set { playerView?.videoSize = newValue }
    }

    var focusY: CGFloat {
        get { playerView?.focusY ?? 0.5 }
        set { playerView?.focusY = newValue }
    }
}

/// Shows a player and cross-fades to the next one once its first frame is ready,
/// so switching wallpapers never flashes black.
///
/// When the video fills a screen with a different shape (a 16:9 clip on a 21:9 ultrawide),
/// `focusY` decides which part stays visible: 0 keeps the top, 1 the bottom.
final class PlayerView: NSView {
    private final class Slot {
        let layer: AVPlayerLayer

        init(player: AVPlayer) {
            layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspect
            layer.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "contentsScale": NSNull()]
        }

        var player: AVPlayer? { layer.player }
    }

    private var current: Slot?
    private var slots: [Slot] = []
    private var readyObservation: NSKeyValueObservation?

    var scaling: Scaling = .fill {
        didSet { if scaling != oldValue { layoutSlots() } }
    }

    /// Natural size of the video, upright. Needed to place a cropped video precisely.
    var videoSize: CGSize? {
        didSet { if videoSize != oldValue { layoutSlots() } }
    }

    var focusY: CGFloat = 0.5 {
        didSet { if focusY != oldValue { layoutSlots() } }
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
        layer.masksToBounds = true
        return layer
    }

    /// Layers we create ourselves don't follow the screen's scale factor on their own. Without
    /// this the video renders at half resolution on Retina and HiDPI displays.
    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutSlots()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutSlots()
    }

    /// Where the video goes. Fitting is left to AVFoundation; filling is done by hand so the
    /// crop can follow `focusY` instead of always keeping the middle.
    private var videoFrame: CGRect {
        guard scaling == .fill, let videoSize, videoSize.width > 0, videoSize.height > 0,
              bounds.width > 0, bounds.height > 0
        else { return bounds }

        let scale = max(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let width = videoSize.width * scale
        let height = videoSize.height * scale
        // Layer coordinates start at the bottom, so focus 0 (top) means the lowest origin.
        let y = (bounds.height - height) * (1 - focusY)
        return CGRect(x: (bounds.width - width) / 2, y: y, width: width, height: height).integral
    }

    private func layoutSlots() {
        let frame = videoFrame
        let gravity: AVLayerVideoGravity = scaling == .fill && videoSize == nil ? .resizeAspectFill : .resizeAspect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for slot in slots {
            slot.layer.contentsScale = backingScale
            slot.layer.videoGravity = gravity
            slot.layer.frame = frame
        }
        CATransaction.commit()
    }

    func show(_ player: AVPlayer?, animated: Bool) {
        guard current?.player !== player else { return }

        // Drop anything left over from a fade that was interrupted by another switch.
        readyObservation = nil
        for slot in slots where slot !== current {
            slot.layer.removeFromSuperlayer()
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
        next.layer.opacity = animated && previous != nil ? 0 : 1
        layer?.addSublayer(next.layer)
        CATransaction.commit()
        current = next
        layoutSlots()

        guard next.layer.opacity == 0 else {
            remove(previous)
            return
        }

        readyObservation = next.layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self, weak next] layer, _ in
            guard layer.isReadyForDisplay, let next else { return }
            DispatchQueue.main.async {
                self?.crossfade(to: next, from: previous)
            }
        }
    }

    private func crossfade(to next: Slot, from previous: Slot?) {
        guard next === current, next.layer.opacity == 0 else { return }
        readyObservation = nil
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.9)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { [weak self] in self?.remove(previous) }
        next.layer.opacity = 1
        CATransaction.commit()
    }

    private func fadeOut(_ slot: Slot?) {
        guard let slot else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        CATransaction.setCompletionBlock { [weak self] in self?.remove(slot) }
        slot.layer.opacity = 0
        CATransaction.commit()
    }

    private func remove(_ slot: Slot?) {
        guard let slot else { return }
        slot.layer.removeFromSuperlayer()
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
