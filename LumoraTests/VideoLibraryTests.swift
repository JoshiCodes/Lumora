import XCTest
@testable import Lumora

final class VideoLibraryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumoraTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testSkipsClipsWhoseVideoIsMissing() throws {
        let kept = Clip(id: UUID(), name: "Waves", fileName: "waves.mov", addedAt: .now, duration: 12)
        let gone = Clip(id: UUID(), name: "Rain", fileName: "rain.mov", addedAt: .now, duration: 4)

        let seed = VideoLibrary(root: root)
        try Data().write(to: seed.videoURL(for: kept))
        try writeIndex(LibraryIndex(clips: [kept, gone], activeClipID: gone.id), to: seed.indexURL)

        let library = VideoLibrary(root: root)
        XCTAssertEqual(library.clips.map(\.id), [kept.id])
        XCTAssertNil(library.activeClipID)
    }

    @MainActor
    func testRenameAndSelectionArePersisted() throws {
        let clip = Clip(id: UUID(), name: "Waves", fileName: "waves.mov", addedAt: .now, duration: 12)

        let seed = VideoLibrary(root: root)
        try Data().write(to: seed.videoURL(for: clip))
        try writeIndex(LibraryIndex(clips: [clip]), to: seed.indexURL)

        let library = VideoLibrary(root: root)
        library.rename(clip, to: "  Ocean at night ")
        library.activeClipID = clip.id

        let reloaded = VideoLibrary(root: root)
        XCTAssertEqual(reloaded.clips.first?.name, "Ocean at night")
        XCTAssertEqual(reloaded.activeClipID, clip.id)
    }

    private func writeIndex(_ index: LibraryIndex, to url: URL) throws {
        try LibraryIndex.encoder.encode(index).write(to: url)
    }
}
