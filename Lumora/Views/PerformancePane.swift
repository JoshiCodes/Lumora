import Charts
import SwiftUI

struct PerformancePane: View {
    @EnvironmentObject private var monitor: PerformanceMonitor
    @EnvironmentObject private var wallpaper: WallpaperController
    @EnvironmentObject private var library: VideoLibrary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                tiles
                chart
                HStack(alignment: .top, spacing: 18) {
                    videoCard
                    impactCard
                }
                Text("Lumora's CPU and memory only cover its own process. Hardware decoding and drawing the video on screen partly happen in macOS services on Lumora's behalf. The impact test captures those too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Performance")
        .onAppear { monitor.beginObserving() }
        .onDisappear { monitor.endObserving() }
        .task(id: library.activeClip?.fileName) { await monitor.refreshVideoDetails() }
        .alert("Impact Test", isPresented: errorBinding, presenting: monitor.impactError) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }

    // MARK: - Tiles

    private var tiles: some View {
        HStack(spacing: 14) {
            MetricTile(title: "Lumora CPU",
                       value: monitor.latest.map { percent($0.appCPU) } ?? "–",
                       detail: "100 % is one core")
            MetricTile(title: "Memory",
                       value: monitor.latest.map { ByteCountFormatter.string(fromByteCount: Int64($0.memory), countStyle: .memory) } ?? "–",
                       detail: "Lumora's footprint")
            MetricTile(title: "GPU",
                       value: monitor.latest?.gpu.map(percent) ?? "–",
                       detail: "Whole system")
            MetricTile(title: "Wallpaper",
                       value: wallpaper.isPlaying ? "Playing" : (library.activeClip == nil ? "Off" : "Paused"),
                       detail: wallpaper.isPlaying ? "Live on your desktop" : wallpaper.pauseReason ?? "Nothing selected")
        }
    }

    // MARK: - Chart

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 3 Minutes")
                    .font(.headline)
                Spacer()
                if let latest = monitor.latest {
                    Text("System CPU \(percent(latest.systemCPU))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if monitor.samples.count < 2 {
                Text("Collecting data…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    ForEach(monitor.samples) { sample in
                        LineMark(x: .value("Time", sample.date), y: .value("Percent", sample.appCPU))
                            .foregroundStyle(by: .value("Series", "Lumora CPU"))
                            .interpolationMethod(.monotone)
                        if let gpu = sample.gpu {
                            LineMark(x: .value("Time", sample.date), y: .value("Percent", gpu))
                                .foregroundStyle(by: .value("Series", "GPU"))
                                .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartForegroundStyleScale(["Lumora CPU": Color.accentColor, "GPU": Color.orange])
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text("\(Int(number)) %")
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 200)
            }
        }
        .card()
    }

    // MARK: - Video

    private var videoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Video")
                .font(.headline)

            if let video = monitor.video {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    row("Resolution", "\(Int(video.resolution.width)) × \(Int(video.resolution.height))")
                    row("Frame rate", String(format: "%.0f fps", video.frameRate))
                    row("Codec", video.codec)
                    row("Decoding", video.hardwareDecoding ? "Hardware" : "Software")
                    row("Audio", video.hasAudio ? "Skipped during playback" : "None")
                    row("File size", ByteCountFormatter.string(fromByteCount: video.fileSize, countStyle: .file))
                    if let dropped = monitor.droppedFrames {
                        row("Dropped frames", "\(dropped)")
                    }
                }
                .font(.callout)

                ForEach(hints(for: video), id: \.self) { hint in
                    Label(hint, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let clip = library.activeClip, needsOptimizing(video) {
                    if library.optimizing.contains(clip.id) {
                        ProgressView("Optimizing…")
                            .controlSize(.small)
                    } else {
                        Button("Optimize This Video") {
                            Task { await library.optimize(clip) }
                        }
                        .help("Re-encodes to HEVC at up to 30 fps and your display's resolution, without audio. Replaces the original in your library.")
                    }
                }
            } else {
                Text(library.activeClip == nil ? "No wallpaper selected." : "Reading video…")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func needsOptimizing(_ video: VideoDetails) -> Bool {
        video.frameRate > 31 || !video.hardwareDecoding
            || video.resolution.width > CGFloat(NSScreen.widestPixelWidth) / 0.9
    }

    private func hints(for video: VideoDetails) -> [String] {
        var hints: [String] = []
        let display = NSScreen.screens.map { $0.frame.width * $0.backingScaleFactor }.max() ?? 0
        if display > 0, video.resolution.width > display * 1.2 {
            hints.append("This video is larger than your display. A smaller version would need less decoding.")
        }
        if !video.hardwareDecoding {
            hints.append("This codec is decoded in software. H.264 or HEVC is much lighter.")
        }
        if video.frameRate > 31 {
            hints.append("At \(Int(video.frameRate.rounded())) fps there is about twice as much to decode as at 30 fps.")
        }
        return hints
    }

    // MARK: - Impact

    private var impactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Impact Test")
                .font(.headline)
            Text("Measures the whole Mac for 10 seconds with your wallpaper playing and 10 seconds paused, then shows the difference. Close busy apps first for a cleaner result.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let progress = monitor.impactProgress {
                ProgressView(value: progress) {
                    Text(progress < 0.5 ? "Measuring while playing…" : "Measuring while paused…")
                        .font(.caption)
                }
            } else {
                if let impact = monitor.impact {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(impactSummary(impact))
                            .font(.title3.weight(.semibold))
                        Text("Measured \(impact.date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(monitor.impact == nil ? "Run Test" : "Run Again") {
                    Task { await monitor.measureImpact() }
                }
                .disabled(library.activeClip == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func impactSummary(_ impact: ImpactResult) -> String {
        var parts = ["\(percent(impact.cpu)) CPU"]
        if let gpu = impact.gpu {
            parts.append("\(percent(gpu)) GPU")
        }
        return parts.joined(separator: " and ")
    }

    // MARK: - Helpers

    private func percent(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f %%", value) : String(format: "%.0f %%", value)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { monitor.impactError != nil }, set: { if !$0 { monitor.impactError = nil } })
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

extension View {
    func card() -> some View {
        padding(16)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
