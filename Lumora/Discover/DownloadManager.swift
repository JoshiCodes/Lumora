import AppKit

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var progress: [String: Double] = [:]
    @Published var failure: String?

    private let library: VideoLibrary
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]

    init(library: VideoLibrary) {
        self.library = library
    }

    func isDownloading(_ video: RemoteVideo) -> Bool {
        progress[video.id] != nil
    }

    func download(_ video: RemoteVideo, activate: Bool = false) {
        guard tasks[video.id] == nil, library.clip(forSourceID: video.id) == nil,
              let file = video.file(covering: Self.targetPixelWidth)
        else {
            if activate, let clip = library.clip(forSourceID: video.id) {
                library.activeClipID = clip.id
            }
            return
        }

        progress[video.id] = 0
        let id = video.id
        let task = URLSession.shared.downloadTask(with: file.url) { [weak self] location, response, error in
            var downloaded: URL?
            var failure = error
            if let location {
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(file.url.pathExtension.isEmpty ? "mp4" : file.url.pathExtension)
                do {
                    try ProviderError.check(response ?? URLResponse())
                    try FileManager.default.moveItem(at: location, to: destination)
                    downloaded = destination
                } catch {
                    failure = error
                }
            }
            Task { @MainActor in
                await self?.finish(video, file: downloaded, error: failure, activate: activate)
            }
        }

        observations[id] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let value = progress.fractionCompleted
            Task { @MainActor in
                guard let self, let current = self.progress[id], value - current >= 0.01 else { return }
                self.progress[id] = value
            }
        }
        tasks[id] = task
        task.resume()
    }

    func cancel(_ video: RemoteVideo) {
        tasks[video.id]?.cancel()
    }

    private func finish(_ video: RemoteVideo, file: URL?, error: Error?, activate: Bool) async {
        defer {
            tasks[video.id] = nil
            observations[video.id] = nil
            progress[video.id] = nil
        }

        if let error {
            if (error as? URLError)?.code != .cancelled {
                failure = "Couldn't download “\(video.title)”: \(error.localizedDescription)"
            }
            return
        }
        guard let file else { return }

        do {
            let clip = try await library.importDownload(file, name: video.title, sourceID: video.id, credit: video.credit)
            if activate {
                library.activeClipID = clip.id
            }
        } catch {
            failure = error.localizedDescription
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Widest display in physical pixels, capped at 4K.
    static var targetPixelWidth: Int {
        let widest = NSScreen.screens.map { $0.frame.width * $0.backingScaleFactor }.max() ?? 2560
        return min(Int(widest), 3840)
    }
}
