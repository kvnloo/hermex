import XCTest
@testable import HermesMobile

final class LiveLaneRouterTests: XCTestCase {
    func testTurnKeepsItsLaneUntilItFinishes() throws {
        var router = LiveLaneRouter()
        let first = try XCTUnwrap(router.attach())
        let second = try XCTUnwrap(router.attach())
        XCTAssertTrue(router.select(first))
        let turn = try XCTUnwrap(router.beginTurn())
        XCTAssertEqual(turn.lane, first)
        XCTAssertFalse(router.select(second))
        XCTAssertNil(router.attach())
        XCTAssertNil(router.detachSelected())
        XCTAssertNil(router.beginTurn())
        XCTAssertTrue(router.finish(turn))
        XCTAssertTrue(router.select(second))
        XCTAssertEqual(router.beginTurn()?.lane, second)
    }

    func testLateCompletionCannotReleaseANewerTurnOnSameLane() throws {
        var router = LiveLaneRouter()
        let old = try XCTUnwrap(router.beginTurn())
        XCTAssertTrue(router.finish(old))
        let new = try XCTUnwrap(router.beginTurn())
        XCTAssertFalse(router.finish(old))
        XCTAssertEqual(router.pending, new)
    }

    func testDetachingReturnsToRootAndDoesNotReuseLaneIdentity() throws {
        var router = LiveLaneRouter()
        XCTAssertNil(router.detachSelected())
        let removed = try XCTUnwrap(router.attach())
        XCTAssertEqual(router.detachSelected(), removed)
        XCTAssertEqual(router.selected, LiveLaneRouter.root)
        XCTAssertFalse(router.select(removed))
        XCTAssertNotEqual(router.attach(), removed)
    }

    func testCapacityMakesRoomAfterDetaching() {
        var router = LiveLaneRouter()
        for _ in 1..<LiveLaneRouter.capacity { XCTAssertNotNil(router.attach()) }
        XCTAssertNil(router.attach())
        XCTAssertNotNil(router.detachSelected())
        XCTAssertNotNil(router.attach())
    }
}
