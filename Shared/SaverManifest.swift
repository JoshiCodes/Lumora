import Foundation

/// Written by the app, read by the screen saver.
///
/// The screen saver runs inside Apple's sandboxed `legacyScreenSaver` host, which can't see
/// Lumora's library and doesn't let other apps write into its container. What it can always
/// read is its own bundle, so the app hard-links the chosen videos into
/// `Lumora.saver/Contents/Resources/Clips` and describes them in this file next to them.
struct SaverManifest: Codable, Equatable {
    var clips: [String]
    var fillsScreen: Bool

    static let folderName = "Clips"
    static let fileName = "saver.json"
}
