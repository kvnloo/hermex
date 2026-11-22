import XCTest
@testable import HermesMobile

final class ForkMissionTests: XCTestCase {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testDelegationStatusBuildsGateThenWorkerTree() throws {
        let status = try decode(ForkMissionDelegationStatus.self, """
        {"paused": true, "max_spawn_depth": 2, "max_concurrent_children": 3, "active": [
          {"subagent_id": "child", "parent_id": "root", "goal": "  Read docs ", "status": "running", "tool_count": 4},
          {"subagent_id": "root", "goal": "Ship it", "status": "running", "model": "m1", "started_at": 1700000000.5},
          {"subagent_id": "late", "parent_id": "gone", "status": "queued"},
          {"subagent_id": "", "status": "running"},
          {"goal": "no id"}
        ]}
        """)
        let board = ForkMissionBoard.assemble(delegation: .loaded(status), tasks: .loaded([]), processes: .loaded([]))
        let nodes = try XCTUnwrap(board.sections.first { $0.kind == .subagent }).nodes

        XCTAssertEqual(nodes.map(\.mission.key), ["spawning", "root", "child", "late"])
        XCTAssertEqual(nodes.map(\.depth), [0, 0, 1, 0])
        XCTAssertEqual(nodes[0].mission.state, .paused)
        XCTAssertEqual(nodes[2].mission.title, "Read docs")
        XCTAssertEqual(nodes[3].mission.state, .blocked)
        XCTAssertEqual(board.liveCount, 3)
    }

    func testUnsupportedCommandsAreDisabledWithAReason() {
        let worker = ForkMission(kind: .subagent, key: "w", title: "", state: .running)
        let process = ForkMission(kind: .process, key: "p", title: "npm run dev", state: .running)
        let task = ForkMission(kind: .task, key: "t", title: "Nightly", state: .running)
        let gate = ForkMission(kind: .delegation, key: "spawning", title: "", state: .running)

        XCTAssertEqual(worker.availability(.pause), .disabled(.hostHasNoControl))
        XCTAssertEqual(worker.availability(.stop), .disabled(.ownedByChat))
        XCTAssertEqual(worker.availability(.retry), .disabled(.hostHasNoControl))
        XCTAssertEqual(process.availability(.resume), .disabled(.hostHasNoControl))
        XCTAssertEqual(process.availability(.stop), .disabled(.ownedByChat))
        XCTAssertEqual(task.availability(.stop), .disabled(.hostHasNoControl))
        XCTAssertEqual(task.availability(.retry), .disabled(.runningNow))
        XCTAssertEqual(gate.availability(.stop), .disabled(.hostHasNoControl))
        for mission in [worker, process, task, gate] {
            for command in ForkMissionCommand.allCases where !mission.availability(command).isEnabled {
                XCTAssertNotNil(mission.availability(command).block, "\(mission.kind) \(command)")
            }
        }
    }

    func testPauseAndResumeFollowTheHostState() {
        var gate = ForkMission(kind: .delegation, key: "spawning", title: "", state: .running)
        XCTAssertEqual(gate.availability(.pause), .enabled)
        XCTAssertEqual(gate.availability(.resume), .disabled(.notPaused))
        gate.state = .paused
        XCTAssertEqual(gate.availability(.pause), .disabled(.alreadyPaused))
        XCTAssertEqual(gate.availability(.resume), .enabled)
        XCTAssertEqual(gate.availability(.resume, busy: true), .disabled(.busy))
    }

    func testTaskStateDecidesRetry() {
        let failed = ForkMissionBoard.mission(ForkMissionTaskInput(
            id: "t1", name: "Digest", schedule: "0 9 * * *", profile: "work", paused: false, running: false,
            failed: true, lastError: "boom"))
        let pausedRunning = ForkMissionBoard.mission(ForkMissionTaskInput(
            id: "t2", name: "Sync", paused: true, running: true, failed: true, lastError: "old"))
        let healthy = ForkMissionBoard.mission(ForkMissionTaskInput(
            id: "t3", name: "Ping", paused: false, running: false, failed: false, lastError: "stale"))

        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.lastError, "boom")
        XCTAssertEqual(failed.profile, "work")
        XCTAssertEqual(failed.availability(.retry), .enabled)
        XCTAssertEqual(pausedRunning.state, .running)
        XCTAssertEqual(healthy.availability(.retry), .disabled(.nothingToRetry))
        XCTAssertNil(healthy.lastError)
    }

    func testProcessesDecodeAndMapStatus() throws {
        let list = try decode(ForkMissionProcessList.self, """
        {"processes": [
          {"session_id": "proc_1", "command": "npm run dev", "status": "running", "uptime": 42},
          {"session_id": "proc_2", "command": "make", "status": "exited", "uptime": 9},
          {"command": "no id", "status": "running", "uptime": 1}
        ]}
        """)
        let missions = list.processes.map(\.mission)

        XCTAssertEqual(missions.map(\.key), ["proc_1", "proc_2"])
        XCTAssertEqual(missions.map(\.state), [.running, .done])
        XCTAssertEqual(missions[0].uptime, 42)
        XCTAssertEqual(missions[1].availability(.stop), .disabled(.notRunning))
    }

    func testFeedsWithoutDataBecomeSectionNotices() {
        let board = ForkMissionBoard.assemble(delegation: .unsupported, tasks: .failed("offline"), processes: .loaded([]))

        XCTAssertEqual(board.sections.map(\.kind), [.subagent, .task, .process])
        XCTAssertEqual(board.sections.map(\.notice), [.unsupported, .failed("offline"), nil])
        XCTAssertTrue(board.missions.isEmpty)
    }

    func testTreeSurvivesCyclesAndDuplicates() {
        let missions = [
            ForkMission(kind: .subagent, key: "a", parentKey: "b", title: "", state: .running),
            ForkMission(kind: .subagent, key: "b", parentKey: "a", title: "", state: .running),
            ForkMission(kind: .subagent, key: "a", title: "", state: .running),
            ForkMission(kind: .subagent, key: "c", parentKey: "c", title: "", state: .running)
        ]
        let nodes = ForkMissionBoard.tree(missions)

        XCTAssertEqual(Set(nodes.map(\.mission.key)), ["a", "b", "c"])
        XCTAssertEqual(nodes.count, 3)
    }
}
