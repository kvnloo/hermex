import Foundation

struct ForkMissionDelegationStatus: Decodable, Equatable, Sendable {
    var active: [ForkMissionSubagentRow]
    var paused: Bool
    var maxSpawnDepth: Int?
    var maxConcurrentChildren: Int?

    private enum CodingKeys: String, CodingKey {
        case active, paused
        case maxSpawnDepth = "max_spawn_depth"
        case maxConcurrentChildren = "max_concurrent_children"
    }

    init(active: [ForkMissionSubagentRow], paused: Bool) {
        self.active = active
        self.paused = paused
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paused = try container.decode(Bool.self, forKey: .paused)
        active = try container.decode([ForkMissionLossy<ForkMissionSubagentRow>].self, forKey: .active).compactMap(\.value)
        maxSpawnDepth = try? container.decodeIfPresent(Int.self, forKey: .maxSpawnDepth)
        maxConcurrentChildren = try? container.decodeIfPresent(Int.self, forKey: .maxConcurrentChildren)
    }
}

struct ForkMissionSubagentRow: Decodable, Equatable, Sendable {
    var subagentID: String
    var parentID: String?
    var goal: String?
    var model: String?
    var startedAt: Double?
    var status: String?
    var toolCount: Int?

    private enum CodingKeys: String, CodingKey {
        case goal, model, status
        case subagentID = "subagent_id"
        case parentID = "parent_id"
        case startedAt = "started_at"
        case toolCount = "tool_count"
    }

    init(subagentID: String, parentID: String? = nil, goal: String? = nil, status: String? = nil) {
        self.subagentID = subagentID
        self.parentID = parentID
        self.goal = goal
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .subagentID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .subagentID, in: container, debugDescription: "empty id")
        }
        subagentID = id
        parentID = ForkMissionText.clean(try? container.decodeIfPresent(String.self, forKey: .parentID))
        goal = ForkMissionText.clean(try? container.decodeIfPresent(String.self, forKey: .goal))
        model = ForkMissionText.clean(try? container.decodeIfPresent(String.self, forKey: .model))
        startedAt = try? container.decodeIfPresent(Double.self, forKey: .startedAt)
        status = ForkMissionText.clean(try? container.decodeIfPresent(String.self, forKey: .status))
        toolCount = (try? container.decodeIfPresent(Int.self, forKey: .toolCount)).flatMap { $0 >= 0 ? $0 : nil }
    }

    func mission(spawnPaused: Bool) -> ForkMission {
        ForkMission(kind: .subagent, key: subagentID, parentKey: parentID, title: goal ?? "", detail: model,
                    state: Self.state(status, spawnPaused: spawnPaused), startedAt: startedAt, toolCount: toolCount)
    }

    static func state(_ status: String?, spawnPaused: Bool) -> ForkMissionState {
        switch status?.lowercased() {
        case "queued": return spawnPaused ? .blocked : .pending
        case "completed": return .done
        case "failed", "error", "timeout": return .failed
        case "interrupted": return .cancelled
        default: return .running
        }
    }
}

struct ForkMissionProcessList: Decodable, Equatable, Sendable {
    var processes: [ForkMissionProcessRow]

    private enum CodingKeys: String, CodingKey { case processes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        processes = try container.decode([ForkMissionLossy<ForkMissionProcessRow>].self, forKey: .processes)
            .compactMap(\.value)
    }
}

struct ForkMissionProcessRow: Decodable, Equatable, Sendable {
    var sessionID: String
    var command: String
    var status: String
    var uptime: Int?

    private enum CodingKeys: String, CodingKey {
        case command, status, uptime
        case sessionID = "session_id"
    }

    init(sessionID: String, command: String, status: String, uptime: Int? = nil) {
        self.sessionID = sessionID
        self.command = command
        self.status = status
        self.uptime = uptime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .sessionID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .sessionID, in: container, debugDescription: "empty id")
        }
        sessionID = id
        command = ForkMissionText.clean(try? container.decodeIfPresent(String.self, forKey: .command)) ?? ""
        status = ForkMissionText.clean(try? container.decodeIfPresent(String.self, forKey: .status)) ?? "running"
        uptime = (try? container.decodeIfPresent(Int.self, forKey: .uptime)).flatMap { $0 >= 0 ? $0 : nil }
    }

    var mission: ForkMission {
        let state: ForkMissionState
        switch status.lowercased() {
        case "exited", "completed", "finished": state = .done
        case "killed", "interrupted", "stopped": state = .cancelled
        case "failed", "error", "timeout": state = .failed
        default: state = .running
        }
        return ForkMission(kind: .process, key: sessionID, title: command, state: state, uptime: uptime)
    }
}

struct ForkMissionLossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

enum ForkMissionText {
    static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
