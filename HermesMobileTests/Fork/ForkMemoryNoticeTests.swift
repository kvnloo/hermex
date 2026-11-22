import XCTest
@testable import HermesMobile

final class ForkMemoryNoticeTests: XCTestCase {
    func testMemoryAndUserProfileLabelsMatch() {
        XCTAssertTrue(ForkMemoryNotice.isMemoryUpdate("💾 Memory updated"))
        XCTAssertTrue(ForkMemoryNotice.isMemoryUpdate("💾 Self-improvement review: User profile updated"))
        XCTAssertTrue(ForkMemoryNotice.isMemoryUpdate("  💾 Self-improvement review: Memory updated · Skill created"))
        XCTAssertTrue(ForkMemoryNotice.isMemoryUpdate("💾 Skill created · Memory updated"))
    }

    func testOtherNoticesDoNotMatch() {
        XCTAssertFalse(ForkMemoryNotice.isMemoryUpdate("Memory updated"))
        XCTAssertFalse(ForkMemoryNotice.isMemoryUpdate("💾 Self-improvement review: Skill created"))
        XCTAssertFalse(ForkMemoryNotice.isMemoryUpdate("💾 Memory update staged for review"))
        XCTAssertFalse(ForkMemoryNotice.isMemoryUpdate("💾 Self-improvement review: Memoryless updated"))
        XCTAssertFalse(ForkMemoryNotice.isMemoryUpdate(""))
        XCTAssertFalse(ForkMemoryNotice.isMemoryUpdate(nil))
    }
}
