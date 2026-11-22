import XCTest
@testable import HermesMobile

final class ForkScanPagesTests: XCTestCase {
    func testAppendsInCaptureOrder() {
        let captured = ["cover", "receipt", "notes"]
        var appended: [String] = []
        ForkScanPages.append(count: captured.count) { appended.append(captured[$0]) }
        XCTAssertEqual(appended, captured)
    }

    func testEmptyScanDoesNotReadPages() {
        ForkScanPages.append(count: 0) { _ in XCTFail("Unexpected page") }
    }
}
