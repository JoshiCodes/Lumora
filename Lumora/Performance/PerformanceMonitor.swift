import AVFoundation
import Darwin
import IOKit
import VideoToolbox

struct PerformanceSample: Identifiable {
    let id = UUID()
    let date: Date
    /// Lumora's own CPU time. 100 means one full core, like Activity Monitor.
    let appCPU: Double
    /// All processes together, same scale.
    let systemCPU: Double
    /// System-wide GPU utilization in percent, if the driver reports it.
    let gpu: Double?
    let memory: UInt64
}

struct VideoDetails: Equatable {
    var resolution: CGSize
    var frameRate: Float
    var codec: String
    var hardwareDecoding: Bool
    var hasAudio: Bool
    var fileSize: Int64
}

struct ImpactResult: Equatable {
    var cpu: Double
    var gpu: Double?
    var date: Date
}

@MainActor
final class PerformanceMonitor: ObservableObject {
    @Published private(set) var samples: [PerformanceSample] = []
    @Published private(set) var video: VideoDetails?
    @Published private(set) var droppedFrames: Int?
    @Published private(set) var impact: ImpactResult?
    @Published private(set) var impactProgress: Double?
    @Published var impactError: String?

    private let library: VideoLibrary
    private let wallpaper: WallpaperController
    private let host = mach_host_self()
    private let coreCount = Double(ProcessInfo.processInfo.activeProcessorCount)

    private var timer: Timer?
    private var viewers = 0
    private var lastProcessTime: Double?
    private var lastSystemTicks: (busy: Double, total: Double)?
    private var lastSampleDate: Date?

    static let interval: TimeInterval = 2
    static let window = 90

    init(library: VideoLibrary, wallpaper: WallpaperController) {
        self.library = library
        self.wallpaper = wallpaper
    }

    var latest: PerformanceSample? { samples.last }

    // MARK: - Sampling

    /// Sampling only runs while someone is looking, so the monitor costs nothing otherwise.
    func beginObserving() {
        viewers += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer?.tolerance = 0.5
    }

    func endObserving() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
        lastProcessTime = nil
        lastSystemTicks = nil
        lastSampleDate = nil
    }

    private func sample() {
        let now = Date()
        let processTime = Self.processCPUTime()
        let ticks = systemTicks()
        defer {
            lastProcessTime = processTime
            lastSystemTicks = ticks
            lastSampleDate = now
        }

        guard let lastProcessTime, let lastSystemTicks, let lastSampleDate else { return }
        let elapsed = now.timeIntervalSince(lastSampleDate)
        guard elapsed > 0 else { return }

        let appCPU = (processTime - lastProcessTime) / elapsed * 100
        var systemCPU = 0.0
        if let ticks, ticks.total > lastSystemTicks.total {
            systemCPU = (ticks.busy - lastSystemTicks.busy) / (ticks.total - lastSystemTicks.total) * 100 * coreCount
        }

        samples.append(PerformanceSample(date: now, appCPU: max(0, appCPU), systemCPU: max(0, systemCPU),
                                         gpu: Self.gpuUtilization(), memory: Self.memoryFootprint()))
        if samples.count > Self.window {
            samples.removeFirst(samples.count - Self.window)
        }

        if let event = wallpaper.player?.currentItem?.accessLog()?.events.last, event.numberOfDroppedVideoFrames >= 0 {
            droppedFrames = event.numberOfDroppedVideoFrames
        } else {
            droppedFrames = nil
        }
    }

    // MARK: - Video

    func refreshVideoDetails() async {
        guard let clip = library.activeClip else {
            video = nil
            return
        }
        let url = library.videoURL(for: clip)
        video = await Self.details(for: url)
    }

    private nonisolated static func details(for url: URL) async -> VideoDetails? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let loaded = try? await track.load(.naturalSize, .preferredTransform,
                                                 .nominalFrameRate, .formatDescriptions)
        else { return nil }
        let (size, transform, rate, formats) = loaded

        let oriented = size.applying(transform)
        let subtype = formats.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
        let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        return VideoDetails(
            resolution: CGSize(width: abs(oriented.width), height: abs(oriented.height)),
            frameRate: rate,
            codec: codecName(subtype),
            hardwareDecoding: VTIsHardwareDecodeSupported(subtype),
            hasAudio: !audio.isEmpty,
            fileSize: bytes
        )
    }

    private nonisolated static func codecName(_ code: FourCharCode) -> String {
        switch code {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha: return "HEVC"
        case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy,
             kCMVideoCodecType_AppleProRes4444: return "ProRes"
        case kCMVideoCodecType_VP9: return "VP9"
        case kCMVideoCodecType_AV1: return "AV1"
        default:
            let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
            return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
        }
    }

    // MARK: - Impact test

    /// Compares system load with and without playback. This catches work that happens outside
    /// Lumora's process, like hardware decoding and compositing in the window server.
    func measureImpact() async {
        guard impactProgress == nil else { return }
        guard wallpaper.isPlaying else {
            impactError = "Start a wallpaper first. The test compares playing against paused."
            return
        }

        impactProgress = 0
        beginObserving()
        defer {
            wallpaper.holdForMeasurement(false)
            endObserving()
            impactProgress = nil
        }

        let phase: TimeInterval = 10
        let playing = await measureLoad(for: phase, progressOffset: 0)
        wallpaper.holdForMeasurement(true)
        try? await Task.sleep(for: .seconds(1))
        let paused = await measureLoad(for: phase, progressOffset: 0.5)

        var gpu: Double?
        if let busy = playing.gpu, let idle = paused.gpu {
            gpu = max(0, busy - idle)
        }
        impact = ImpactResult(cpu: max(0, playing.cpu - paused.cpu), gpu: gpu, date: .now)
    }

    private func measureLoad(for duration: TimeInterval, progressOffset: Double) async -> (cpu: Double, gpu: Double?) {
        let start = systemTicks()
        var gpuReadings: [Double] = []
        let steps = Int(duration * 2)
        for step in 0..<steps {
            try? await Task.sleep(for: .milliseconds(500))
            if let gpu = Self.gpuUtilization() { gpuReadings.append(gpu) }
            impactProgress = progressOffset + 0.5 * Double(step + 1) / Double(steps)
        }
        let end = systemTicks()

        var cpu = 0.0
        if let start, let end, end.total > start.total {
            cpu = (end.busy - start.busy) / (end.total - start.total) * 100 * coreCount
        }
        let gpu = gpuReadings.isEmpty ? nil : gpuReadings.reduce(0, +) / Double(gpuReadings.count)
        return (cpu, gpu)
    }

    // MARK: - System readings

    private nonisolated static func processCPUTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    private nonisolated static func memoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private func systemTicks() -> (busy: Double, total: Double)? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = Double(load.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// Reads "Device Utilization %" from the GPU driver's statistics in the I/O Registry.
    private nonisolated static func gpuUtilization() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var value: Double?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            guard value == nil,
                  let property = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString,
                                                                 kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let stats = property as? [String: Any],
                  let utilization = stats["Device Utilization %"] as? NSNumber
            else { continue }
            value = utilization.doubleValue
        }
        return value
    }
}
