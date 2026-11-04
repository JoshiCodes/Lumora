import CoreImage
import SwiftUI

/// Loads a thumbnail off the main thread. With `blur`, the image is blurred once up front
/// instead of with a live SwiftUI blur, which would be recomputed on every frame.
struct ThumbnailImage: View {
    let url: URL?
    var blur: CGFloat = 0

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let radius = blur
            let loaded = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return radius > 0 ? Self.blurred(data, radius: radius) : NSImage(data: data)
            }.value
            withAnimation(.easeOut(duration: 0.35)) { image = loaded }
        }
    }

    private nonisolated static func blurred(_ data: Data, radius: CGFloat) -> NSImage? {
        guard let input = CIImage(data: data) else { return nil }
        let output = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: input.extent)
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: input.extent.size)
    }
}
