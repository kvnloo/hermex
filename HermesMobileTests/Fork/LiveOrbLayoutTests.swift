import XCTest
@testable import HermesMobile

final class LiveOrbLayoutTests: XCTestCase {
    func testOutsideFocusTheOrbIsASmallBubbleAndCardsStayInTheTranscript() {
        let layout = LiveOrbLayout.make(mode: .bubble, approvals: ["a1"], cards: ["c1", "c2"])
        XCTAssertEqual(layout.mode, .bubble)
        XCTAssertEqual(layout.diameter, LiveOrbLayout.bubbleDiameter)
        XCTAssertLessThanOrEqual(layout.diameter, 64)
        XCTAssertTrue(layout.showsTranscript)
        XCTAssertFalse(layout.cardsBelowOrb)
        XCTAssertEqual(layout.items, [])
        XCTAssertEqual(layout.badge, 1)
    }

    func testFocusMakesTheOrbLargeWithApprovalsThenCardsBelowIt() {
        let layout = LiveOrbLayout.make(mode: .focus, approvals: ["a1"], cards: ["c1", "c2", "c1"])
        XCTAssertEqual(layout.diameter, LiveOrbLayout.focusDiameter)
        XCTAssertGreaterThan(layout.diameter, LiveOrbLayout.bubbleDiameter * 2)
        XCTAssertFalse(layout.showsTranscript)
        XCTAssertTrue(layout.cardsBelowOrb)
        XCTAssertEqual(layout.items, [.approval("a1"), .card("c1"), .card("c2")])
        XCTAssertEqual(layout.badge, 0)
    }

    func testFocusKeepsOnlyTheNewestCards() {
        let cards = (1...10).map { "c\($0)" }
        let layout = LiveOrbLayout.make(mode: .focus, approvals: [], cards: cards)
        XCTAssertEqual(layout.items, cards.suffix(LiveOrbLayout.maxFocusCards).map(LiveFocusItem.card))
    }

    func testFocusWithNothingPendingIsStillLarge() {
        let layout = LiveOrbLayout.make(mode: .focus, approvals: [], cards: [])
        XCTAssertEqual(layout.diameter, LiveOrbLayout.focusDiameter)
        XCTAssertFalse(layout.cardsBelowOrb)
    }

    func testFocusCardsComeFromKitAndBoardFencesInTheTranscript() {
        let turns: [LiveTurn<Int>] = [
            LiveTurn(id: "t1", said: "mail?", replies: ["Here:\n```ephemeral-ui\n{\"kind\": \"inbox\"}\n```"]),
            LiveTurn(id: "t2", said: "pr?", replies: ["```openui-v2\nroot = Board(\"a\", \"\", [])\n```\nand\n```swift\nlet x = 1\n```"]),
        ]
        let cards = LiveReplyCards.focusCards(turns)
        XCTAssertEqual(cards.map(\.id), ["t1-0", "t2-0"])
        XCTAssertEqual(cards.map(\.language), ["ephemeral-ui", "openui-v2"])
        XCTAssertTrue(LiveReplyCards.isCardLanguage(KitCardProgram.fenceLanguage))
    }
}
