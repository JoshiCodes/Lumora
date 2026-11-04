import SwiftUI

enum Pane: String, Hashable {
    case nowPlaying, library, discover, screenSaver, settings
}

struct MainView: View {
    @EnvironmentObject private var library: VideoLibrary
    @SceneStorage("pane") private var pane: Pane = .nowPlaying

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Wallpaper") {
                    Label("Now Playing", systemImage: "play.rectangle").tag(Pane.nowPlaying)
                    Label {
                        Text("Library")
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .badge(library.clips.count)
                    .tag(Pane.library)
                    Label("Discover", systemImage: "sparkle.magnifyingglass").tag(Pane.discover)
                }
                Section("Mac") {
                    Label("Screen Saver", systemImage: "moon.stars").tag(Pane.screenSaver)
                    Label("Settings", systemImage: "gearshape").tag(Pane.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            switch pane {
            case .nowPlaying: NowPlayingView(pane: $pane)
            case .library: LibraryView()
            case .discover: DiscoverView()
            case .screenSaver: ScreenSaverPane()
            case .settings: SettingsPane()
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .onAppear {
            // Behave like a regular app while the window is open, then go back to the menu bar.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var selection: Binding<Pane?> {
        Binding(get: { pane }, set: { if let value = $0 { pane = value } })
    }
}
