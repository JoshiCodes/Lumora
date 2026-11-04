import Foundation

enum ProviderID: String, CaseIterable, Identifiable, Codable {
    case pexels
    case pixabay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pexels: "Pexels"
        case .pixabay: "Pixabay"
        }
    }

    var homepage: URL {
        switch self {
        case .pexels: URL(string: "https://www.pexels.com")!
        case .pixabay: URL(string: "https://pixabay.com")!
        }
    }

    var keySignupURL: URL {
        switch self {
        case .pexels: URL(string: "https://www.pexels.com/api/new/")!
        case .pixabay: URL(string: "https://pixabay.com/api/docs/")!
        }
    }

    var client: VideoProvider {
        switch self {
        case .pexels: PexelsProvider()
        case .pixabay: PixabayProvider()
        }
    }
}

struct RemoteVideo: Identifiable, Hashable {
    struct File: Hashable {
        let url: URL
        let width: Int
        let height: Int
    }

    let id: String
    let provider: ProviderID
    let title: String
    let author: String
    let pageURL: URL
    let thumbnailURL: URL?
    let duration: TimeInterval
    let files: [File]

    var credit: String { "\(author) on \(provider.title)" }

    var maxWidth: Int { files.map(\.width).max() ?? 0 }

    /// Smallest file that still covers `pixelWidth`, so we never decode more pixels than the display shows.
    func file(covering pixelWidth: Int) -> File? {
        let sorted = files.sorted { $0.width < $1.width }
        return sorted.first { $0.width >= pixelWidth } ?? sorted.last
    }

    var previewFile: File? { file(covering: 960) }
}

protocol VideoProvider {
    func videos(matching query: String, page: Int, apiKey: String) async throws -> [RemoteVideo]
}

enum ProviderError: LocalizedError {
    case invalidKey
    case rateLimited
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidKey: "The API key was rejected. Check it in Settings."
        case .rateLimited: "Too many requests. Give it a minute and try again."
        case .server(let code): "The server answered with status \(code)."
        }
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw ProviderError.invalidKey
        case 429: throw ProviderError.rateLimited
        default: throw ProviderError.server(http.statusCode)
        }
    }
}
