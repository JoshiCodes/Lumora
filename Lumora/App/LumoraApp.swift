import SwiftUI

@main
struct LumoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .lumoraEnvironment(delegate)
        } label: {
            MenuBarIcon(wallpaper: delegate.wallpaper)
        }

        Window("Lumora", id: WindowID.main) {
            MainView()
                .lumoraEnvironment(delegate)
        }
        .defaultSize(width: 1080, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(delegate.library.clips.isEmpty ? .presented : .suppressed)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

enum WindowID {
    static let main = "main"
}

private struct MenuBarIcon: View {
    @ObservedObject var wallpaper: WallpaperController

    var body: some View {
        Image(systemName: wallpaper.isUserPaused ? "pause.circle" : "sparkles")
    }
}
