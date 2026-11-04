import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var library: VideoLibrary
    @EnvironmentObject private var wallpaper: WallpaperController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let clip = library.activeClip {
            Text(clip.name)
            if let reason = wallpaper.pauseReason, !wallpaper.isUserPaused {
                Text(reason)
            }
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

        Button("Open Lumora…") {
            openWindow(id: WindowID.main)
            NSApp.activate()
        }
        .keyboardShortcut("o")

        Divider()

        Button("Quit Lumora") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
