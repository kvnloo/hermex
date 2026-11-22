import Foundation

struct ForkBotSessionRow: Equatable, Identifiable {
    let id: String
    let identity: String
    let title: String?
    let preview: String?
    let activity: Date?
    var unread = false
    var hidden = false
    var archived = false

    var displayTitle: String? {
        [title, preview].lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
}

struct ForkBotSessionBranch: Equatable {
    static let previewLimit = 5

    let rows: [ForkBotSessionRow]
    let isPartial: Bool

    init(rows: [ForkBotSessionRow], pageIsFull: Bool) {
        var identities = Set<String>()
        let shown = rows.filter { !$0.hidden && !$0.archived && identities.insert($0.identity).inserted }
        self.rows = shown.enumerated().sorted { lhs, rhs in
            switch (lhs.element.activity, rhs.element.activity) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
        isPartial = pageIsFull
    }

    var preview: [ForkBotSessionRow] { Array(rows.prefix(Self.previewLimit)) }
    var offersShowAll: Bool { rows.count > Self.previewLimit || isPartial }
    var isEmpty: Bool { rows.isEmpty }
}

struct ForkBotSessionTreeState: Equatable {
    enum Phase: Equatable {
        case loading
        case loaded(ForkBotSessionBranch)
        case failed
    }

    private(set) var phases: [String: Phase] = [:]
    private var serials: [String: Int] = [:]
    private var serial = 0

    func phase(_ profile: String) -> Phase? { phases[profile] }

    mutating func begin(_ profile: String) -> Int {
        serial += 1
        serials[profile] = serial
        if case .loaded? = phases[profile] {} else { phases[profile] = .loading }
        return serial
    }

    @discardableResult
    mutating func finish(_ profile: String, serial: Int, branch: ForkBotSessionBranch?) -> Bool {
        guard serials[profile] == serial else { return false }
        serials[profile] = nil
        if let branch {
            phases[profile] = .loaded(branch)
        } else if case .loaded? = phases[profile] {
        } else {
            phases[profile] = .failed
        }
        return true
    }

    mutating func retain(_ profiles: Set<String>) {
        phases = phases.filter { profiles.contains($0.key) }
        serials = serials.filter { profiles.contains($0.key) }
    }
}

enum ForkBotSessionExpansion {
    private static let prefix = "fork.botSessionTree.expanded|"

    static func key(server: URL, connectionID: UUID, profile: String) -> String {
        scope(server: server, connectionID: connectionID) + profile
    }

    static func isExpanded(server: URL, connectionID: UUID, profile: String, in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(server: server, connectionID: connectionID, profile: profile))
    }

    static func setExpanded(_ expanded: Bool, server: URL, connectionID: UUID, profile: String,
                            in defaults: UserDefaults = .standard) {
        let key = key(server: server, connectionID: connectionID, profile: profile)
        if expanded { defaults.set(true, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    static func forget(server: URL, connectionID: UUID, in defaults: UserDefaults = .standard) {
        let scope = scope(server: server, connectionID: connectionID)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(scope) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func scope(server: URL, connectionID: UUID) -> String {
        prefix + server.absoluteString + "|" + connectionID.uuidString + "|"
    }
}
