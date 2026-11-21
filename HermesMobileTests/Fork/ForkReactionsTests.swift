import XCTest
@testable import HermesMobile

final class ForkReactionsTests: XCTestCase {
    func testReactionRejectsBlankEmojiOrMissingAuthor() {
        XCTAssertNil(ForkReaction(emoji: "  ", author: "user"))
        XCTAssertNil(ForkReaction(emoji: "👍", author: nil))
        XCTAssertNil(ForkReaction(emoji: nil, author: "agent"))
        XCTAssertEqual(ForkReaction(emoji: " 👍 ", author: "agent")?.emoji, "👍")
    }

    func testSkinToneAppliesOnlyToModifiableEmoji() {
        XCTAssertEqual(ForkReactionCatalog.applying(.mediumLight, to: "👍"), "👍🏼")
        XCTAssertEqual(ForkReactionCatalog.applying(.dark, to: "🙏"), "🙏🏿")
        XCTAssertEqual(ForkReactionCatalog.applying(.dark, to: "❤️"), "❤️")
        XCTAssertEqual(ForkReactionCatalog.applying(.none, to: "👍🏼"), "👍")
        XCTAssertEqual(ForkReactionCatalog.applying(.light, to: "👎🏾"), "👎🏻")
    }

    func testPaletteKeepsTheEightReactionsInOrder() {
        let palette = ForkReactionCatalog.palette(.medium)
        XCTAssertEqual(palette.count, 8)
        XCTAssertEqual(palette.first, "👍🏽")
        XCTAssertEqual(palette[2], "❤️")
        XCTAssertEqual(palette[6], "🙏🏽")
    }

    func testStoredToneFallsBackToNone() {
        XCTAssertEqual(ForkSkinTone(stored: "🏼"), .mediumLight)
        XCTAssertEqual(ForkSkinTone(stored: "nonsense"), ForkSkinTone.none)
        XCTAssertEqual(ForkSkinTone(stored: nil), ForkSkinTone.none)
        XCTAssertEqual(ForkSkinTone.allCases.count, 6)
    }

    func testChipsGroupByEmojiInFirstSeenOrderAndFlagMine() {
        let reactions = [
            ForkReaction(emoji: "🎉", author: "agent")!,
            ForkReaction(emoji: "👍🏼", author: "user")!,
            ForkReaction(emoji: "🎉", author: "user")!,
        ]
        let chips = ForkReactionBook.chips(reactions)
        XCTAssertEqual(chips.map(\.emoji), ["🎉", "👍🏼"])
        XCTAssertEqual(chips.map(\.count), [2, 1])
        XCTAssertEqual(chips.map(\.includesMine), [true, true])
        XCTAssertEqual(ForkReactionBook.mine(in: reactions)?.emoji, "🎉")
    }

    func testLiveRowsOverrideSeededHistory() {
        var book = ForkReactionBook()
        let seeded = [ForkReaction(emoji: "👍", author: "user")!]
        XCTAssertEqual(book.reactions(rowID: 7, seeded: seeded), seeded)
        XCTAssertEqual(book.reactions(rowID: nil, seeded: seeded), seeded)
        book.set([], rowID: 7)
        XCTAssertEqual(book.reactions(rowID: 7, seeded: seeded), [])
    }

    func testReplyKeepsAnAgentReactionThatArrivedWhileSending() {
        var book = ForkReactionBook()
        let before = book.rows[3]
        let agent = ForkReaction(emoji: "🎉", author: "agent")!
        book.set([agent], rowID: 3)
        let mine = ForkReaction(emoji: "👍", author: "user")!
        book.merge(reply: [mine], rowID: 3, before: before)
        XCTAssertEqual(book.rows[3], [mine, agent])
    }

    func testReplyReplacesWhenNothingChangedMeanwhile() {
        var book = ForkReactionBook()
        let old = [ForkReaction(emoji: "😮", author: "user")!]
        book.set(old, rowID: 3)
        let reply = [ForkReaction(emoji: "👍", author: "user")!]
        book.merge(reply: reply, rowID: 3, before: old)
        XCTAssertEqual(book.rows[3], reply)
    }

    func testChoosingTheCurrentEmojiClearsIt() {
        let current = ForkReaction(emoji: "👍🏼", author: "user")
        XCTAssertNil(ForkReactionBook.requestEmoji(choosing: "👍🏼", current: current))
        XCTAssertNil(ForkReactionBook.requestEmoji(choosing: "", current: current))
        XCTAssertNil(ForkReactionBook.requestEmoji(choosing: nil, current: nil))
        XCTAssertEqual(ForkReactionBook.requestEmoji(choosing: "🎉", current: current), "🎉")
    }
}
