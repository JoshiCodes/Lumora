import Foundation

/// motionbgs.com has no API, so this reads its listing pages. Kept deliberately small:
/// one request per page, downloads go through the site's own download links.
struct MotionBGsProvider: VideoProvider {
    private static let base = URL(string: "https://motionbgs.com")!

    func videos(matching query: String, page: Int, apiKey: String) async throws -> [RemoteVideo] {
        let url: URL
        if query.isEmpty {
            url = page == 1 ? Self.base : Self.base.appendingPathComponent("\(page)/")
        } else {
            var components = URLComponents(url: Self.base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "page", value: String(page))]
            url = components.url!
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        try ProviderError.check(response)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        return Self.parse(html)
    }

    static func parse(_ html: String) -> [RemoteVideo] {
        let item = #/<a title="(?<title>[^"]*?) live wallpaper" href=\/(?<slug>[a-z0-9-]+)>(?<body>.*?)<\/a>/#
            .dotMatchesNewlines()
        let thumbnail = #/\/i\/c\/546x308\/media\/(?<id>\d+)\/(?<file>[^ >]+?)\.jpg(?=[ >])/#

        var seen = Set<String>()
        return html.matches(of: item).compactMap { match -> RemoteVideo? in
            let body = String(match.output.body)
            guard let thumb = body.firstMatch(of: thumbnail) else { return nil }
            let id = String(thumb.output.id)
            guard seen.insert(id).inserted else { return nil }

            let slug = String(match.output.slug)
            // "black-hole.3840x2160" → "black-hole"; the preview clip uses that name.
            let baseName = String(thumb.output.file).replacing(#/\.\d+x\d+$/#, with: "")
            let has4K = body.contains(">4K<") || body.contains("> 4K <")

            var files = [RemoteVideo.File(url: base.appendingPathComponent("dl/hd/\(id)/"), width: 1920, height: 1080)]
            if has4K {
                files.append(RemoteVideo.File(url: base.appendingPathComponent("dl/4k/\(id)/"), width: 3840, height: 2160))
            }
            files.append(RemoteVideo.File(url: base.appendingPathComponent("media/\(id)/\(baseName).960x540.mp4"),
                                          width: 960, height: 540))

            return RemoteVideo(
                id: "motionbgs-\(id)",
                provider: .motionBGs,
                title: decodeEntities(String(match.output.title)),
                author: "MotionBGs",
                pageURL: base.appendingPathComponent(slug),
                thumbnailURL: base.appendingPathComponent("i/c/546x308/media/\(id)/\(thumb.output.file).jpg"),
                duration: 0,
                files: files
            )
        }
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, character) in [("&amp;", "&"), ("&#39;", "'"), ("&#039;", "'"), ("&quot;", "\""),
                                    ("&lt;", "<"), ("&gt;", ">"), ("&apos;", "'")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
