import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences: Preferences
    let library: VideoLibrary
    let wallpaper: WallpaperController
    let apiKeys: APIKeys
    let discover: DiscoverModel
    let downloads: DownloadManager
    let screenSaver: ScreenSaverManager
    let performance: PerformanceMonitor
    let updater: Updater

    override init() {
        preferences = Preferences()
        library = VideoLibrary()
        wallpaper = WallpaperController(library: library, preferences: preferences)
        apiKeys = APIKeys()
        discover = DiscoverModel(keys: apiKeys)
        downloads = DownloadManager(library: library)
        screenSaver = ScreenSaverManager(library: library, preferences: preferences)
        performance = PerformanceMonitor(library: library, wallpaper: wallpaper)
        updater = Updater()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        wallpaper.start()
        screenSaver.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}

extension View {
    func lumoraEnvironment(_ delegate: AppDelegate) -> some View {
        environmentObject(delegate.preferences)
            .environmentObject(delegate.library)
            .environmentObject(delegate.wallpaper)
            .environmentObject(delegate.apiKeys)
            .environmentObject(delegate.discover)
            .environmentObject(delegate.downloads)
            .environmentObject(delegate.screenSaver)
            .environmentObject(delegate.performance)
            .environmentObject(delegate.updater)
    }
}
