import Foundation
import Observation

extension ForkRPC {
    static let delegationStatus = ForkRPC(method: "delegation.status")
    static let agentsList = ForkRPC(method: "agents.list")

    static func delegationPause(_ paused: Bool) -> ForkRPC {
        ForkRPC(method: "delegation.pause", params: ["paused": .bool(paused)])
    }
}

@MainActor
final class ForkMissionClient {
    private let http: HermesConnection
    private let cron: HermesCronClient

    init(saved connection: BotConnection, server: URL) {
        http = HermesConnections.shared.connection(for: connection, server: server)
        cron = HermesCronClient(http: http)
    }

    func board() async -> ForkMissionBoard {
        let client = BotClient(http: http)
        defer { client.close() }
        let joined: Error?
        do { try await client.connect(); joined = nil } catch { joined = error }
        let delegation: ForkMissionFeed<ForkMissionDelegationStatus> = await feed(joined) {
            try Self.decode(ForkMissionDelegationStatus.self, try await client.call(.fork(.delegationStatus)))
        }
        let processes: ForkMissionFeed<[ForkMissionProcessRow]> = await feed(joined) {
            try Self.decode(ForkMissionProcessList.self, try await client.call(.fork(.agentsList))).processes
        }
        let tasks: ForkMissionFeed<[ForkMissionTaskInput]> = await feed(nil) {
            Self.tasks(try await self.cron.cronJobs())
        }
        return ForkMissionBoard.assemble(delegation: delegation, tasks: tasks, processes: processes)
    }

    func perform(_ command: ForkMissionCommand, on mission: ForkMission) async throws {
        switch (mission.kind, command) {
        case (.delegation, .pause), (.delegation, .resume):
            let wanted = command == .pause
            let client = BotClient(http: http)
            defer { client.close() }
            try await client.connect()
            let reply = try await client.call(.fork(.delegationPause(wanted)))
            guard reply["paused"].flag == wanted else { throw BotFailure.unsupported }
        case (.task, .pause):
            _ = try await cron.pauseCron(jobID: mission.key, profile: mission.profile, reason: nil)
        case (.task, .resume):
            _ = try await cron.resumeCron(jobID: mission.key, profile: mission.profile)
        case (.task, .retry):
            do {
                _ = try await cron.runCron(jobID: mission.key, profile: mission.profile)
            } catch let error where Self.isUnansweredTrigger(error) {
                return
            }
        default:
            throw BotFailure.unsupported
        }
    }

    private func feed<Value>(_ joined: Error?, _ load: () async throws -> Value) async -> ForkMissionFeed<Value> {
        do {
            if let joined { throw joined }
            return .loaded(try await load())
        } catch {
            if Self.isUnsupported(error) { return .unsupported }
            return .failed(ForkMissionClient.message(error))
        }
    }

    static func tasks(_ list: CronJobList) -> [ForkMissionTaskInput] {
        list.jobs.compactMap { job in
            guard let id = job.jobId, !id.isEmpty else { return nil }
            let status = job.status
            return ForkMissionTaskInput(
                id: id, name: job.displayName, schedule: job.scheduleText, profile: job.profile,
                paused: status == .paused || status == .off, running: list.runningJobs[id] != nil,
                failed: status == .error || status == .needsAttention,
                lastError: ForkMissionText.clean(job.lastError)
            )
        }
    }

    static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ reply: BotJSON) throws -> Value {
        do { return try JSONDecoder().decode(type, from: try JSONEncoder().encode(reply)) } catch {
            throw BotFailure.unsupported
        }
    }

    private static func isUnsupported(_ error: Error) -> Bool {
        switch error as? BotFailure {
        case .unsupported, .rejected(-32601), .rejected(404): return true
        default: return false
        }
    }

    private static func isUnansweredTrigger(_ error: Error) -> Bool {
        if case .rejected(let status)? = error as? BotFailure { return status == 504 || status == 524 }
        guard case .network(let underlying)? = error as? APIError, let code = (underlying as? URLError)?.code else {
            return false
        }
        return code == .timedOut || code == .networkConnectionLost
    }
}

@MainActor @Observable
final class ForkMissionControlModel {
    static let refreshInterval: Duration = .seconds(5)

    private(set) var board: ForkMissionBoard?
    private(set) var busyMission: String?
    private(set) var actionError: String?

    @ObservationIgnored private let client: ForkMissionClient
    @ObservationIgnored private var generation = 0

    init(client: ForkMissionClient) {
        self.client = client
    }

    func refresh() async {
        generation += 1
        let mine = generation
        let next = await client.board()
        guard mine == generation, !Task.isCancelled, next != board else { return }
        board = next
    }

    func follow() async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: Self.refreshInterval) } catch { return }
        }
    }

    func availability(_ command: ForkMissionCommand, for mission: ForkMission) -> ForkMissionCommandState {
        mission.availability(command, busy: busyMission != nil)
    }

    func perform(_ command: ForkMissionCommand, on mission: ForkMission) async {
        guard availability(command, for: mission).isEnabled else { return }
        if command == .retry {
            retry(mission)
            return
        }
        busyMission = mission.id
        actionError = nil
        defer { busyMission = nil }
        do {
            try await client.perform(command, on: mission)
        } catch {
            actionError = ForkMissionClient.message(error)
        }
        await refresh()
    }

    private func retry(_ mission: ForkMission) {
        actionError = nil
        let client = client
        Task { [weak self] in
            do {
                try await client.perform(.retry, on: mission)
            } catch {
                self?.actionError = ForkMissionClient.message(error)
            }
            await self?.refresh()
        }
    }
}
