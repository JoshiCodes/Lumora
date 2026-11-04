import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: VideoLibrary
    @EnvironmentObject private var wallpaper: WallpaperController

    @State private var showingImporter = false
    @State private var isDropTargeted = false
    @State private var clipToRename: Clip?
    @State private var draftName = ""

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 18)]

    var body: some View {
        Group {
            if library.clips.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let movies = urls.filter(\.isMovie)
            guard !movies.isEmpty else { return false }
            Task { await library.importFiles(movies) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .toolbar { toolbar }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.movie], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await library.importFiles(urls) }
        }
        .alert("Rename Video", isPresented: renameBinding) {
            TextField("Name", text: $draftName)
            Button("Rename") {
                if let clip = clipToRename { library.rename(clip, to: draftName) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Something went wrong", isPresented: errorBinding, presenting: library.lastError) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if library.isImporting {
                ProgressView()
                    .controlSize(.small)
                    .help("Importing…")
            }
            if library.activeClip != nil {
                Button {
                    wallpaper.togglePause()
                } label: {
                    Label(wallpaper.isUserPaused ? "Resume" : "Pause",
                          systemImage: wallpaper.isUserPaused ? "play.fill" : "pause.fill")
                }
                Button {
                    wallpaper.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            }
            Button {
                showingImporter = true
            } label: {
                Label("Add Videos", systemImage: "plus")
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(library.clips) { clip in
                    ClipCard(clip: clip,
                             thumbnailURL: library.thumbnailURL(for: clip),
                             isActive: clip.id == library.activeClipID)
                        .onTapGesture { library.activeClipID = clip.id }
                        .contextMenu { menu(for: clip) }
                }
            }
            .padding(22)
        }
    }

    @ViewBuilder
    private func menu(for clip: Clip) -> some View {
        Button("Set as Wallpaper") { library.activeClipID = clip.id }
        Button("Rename…") {
            draftName = clip.name
            clipToRename = clip
        }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([library.videoURL(for: clip)])
        }
        Divider()
        Button("Remove from Library", role: .destructive) { library.remove(clip) }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your library is empty", systemImage: "film.stack")
        } description: {
            Text("Drop a video here or add one from Finder.\nMP4 and MOV in H.264 or HEVC work best.")
        } actions: {
            Button("Add Videos…") { showingImporter = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { clipToRename != nil }, set: { if !$0 { clipToRename = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })
    }
}

private extension URL {
    var isMovie: Bool {
        UTType(filenameExtension: pathExtension)?.conforms(to: .movie) ?? false
    }
}
