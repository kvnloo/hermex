import Foundation
import XCTest
@testable import HermesMobile

final class ForkHomeFiltersTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 800_000)

    func testAgentSelectionHiddenAndGroupsCompose() {
        let agent = ForkHomeFilters.Row(id: "bot:a", name: "A", activity: nil, agentID: "a")
        var room = ForkHomeFilters.Row(id: "room:a", name: "Room", activity: nil)
        var filters = ForkHomeFilters()
        XCTAssertTrue(filters.includes(agent, now: now))
        XCTAssertTrue(filters.includes(room, now: now))

        filters.excludedAgents = ["a"]
        filters.includeGroups = false
        XCTAssertFalse(filters.includes(agent, now: now))
        XCTAssertFalse(filters.includes(room, now: now))
        filters.includeHidden = true
        XCTAssertTrue(filters.includes(agent, now: now))
        XCTAssertFalse(filters.includes(room, now: now))

        filters.includeGroups = true
        room.hidden = true
        XCTAssertTrue(filters.includes(room, now: now))
        filters.includeHidden = false
        XCTAssertFalse(filters.includes(room, now: now))
    }

    func testUnreadIsScopedToRecentWindowAndExcludesGroups() {
        var filters = ForkHomeFilters(show: .unread)
        var row = ForkHomeFilters.Row(id: "bot:a", name: "A", activity: now.addingTimeInterval(-86_400),
                                     agentID: "a", unread: true)
        XCTAssertTrue(filters.includes(row, now: now))
        row = .init(id: row.id, name: row.name, activity: now.addingTimeInterval(-86_401), agentID: "a", unread: true)
        XCTAssertFalse(filters.includes(row, now: now))
        filters.recent = .threeDays
        XCTAssertTrue(filters.includes(row, now: now))
        row.unread = false
        XCTAssertFalse(filters.includes(row, now: now))
        row.agentID = nil
        row.unread = true
        XCTAssertFalse(filters.includes(row, now: now))
        filters.show = .all
        XCTAssertTrue(filters.includes(row, now: now))
    }

    func testExplicitSortsAreDeterministic() {
        let rows = [
            ForkHomeFilters.Row(id: "3", name: "Agent 10", activity: now),
            ForkHomeFilters.Row(id: "2", name: "Agent 2", activity: nil),
            ForkHomeFilters.Row(id: "1", name: "Agent 2", activity: now),
        ]
        XCTAssertEqual(rows.sorted(by: ForkHomeFilters(sort: .name).precedes).map(\.id), ["1", "2", "3"])
        XCTAssertEqual(rows.sorted(by: ForkHomeFilters(sort: .recent).precedes).map(\.id), ["1", "3", "2"])
    }
}
