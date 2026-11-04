import Foundation

/// NASA Image and Video Library. Public domain, no key required.
/// https://images.nasa.gov/docs/images.nasa.gov_api_docs.pdf
struct NASAProvider: VideoProvider {
    private static let defaultQuery = "earth from space"

    func videos(matching query: String, page: Int, apiKey: String) async throws -> [RemoteVideo] {
        var components = URLComponents(string: "https://images-api.nasa.gov/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query.isEmpty ? Self.defaultQuery : query),
            URLQueryItem(name: "media_type", value: "video"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: "30"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try ProviderError.check(response)
        return try JSONDecoder().decode(Response.self, from: data).collection.items.compactMap(\.remoteVideo)
    }

    func files(for video: RemoteVideo) async throws -> [RemoteVideo.File] {
        guard let detailsURL = video.detailsURL else { return video.files }
        let (data, response) = try await URLSession.shared.data(from: detailsURL)
        try ProviderError.check(response)

        // The asset list is a flat array of URLs. The suffix tells the rendition apart.
        let renditions: [(suffix: String, width: Int)] = [
            ("~orig.mp4", 3840), ("~large.mp4", 1920), ("~medium.mp4", 1280),
            ("~small.mp4", 640), ("~mobile.mp4", 480),
        ]
        let files = try JSONDecoder().decode([String].self, from: data).compactMap { link -> RemoteVideo.File? in
            guard let rendition = renditions.first(where: { link.hasSuffix($0.suffix) }),
                  let url = URL(lenient: link.replacingOccurrences(of: "http://", with: "https://"))
            else { return nil }
            return RemoteVideo.File(url: url, width: rendition.width, height: rendition.width * 9 / 16)
        }
        guard !files.isEmpty else { throw ResolveError.noPlayableFile }
        return files
    }

    private struct Response: Decodable {
        let collection: Collection
    }

    private struct Collection: Decodable {
        let items: [Item]
    }

    private struct Item: Decodable {
        let href: String
        let data: [Metadata]
        let links: [Link]?

        var remoteVideo: RemoteVideo? {
            guard let meta = data.first,
                  let details = URL(lenient: href),
                  let page = URL(string: "https://images.nasa.gov/details/\(meta.nasaID)")
            else { return nil }
            let thumbnail = links?.first { $0.rel == "preview" }.flatMap { URL(lenient: $0.href) }
            return RemoteVideo(
                id: "nasa-\(meta.nasaID)",
                provider: .nasa,
                title: meta.title.trimmingCharacters(in: .whitespacesAndNewlines),
                author: meta.secondaryCreator ?? meta.center.map { "NASA \($0)" } ?? "NASA",
                pageURL: page,
                thumbnailURL: thumbnail,
                duration: 0,
                files: [],
                detailsURL: details
            )
        }
    }

    private struct Metadata: Decodable {
        let nasaID: String
        let title: String
        let center: String?
        let secondaryCreator: String?

        enum CodingKeys: String, CodingKey {
            case nasaID = "nasa_id"
            case title
            case center
            case secondaryCreator = "secondary_creator"
        }
    }

    private struct Link: Decodable {
        let href: String
        let rel: String?
    }
}

extension URL {
    /// Accepts the occasional unescaped space that some APIs return.
    init?(lenient string: String) {
        if let url = URL(string: string) {
            self = url
        } else if let escaped = string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
                  let url = URL(string: escaped) {
            self = url
        } else {
            return nil
        }
    }
}
