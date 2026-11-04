import Foundation

/// Internet Archive. No key required.
/// https://archive.org/developers/
struct ArchiveProvider: VideoProvider {
    private static let defaultQuery = #"subject:(timelapse OR "time lapse" OR aerial OR drone OR nature)"#

    func videos(matching query: String, page: Int, apiKey: String) async throws -> [RemoteVideo] {
        let search = query.isEmpty ? Self.defaultQuery : "(\(query))"
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(search) AND mediatype:movies AND format:(\"h.264\" OR MPEG4)"),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "creator"),
            URLQueryItem(name: "sort[]", value: "downloads desc"),
            URLQueryItem(name: "rows", value: "30"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "output", value: "json"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try ProviderError.check(response)
        return try JSONDecoder().decode(SearchResponse.self, from: data).response.docs.compactMap(\.remoteVideo)
    }

    func files(for video: RemoteVideo) async throws -> [RemoteVideo.File] {
        guard let detailsURL = video.detailsURL else { return video.files }
        let (data, response) = try await URLSession.shared.data(from: detailsURL)
        try ProviderError.check(response)

        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        let identifier = detailsURL.lastPathComponent
        let files = metadata.files.compactMap { file -> RemoteVideo.File? in
            guard file.name.lowercased().hasSuffix(".mp4"),
                  let url = URL(string: "https://archive.org/download/\(identifier)/")?
                      .appendingPathComponent(file.name)
            else { return nil }
            let width = file.width.flatMap(Int.init) ?? (file.format == "512Kb MPEG4" ? 640 : 1280)
            let height = file.height.flatMap(Int.init) ?? width * 9 / 16
            return RemoteVideo.File(url: url, width: width, height: height)
        }
        guard !files.isEmpty else { throw ResolveError.noPlayableFile }
        return files
    }

    private struct SearchResponse: Decodable {
        let response: Docs
    }

    private struct Docs: Decodable {
        let docs: [Doc]
    }

    private struct Doc: Decodable {
        let identifier: String
        let title: FlexibleString?
        let creator: FlexibleString?

        var remoteVideo: RemoteVideo? {
            guard let page = URL(string: "https://archive.org/details/\(identifier)"),
                  let details = URL(string: "https://archive.org/metadata/\(identifier)")
            else { return nil }
            return RemoteVideo(
                id: "archive-\(identifier)",
                provider: .archive,
                title: title?.value ?? identifier,
                author: creator?.value ?? "Internet Archive",
                pageURL: page,
                thumbnailURL: URL(string: "https://archive.org/services/img/\(identifier)"),
                duration: 0,
                files: [],
                detailsURL: details
            )
        }
    }

    private struct Metadata: Decodable {
        let files: [File]
    }

    private struct File: Decodable {
        let name: String
        let format: String?
        let width: String?
        let height: String?
    }

    /// Archive fields are either a string or an array of strings.
    private struct FlexibleString: Decodable {
        let value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(String.self) {
                value = single
            } else {
                value = try container.decode([String].self).joined(separator: ", ")
            }
        }
    }
}
