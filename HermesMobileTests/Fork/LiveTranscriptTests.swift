import XCTest
@testable import HermesMobile

final class LiveTranscriptTests: XCTestCase {
    private struct Step: LiveStepStatus, Equatable {
        let id: String
        var liveStepIsRunning = false
        var liveStepIsFailed = false
    }

    private func user(_ id: String, _ text: String) -> LiveTranscriptMessage<Step> {
        LiveTranscriptMessage(id: id, isUser: true, text: text, steps: [])
    }

    private func assistant(_ id: String, _ text: String, _ steps: [Step] = []) -> LiveTranscriptMessage<Step> {
        LiveTranscriptMessage(id: id, isUser: false, text: text, steps: steps)
    }

    func testEachSpokenTurnGathersItsToolStepsAndReplies() {
        let turns = LiveTranscript.turns([
            user("u1", "check the build"),
            assistant("a1", "Looking.", [Step(id: "t1")]),
            assistant("a2", "It passed.", [Step(id: "t2")]),
            user("u2", "thanks"),
            assistant("a3", "Anytime."),
        ], liveSteps: [])

        XCTAssertEqual(turns.map(\.id), ["u1", "u2"])
        XCTAssertEqual(turns[0].said, "check the build")
        XCTAssertEqual(turns[0].steps.map(\.id), ["t1", "t2"])
        XCTAssertEqual(turns[0].reply, "Looking.\n\nIt passed.")
        XCTAssertTrue(turns[1].steps.isEmpty)
        XCTAssertEqual(turns[1].reply, "Anytime.")
    }

    func testRunningStepsJoinTheTurnStillInProgressBeforeAnyReply() {
        let turns = LiveTranscript.turns([
            user("u1", "first"),
            assistant("a1", "Done."),
            user("u2", "run the long migration"),
            assistant("a2", ""),
        ], liveSteps: [Step(id: "live", liveStepIsRunning: true)])

        XCTAssertEqual(turns.last?.id, "u2")
        XCTAssertEqual(turns.last?.steps.map(\.id), ["live"])
        XCTAssertEqual(turns.last?.reply, "")
        XCTAssertTrue(LiveProgressSummary(turns.last?.steps ?? []).isWorking)
        XCTAssertTrue(turns.first?.steps.isEmpty ?? false)
    }

    func testSummaryCountsRunningAndFailedSteps() {
        let summary = LiveProgressSummary([
            Step(id: "a"),
            Step(id: "b", liveStepIsFailed: true),
            Step(id: "c", liveStepIsRunning: true),
        ])

        XCTAssertEqual(summary, LiveProgressSummary([Step(id: "x"), Step(id: "y", liveStepIsFailed: true), Step(id: "z", liveStepIsRunning: true)]))
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.running, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertFalse(LiveProgressSummary([Step(id: "done")]).isWorking)
    }
}
