import AVFoundation
import SwiftUI

struct PlayerPreview: NSViewRepresentable {
    let player: AVPlayer?
    var scaling: Scaling = .fill
    var videoSize: CGSize?
    var focusY: CGFloat = 0.5

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView(player: player)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {
        view.scaling = scaling
        view.videoSize = videoSize
        view.focusY = focusY
        view.show(player, animated: true)
    }
}
