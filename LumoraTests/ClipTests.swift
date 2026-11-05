import XCTest
@testable import Lumora

final class ClipTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(Clip.format(0), "0:00")
        XCTAssertEqual(Clip.format(9.4), "0:09")
        XCTAssertEqual(Clip.format(75), "1:15")
        XCTAssertEqual(Clip.format(3725), "1:02:05")
        XCTAssertEqual(Clip.format(.nan), "0:00")
    }
}

final class OptimizationPlanTests: XCTestCase {
    func testSixtyFramesIsWorthOptimizing() {
        let plan = VideoLibrary.OptimizationPlan(size: CGSize(width: 1920, height: 1080), scale: 1,
                                                 frameRate: 59.94, hardwareDecoded: true)
        XCTAssertTrue(plan.isWorthIt)
    }

    func testEfficientClipIsLeftAlone() {
        let plan = VideoLibrary.OptimizationPlan(size: CGSize(width: 3840, height: 2160), scale: 0.95,
                                                 frameRate: 30, hardwareDecoded: true)
        XCTAssertFalse(plan.isWorthIt)
    }

    func testSoftwareCodecIsWorthOptimizing() {
        let plan = VideoLibrary.OptimizationPlan(size: CGSize(width: 1920, height: 1080), scale: 1,
                                                 frameRate: 24, hardwareDecoded: false)
        XCTAssertTrue(plan.isWorthIt)
    }
}

final class RemoteFileTests: XCTestCase {
    private func file(_ width: Int) -> RemoteVideo.File {
        RemoteVideo.File(url: URL(string: "https://example.com/\(width).mp4")!, width: width, height: width * 9 / 16)
    }

    func testPicksSmallestFileCoveringTheDisplay() {
        let files = [file(3840), file(1280), file(2560), file(1920)]
        XCTAssertEqual(RemoteVideo.File.best(in: files, covering: 2000)?.width, 2560)
    }

    func testFallsBackToLargestFile() {
        let files = [file(1280), file(1920)]
        XCTAssertEqual(RemoteVideo.File.best(in: files, covering: 3024)?.width, 1920)
    }
}

final class MotionBGsParserTests: XCTestCase {
    func testParsesListingEntries() {
        let html = """
        <div class=tmb><a title="Black Hole &amp; Stars live wallpaper" href=/black-hole> <figure><picture>\
        <source srcset=/i/c/546x308/media/53/black-hole.3840x2160.jpg type=image/jpeg></picture>\
        <span class=ttl>Black Hole</span> <span class=frm> 4K </span> </a>\
        <a title="Spaceman Walking live wallpaper" href=/spaceman-walking> <figure><picture>\
        <source srcset=/i/c/546x308/media/3/spaceman-walking.1920x1080.jpg type=image/jpeg></picture>\
        <span class=frm> HD </span> </a>
        """
        let videos = MotionBGsProvider.parse(html)
        XCTAssertEqual(videos.map(\.id), ["motionbgs-53", "motionbgs-3"])
        XCTAssertEqual(videos.first?.title, "Black Hole & Stars")
        XCTAssertEqual(videos.first?.maxWidth, 3840)
        XCTAssertEqual(videos.last?.maxWidth, 1920)
        XCTAssertEqual(videos.last?.previewFile?.url.absoluteString,
                       "https://motionbgs.com/media/3/spaceman-walking.960x540.mp4")
    }
}
