import Foundation

enum ForkMissionKind: String, CaseIterable, Sendable {
    case delegation, subagent, task, process
}

enum ForkMissionState: String, Sendable {
    case pending, running, paused, blocked, done, failed, cancelled

    var isLive: Bool { self == .pending || self == .running || self == .blocked }
}

enum ForkMissionCommand: String, CaseIterable, Sendable {
    case pause, resume, stop, retry
}

enum ForkMissionBlock: Equatable, Sendable {
    case hostHasNoControl
    case ownedByChat
    case alreadyPaused
    case notPaused
    case notRunning
    case nothingToRetry
    case runningNow
    case busy
}

enum ForkMissionCommandState: Equatable, Sendable {
    case enabled
    case disabled(ForkMissionBlock)

    var isEnabled: Bool { self == .enabled }

    var block: ForkMissionBlock? {
        if case .disabled(let block) = self { return block }
        return nil
    }
}

struct ForkMission: Identifiable, Equatable, Sendable {
    let kind: ForkMissionKind
    let key: String
    var parentKey: String?
    var title: String
    var detail: String?
    var state: ForkMissionState
    var startedAt: Double?
    var toolCount: Int?
    var uptime: Int?
    var lastError: String?
    var profile: String?

    var id: String { "\(kind.rawValue):\(key)" }

    func availability(_ command: ForkMissionCommand, busy: Bool = false) -> ForkMissionCommandState {
        let base = rule(command)
        guard busy, base.isEnabled else { return base }
        return .disabled(.busy)
    }

    private func rule(_ command: ForkMissionCommand) -> ForkMissionCommandState {
        switch (kind, command) {
        case (.delegation, .pause), (.task, .pause):
            return state == .paused ? .disabled(.alreadyPaused) : .enabled
        case (.delegation, .resume), (.task, .resume):
            return state == .paused ? .enabled : .disabled(.notPaused)
        case (.subagent, .stop), (.process, .stop):
            return state.isLive ? .disabled(.ownedByChat) : .disabled(.notRunning)
        case (.task, .retry):
            if state == .running { return .disabled(.runningNow) }
            return state == .failed ? .enabled : .disabled(.nothingToRetry)
        case (.delegation, .stop), (.delegation, .retry), (.subagent, .pause), (.subagent, .resume),
             (.subagent, .retry), (.task, .stop), (.process, .pause), (.process, .resume), (.process, .retry):
            return .disabled(.hostHasNoControl)
        }
    }
}

struct ForkMissionNode: Identifiable, Equatable, Sendable {
    let mission: ForkMission
    let depth: Int

    var id: String { mission.id }
}

enum ForkMissionNotice: Equatable, Sendable {
    case unsupported
    case failed(String)
}

enum ForkMissionFeed<Value: Sendable>: Sendable {
    case loaded(Value)
    case unsupported
    case failed(String)
}

struct ForkMissionSection: Identifiable, Equatable, Sendable {
    let kind: ForkMissionKind
    var nodes: [ForkMissionNode]
    var notice: ForkMissionNotice?

    var id: String { kind.rawValue }
}

struct ForkMissionTaskInput: Equatable, Sendable {
    let id: String
    let name: String
    var schedule: String?
    var profile: String?
    var paused: Bool
    var running: Bool
    var failed: Bool
    var lastError: String?
}

struct ForkMissionBoard: Equatable, Sendable {
    static let maximumRows = 200

    var sections: [ForkMissionSection]

    var missions: [ForkMission] { sections.flatMap { $0.nodes.map(\.mission) } }

    func mission(_ id: String) -> ForkMission? { missions.first { $0.id == id } }

    var liveCount: Int { missions.filter { $0.kind != .delegation && $0.state.isLive }.count }

    static func assemble(
        delegation: ForkMissionFeed<ForkMissionDelegationStatus>,
        tasks: ForkMissionFeed<[ForkMissionTaskInput]>,
        processes: ForkMissionFeed<[ForkMissionProcessRow]>
    ) -> ForkMissionBoard {
        ForkMissionBoard(sections: [
            section(.subagent, delegation) { status in
                let gate = ForkMission(kind: .delegation, key: "spawning", title: "",
                                       state: status.paused ? .paused : .running)
                let workers = status.active.map { $0.mission(spawnPaused: status.paused) }
                return [ForkMissionNode(mission: gate, depth: 0)] + tree(workers)
            },
            section(.task, tasks) { rows in rows.map { ForkMissionNode(mission: mission($0), depth: 0) } },
            section(.process, processes) { rows in rows.map { ForkMissionNode(mission: $0.mission, depth: 0) } }
        ])
    }

    static func tree(_ missions: [ForkMission]) -> [ForkMissionNode] {
        var seenKeys = Set<String>()
        let unique = missions.filter { seenKeys.insert($0.key).inserted }
        let keys = Set(unique.map(\.key))
        var children: [String: [ForkMission]] = [:]
        var roots: [ForkMission] = []
        for mission in unique {
            if let parent = mission.parentKey, parent != mission.key, keys.contains(parent) {
                children[parent, default: []].append(mission)
            } else {
                roots.append(mission)
            }
        }
        var result: [ForkMissionNode] = []
        var visited = Set<String>()
        func visit(_ mission: ForkMission, depth: Int) {
            guard visited.insert(mission.key).inserted else { return }
            result.append(ForkMissionNode(mission: mission, depth: depth))
            for child in children[mission.key] ?? [] { visit(child, depth: depth + 1) }
        }
        for root in roots { visit(root, depth: 0) }
        for mission in unique where !visited.contains(mission.key) { visit(mission, depth: 0) }
        return result
    }

    static func mission(_ task: ForkMissionTaskInput) -> ForkMission {
        let state: ForkMissionState = task.running ? .running : task.paused ? .paused : task.failed ? .failed : .pending
        return ForkMission(kind: .task, key: task.id, title: task.name, detail: task.schedule, state: state,
                           lastError: task.failed ? task.lastError : nil, profile: task.profile)
    }

    private static func section<Value>(
        _ kind: ForkMissionKind, _ feed: ForkMissionFeed<Value>, _ nodes: (Value) -> [ForkMissionNode]
    ) -> ForkMissionSection {
        switch feed {
        case .loaded(let value):
            return ForkMissionSection(kind: kind, nodes: Array(nodes(value).prefix(maximumRows)))
        case .unsupported:
            return ForkMissionSection(kind: kind, nodes: [], notice: .unsupported)
        case .failed(let message):
            return ForkMissionSection(kind: kind, nodes: [], notice: .failed(message))
        }
    }
}
