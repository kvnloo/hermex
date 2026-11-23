import XCTest
@testable import HermesMobile

final class LiveCallRoomTests: XCTestCase {
    func testCallSurvivesDismissAndPresent() {
        var room = LiveCallRoom()
        XCTAssertEqual(room.requestStart("chat-a"), [.begin("chat-a")])
        let callID = room.callID
        XCTAssertEqual(room.dismiss(), [.minimize])
        XCTAssertTrue(room.isRunning)
        XCTAssertEqual(room.present(), [.restore])
        XCTAssertEqual(room.requestStart("chat-a"), [.restore])
        XCTAssertEqual(room.callID, callID)
        XCTAssertEqual(room.chat, "chat-a")
    }

    func testEndFromTheBarEndsTheCall() {
        var room = LiveCallRoom()
        _ = room.requestStart("chat-a")
        _ = room.dismiss()
        XCTAssertEqual(room.end(.bar), [.end(.bar)])
        XCTAssertFalse(room.isRunning)
        XCTAssertEqual(room.dismiss(), [])
        XCTAssertEqual(room.end(.bar), [])
    }

    func testLiveActivityEndsAndReturnsOnlyItsOwnCall() throws {
        var room = LiveCallRoom()
        _ = room.requestStart("chat-a")
        let first = try XCTUnwrap(room.callID)
        XCTAssertEqual(room.activity(.returnToCall, callID: first), [.restore])
        XCTAssertEqual(room.activity(.end, callID: "stale-call"), [])
        XCTAssertTrue(room.isRunning)
        XCTAssertEqual(room.activity(.end, callID: first), [.end(.liveActivity)])
        XCTAssertFalse(room.isRunning)
        XCTAssertEqual(room.activity(.returnToCall, callID: first), [])
        _ = room.requestStart("chat-a")
        XCTAssertNotEqual(room.callID, first)
        XCTAssertEqual(room.activity(.end, callID: first), [])
    }

    func testSecondChatAsksOnceThenSwitchesOrKeeps() {
        var room = LiveCallRoom()
        _ = room.requestStart("chat-a")
        XCTAssertEqual(room.requestStart("chat-b"), [])
        XCTAssertEqual(room.switchPrompt, .init(current: "chat-a", requested: "chat-b"))
        XCTAssertEqual(room.requestStart("chat-c"), [])
        XCTAssertEqual(room.switchPrompt?.requested, "chat-b")
        XCTAssertEqual(room.resolveSwitch(switching: false), [])
        XCTAssertEqual(room.chat, "chat-a")
        XCTAssertNil(room.switchPrompt)

        _ = room.requestStart("chat-b")
        XCTAssertEqual(room.resolveSwitch(switching: true), [.end(.replaced), .begin("chat-b")])
        XCTAssertEqual(room.chat, "chat-b")
        XCTAssertNil(room.switchPrompt)
        XCTAssertEqual(room.resolveSwitch(switching: true), [])
    }

    func testSwitchAfterTheCallAlreadyEndedJustStarts() {
        var room = LiveCallRoom()
        _ = room.requestStart("chat-a")
        _ = room.requestStart("chat-b")
        _ = room.end(.limit)
        XCTAssertNil(room.switchPrompt)
        XCTAssertEqual(room.requestStart("chat-b"), [.begin("chat-b")])
    }
}

final class LiveApprovalSpeechTests: XCTestCase {
    func testClearCommandsMatch() {
        for phrase in ["Allow", "allow it", "Yes, allow it once please.", "approve", "OK approve that"] {
            XCTAssertEqual(LiveApprovalSpeech.command(phrase), .allow, phrase)
        }
        for phrase in ["Deny.", "deny it", "reject", "decline that", "No", "nope"] {
            XCTAssertEqual(LiveApprovalSpeech.command(phrase), .deny, phrase)
        }
        for phrase in ["open it", "Open the chat", "show me", "open"] {
            XCTAssertEqual(LiveApprovalSpeech.command(phrase), .open, phrase)
        }
    }

    func testRefusalsThatMentionAllowDeny() {
        for phrase in ["don't allow", "Don\u{2019}t allow it", "do not approve", "never allow that", "no, don't allow it", "not allowed"] {
            XCTAssertEqual(LiveApprovalSpeech.command(phrase), .deny, phrase)
        }
    }

    func testAmbiguousSpeechNeverApproves() {
        let phrases = [
            "yes", "ok", "sure", "go ahead", "allow always", "always allow", "allow, no", "no allow",
            "allow it, don't", "don't deny", "don't open it", "wait", "what is it asking",
            "allow it to delete everything in the repo", "", "the chat",
        ]
        for phrase in phrases {
            XCTAssertNil(LiveApprovalSpeech.command(phrase), phrase)
        }
    }
}

final class LiveAskRouteTests: XCTestCase {
    private let approval = LiveAsk.approval(id: "a1", summary: "Run ls", allowsOnce: true, allowsDeny: true)
    private let laneQuestion = LiveAsk.question(id: "q2", summary: "Which branch?")

    func testOnlyTheCallsLanesReachLive() {
        let other = LiveAskCandidate(ask: approval, lane: 9)
        XCTAssertNil(LiveAskRoute.pick([other], callLanes: [0, 1], selectedLane: 0))
    }

    func testSelectedLaneWinsThenAnyCallLane() {
        let root = LiveAskCandidate(ask: approval, lane: 0)
        let lane = LiveAskCandidate(ask: laneQuestion, lane: 1)
        XCTAssertEqual(LiveAskRoute.pick([root, lane], callLanes: [0, 1], selectedLane: 1), laneQuestion)
        XCTAssertEqual(LiveAskRoute.pick([root, lane], callLanes: [0, 1], selectedLane: 0), approval)
        XCTAssertEqual(LiveAskRoute.pick([lane], callLanes: [0, 1], selectedLane: 0), laneQuestion)
        XCTAssertNil(LiveAskRoute.pick([], callLanes: [0], selectedLane: 0))
    }

    func testOffersFollowTheRequestChoices() {
        XCTAssertEqual(approval.offers, [.allow, .deny, .open])
        XCTAssertEqual(LiveAsk.approval(id: "a", summary: "", allowsOnce: false, allowsDeny: true).offers, [.deny, .open])
        XCTAssertEqual(laneQuestion.offers, [.open])
    }
}

final class LiveModeMachineCallTests: XCTestCase {
    private let ask = LiveAsk.approval(id: "req-1", summary: "Run rm build", allowsOnce: true, allowsDeny: true)

    private func thinking() -> LiveModeMachine {
        var machine = LiveModeMachine()
        _ = machine.handle(.start, at: 0)
        _ = machine.handle(.heard("clean the build"), at: 0.5)
        _ = machine.handle(.tick, at: 2)
        _ = machine.handle(.sendAccepted, at: 2)
        return machine
    }

    func testMinimizeKeepsTheCallRunningAndRestoreReturns() {
        var machine = thinking()
        XCTAssertEqual(machine.handle(.minimize, at: 3), [])
        XCTAssertTrue(machine.isMinimized)
        XCTAssertEqual(machine.phase, .thinking)
        XCTAssertEqual(machine.handle(.replyFinished("Done."), at: 4), [.speak(["Done."])])
        XCTAssertEqual(machine.handle(.speechFinished, at: 5), [.startListening])
        XCTAssertTrue(machine.isMinimized)
        XCTAssertEqual(machine.handle(.restore, at: 6), [])
        XCTAssertFalse(machine.isMinimized)
        XCTAssertEqual(machine.phase, .listening)
    }

    func testStopFromMinimizedClosesAndResets() {
        var machine = thinking()
        _ = machine.handle(.minimize, at: 3)
        XCTAssertEqual(machine.handle(.stop, at: 4), [.stopListening, .close])
        XCTAssertFalse(machine.isActive)
        XCTAssertFalse(machine.isMinimized)
        XCTAssertEqual(machine.handle(.tick, at: 5), [])
    }

    func testCardsWhileMinimizedRaiseTheDotAndAreNeverSpoken() {
        var machine = thinking()
        _ = machine.handle(.minimize, at: 3)
        let reply = "Here is the chart.\n```openui\nroot = Card([])\n```"
        XCTAssertEqual(machine.handle(.replyFinished(reply), at: 4), [.speak(["Here is the chart."])])
        XCTAssertTrue(machine.hasUnseenCard)
        _ = machine.handle(.restore, at: 5)
        XCTAssertFalse(machine.hasUnseenCard)
    }

    func testCardsWhileShownDoNotRaiseTheDot() {
        var machine = thinking()
        _ = machine.handle(.replyFinished("```openui\nroot = Card([])\n```"), at: 4)
        XCTAssertFalse(machine.hasUnseenCard)
    }

    func testMuteStopsTheMicButLetsTheReplyFinish() {
        var machine = thinking()
        XCTAssertEqual(machine.handle(.mute, at: 3), [])
        XCTAssertEqual(machine.handle(.replyFinished("Sure."), at: 4), [.speak(["Sure."])])
        XCTAssertEqual(machine.handle(.speechFinished, at: 5), [])
        XCTAssertEqual(machine.phase, .paused)
        XCTAssertEqual(machine.handle(.unmute, at: 6), [.startListening])
        XCTAssertEqual(machine.handle(.mute, at: 7), [.stopListening])
        XCTAssertEqual(machine.phase, .paused)
    }

    func testAQuietCallEndsAtTheLimit() {
        var machine = LiveModeMachine()
        _ = machine.handle(.start, at: 0)
        _ = machine.handle(.mute, at: 1)
        XCTAssertEqual(machine.handle(.tick, at: 1 + LiveModeMachine.quietLimit - 1), [])
        XCTAssertEqual(machine.handle(.tick, at: 1 + LiveModeMachine.quietLimit), [.close])
        XCTAssertFalse(machine.isActive)
    }

    func testAnApprovalIsAnnouncedOnceThenAnsweredBySpeech() {
        var machine = thinking()
        XCTAssertEqual(machine.handle(.askOpened(ask), at: 3), [.announceAsk(ask)])
        XCTAssertEqual(machine.handle(.askOpened(ask), at: 3.2), [])
        XCTAssertEqual(machine.handle(.speechFinished, at: 4), [.startListening])
        _ = machine.handle(.heard("allow it"), at: 4.5)
        XCTAssertEqual(machine.handle(.tick, at: 6), [.stopListening, .answerAsk("req-1", .allow)])
        XCTAssertEqual(machine.phase, .thinking)
        XCTAssertNil(machine.ask)
        XCTAssertEqual(machine.handle(.askOpened(ask), at: 6.2), [])
        XCTAssertEqual(machine.handle(.replyFinished("Cleaned."), at: 8), [.speak(["Cleaned."])])
    }

    func testAmbiguousSpeechAsksAgainAndIsNeverSent() {
        var machine = thinking()
        _ = machine.handle(.askOpened(ask), at: 3)
        _ = machine.handle(.speechFinished, at: 4)
        _ = machine.handle(.heard("yes"), at: 4.5)
        XCTAssertEqual(machine.handle(.tick, at: 6), [.stopListening, .askAgain(ask)])
        XCTAssertEqual(machine.phase, .speaking)
        XCTAssertEqual(machine.handle(.speechFinished, at: 7), [.startListening])
        _ = machine.handle(.heard("don't allow that"), at: 7.5)
        XCTAssertEqual(machine.handle(.tick, at: 9), [.stopListening, .answerAsk("req-1", .deny)])
    }

    func testAQuestionOnlyOffersOpen() {
        let question = LiveAsk.question(id: "q", summary: "Which file?")
        var machine = thinking()
        _ = machine.handle(.askOpened(question), at: 3)
        _ = machine.handle(.speechFinished, at: 4)
        _ = machine.handle(.heard("allow"), at: 4.5)
        XCTAssertEqual(machine.handle(.tick, at: 6), [.stopListening, .askAgain(question)])
        _ = machine.handle(.speechFinished, at: 7)
        _ = machine.handle(.heard("open it"), at: 7.5)
        XCTAssertEqual(machine.handle(.tick, at: 9), [.stopListening, .answerAsk("q", .open)])
    }

    func testATapOrAnAnswerElsewhereSettlesTheAsk() {
        var machine = thinking()
        _ = machine.handle(.askOpened(ask), at: 3)
        XCTAssertEqual(machine.handle(.askHandled("req-1"), at: 3.5), [.stopSpeaking])
        XCTAssertEqual(machine.phase, .thinking)
        XCTAssertEqual(machine.handle(.askOpened(ask), at: 4), [])

        var elsewhere = thinking()
        _ = elsewhere.handle(.askOpened(ask), at: 3)
        _ = elsewhere.handle(.speechFinished, at: 4)
        XCTAssertEqual(elsewhere.handle(.askClosed("req-1"), at: 5), [.stopListening])
        XCTAssertEqual(elsewhere.phase, .thinking)
    }

    func testAFailedAnswerCanBeAskedAgainAfterItCloses() {
        var machine = thinking()
        _ = machine.handle(.askOpened(ask), at: 3)
        _ = machine.handle(.askHandled("req-1"), at: 3.5)
        _ = machine.handle(.askClosed("req-1"), at: 4)
        XCTAssertEqual(machine.handle(.askOpened(ask), at: 4.2), [.announceAsk(ask)])
    }

    func testAsksDuringIdleOrSendingWait() {
        var idle = LiveModeMachine()
        XCTAssertEqual(idle.handle(.askOpened(ask), at: 0), [])
        var sending = LiveModeMachine()
        _ = sending.handle(.start, at: 0)
        _ = sending.handle(.heard("go"), at: 0.5)
        _ = sending.handle(.tick, at: 2)
        XCTAssertEqual(sending.handle(.askOpened(ask), at: 2.1), [])
        _ = sending.handle(.sendAccepted, at: 2.2)
        XCTAssertEqual(sending.handle(.askOpened(ask), at: 2.3), [.announceAsk(ask)])
    }

    func testWhileAskingSilenceDoesNotPauseTheCall() {
        var machine = thinking()
        _ = machine.handle(.askOpened(ask), at: 3)
        _ = machine.handle(.speechFinished, at: 4)
        XCTAssertEqual(machine.handle(.tick, at: 40), [])
        XCTAssertEqual(machine.phase, .listening)
    }
}

final class LiveModeMachineRestartTests: XCTestCase {
    func testRestartingTheConversationKeepsTheCallMinimized() {
        var machine = LiveModeMachine()
        _ = machine.handle(.start, at: 0)
        _ = machine.handle(.minimize, at: 1)
        let next = machine.restartingConversation()
        XCTAssertTrue(next.isMinimized)
        XCTAssertEqual(next.phase, .idle)
    }
}
