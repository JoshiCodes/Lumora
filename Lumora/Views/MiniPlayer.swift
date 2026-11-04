import SwiftUI

/// Compact now-playing strip at the bottom of the sidebar.
struct MiniPlayer: View {
    @Binding var pane: Pane

    @EnvironmentObject private var library: VideoLibrary
    @EnvironmentObject private var wallpaper: WallpaperController

    var body: some View {
        if let clip = library.activeClip {
            HStack(spacing: 10) {
                ThumbnailImage(url: library.thumbnailURL(for: clip))
                    .frame(width: 46, height: 30)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(clip.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(wallpaper.isPlaying ? "Playing" : wallpaper.pauseReason ?? "Paused")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    wallpaper.togglePause()
                } label: {
                    Image(systemName: wallpaper.isUserPaused ? "play.fill" : "pause.fill")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(wallpaper.isUserPaused ? "Resume" : "Pause")
            }
            .padding(8)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { pane = .nowPlaying }
            .padding(10)
        }
    }
}
