import SwiftUI

struct ClipCard: View {
    let clip: Clip
    let thumbnailURL: URL
    let isActive: Bool

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
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(clip.durationText)
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(7)
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(isActive ? Color.accentColor : Color.primary.opacity(0.08),
                                       lineWidth: isActive ? 3 : 1)
                }
                .shadow(color: .black.opacity(isHovering ? 0.25 : 0.1), radius: isHovering ? 10 : 4, y: 3)
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
            thumbnail = NSImage(contentsOf: thumbnailURL)
        }
    }
}
