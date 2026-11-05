import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var model: DiscoverModel
    @EnvironmentObject private var downloads: DownloadManager

    @State private var selected: RemoteVideo?

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 18)]
    private let topics = ["Nature", "Space", "Anime", "Cyberpunk", "Rain", "Ocean", "City",
                          "Fantasy", "Games", "Cars", "Sunset", "Abstract"]

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if !model.needsKey { topicBar }
            }
            .navigationTitle("Discover")
            .searchable(text: $model.query, placement: .toolbar, prompt: model.provider.searchPrompt)
            .onSubmit(of: .search) { model.reload() }
            .onChange(of: model.query) { _, query in
                if query.isEmpty { model.reload() }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Picker("Source", selection: $model.provider) {
                        ForEach(ProviderID.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .task {
                if model.results.isEmpty { model.reload() }
            }
            .sheet(item: $selected) { video in
                RemoteVideoDetail(video: video)
            }
            .alert("Download failed", isPresented: failureBinding, presenting: downloads.failure) { _ in
                Button("OK") {}
            } message: { Text($0) }
    }

    private var topicBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(topics, id: \.self) { topic in
                    let selected = model.query.caseInsensitiveCompare(topic) == .orderedSame
                    Button(topic) {
                        model.query = selected ? "" : topic
                        model.reload()
                    }
                    .buttonStyle(TopicChipStyle(isSelected: selected))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var content: some View {
        if model.needsKey {
            KeyPrompt(provider: model.provider)
        } else if model.results.isEmpty, model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.results.isEmpty, let message = model.errorMessage {
            ContentUnavailableView {
                Label("Couldn't load videos", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { model.reload() }
            }
        } else if model.results.isEmpty, !model.query.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(model.results) { video in
                    RemoteVideoCard(video: video)
                        .onTapGesture { selected = video }
                        .onAppear { model.loadMore(after: video) }
                }
            }
            .padding(22)

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 12)
            }

            VStack(spacing: 4) {
                Link("Videos provided by \(model.provider.title)", destination: model.provider.homepage)
                if model.provider == .motionBGs {
                    Text("Fan-made wallpapers, many based on games, anime and films. Meant for personal use on your own desktop.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 18)
        }
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { downloads.failure != nil }, set: { if !$0 { downloads.failure = nil } })
    }
}

struct RemoteVideoCard: View {
    let video: RemoteVideo

    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var library: VideoLibrary
    @State private var isHovering = false

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(.quaternary)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    AsyncImage(url: video.thumbnailURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        DurationBadge(text: badge)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    DownloadButton(video: video)
                        .padding(8)
                        .opacity(isHovering || isBusyOrOwned ? 1 : 0)
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.08)) }
                .shadow(color: .black.opacity(isHovering ? 0.22 : 0.08), radius: isHovering ? 10 : 4, y: 3)
                .scaleEffect(isHovering ? 1.02 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(video.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var badge: String? {
        var parts: [String] = []
        if video.maxWidth >= 3840 { parts.append("4K") }
        if video.duration > 0 { parts.append(Clip.format(video.duration)) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }

    private var isBusyOrOwned: Bool {
        downloads.isDownloading(video) || library.clip(forSourceID: video.id) != nil
    }
}

struct DownloadButton: View {
    let video: RemoteVideo

    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var library: VideoLibrary

    var body: some View {
        Group {
            if let clip = library.clip(forSourceID: video.id) {
                Button {
                    library.activeClipID = clip.id
                } label: {
                    Image(systemName: library.activeClipID == clip.id ? "checkmark" : "play.fill")
                }
                .help(library.activeClipID == clip.id ? "On your desktop" : "Set as Wallpaper")
            } else if let progress = downloads.progress[video.id] {
                Button {
                    downloads.cancel(video)
                } label: {
                    ZStack {
                        Circle().stroke(.white.opacity(0.3), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: max(progress, 0.03))
                            .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.2), value: progress)
                    }
                    .frame(width: 14, height: 14)
                }
                .help("Cancel Download")
            } else {
                Button {
                    downloads.download(video)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .help("Add to Library")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 30, height: 30)
        .background(.black.opacity(0.45), in: Circle())
        .contentShape(Circle())
    }
}

struct KeyPrompt: View {
    let provider: ProviderID

    @EnvironmentObject private var keys: APIKeys
    @EnvironmentObject private var model: DiscoverModel
    @State private var key = ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "key")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tint)
            Text("Connect \(provider.title)")
                .font(.title2.weight(.semibold))
            Text("\(provider.title) has a free API for its video catalog. Create a key, paste it here and you're set. It's only stored on this Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            HStack {
                SecureField("API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit(save)
                Button("Connect", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Link("Get a free key from \(provider.title)", destination: provider.keySignupURL)
                .font(.callout)
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save() {
        keys.setKey(key, for: provider)
        key = ""
        model.reload()
    }
}

struct TopicChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07)))
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
