import Foundation
import XCTest
@testable import HermesMobile

final class ForkBotSessionTreeTests: XCTestCase {
    private func row(_ id: String, at seconds: Double?, identity: String? = nil, title: String? = nil,
                     hidden: Bool = false, archived: Bool = false) -> ForkBotSessionRow {
        ForkBotSessionRow(id: id, identity: identity ?? id, title: title ?? id, preview: nil,
                          activity: seconds.map(Date.init(timeIntervalSince1970:)), hidden: hidden, archived: archived)
    }

    func testBranchListsVisibleSessionsNewestFirstAndOncePerLineage() {
        let branch = ForkBotSessionBranch(rows: [
            row("old", at: 100),
            row("bot-chat", at: 900, hidden: true),
            row("new", at: 500),
            row("undated", at: nil),
            row("archived", at: 800, archived: true),
            row("tip", at: 300, identity: "new"),
            row("mid", at: 200),
        ], pageIsFull: false)

        XCTAssertEqual(branch.rows.map(\.id), ["new", "mid", "old", "undated"])
        XCTAssertFalse(branch.offersShowAll)
    }

    func testBranchPreviewsFiveAndOffersShowAllBeyondThemOrWhenThePageWasFull() {
        let rows = (1...7).map { row("s\($0)", at: Double($0)) }
        let branch = ForkBotSessionBranch(rows: rows, pageIsFull: false)
        XCTAssertEqual(branch.preview.map(\.id), ["s7", "s6", "s5", "s4", "s3"])
        XCTAssertTrue(branch.offersShowAll)

        let few = ForkBotSessionBranch(rows: Array(rows.prefix(3)), pageIsFull: true)
        XCTAssertEqual(few.preview.count, 3)
        XCTAssertTrue(few.offersShowAll)
        XCTAssertTrue(ForkBotSessionBranch(rows: [], pageIsFull: false).isEmpty)
    }

    func testDisplayTitleFallsBackToThePreview() {
        XCTAssertEqual(ForkBotSessionRow(id: "a", identity: "a", title: "  ", preview: "First prompt", activity: nil).displayTitle,
                       "First prompt")
        XCTAssertNil(ForkBotSessionRow(id: "a", identity: "a", title: nil, preview: "", activity: nil).displayTitle)
    }

    func testTreeStateAppliesOnlyTheNewestReadAndKeepsRowsWhenARefreshFails() {
        var state = ForkBotSessionTreeState()
        let first = state.begin("coder")
        XCTAssertEqual(state.phase("coder"), .loading)
        let second = state.begin("coder")
        let loaded = ForkBotSessionBranch(rows: [row("a", at: 1)], pageIsFull: false)

        XCTAssertFalse(state.finish("coder", serial: first, branch: nil))
        XCTAssertEqual(state.phase("coder"), .loading)
        XCTAssertTrue(state.finish("coder", serial: second, branch: loaded))
        XCTAssertEqual(state.phase("coder"), .loaded(loaded))

        let refresh = state.begin("coder")
        XCTAssertEqual(state.phase("coder"), .loaded(loaded))
        state.finish("coder", serial: refresh, branch: nil)
        XCTAssertEqual(state.phase("coder"), .loaded(loaded))

        state.finish("writer", serial: state.begin("writer"), branch: nil)
        XCTAssertEqual(state.phase("writer"), .failed)
        state.retain(["writer"])
        XCTAssertNil(state.phase("coder"))
        XCTAssertEqual(state.phase("writer"), .failed)
    }

    func testExpansionPersistsPerServerConnectionAndBot() throws {
        let suite = "ForkBotSessionTreeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = try XCTUnwrap(URL(string: "https://one.example"))
        let other = try XCTUnwrap(URL(string: "https://two.example"))
        let connection = UUID(), replaced = UUID()

        XCTAssertFalse(ForkBotSessionExpansion.isExpanded(server: server, connectionID: connection, profile: "coder", in: defaults))
        ForkBotSessionExpansion.setExpanded(true, server: server, connectionID: connection, profile: "coder", in: defaults)
        ForkBotSessionExpansion.setExpanded(true, server: other, connectionID: connection, profile: "coder", in: defaults)

        XCTAssertTrue(ForkBotSessionExpansion.isExpanded(server: server, connectionID: connection, profile: "coder", in: defaults))
        XCTAssertFalse(ForkBotSessionExpansion.isExpanded(server: server, connectionID: connection, profile: "writer", in: defaults))
        XCTAssertFalse(ForkBotSessionExpansion.isExpanded(server: server, connectionID: replaced, profile: "coder", in: defaults))

        ForkBotSessionExpansion.forget(server: server, connectionID: connection, in: defaults)
        XCTAssertFalse(ForkBotSessionExpansion.isExpanded(server: server, connectionID: connection, profile: "coder", in: defaults))
        XCTAssertTrue(ForkBotSessionExpansion.isExpanded(server: other, connectionID: connection, profile: "coder", in: defaults))

        ForkBotSessionExpansion.setExpanded(false, server: other, connectionID: connection, profile: "coder", in: defaults)
        XCTAssertNil(defaults.object(forKey: ForkBotSessionExpansion.key(server: other, connectionID: connection, profile: "coder")))
    }
}
