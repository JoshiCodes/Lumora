import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences: Preferences
    let library: VideoLibrary
    let wallpaper: WallpaperController

    override init() {
        preferences = Preferences()
        library = VideoLibrary()
        wallpaper = WallpaperController(library: library, preferences: preferences)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        wallpaper.start()
    }
}
