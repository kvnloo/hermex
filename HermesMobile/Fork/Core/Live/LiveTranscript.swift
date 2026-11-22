import Foundation

protocol LiveStepStatus {
    var liveStepIsRunning: Bool { get }
    var liveStepIsFailed: Bool { get }
}

struct LiveTranscriptMessage<Step> {
    let id: String
    let isUser: Bool
    let text: String
    let steps: [Step]
}

struct LiveTurn<Step>: Identifiable {
    let id: String
    var said: String?
    var steps: [Step] = []
    var replies: [String] = []

    var reply: String { replies.joined(separator: "\n\n") }
}

struct LiveProgressSummary: Equatable, Sendable {
    let count: Int
    let running: Int
    let failed: Int

    var isWorking: Bool { running > 0 }

    init<Step: LiveStepStatus>(_ steps: [Step]) {
        count = steps.count
        running = steps.filter(\.liveStepIsRunning).count
        failed = steps.filter(\.liveStepIsFailed).count
    }
}

enum LiveTranscript {
    static let openingTurnID = "live-turn-start"

    static func turns<Step>(_ messages: [LiveTranscriptMessage<Step>], liveSteps: [Step]) -> [LiveTurn<Step>] {
        var turns: [LiveTurn<Step>] = []
        for message in messages {
            if message.isUser {
                let said = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                turns.append(LiveTurn(id: message.id, said: said.isEmpty ? nil : said))
                continue
            }
            if turns.isEmpty { turns.append(LiveTurn(id: openingTurnID)) }
            turns[turns.count - 1].steps += message.steps
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { turns[turns.count - 1].replies.append(text) }
        }
        if !liveSteps.isEmpty {
            if turns.isEmpty { turns.append(LiveTurn(id: openingTurnID)) }
            turns[turns.count - 1].steps += liveSteps
        }
        return turns
    }
}
