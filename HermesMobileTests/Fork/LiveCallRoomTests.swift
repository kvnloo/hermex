import XCTest
@testable import HermesMobile

final class LiveCallRoomTests: XCTestCase {
    func testStartingLiveOpensFocusForTheChatOnScreen() throws {
        var room = LiveCallRoom()
        let begun = try XCTUnwrap(room.start(chat: "chat-a"))
        XCTAssertEqual(room.call, begun)
        XCTAssertEqual(begun.chat, "chat-a")
        XCTAssertEqual(begun.presentation, .focus)
        XCTAssertTrue(begun.chatOnScreen)
    }

    func testCompactAndExpandKeepTheSameCallWithoutRestartingIt() throws {
        var room = LiveCallRoom()
        let begun = try XCTUnwrap(room.start(chat: "chat-a"))

        room.compact()
        XCTAssertEqual(room.call?.presentation, .bubble)
        XCTAssertEqual(room.call?.id, begun.id)

        room.expand()
        XCTAssertEqual(room.call?.presentation, .focus)
        XCTAssertEqual(room.call?.id, begun.id)
        XCTAssertEqual(room.call?.chat, "chat-a")
    }

    func testAskingForLiveWhileACallRunsExpandsThatCallInsteadOfBindingANewOne() throws {
        var room = LiveCallRoom()
        let begun = try XCTUnwrap(room.start(chat: "chat-a"))
        room.compact()

        XCTAssertNil(room.start(chat: "chat-b"))
        XCTAssertEqual(room.call?.id, begun.id)
        XCTAssertEqual(room.call?.chat, "chat-a")
        XCTAssertEqual(room.call?.presentation, .focus)

        room.compact()
        XCTAssertNil(room.start(chat: "chat-a"))
        XCTAssertEqual(room.call?.id, begun.id)
        XCTAssertEqual(room.call?.presentation, .focus)
    }

    func testLeavingTheOriginatingChatKeepsTheCallAndHandsItsStreamToTheCall() throws {
        var room = LiveCallRoom()
        let begun = try XCTUnwrap(room.start(chat: "chat-a"))
        room.compact()

        XCTAssertFalse(room.chatLeft("chat-b"), "another chat leaving is not the call's business")
        XCTAssertTrue(room.chatLeft("chat-a"), "the call adopts its chat, so the chat must not suspend its stream")
        XCTAssertEqual(room.call?.id, begun.id)
        XCTAssertEqual(room.call?.presentation, .bubble)

        let ending = try XCTUnwrap(room.end(.user))
        XCTAssertEqual(ending.call.id, begun.id)
        XCTAssertTrue(ending.releasesChat, "the chat is gone, so ending the call must release its stream")
    }

    func testEndingWithTheChatOnScreenLeavesTheStreamToTheChat() throws {
        var room = LiveCallRoom()
        _ = room.start(chat: "chat-a")
        room.compact()
        _ = room.chatLeft("chat-a")
        room.chatAppeared("chat-a")

        let ending = try XCTUnwrap(room.end(.user))
        XCTAssertFalse(ending.releasesChat)
    }

    func testNoChatIsAdoptedWithoutACall() {
        var room = LiveCallRoom()
        XCTAssertFalse(room.chatLeft("chat-a"))
        room.compact()
        room.expand()
        XCTAssertNil(room.call)
    }

    func testEndBackgroundAndAccountChangeEachEndTheCallOnce() throws {
        for reason in [LiveCallEnd.user, .background, .accountChanged] {
            var room = LiveCallRoom()
            let begun = try XCTUnwrap(room.start(chat: "chat-a"))
            room.compact()

            let ending = try XCTUnwrap(room.end(reason))
            XCTAssertEqual(ending.reason, reason)
            XCTAssertEqual(ending.call.id, begun.id)
            XCTAssertNil(room.call)
            XCTAssertNil(room.end(reason), "a second end is a no-op")

            room.expand()
            XCTAssertNil(room.call, "nothing to expand after the call ends")
        }
    }

    func testANewCallAfterEndingIsADifferentCall() throws {
        var room = LiveCallRoom()
        let first = try XCTUnwrap(room.start(chat: "chat-a"))
        _ = room.end(.user)
        let second = try XCTUnwrap(room.start(chat: "chat-a"))
        XCTAssertNotEqual(first.id, second.id)
    }

    func testThePresentationDrivesASmallBubbleOrALargeOrbWithApprovalsAndCardsBelow() throws {
        var room = LiveCallRoom()
        _ = room.start(chat: "chat-a")
        room.compact()

        let compact = LiveOrbLayout.make(mode: try XCTUnwrap(room.call?.presentation), approvals: ["a1"], cards: ["c1"])
        XCTAssertEqual(compact.diameter, LiveOrbLayout.bubbleDiameter)
        XCTAssertEqual(compact.items, [])
        XCTAssertEqual(compact.badge, 1, "a pending approval is visible on the small bubble")

        room.expand()
        let focus = LiveOrbLayout.make(mode: try XCTUnwrap(room.call?.presentation), approvals: ["a1"], cards: ["c1"])
        XCTAssertEqual(focus.diameter, LiveOrbLayout.focusDiameter)
        XCTAssertEqual(focus.items, [.approval("a1"), .card("c1")])

        room.compact()
        let back = LiveOrbLayout.make(mode: try XCTUnwrap(room.call?.presentation), approvals: [], cards: ["c1"])
        XCTAssertEqual(back.diameter, LiveOrbLayout.bubbleDiameter)
        XCTAssertEqual(back.items, [])
    }
}
