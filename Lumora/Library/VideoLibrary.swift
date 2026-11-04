import AVFoundation
import AppKit

enum ImportError: LocalizedError {
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let name): "“\(name)” doesn't contain a playable video track."
        }
    }
}

@MainActor
final class VideoLibrary: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    @Published var activeClipID: UUID? {
        didSet { if oldValue != activeClipID { save() } }
    }
    @Published private(set) var importsInFlight = 0
    @Published var lastError: String?
    @Published private(set) var optimizing: Set<UUID> = []

    let root: URL
    private let fileManager = FileManager.default
    private var isLoading = false

    nonisolated static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumora", isDirectory: true)
    }

    init(root: URL = VideoLibrary.defaultRoot) {
        self.root = root
        for directory in [videosURL, thumbnailsURL, stillsURL] {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        load()
    }

    var videosURL: URL { root.appendingPathComponent("Videos", isDirectory: true) }
    var thumbnailsURL: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }
    var stillsURL: URL { root.appendingPathComponent("Stills", isDirectory: true) }
    var indexURL: URL { root.appendingPathComponent(LibraryIndex.fileName) }

    var isImporting: Bool { importsInFlight > 0 }
    var activeClip: Clip? { clips.first { $0.id == activeClipID } }

    func clip(withID id: UUID) -> Clip? {
        clips.first { $0.id == id }
    }

    func clip(forSourceID sourceID: String) -> Clip? {
        clips.first { $0.sourceID == sourceID }
    }

    func videoURL(for clip: Clip) -> URL {
        videosURL.appendingPathComponent(clip.fileName)
    }

    func thumbnailURL(for clip: Clip) -> URL {
        thumbnailsURL.appendingPathComponent("\(clip.id.uuidString).jpg")
    }

    func stillURL(for clip: Clip) -> URL {
        stillsURL.appendingPathComponent("\(clip.id.uuidString).jpg")
    }

    /// Bytes used by the imported videos.
    func storageSize() -> Int64 {
        let files = (try? fileManager.contentsOfDirectory(at: videosURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    // MARK: - Editing

    func importFiles(_ urls: [URL]) async {
        for url in urls {
            importsInFlight += 1
            do {
                let clip = try await importFile(url, move: false)
                clips.append(clip)
                save()
            } catch {
                lastError = error.localizedDescription
            }
            importsInFlight -= 1
        }
    }

    @discardableResult
    func importDownload(_ file: URL, name: String, sourceID: String, credit: String?) async throws -> Clip {
        importsInFlight += 1
        defer { importsInFlight -= 1 }

        var clip = try await importFile(file, move: true)
        clip.name = name
        clip.sourceID = sourceID
        clip.credit = credit
        clips.append(clip)
        save()
        return clip
    }

    func rename(_ clip: Clip, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[index].name = trimmed
        save()
    }

    func remove(_ clip: Clip) {
        if activeClipID == clip.id {
            activeClipID = nil
        }
        clips.removeAll { $0.id == clip.id }
        for url in [videoURL(for: clip), thumbnailURL(for: clip), stillURL(for: clip)] {
            try? fileManager.removeItem(at: url)
        }
        save()
    }

    // MARK: - Optimizing

    /// Re-encodes a clip to HEVC at no more than 30 fps without audio.
    /// High frame rates are the most common reason a wallpaper is expensive to play.
    func optimize(_ clip: Clip) async {
        guard !optimizing.contains(clip.id) else { return }
        optimizing.insert(clip.id)
        defer { optimizing.remove(clip.id) }

        let source = videoURL(for: clip)
        let fileName = "\(clip.id.uuidString)-\(Int(Date().timeIntervalSince1970)).mov"
        let destination = videosURL.appendingPathComponent(fileName)

        do {
            try await Self.encodeOptimized(from: source, to: destination)
            guard let index = clips.firstIndex(where: { $0.id == clip.id }) else {
                try? fileManager.removeItem(at: destination)
                return
            }
            clips[index] = Clip(id: clip.id, name: clips[index].name, fileName: fileName,
                                addedAt: clip.addedAt, duration: clip.duration,
                                sourceID: clip.sourceID, credit: clip.credit)
            save()
            try? fileManager.removeItem(at: source)
        } catch {
            try? fileManager.removeItem(at: destination)
            lastError = "Couldn't optimize “\(clip.name)”: \(error.localizedDescription)"
        }
    }

    private nonisolated static func encodeOptimized(from source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ImportError.unsupported(source.lastPathComponent)
        }
        let (range, transform, frameRate) = try await video.load(.timeRange, .preferredTransform, .nominalFrameRate)

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ImportError.unsupported(source.lastPathComponent)
        }
        try track.insertTimeRange(range, of: video, at: .zero)
        track.preferredTransform = transform

        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        if frameRate > 31 {
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw ImportError.unsupported(source.lastPathComponent)
        }
        export.videoComposition = videoComposition
        try await export.export(to: destination, as: .mov)
    }

    // MARK: - Import

    private func importFile(_ source: URL, move: Bool) async throws -> Clip {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let probe = AVURLAsset(url: source)
        let (playable, duration) = try await probe.load(.isPlayable, .duration)
        let videoTracks = try await probe.loadTracks(withMediaType: .video)
        guard playable, !videoTracks.isEmpty else {
            throw ImportError.unsupported(source.lastPathComponent)
        }

        let id = UUID()
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let destination = videosURL.appendingPathComponent("\(id.uuidString).\(ext)")
        try await Task.detached(priority: .userInitiated) {
            if move {
                try FileManager.default.moveItem(at: source, to: destination)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }.value

        let clip = Clip(
            id: id,
            name: source.deletingPathExtension().lastPathComponent,
            fileName: destination.lastPathComponent,
            addedAt: .now,
            duration: duration.seconds
        )

        let asset = AVURLAsset(url: destination)
        let posterTime = CMTime(seconds: min(1, clip.duration / 2), preferredTimescale: 600)
        try? await writeFrame(of: asset, at: posterTime, to: thumbnailURL(for: clip),
                              maxSize: CGSize(width: 640, height: 640), quality: 0.8)
        try? await writeFrame(of: asset, at: .zero, to: stillURL(for: clip),
                              maxSize: .zero, quality: 0.92)
        return clip
    }

    private func writeFrame(of asset: AVAsset, at time: CMTime, to url: URL,
                            maxSize: CGSize, quality: Double) async throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        generator.requestedTimeToleranceBefore = .zero
        let (image, _) = try await generator.image(at: time)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else { return }
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? LibraryIndex.decoder.decode(LibraryIndex.self, from: data)
        else { return }

        isLoading = true
        defer { isLoading = false }
        clips = index.clips.filter { fileManager.fileExists(atPath: videoURL(for: $0).path) }
        activeClipID = clips.contains { $0.id == index.activeClipID } ? index.activeClipID : nil
    }

    private func save() {
        guard !isLoading else { return }
        do {
            let data = try LibraryIndex.encoder.encode(LibraryIndex(clips: clips, activeClipID: activeClipID))
            try data.write(to: indexURL, options: .atomic)
        } catch {
            lastError = "Couldn't save the library: \(error.localizedDescription)"
        }
    }
}
