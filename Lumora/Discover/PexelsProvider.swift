import Foundation

struct PexelsProvider: VideoProvider {
    func videos(matching query: String, page: Int, apiKey: String) async throws -> [RemoteVideo] {
        var components: URLComponents
        var items = [
            URLQueryItem(name: "per_page", value: "30"),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if query.isEmpty {
            components = URLComponents(string: "https://api.pexels.com/videos/popular")!
            items.append(URLQueryItem(name: "min_width", value: "1920"))
        } else {
            components = URLComponents(string: "https://api.pexels.com/videos/search")!
            items += [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "orientation", value: "landscape"),
                URLQueryItem(name: "size", value: "large"),
            ]
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try ProviderError.check(response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data).videos.compactMap(\.remoteVideo)
    }

    private struct Response: Decodable {
        let videos: [Video]
    }

    private struct Video: Decodable {
        let id: Int
        let duration: Double
        let url: String
        let image: String?
        let user: User
        let videoFiles: [VideoFile]

        var remoteVideo: RemoteVideo? {
            let files = videoFiles.compactMap { file -> RemoteVideo.File? in
                guard file.fileType == "video/mp4",
                      let width = file.width, let height = file.height, width >= height,
                      let url = URL(string: file.link)
                else { return nil }
                return RemoteVideo.File(url: url, width: width, height: height)
            }
            guard !files.isEmpty, let page = URL(string: url) else { return nil }
            return RemoteVideo(
                id: "pexels-\(id)",
                provider: .pexels,
                title: Self.title(fromPage: page),
                author: user.name,
                pageURL: page,
                thumbnailURL: image.flatMap(URL.init(string:)),
                duration: duration,
                files: files
            )
        }

        /// Pexels has no title field, but the page slug reads like one: /video/calm-ocean-waves-1234/
        static func title(fromPage url: URL) -> String {
            var words = url.lastPathComponent.split(separator: "-")
            if let last = words.last, Int(last) != nil { words.removeLast() }
            let title = words.joined(separator: " ")
            return title.isEmpty ? "Untitled" : title.prefix(1).uppercased() + title.dropFirst()
        }
    }

    private struct User: Decodable {
        let name: String
    }

    private struct VideoFile: Decodable {
        let fileType: String?
        let width: Int?
        let height: Int?
        let link: String
    }
}
