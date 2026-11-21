import XCTest
@testable import HermesMobile

final class LiveModeMachineTests: XCTestCase {
    func testOneFullTurnListensSendsThinksSpeaksAndListensAgain() {
        var machine = LiveModeMachine()
        XCTAssertEqual(machine.handle(.start, at: 0), [.startListening])
        XCTAssertEqual(machine.handle(.heard("what's the"), at: 1), [])
        XCTAssertEqual(machine.handle(.heard("what's the weather"), at: 2), [])
        XCTAssertEqual(machine.handle(.tick, at: 3), [])
        XCTAssertEqual(machine.handle(.tick, at: 3.5), [.stopListening, .send("what's the weather")])
        XCTAssertEqual(machine.phase, .sending)
        XCTAssertEqual(machine.handle(.sendAccepted, at: 4), [])
        XCTAssertEqual(machine.phase, .thinking)
        XCTAssertEqual(machine.handle(.replyFinished("**Sunny**, 21°C."), at: 9), [.speak(["Sunny, 21°C."])])
        XCTAssertEqual(machine.handle(.speechFinished, at: 11), [.startListening])
        XCTAssertEqual(machine.phase, .listening)
        XCTAssertEqual(machine.heard, "")
        XCTAssertEqual(machine.turns, 1)
    }

    func testSilenceAfterAReplyPausesButNotBeforeTheFirstTurn() {
        var machine = LiveModeMachine()
        _ = machine.handle(.start, at: 0)
        XCTAssertEqual(machine.handle(.tick, at: 30), [])
        XCTAssertEqual(machine.phase, .listening)
        _ = machine.handle(.heard("hi"), at: 31)
        _ = machine.handle(.tick, at: 33)
        _ = machine.handle(.sendAccepted, at: 33)
        _ = machine.handle(.replyFinished("Hello."), at: 34)
        _ = machine.handle(.speechFinished, at: 35)
        XCTAssertEqual(machine.handle(.tick, at: 44), [])
        XCTAssertEqual(machine.handle(.tick, at: 45.1), [.stopListening])
        XCTAssertEqual(machine.phase, .paused)
        XCTAssertEqual(machine.handle(.start, at: 50), [.startListening])
    }

    func testLongMonologueIsCutAtTheMaximum() {
        var machine = LiveModeMachine()
        _ = machine.handle(.start, at: 0)
        for second in 1...60 { _ = machine.handle(.heard("word \(second)"), at: Double(second)) }
        XCTAssertEqual(machine.handle(.tick, at: 60), [.stopListening, .send("word 60")])
    }

    func testEmptyReplyGoesStraightBackToListening() {
        var machine = LiveModeMachine()
        _ = machine.handle(.start, at: 0)
        _ = machine.handle(.heard("run it"), at: 0.5)
        _ = machine.handle(.tick, at: 2)
        _ = machine.handle(.sendAccepted, at: 2)
        XCTAssertEqual(machine.handle(.replyFinished("```\nls\n```"), at: 3), [.startListening])
    }

    func testBargeInStopsSpeechAndListens() {
        var machine = LiveModeMachine()
        _ = machine.handle(.start, at: 0)
        _ = machine.handle(.heard("tell me a story"), at: 0.5)
        _ = machine.handle(.tick, at: 2)
        _ = machine.handle(.sendAccepted, at: 2)
        _ = machine.handle(.replyFinished("Once upon a time."), at: 3)
        XCTAssertEqual(machine.handle(.bargeIn, at: 4), [.stopSpeaking, .startListening])
    }

    func testRefusalsAndFailuresStopWithoutResending() {
        var machine = LiveModeMachine()
        _ = machine.handle(.start, at: 0)
        _ = machine.handle(.heard("hi"), at: 0.5)
        _ = machine.handle(.tick, at: 2)
        XCTAssertEqual(machine.handle(.sendRefused, at: 2), [])
        XCTAssertEqual(machine.phase, .failed)
        XCTAssertEqual(machine.handle(.tick, at: 9), [])
        XCTAssertEqual(machine.handle(.start, at: 10), [.startListening])
    }

    func testStopClosesFromAnyPhase() {
        var machine = LiveModeMachine()
        _ = machine.handle(.start, at: 0)
        XCTAssertEqual(machine.handle(.stop, at: 1), [.stopListening, .close])
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.handle(.tick, at: 2), [])
    }

    func testEventsOutOfPhaseAreIgnored() {
        var machine = LiveModeMachine()
        XCTAssertEqual(machine.handle(.replyFinished("x"), at: 0), [])
        XCTAssertEqual(machine.handle(.speechFinished, at: 0), [])
        XCTAssertEqual(machine.handle(.heard("x"), at: 0), [])
        XCTAssertEqual(machine.phase, .idle)
    }
}

final class LiveSpeechTextTests: XCTestCase {
    func testMarkdownBecomesPlainSpeech() {
        let markdown = """
        # Plan
        Here is **bold**, _soft_ and `code` with a [link](https://example.com).
        - first item
        1. second item
        > quoted
        | a | b |
        |---|---|
        ```swift
        let hidden = true
        ```
        See https://example.com/path for more. ![img](x.png)
        """
        XCTAssertEqual(LiveSpeechText.speakable(markdown),
                       "Plan Here is bold, soft and code with a link. first item second item quoted a b See for more.")
    }

    func testSnakeCaseIsNotTreatedAsEmphasis() {
        XCTAssertEqual(LiveSpeechText.speakable("use file_name_here now"), "use file_name_here now")
    }

    func testChunksKeepSentencesTogetherUnderTheLimit() {
        let sentence = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces) + "."
        let chunks = LiveSpeechText.chunks([sentence, sentence, "Short one."].joined(separator: " "))
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= LiveSpeechText.chunkLimit })
        XCTAssertTrue(chunks[1].hasSuffix("Short one."))
    }

    func testOverlongSentenceIsSplitAtASpace() {
        let long = String(repeating: "abcdefghi ", count: 50)
        let chunks = LiveSpeechText.chunks(long.trimmingCharacters(in: .whitespaces))
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= LiveSpeechText.chunkLimit && !$0.hasPrefix(" ") })
        XCTAssertEqual(chunks.joined(separator: " ").split(separator: " ").count, 50)
    }
}

final class LiveOrbGeometryTests: XCTestCase {
    func testSmoothingRisesFastAndFallsSlowly() {
        XCTAssertEqual(LiveOrbGeometry.smoothed(previous: 0, level: 1), 0.55, accuracy: 1e-9)
        XCTAssertEqual(LiveOrbGeometry.smoothed(previous: 1, level: 0), 0.88, accuracy: 1e-9)
        XCTAssertEqual(LiveOrbGeometry.smoothed(previous: 0, level: 7), 0.55, accuracy: 1e-9)
    }

    func testListeningOrbGrowsWithLevel() {
        let quiet = LiveOrbGeometry.voiceScale(level: 0, time: 0, phase: .listening)
        let loud = LiveOrbGeometry.voiceScale(level: 1, time: 0, phase: .listening)
        XCTAssertEqual(loud - quiet, 0.35, accuracy: 1e-9)
    }

    func testThinkingDotsCircleTheCenter() {
        let dots = LiveOrbGeometry.thinkingDots(time: 1.3, count: 5)
        XCTAssertEqual(dots.count, 5)
        for dot in dots {
            let distance = (dot.x * dot.x + dot.y * dot.y).squareRoot()
            XCTAssertEqual(distance, 0.32, accuracy: 0.32 * 0.13)
            XCTAssertTrue((0...1).contains(dot.opacity))
        }
        XCTAssertTrue(LiveOrbGeometry.thinkingDots(time: 0, count: 0).isEmpty)
    }

    func testBlobStaysNearTheUnitCircle() {
        let points = LiveOrbGeometry.blob(level: 1, time: 2)
        XCTAssertEqual(points.count, 48)
        for point in points {
            let radius = (point.x * point.x + point.y * point.y).squareRoot()
            XCTAssertTrue((0.84...1.16).contains(radius), "\(radius)")
        }
    }
}

final class LiveModeRequestTests: XCTestCase {
    func testRequestsExpireAfterThirtySeconds() {
        XCTAssertTrue(LiveModeRequest.isFresh(100, now: 100))
        XCTAssertTrue(LiveModeRequest.isFresh(100, now: 130))
        XCTAssertFalse(LiveModeRequest.isFresh(100, now: 130.5))
        XCTAssertFalse(LiveModeRequest.isFresh(0, now: 10))
        XCTAssertFalse(LiveModeRequest.isFresh(100, now: 99))
    }
}
