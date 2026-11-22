import XCTest
@testable import HermesMobile

final class LiveReplyWatchTests: XCTestCase {
    private let live = LiveReplyWatch.Observation(hasStream: true, isConnected: true)
    private let dropped = LiveReplyWatch.Observation(hasStream: true, isConnected: false)
    private let ended = LiveReplyWatch.Observation(hasStream: false, isConnected: true)

    func testLongToolCallOnAConnectedStreamNeverTimesOut() {
        var watch = LiveReplyWatch(sentAt: 0)

        for minute in 1...30 {
            XCTAssertEqual(watch.observe(live, at: Double(minute) * 60), .wait)
        }
        XCTAssertFalse(watch.isReconnecting)
    }

    func testDroppedStreamReconnectsWithBackoffAndRecovers() {
        var watch = LiveReplyWatch(sentAt: 0)
        _ = watch.observe(live, at: 1)

        XCTAssertEqual(watch.observe(dropped, at: 10), .reconnect)
        XCTAssertTrue(watch.isReconnecting)
        XCTAssertEqual(watch.observe(dropped, at: 10.5), .wait)
        XCTAssertEqual(watch.observe(dropped, at: 11), .reconnect)
        XCTAssertEqual(watch.observe(dropped, at: 12), .wait)
        XCTAssertEqual(watch.observe(dropped, at: 13), .reconnect)
        XCTAssertEqual(watch.attempts, 3)

        XCTAssertEqual(watch.observe(live, at: 14), .wait)
        XCTAssertFalse(watch.isReconnecting)
        XCTAssertEqual(watch.observe(dropped, at: 400), .reconnect)
        XCTAssertEqual(watch.attempts, 1)
    }

    func testGivesUpOnlyAfterStayingDisconnected() {
        var watch = LiveReplyWatch(sentAt: 0)
        _ = watch.observe(dropped, at: 1)

        XCTAssertNotEqual(watch.observe(dropped, at: 1 + LiveReplyWatch.disconnectedLimit - 1), .fail)
        XCTAssertEqual(watch.observe(dropped, at: 1 + LiveReplyWatch.disconnectedLimit), .fail)
    }

    func testStreamThatEndsWithoutAReplyRefreshesTheSameConversationOnceThenFails() {
        var watch = LiveReplyWatch(sentAt: 0)
        _ = watch.observe(live, at: 1)

        XCTAssertEqual(watch.observe(ended, at: 100), .wait)
        XCTAssertEqual(watch.observe(ended, at: 103), .refresh)
        XCTAssertEqual(watch.observe(ended, at: 110), .wait)
        XCTAssertEqual(watch.observe(ended, at: 120), .fail)
    }

    func testSendThatNeverStartsAStreamKeepsTheOldLimit() {
        var watch = LiveReplyWatch(sentAt: 0)

        XCTAssertEqual(watch.observe(ended, at: LiveReplyWatch.neverStartedLimit - 1), .wait)
        XCTAssertEqual(watch.observe(ended, at: LiveReplyWatch.neverStartedLimit), .fail)
    }
}
