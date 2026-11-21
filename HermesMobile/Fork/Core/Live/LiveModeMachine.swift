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
}

enum LiveEffect: Equatable, Sendable {
    case startListening
    case stopListening
    case send(String)
    case speak([String])
    case stopSpeaking
    case close
}

struct LiveModeMachine: Equatable, Sendable {
    static let endOfUtterance: Double = 1.4
    static let followUpWindow: Double = 10
    static let maximumUtterance: Double = 60

    private(set) var phase: LivePhase = .idle
    private(set) var heard = ""
    private(set) var turns = 0
    private var listeningSince: Double = 0
    private var lastHeardChange: Double = 0

    mutating func handle(_ event: LiveEvent, at time: Double) -> [LiveEffect] {
        switch (event, phase) {
        case (.stop, _):
            let effects: [LiveEffect] = phase == .speaking ? [.stopSpeaking, .close] : [.stopListening, .close]
            phase = .idle
            heard = ""
            return effects
        case (.start, .idle), (.start, .paused), (.start, .failed):
            return listen(at: time)
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
                phase = .sending
                return [.stopListening, .send(utterance)]
            }
            if utterance.isEmpty, turns > 0, time - listeningSince >= Self.followUpWindow {
                phase = .paused
                return [.stopListening]
            }
            return []
        case (.sendAccepted, .sending):
            phase = .thinking
            turns += 1
            return []
        case (.sendRefused, .sending):
            phase = .failed
            return []
        case (.replyFinished(let text), .thinking):
            let chunks = LiveSpeechText.chunks(LiveSpeechText.speakable(text))
            guard !chunks.isEmpty else { return listen(at: time) }
            phase = .speaking
            return [.speak(chunks)]
        case (.replyFailed, .thinking):
            phase = .failed
            return []
        case (.speechFinished, .speaking):
            return listen(at: time)
        case (.bargeIn, .speaking):
            return [.stopSpeaking] + listen(at: time)
        case (.pause, .listening):
            phase = .paused
            return [.stopListening]
        case (.pause, .speaking):
            phase = .paused
            return [.stopSpeaking]
        default:
            return []
        }
    }

    private mutating func listen(at time: Double) -> [LiveEffect] {
        phase = .listening
        heard = ""
        listeningSince = time
        lastHeardChange = time
        return [.startListening]
    }
}
