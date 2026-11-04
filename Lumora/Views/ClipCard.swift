import SwiftUI

struct ClipCard: View {
    let clip: Clip
    let thumbnailURL: URL
    var isActive = false
    /// Shows a checkbox when set, used for picking screen saver videos.
    var isChecked: Bool? = nil

    var isBusy = false

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(.quaternary)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    DurationBadge(text: clip.durationText)
                }
                .overlay {
                    if isBusy {
                        ZStack {
                            Color.black.opacity(0.45)
                            VStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Optimizing…").font(.caption)
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let isChecked {
                        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, isChecked ? Color.accentColor : .black.opacity(0.3))
                            .padding(8)
                    }
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(isActive ? Color.accentColor : Color.primary.opacity(0.08),
                                       lineWidth: isActive ? 3 : 1)
                }
                .shadow(color: .black.opacity(isHovering ? 0.22 : 0.08), radius: isHovering ? 10 : 4, y: 3)
                .scaleEffect(isHovering ? 1.02 : 1)

            HStack(spacing: 6) {
                if isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                }
                Text(clip.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .task(id: thumbnailURL) {
            let url = thumbnailURL
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            withAnimation(.easeOut(duration: 0.2)) {
                thumbnail = data.flatMap(NSImage.init(data:))
            }
        }
    }
}

struct DurationBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(7)
    }
}
