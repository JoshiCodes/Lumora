import AVFoundation
import SwiftUI

struct PlayerPreview: NSViewRepresentable {
    let player: AVPlayer?
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    var blurredEdges = false

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView(player: player)
        view.videoGravity = gravity
        view.showsBlurredEdges = blurredEdges
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {
        view.videoGravity = gravity
        view.showsBlurredEdges = blurredEdges
        view.show(player, animated: true)
    }
}
