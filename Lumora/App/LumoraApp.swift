import SwiftUI

@main
struct LumoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .lumoraEnvironment(delegate)
        } label: {
            Image(systemName: "sparkles")
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
