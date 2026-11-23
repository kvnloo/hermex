import Foundation

enum LivePhase: Equatable, Sendable {
    case idle
    case listening
    case sending
    case thinking
    case speaking
    case paused
    case failed
}

enum LiveEvent: Equatable, Sendable {
    case start
    case heard(String)
    case tick
    case sendAccepted
    case sendRefused
    case replyFinished(String)
    case replyFailed
    case speechFinished
    case bargeIn
    case pause
    case stop
    case minimize
    case restore
    case mute
    case unmute
    case askOpened(LiveAsk)
    case askClosed(String)
    case askHandled(String)
}

enum LiveEffect: Equatable, Sendable {
    case startListening
    case stopListening
    case send(String)
    case speak([String])
    case stopSpeaking
    case close
    case announceAsk(LiveAsk)
    case askAgain(LiveAsk)
    case answerAsk(String, LiveApprovalCommand)
}

struct LiveModeMachine: Equatable, Sendable {
    static let endOfUtterance: Double = 1.4
    static let followUpWindow: Double = 10
    static let maximumUtterance: Double = 60
    static let quietLimit: Double = 15 * 60

    private(set) var phase: LivePhase = .idle
    private(set) var heard = ""
    private(set) var turns = 0
    private(set) var isMinimized = false
    private(set) var isMuted = false
    private(set) var hasUnseenCard = false
    private(set) var ask: LiveAsk?
    private var answered: Set<String> = []
    private var replyPending = false
    private var listeningSince: Double = 0
    private var lastHeardChange: Double = 0
    private var quietSince: Double = 0

    var isActive: Bool { phase != .idle }

    mutating func handle(_ event: LiveEvent, at time: Double) -> [LiveEffect] {
        switch (event, phase) {
        case (.stop, _):
            let effects: [LiveEffect] = phase == .speaking ? [.stopSpeaking, .close] : [.stopListening, .close]
            close()
            return effects
        case (_, .idle) where !Self.startsCall(event):
            return []
        case (.start, .idle), (.start, .paused), (.start, .failed):
            isMuted = false
            return listen(at: time)
        case (.minimize, _):
            isMinimized = true
            return []
        case (.restore, _):
            isMinimized = false
            hasUnseenCard = false
            return []
        case (.mute, _):
            isMuted = true
            guard phase == .listening else { return [] }
            return [.stopListening] + quiet(.paused, at: time)
        case (.unmute, _):
            guard isMuted else { return [] }
            isMuted = false
            return phase == .paused ? listen(at: time) : []
        case (.askOpened(let new), _):
            return open(new, at: time)
        case (.askClosed(let id), _):
            answered.remove(id)
            guard ask?.id == id else { return [] }
            return audioOff() + settle(at: time)
        case (.askHandled(let id), _):
            answered.insert(id)
            guard ask?.id == id else { return [] }
            return audioOff() + settle(at: time)
        case (.heard(let text), .listening):
            if text != heard {
                heard = text
                lastHeardChange = time
            }
            return []
        case (.tick, .listening):
            let utterance = heard.trimmingCharacters(in: .whitespacesAndNewlines)
            if !utterance.isEmpty,
               time - lastHeardChange >= Self.endOfUtterance || time - listeningSince >= Self.maximumUtterance {
                if let ask { return answer(utterance, to: ask, at: time) }
                phase = .sending
                return [.stopListening, .send(utterance)]
            }
            if utterance.isEmpty, ask == nil, turns > 0, time - listeningSince >= Self.followUpWindow {
                return [.stopListening] + quiet(.paused, at: time)
            }
            return []
        case (.tick, .paused), (.tick, .failed):
            guard time - quietSince >= Self.quietLimit else { return [] }
            close()
            return [.close]
        case (.sendAccepted, .sending):
            phase = .thinking
            turns += 1
            return []
        case (.sendRefused, .sending):
            return quiet(.failed, at: time)
        case (.replyFinished(let text), .thinking):
            if isMinimized, LiveReplyCards.segments(text).contains(where: \.isCard) { hasUnseenCard = true }
            let chunks = LiveSpeechText.chunks(LiveSpeechText.speakable(text))
            guard !chunks.isEmpty else { return resume(at: time) }
            phase = .speaking
            return [.speak(chunks)]
        case (.replyFailed, .thinking):
            return quiet(.failed, at: time)
        case (.speechFinished, .speaking):
            return resume(at: time)
        case (.bargeIn, .speaking):
            isMuted = false
            return [.stopSpeaking] + listen(at: time)
        case (.pause, .listening):
            return [.stopListening] + quiet(.paused, at: time)
        case (.pause, .speaking):
            return [.stopSpeaking] + quiet(.paused, at: time)
        default:
            return []
        }
    }

    private static func startsCall(_ event: LiveEvent) -> Bool {
        if case .start = event { return true }
        if case .restore = event { return true }
        return false
    }

    private mutating func open(_ new: LiveAsk, at time: Double) -> [LiveEffect] {
        guard phase != .sending, !answered.contains(new.id) else { return [] }
        if ask?.id == new.id {
            ask = new
            return []
        }
        let effects = audioOff()
        if ask == nil, phase == .thinking { replyPending = true }
        ask = new
        phase = .speaking
        heard = ""
        return effects + [.announceAsk(new)]
    }

    private mutating func answer(_ utterance: String, to ask: LiveAsk, at time: Double) -> [LiveEffect] {
        if let command = LiveApprovalSpeech.command(utterance), ask.offers.contains(command) {
            answered.insert(ask.id)
            return [.stopListening, .answerAsk(ask.id, command)] + settle(at: time)
        }
        phase = .speaking
        heard = ""
        return [.stopListening, .askAgain(ask)]
    }

    private mutating func settle(at time: Double) -> [LiveEffect] {
        ask = nil
        guard !replyPending else {
            replyPending = false
            phase = .thinking
            heard = ""
            return []
        }
        return resume(at: time)
    }

    private mutating func resume(at time: Double) -> [LiveEffect] {
        isMuted && ask == nil ? quiet(.paused, at: time) : listen(at: time)
    }

    private func audioOff() -> [LiveEffect] {
        switch phase {
        case .listening: [.stopListening]
        case .speaking: [.stopSpeaking]
        default: []
        }
    }

    private mutating func quiet(_ next: LivePhase, at time: Double) -> [LiveEffect] {
        phase = next
        quietSince = time
        return []
    }

    private mutating func close() {
        let turns = turns
        self = LiveModeMachine()
        self.turns = turns
    }

    private mutating func listen(at time: Double) -> [LiveEffect] {
        phase = .listening
        heard = ""
        listeningSince = time
        lastHeardChange = time
        return [.startListening]
    }
}

private extension LiveReplySegment {
    var isCard: Bool {
        if case .card = self { return true }
        return false
    }
}
