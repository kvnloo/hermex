import XCTest
@testable import HermesMobile

final class ForkLiveVoiceRequestTests: XCTestCase {
    private var local: UserDefaults!
    private var shared: UserDefaults!

    override func setUp() {
        super.setUp()
        local = UserDefaults(suiteName: "ForkLiveVoiceRequestTests.local")
        shared = UserDefaults(suiteName: "ForkLiveVoiceRequestTests.shared")
        local.removeObject(forKey: ForkLiveVoiceRequest.storageKey)
        shared.removeObject(forKey: ForkLiveVoiceRequest.storageKey)
    }

    func testKeyMatchesTheLiveModeEntryKey() {
        XCTAssertEqual(ForkLiveVoiceRequest.storageKey, "fork.liveMode.requestedAt")
    }

    func testRecordWritesBothStores() {
        ForkLiveVoiceRequest.record(now: 100, local: local, shared: shared)
        XCTAssertEqual(local.double(forKey: ForkLiveVoiceRequest.storageKey), 100)
        XCTAssertEqual(shared.double(forKey: ForkLiveVoiceRequest.storageKey), 100)
    }

    func testBridgeCopiesAFreshSharedRequestOnceAndClearsIt() {
        shared.set(100.0, forKey: ForkLiveVoiceRequest.storageKey)
        XCTAssertTrue(ForkLiveVoiceRequest.bridge(now: 110, local: local, shared: shared))
        XCTAssertEqual(local.double(forKey: ForkLiveVoiceRequest.storageKey), 100)
        XCTAssertEqual(shared.double(forKey: ForkLiveVoiceRequest.storageKey), 0)
        XCTAssertFalse(ForkLiveVoiceRequest.bridge(now: 111, local: local, shared: shared))
    }

    func testBridgeDropsStaleOrAlreadyHandledRequests() {
        shared.set(100.0, forKey: ForkLiveVoiceRequest.storageKey)
        XCTAssertFalse(ForkLiveVoiceRequest.bridge(now: 200, local: local, shared: shared))
        XCTAssertEqual(shared.double(forKey: ForkLiveVoiceRequest.storageKey), 0)
        local.set(150.0, forKey: ForkLiveVoiceRequest.storageKey)
        shared.set(140.0, forKey: ForkLiveVoiceRequest.storageKey)
        XCTAssertFalse(ForkLiveVoiceRequest.bridge(now: 150, local: local, shared: shared))
        XCTAssertFalse(ForkLiveVoiceRequest.bridge(now: 150, local: local, shared: nil))
    }
}
