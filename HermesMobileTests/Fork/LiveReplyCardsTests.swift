import XCTest
@testable import HermesMobile

final class LiveReplyCardsTests: XCTestCase {
    func testBoardFencesBecomeInlineCardsBetweenProse() {
        let reply = """
        Here is the spend.

        ```OpenUI-v2
        root = Board("Spend", "", [Stat("Total", 12, null)])
        ```
        That is all.
        """

        XCTAssertEqual(LiveReplyCards.segments(reply), [
            .text("Here is the spend."),
            .card(language: "openui-v2", source: #"root = Board("Spend", "", [Stat("Total", 12, null)])"#),
            .text("That is all."),
        ])
    }

    func testOrdinaryCodeStaysInTheProse() {
        let reply = "Run this:\n~~~sh\nmake test\n~~~\nthen tell me."

        XCTAssertEqual(LiveReplyCards.segments(reply), [.text(reply)])
    }

    func testCardStillStreamingIsPendingUntilItsFenceCloses() {
        let streaming = "Drawing it now.\n```html\n<div>partial"

        XCTAssertEqual(LiveReplyCards.segments(streaming), [.text("Drawing it now."), .pendingCard(language: "html")])
        XCTAssertEqual(LiveReplyCards.segments(streaming + "</div>\n```"), [
            .text("Drawing it now."),
            .card(language: "html", source: "<div>partial</div>"),
        ])
    }

    func testCardMarkdownRoundTripsToTheChatFence() {
        let card = LiveReplySegment.card(language: "openui", source: "root = Board()")

        XCTAssertEqual(LiveReplyCards.segments(card.markdown), [card])
    }
}
