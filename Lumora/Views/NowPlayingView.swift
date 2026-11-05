import SwiftUI

struct NowPlayingView: View {
    @Binding var pane: Pane

    @EnvironmentObject private var library: VideoLibrary
    @EnvironmentObject private var wallpaper: WallpaperController
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                stage
                if let clip = library.activeClip {
                    controls(for: clip)
                }
                if !library.clips.isEmpty {
                    recents
                }
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background { backdrop }
        .navigationTitle("Now Playing")
    }

    private var stage: some View {
        ZStack {
            if library.activeClip != nil {
                PlayerPreview(player: wallpaper.player, gravity: preferences.scaling.videoGravity,
                              blurredEdges: preferences.scaling.showsBlurredEdges)
                    .background(.black)
            } else {
                placeholder
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .overlay(alignment: .topLeading) {
            if library.activeClip != nil {
                statusPill.padding(14)
            }
        }
    }

    /// Soft, blurred version of the current clip behind the page.
    private var backdrop: some View {
        ZStack {
            if let clip = library.activeClip {
                ThumbnailImage(url: library.thumbnailURL(for: clip), blur: 40)
                    .opacity(0.32)
                    .id(clip.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: library.activeClipID)
        .overlay {
            LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .clipped()
        .allowsHitTesting(false)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(wallpaper.isPlaying ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(wallpaper.isPlaying ? "Live on your desktop" : wallpaper.pauseReason ?? "Paused")
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.11, green: 0.09, blue: 0.27),
                                    Color(red: 0.33, green: 0.16, blue: 0.52),
                                    Color(red: 0.80, green: 0.43, blue: 0.52)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                Text("Nothing on your desktop yet")
                    .font(.title2.weight(.semibold))
                Text("Pick a video from your library or find one in Discover.")
                    .foregroundStyle(.white.opacity(0.75))
                HStack {
                    Button("Open Library") { pane = .library }
                    Button("Discover Videos") { pane = .discover }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
        }
    }

    private func controls(for clip: Clip) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text([clip.durationText, clip.credit, rotationText].compactMap { $0 }.joined(separator: "  ·  "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("Scaling", selection: $preferences.scaling) {
                ForEach(Scaling.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button {
                wallpaper.togglePause()
            } label: {
                Label(wallpaper.isUserPaused ? "Resume" : "Pause",
                      systemImage: wallpaper.isUserPaused ? "play.fill" : "pause.fill")
                    .frame(minWidth: 76)
            }
            .buttonStyle(.borderedProminent)

            if wallpaper.canSkip {
                Button {
                    wallpaper.next()
                } label: {
                    Label("Next", systemImage: "forward.fill")
                }
                .help("Next Wallpaper")
            }

            Button("Stop") { wallpaper.stop() }
        }
        .controlSize(.large)
    }

    private var rotationText: String? {
        guard let next = wallpaper.nextRotation else { return nil }
        return "Next change at \(next.formatted(date: .omitted, time: .shortened))"
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recently Added")
                    .font(.headline)
                Spacer()
                Button("Show All") { pane = .library }
                    .buttonStyle(.link)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(library.clips.suffix(12).reversed())) { clip in
                        ClipCard(clip: clip,
                                 thumbnailURL: library.thumbnailURL(for: clip),
                                 isActive: clip.id == library.activeClipID)
                            .frame(width: 210)
                            .onTapGesture { library.activeClipID = clip.id }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        }
    }
}
