import Foundation

struct PixabayProvider: VideoProvider {
    func videos(matching query: String, page: Int, apiKey: String) async throws -> [RemoteVideo] {
        var components = URLComponents(string: "https://pixabay.com/api/videos/")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: "30"),
            URLQueryItem(name: "order", value: "popular"),
            URLQueryItem(name: "min_width", value: "1920"),
            URLQueryItem(name: "safesearch", value: "true"),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, http.statusCode == 400 {
            // Pixabay answers a bad key with 400 and a plain-text body.
            throw ProviderError.invalidKey
        }
        try ProviderError.check(response)
        return try JSONDecoder().decode(Response.self, from: data).hits.compactMap(\.remoteVideo)
    }

    private struct Response: Decodable {
        let hits: [Hit]
    }

    private struct Hit: Decodable {
        let id: Int
        let pageURL: String
        let tags: String
        let duration: Double
        let user: String
        let videos: [String: Rendition]

        var remoteVideo: RemoteVideo? {
            let files = videos.values.compactMap { rendition -> RemoteVideo.File? in
                guard let url = URL(string: rendition.url), rendition.width > 0 else { return nil }
                return RemoteVideo.File(url: url, width: rendition.width, height: rendition.height)
            }
            guard !files.isEmpty, let page = URL(string: pageURL) else { return nil }

            let thumbnail = (videos["medium"] ?? videos["large"])?.thumbnail.flatMap(URL.init(string:))
            let title = tags.split(separator: ",")
                .prefix(3)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: ", ")

            return RemoteVideo(
                id: "pixabay-\(id)",
                provider: .pixabay,
                title: title.isEmpty ? "Untitled" : title.prefix(1).uppercased() + title.dropFirst(),
                author: user,
                pageURL: page,
                thumbnailURL: thumbnail,
                duration: duration,
                files: files
            )
        }
    }

    private struct Rendition: Decodable {
        let url: String
        let width: Int
        let height: Int
        let thumbnail: String?
    }
}
