import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var library: VideoLibrary
    @EnvironmentObject private var wallpaper: WallpaperController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let clip = library.activeClip {
            Text(clip.name)
            Button(wallpaper.isUserPaused ? "Resume" : "Pause") {
                wallpaper.togglePause()
            }
            .keyboardShortcut("p")
            Button("Stop") {
                wallpaper.stop()
            }
        } else {
            Text("No wallpaper playing")
        }

        Divider()

        if !library.clips.isEmpty {
            Picker("Wallpaper", selection: $library.activeClipID) {
                ForEach(library.clips) { clip in
                    Text(clip.name).tag(Optional(clip.id))
                }
            }
        }

        Button("Library…") { show(WindowID.library) }
            .keyboardShortcut("l")
        Button("Settings…") { show(WindowID.settings) }
            .keyboardShortcut(",")

        Divider()

        Button("Quit Lumora") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}
