import Foundation

/// Written by the app, read by the screen saver.
///
/// The screen saver runs inside Apple's sandboxed `legacyScreenSaver` host, so it can only
/// see its own container. The app hard-links the chosen videos into that container and
/// describes them here.
struct SaverManifest: Codable, Equatable {
    var clips: [String]
    var fillsScreen: Bool

    static let folderName = "Lumora"
    static let fileName = "saver.json"
    static let hostBundleID = "com.apple.ScreenSaver.Engine.legacyScreenSaver"
}
