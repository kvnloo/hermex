import XCTest
@testable import HermesMobile

final class ForkChatRPCTests: XCTestCase {
    func testMessageReactEncodesTheContractShape() throws {
        let call = HermesCall.fork(.messageReact(sessionID: "s1", rowID: 42, emoji: "👍🏼"))
        XCTAssertEqual(call.method, "message.react")
        XCTAssertEqual(try call.params(), [
            "session_id": .string("s1"), "row_id": .number(42), "emoji": .string("👍🏼"), "author": .string("user"),
        ])
    }

    func testClearingSendsNullEmoji() throws {
        let params = try HermesCall.fork(.messageReact(sessionID: "s1", rowID: 42, emoji: nil)).params()
        XCTAssertEqual(params["emoji"], .null)
    }

    func testInadmissibleReactIsRefusedBeforeSending() {
        XCTAssertThrowsError(try HermesCall.fork(.messageReact(sessionID: "", rowID: 42, emoji: "🎉")).params())
        XCTAssertThrowsError(try HermesCall.fork(.messageReact(sessionID: "s1", rowID: 0, emoji: "🎉")).params())
    }

    func testHistoryRowsCarryTopLevelReactionsIntoDisplayMetadata() {
        let row: BotJSON = .object([
            "reactions": .array([.object(["emoji": .string("🎉"), "author": .string("agent")])]),
        ])
        let message = ChatMessage(role: "assistant", content: "hi", timestamp: nil, messageId: "r/row-1",
                                  displayMetadata: ForkReactionRows.displayMetadata(row), rowID: 1)
        XCTAssertEqual(ForkReactionRows.seeded(message), [ForkReaction(emoji: "🎉", author: "agent")!])
    }

    func testRowsWithoutReactionsKeepTheirMetadata() {
        XCTAssertNil(ForkReactionRows.displayMetadata(.object([:])))
        let row: BotJSON = .object(["display_metadata": .object(["model_only": .bool(true)])])
        XCTAssertEqual(ForkReactionRows.displayMetadata(row), ["model_only": .bool(true)])
    }

    func testLiveReactionPayloadParses() {
        let payload: BotJSON = .array([
            .object(["emoji": .string("👍"), "author": .string("user"), "at": .number(1)]),
            .object(["emoji": .string(" "), "author": .string("agent")]),
        ])
        XCTAssertEqual(ForkReactionRows.parse(payload), [ForkReaction(emoji: "👍", author: "user")!])
    }
}
