import XCTest
@testable import HermesMobile

final class CouncilRunTests: XCTestCase {
    private func json(_ body: String) -> Data { Data(body.utf8) }

    private let minimal = """
    {"schema":"glide.council-run/v1","brief":"Ship it?","rounds":2,"extra":true,
     "seats":[{"id":"a","name":"Ada","family":"Anthropic"},{"id":"b","name":"Bo","family":"anthropic"},{"id":"c","name":"Cy","family":"Mistral"}],
     "events":[{"type":"spawn","seat":"a"},{"type":"turn","seat":"a","round":1},{"type":"turn","seat":"b","round":2,"cites":["a","c"]}],
     "verdicts":[{"seat":"a","stance":"agree","text":"Yes."},{"seat":"b","stance":"dissent","text":"No."}]}
    """

    func testParsesARunAndAssignsFamilyMineralsInOrder() throws {
        let run = try CouncilRun.parse(json: json(minimal))
        XCTAssertEqual(run.seats.map(\.mineral), [.citrine, .rose, .clear])
        XCTAssertEqual(run.events[2], .turn(seat: 1, round: 2, cites: [0, 2]))
        XCTAssertEqual(run.verdicts.map(\.stance), [.agree, .dissent])
        XCTAssertNil(run.outcome)
        XCTAssertEqual(run.helpers, 1)
    }

    func testRejectsRunsThatWouldDrawSomethingTheCouncilDidNotSay() {
        let cases: [(String, String)] = [
            (minimal.replacingOccurrences(of: "v1", with: "v2"), "schema"),
            (minimal.replacingOccurrences(of: "\"round\":2", with: "\"round\":3"), "events.2.round"),
            (minimal.replacingOccurrences(of: "\"cites\":[\"a\",\"c\"]", with: "\"cites\":[\"z\"]"), "events.2.cites.0"),
            (minimal.replacingOccurrences(of: "{\"seat\":\"b\",\"stance\":\"dissent\"", with: "{\"seat\":\"a\",\"stance\":\"dissent\""), "verdicts.1.seat"),
            (minimal.replacingOccurrences(of: "\"id\":\"b\"", with: "\"id\":\"a\""), "seats.1.id"),
            (minimal.replacingOccurrences(of: "\"stance\":\"agree\"", with: "\"stance\":\"maybe\""), "verdicts.0.stance"),
        ]
        for (body, path) in cases {
            XCTAssertThrowsError(try CouncilRun.parse(json: json(body)), path) { error in
                XCTAssertEqual((error as? CouncilRunError)?.path, path)
            }
        }
    }

    func testFindsTheLatestRunInAssistantReplies() throws {
        let older = "Here is the council:\n```json\n\(minimal)\n```"
        let newer = "```json\n\(minimal.replacingOccurrences(of: "Ship it?", with: "Rewrite it?"))\n```\nDone."
        let broken = "```json\n{\"schema\":\"glide.council-run/v1\"}\n```"
        XCTAssertEqual(CouncilRun.latest(in: [older, newer, broken, "plain reply"])?.brief, "Rewrite it?")
        XCTAssertEqual(CouncilRun.latest(in: [minimal])?.brief, "Ship it?")
        XCTAssertNil(CouncilRun.latest(in: ["no council here", broken]))
    }

    func testDemoRunIsValidAndCarriedByMajority() {
        let demo = CouncilRun.demo
        XCTAssertEqual(demo.seats.map(\.mineral), [.malachite, .labradorite, .rose, .citrine])
        XCTAssertEqual([demo.count(.agree), demo.count(.dissent), demo.count(.abstain)], [3, 1, 0])
        XCTAssertTrue(demo.carried)
    }
}

final class CouncilExchangeTests: XCTestCase {
    private let run = CouncilRun.demo

    func testPhasesFollowOneClockFromBriefToReport() {
        let timing = CouncilTiming(run: run, reduceMotion: false)
        let at = { (t: Double?) in CouncilExchange(run: self.run, timing: timing, elapsed: t) }
        XCTAssertEqual(at(nil).phase, .seated)
        XCTAssertEqual(at(nil).brief, run.brief)
        XCTAssertEqual(at(0).phase, .brief)
        XCTAssertEqual(at(0).brief, "")
        XCTAssertLessThan(at(timing.typing / 4).brief.count, run.brief.count)
        XCTAssertEqual(at(timing.typing / 4).constraints, ["", ""])
        XCTAssertEqual(at(timing.typing).phase, .sending)
        XCTAssertEqual(at(timing.typing).constraints, run.constraints)
        XCTAssertEqual(at(timing.working + 0.01).phase, .working)
        XCTAssertEqual(at(timing.report).phase, .report)
        XCTAssertEqual(at(timing.report).clauses.count, 1)
        XCTAssertEqual(at(timing.total).phase, .done)
        XCTAssertEqual(at(timing.total).clauses, CouncilReport.clauses(run))
        XCTAssertEqual(at(timing.total).closed, Set(run.seats.indices))
    }

    func testSeatsReceiveTheBriefThenThinkDraftAndClose() {
        let timing = CouncilTiming(run: run, reduceMotion: false)
        let sending = CouncilExchange(run: run, timing: timing, elapsed: timing.typing + CouncilTiming.delivery * 0.5)
        XCTAssertEqual(sending.seats, [.received, .received, .waiting, .waiting])
        let firstTurn = run.events.firstIndex { !$0.isSpawn }!
        let drafting = CouncilExchange(run: run, timing: timing, elapsed: timing.working + timing.starts[firstTurn] + 0.1)
        XCTAssertEqual(drafting.seats[0], .drafting)
        XCTAssertEqual(drafting.seats[1], .thinking)
        XCTAssertEqual(drafting.narration, .answersAlone(seat: 0))
        XCTAssertEqual(drafting.round, 1)
        let lastTurn = run.events.lastIndex { !$0.isSpawn }!
        let closing = CouncilExchange(run: run, timing: timing, elapsed: timing.working + timing.starts[lastTurn] + 0.1)
        XCTAssertEqual(closing.narration, .closes(round: 4, seat: 3))
        XCTAssertEqual(closing.closed, [0, 1, 2])
    }

    func testReduceMotionSkipsTypingDeliveryAndClauseReveal() {
        let timing = CouncilTiming(run: run, reduceMotion: true)
        XCTAssertEqual(timing.typing, 0)
        XCTAssertEqual(timing.working, 0)
        XCTAssertEqual(timing.total, timing.report)
        XCTAssertEqual(CouncilExchange(run: run, timing: timing, elapsed: 0).brief, run.brief)
    }

    func testReportQuotesTheRunAndItsLastCitationsOnly() {
        let clauses = CouncilReport.clauses(run)
        XCTAssertEqual(clauses.first, .verdict(outcome: "Ship the plugin first", recorded: true))
        XCTAssertEqual(clauses[2], .replies(.dissent, [run.verdicts[1]]))
        XCTAssertEqual(clauses[3], .replies(.abstain, []))
        guard case .receipts(let receipts) = clauses.last else { return XCTFail("no receipts clause") }
        XCTAssertEqual(receipts.map(\.round), [4, 4, 4, 4])
        XCTAssertEqual(receipts[0], CouncilReceipt(round: 4, seat: 0, cites: [1]))
    }
}

final class CouncilReaderTests: XCTestCase {
    private let run = CouncilRun.demo

    func testReadAloudReadsTheBriefWhileItIsSentAndHoldsTheClock() {
        var reader = CouncilReader(run: run, reduceMotion: false)
        _ = reader.handle(.toggleReadAloud, at: 0)
        XCTAssertEqual(reader.handle(.convene, at: 10), [.startClock])
        XCTAssertEqual(reader.handle(.tick, at: 10.1), [])
        let sending = 10 + reader.timing.typing + 0.1
        XCTAssertEqual(reader.handle(.tick, at: sending), [.read(.brief)])
        XCTAssertEqual(reader.reading, .brief)
        let held = reader.elapsed(at: sending)
        XCTAssertEqual(reader.elapsed(at: sending + 30), held)
        _ = reader.handle(.readingFinished, at: sending + 30)
        XCTAssertNil(reader.reading)
        XCTAssertEqual(reader.elapsed(at: sending + 30)!, held!, accuracy: 0.0001)
        XCTAssertEqual(reader.handle(.tick, at: sending + 31), [])
    }

    func testReportIsReadOnceAtTheEndAndTheClockStopsAfterIt() {
        var reader = CouncilReader(run: run, reduceMotion: false)
        _ = reader.handle(.toggleReadAloud, at: 0)
        _ = reader.handle(.convene, at: 0)
        _ = reader.handle(.tick, at: reader.timing.typing + 0.01)
        _ = reader.handle(.readingFinished, at: reader.timing.typing + 0.01)
        let end = reader.timing.total + 1
        XCTAssertEqual(reader.handle(.tick, at: end), [.read(.report)])
        XCTAssertFalse(reader.canConvene)
        XCTAssertEqual(reader.handle(.readingFinished, at: end + 5), [])
        XCTAssertEqual(reader.handle(.tick, at: end + 5), [.stopClock])
        XCTAssertTrue(reader.canConvene)
        XCTAssertEqual(reader.handle(.tick, at: end + 6), [])
    }

    func testWithoutReadAloudTheRunPlaysSilentlyAndStops() {
        var reader = CouncilReader(run: run, reduceMotion: false)
        _ = reader.handle(.convene, at: 0)
        XCTAssertEqual(reader.handle(.convene, at: 1), [])
        XCTAssertEqual(reader.handle(.tick, at: reader.timing.typing + 0.1), [])
        XCTAssertEqual(reader.handle(.tick, at: reader.timing.total), [.stopClock])
    }

    func testMuteAndReturnToCardStopSpeechAndResumeTheClock() {
        var reader = CouncilReader(run: run, reduceMotion: false)
        _ = reader.handle(.toggleReadAloud, at: 0)
        _ = reader.handle(.convene, at: 0)
        let t = reader.timing.typing + 0.1
        _ = reader.handle(.tick, at: t)
        XCTAssertEqual(reader.handle(.toggleMute, at: t + 2), [.stopSpeaking])
        XCTAssertEqual(reader.elapsed(at: t + 3)!, t + 1, accuracy: 0.0001)
        XCTAssertEqual(reader.handle(.tick, at: reader.timing.total + 10), [.stopClock])
        _ = reader.handle(.toggleMute, at: 100)
        XCTAssertEqual(reader.handle(.toggleReadAloud, at: 100), [])
        XCTAssertEqual(reader.handle(.toggleReadAloud, at: 101), [.startClock, .read(.report)])
        XCTAssertEqual(reader.handle(.returnToCard, at: 102), [.stopSpeaking])
        XCTAssertNil(reader.reading)
    }

    func testReduceMotionReadsTheBriefOnConveneAndCloseStopsEverything() {
        var reader = CouncilReader(run: run, reduceMotion: true)
        _ = reader.handle(.toggleReadAloud, at: 0)
        XCTAssertEqual(reader.handle(.convene, at: 0), [.startClock, .read(.brief)])
        XCTAssertEqual(reader.handle(.close, at: 2), [.stopSpeaking, .stopClock])
        XCTAssertNil(reader.reading)
        XCTAssertTrue(reader.canConvene)
    }
}
