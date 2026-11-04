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
