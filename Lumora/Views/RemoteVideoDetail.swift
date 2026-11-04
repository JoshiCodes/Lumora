import AVFoundation
import SwiftUI

struct RemoteVideoDetail: View {
    let video: RemoteVideo

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var library: VideoLibrary

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Color.black
                AsyncImage(url: video.thumbnailURL) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                if let player {
                    PlayerPreview(player: player, gravity: .resizeAspect)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 4) {
                    Text("by")
                    Link(video.author, destination: video.pageURL)
                    Text("on \(video.provider.title)")
                }
                .foregroundStyle(.secondary)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                actions
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 660)
        .task { startPreview() }
        .onDisappear {
            player?.pause()
            looper = nil
            player = nil
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let clip = library.clip(forSourceID: video.id) {
            if library.activeClipID == clip.id {
                Label("On your desktop", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            } else {
                Button("Set as Wallpaper") {
                    library.activeClipID = clip.id
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let progress = downloads.progress[video.id] {
            ProgressView(value: progress)
                .frame(width: 160)
            Button("Cancel") { downloads.cancel(video) }
        } else {
            Button("Add to Library") { downloads.download(video) }
            Button("Set as Wallpaper") { downloads.download(video, activate: true) }
                .buttonStyle(.borderedProminent)
        }
    }

    private var details: String {
        var parts = [Clip.format(video.duration)]
        if let file = video.file(covering: DownloadManager.targetPixelWidth) {
            parts.append("Downloads at \(file.width) × \(file.height)")
        }
        return parts.joined(separator: "  ·  ")
    }

    private func startPreview() {
        guard player == nil, let file = video.previewFile else { return }
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: file.url))
        player.play()
        self.player = player
    }
}
