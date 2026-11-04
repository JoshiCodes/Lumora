import AVFoundation
import SwiftUI

struct PlayerPreview: NSViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView(player: player)
        view.videoGravity = gravity
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {
        view.videoGravity = gravity
    }
}
