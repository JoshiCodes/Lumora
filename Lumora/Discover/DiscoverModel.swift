import Foundation

@MainActor
final class DiscoverModel: ObservableObject {
    @Published var provider: ProviderID = .nasa {
        didSet { if oldValue != provider { reload() } }
    }
    @Published var query = ""
    @Published private(set) var results: [RemoteVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var needsKey = false

    let keys: APIKeys
    private var page = 1
    private var reachedEnd = false
    private var generation = 0

    init(keys: APIKeys) {
        self.keys = keys
    }

    func reload() {
        generation += 1
        page = 1
        reachedEnd = false
        results = []
        errorMessage = nil
        isLoading = false
        loadNextPage()
    }

    func loadMore(after video: RemoteVideo) {
        guard video.id == results.last?.id else { return }
        loadNextPage()
    }

    private func loadNextPage() {
        guard !isLoading, !reachedEnd else { return }
        let key = keys.key(for: provider) ?? ""
        guard !provider.needsKey || !key.isEmpty else {
            needsKey = true
            return
        }
        needsKey = false
        isLoading = true

        let request = (provider, query.trimmingCharacters(in: .whitespacesAndNewlines), page, generation)
        Task {
            do {
                let videos = try await request.0.client.videos(matching: request.1, page: request.2, apiKey: key)
                guard request.3 == generation else { return }
                let known = Set(results.map(\.id))
                results += videos.filter { !known.contains($0.id) }
                page += 1
                reachedEnd = videos.isEmpty
            } catch {
                guard request.3 == generation else { return }
                if case ProviderError.invalidKey = error { needsKey = true }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
