import AVFoundation
import VideoToolbox
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
                optimizeIfWanted(clip)
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
        optimizeIfWanted(clip)
        return clip
    }

    /// Encodes run one after another. A batch import shouldn't start a dozen HEVC encoders at once.
    private func optimizeIfWanted(_ clip: Clip) {
        guard optimizesNewClips else { return }
        let previous = optimizationQueue
        optimizationQueue = Task {
            await previous?.value
            guard let current = self.clip(withID: clip.id) else { return }
            await optimize(current)
        }
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

    /// Set from preferences. New imports and downloads are optimized right after they're added.
    var optimizesNewClips = false
    private var optimizationQueue: Task<Void, Never>?

    func needsOptimization(_ clip: Clip) async -> Bool {
        await Self.plan(for: videoURL(for: clip), targetWidth: NSScreen.widestPixelWidth)?.isWorthIt ?? false
    }

    /// Optimizes every clip that would benefit, one at a time.
    func optimizeAll() async {
        for clip in clips {
            await optimize(clip)
        }
    }

    /// Re-encodes a clip to HEVC at no more than 30 fps, no larger than the widest display and
    /// without audio. Frame rate and resolution decide how much work every frame of playback is.
    func optimize(_ clip: Clip) async {
        guard !optimizing.contains(clip.id) else { return }
        optimizing.insert(clip.id)
        defer { optimizing.remove(clip.id) }

        let source = videoURL(for: clip)
        guard let plan = await Self.plan(for: source, targetWidth: NSScreen.widestPixelWidth), plan.isWorthIt else { return }

        let fileName = "\(clip.id.uuidString)-\(Int(Date().timeIntervalSince1970)).mov"
        let destination = videosURL.appendingPathComponent(fileName)

        do {
            try await Self.encode(from: source, to: destination, plan: plan)
            guard let index = clips.firstIndex(where: { $0.id == clip.id }) else {
                try? fileManager.removeItem(at: destination)
                return
            }
            let old = clips[index]
            clips[index] = Clip(id: old.id, name: old.name, fileName: fileName, addedAt: old.addedAt,
                                duration: old.duration, sourceID: old.sourceID, credit: old.credit)
            save()
            try? fileManager.removeItem(at: source)
        } catch {
            try? fileManager.removeItem(at: destination)
            lastError = "Couldn't optimize “\(clip.name)”: \(error.localizedDescription)"
        }
    }

    struct OptimizationPlan: Sendable {
        var size: CGSize
        var scale: CGFloat
        var frameRate: Float
        var hardwareDecoded: Bool
        var isHEVC = false

        var capsFrameRate: Bool { frameRate > 31 }

        /// Skip clips that would only change by a few percent; re-encoding always costs a little quality.
        var isWorthIt: Bool { scale < 0.9 || capsFrameRate || !hardwareDecoded }
    }

    nonisolated static func plan(for url: URL, targetWidth: Int) async -> OptimizationPlan? {
        let asset = AVURLAsset(url: url)
        guard let video = try? await asset.loadTracks(withMediaType: .video).first,
              let loaded = try? await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
        else { return nil }
        let (naturalSize, transform, frameRate, formats) = loaded

        let oriented = naturalSize.applying(transform)
        let size = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let codec = formats.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
        let scale = size.width > CGFloat(targetWidth) ? CGFloat(targetWidth) / size.width : 1

        return OptimizationPlan(size: size, scale: scale, frameRate: frameRate,
                                hardwareDecoded: VTIsHardwareDecodeSupported(codec),
                                isHEVC: codec == kCMVideoCodecType_HEVC)
    }

    nonisolated static func encode(from source: URL, to destination: URL, plan: OptimizationPlan) async throws {
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ImportError.unsupported(source.lastPathComponent)
        }
        let (range, transform) = try await video.load(.timeRange, .preferredTransform)

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ImportError.unsupported(source.lastPathComponent)
        }
        try track.insertTimeRange(range, of: video, at: .zero)

        func even(_ value: CGFloat) -> CGFloat { CGFloat(max(2, Int(value.rounded()) / 2 * 2)) }
        let renderSize = CGSize(width: even(plan.size.width * plan.scale), height: even(plan.size.height * plan.scale))
        let fps = plan.frameRate > 0 ? min(30, Int32(plan.frameRate.rounded())) : 30

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform.concatenating(CGAffineTransform(scaleX: plan.scale, y: plan.scale)), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: range.duration)
        instruction.layerInstructions = [layer]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: max(1, fps))
        videoComposition.instructions = [instruction]

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
