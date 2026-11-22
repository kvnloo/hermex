import Foundation

struct ForkHomeFilters: Equatable {
    enum Sort: Hashable { case inbox, recent, name }
    enum Recent: Int, CaseIterable { case day = 1, threeDays = 3, week = 7 }
    enum Show: Hashable { case all, unread }

    struct Row {
        let id: String
        let name: String
        let activity: Date?
        var agentID: String? = nil
        var hidden = false
        var unread = false
    }

    var sort: Sort = .inbox
    var recent: Recent = .day
    var show: Show = .all
    var excludedAgents: Set<String> = []
    var includeGroups = true
    var includeHidden = false

    func isRecent(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return date >= now.addingTimeInterval(-Double(recent.rawValue) * 86_400)
    }

    func includes(_ row: Row, now: Date) -> Bool {
        if let agent = row.agentID {
            guard includeHidden || (!row.hidden && !excludedAgents.contains(agent)) else { return false }
            return show == .all || (row.unread && isRecent(row.activity, now: now))
        }
        return includeGroups && show == .all && (includeHidden || !row.hidden)
    }

    func precedes(_ lhs: Row, _ rhs: Row) -> Bool {
        if sort == .name {
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame { return order == .orderedAscending }
        } else if sort == .recent {
            if let left = lhs.activity, let right = rhs.activity, left != right { return left > right }
            if (lhs.activity != nil) != (rhs.activity != nil) { return lhs.activity != nil }
        }
        return lhs.id < rhs.id
    }
}
