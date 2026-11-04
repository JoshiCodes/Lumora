import SwiftUI

@main
struct LumoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Lumora", systemImage: "sparkles") {
            MenuContent()
                .environmentObject(delegate.library)
                .environmentObject(delegate.wallpaper)
        }

        Window("Lumora", id: WindowID.library) {
            LibraryView()
                .environmentObject(delegate.library)
                .environmentObject(delegate.wallpaper)
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 820, height: 560)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(delegate.library.clips.isEmpty ? .presented : .suppressed)

        Window("Settings", id: WindowID.settings) {
            SettingsView()
                .environmentObject(delegate.preferences)
                .environmentObject(delegate.library)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

enum WindowID {
    static let library = "library"
    static let settings = "settings"
}
