import XCTest
@testable import HermesMobile

final class ForkRoutineRequestTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ForkRoutineRequestTests")
        defaults.removeObject(forKey: ForkRoutineRequest.storageKey)
    }

    func testAFreshRequestOpensTasksOnce() {
        ForkRoutineRequest.record(now: 100, in: defaults)
        XCTAssertTrue(ForkRoutineRequest.isPending(now: 120, in: defaults))
        XCTAssertTrue(ForkRoutineRequest.take(now: 120, from: defaults))
        XCTAssertFalse(ForkRoutineRequest.isPending(now: 121, in: defaults))
        XCTAssertFalse(ForkRoutineRequest.take(now: 121, from: defaults))
    }

    func testAStaleOrFutureRequestIsDroppedWithoutOpening() {
        ForkRoutineRequest.record(now: 100, in: defaults)
        XCTAssertFalse(ForkRoutineRequest.isPending(now: 100 + ForkRoutineRequest.freshness + 1, in: defaults))
        XCTAssertFalse(ForkRoutineRequest.take(now: 100 + ForkRoutineRequest.freshness + 1, from: defaults))
        XCTAssertEqual(defaults.double(forKey: ForkRoutineRequest.storageKey), 0)

        ForkRoutineRequest.record(now: 500, in: defaults)
        XCTAssertFalse(ForkRoutineRequest.take(now: 400, from: defaults))
        XCTAssertEqual(defaults.double(forKey: ForkRoutineRequest.storageKey), 0)
    }
}
