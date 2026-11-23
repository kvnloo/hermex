import Foundation

enum LiveApprovalCommand: String, Equatable, Hashable, Sendable, CaseIterable {
    case allow
    case deny
    case open
}

struct LiveAsk: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case approval
        case question
    }

    let id: String
    let kind: Kind
    let offers: [LiveApprovalCommand]
    let summary: String

    static func approval(id: String, summary: String, allowsOnce: Bool, allowsDeny: Bool) -> LiveAsk {
        var offers: [LiveApprovalCommand] = []
        if allowsOnce { offers.append(.allow) }
        if allowsDeny { offers.append(.deny) }
        offers.append(.open)
        return LiveAsk(id: id, kind: .approval, offers: offers, summary: summary)
    }

    static func question(id: String, summary: String) -> LiveAsk {
        LiveAsk(id: id, kind: .question, offers: [.open], summary: summary)
    }
}

struct LiveAskCandidate: Equatable, Sendable {
    let ask: LiveAsk
    let lane: Int
}

enum LiveAskRoute {
    static func pick(_ candidates: [LiveAskCandidate], callLanes: [Int], selectedLane: Int) -> LiveAsk? {
        let mine = candidates.filter { callLanes.contains($0.lane) }
        return (mine.first { $0.lane == selectedLane } ?? mine.first)?.ask
    }
}

enum LiveApprovalSpeech {
    static let maximumWords = 6

    private static let allowWords: Set<String> = ["allow", "allowed", "approve", "approved"]
    private static let denyWords: Set<String> = ["deny", "denied", "reject", "decline", "refuse", "block", "no", "nope", "nah"]
    private static let negations: Set<String> = ["dont", "not", "never"]
    private static let openWords: Set<String> = ["open", "show"]
    private static let openTargets: Set<String> = ["chat", "me", "in", "app", "card", "details", "approval", "question", "up"]
    private static let filler: Set<String> = [
        "please", "it", "that", "this", "once", "now", "just", "ok", "okay", "yes", "yeah", "yep", "sure",
        "the", "request", "one", "hermes",
    ]

    static func command(_ utterance: String) -> LiveApprovalCommand? {
        let words = normalized(utterance)
        guard !words.isEmpty, words.count <= maximumWords else { return nil }
        let known = allowWords.union(denyWords).union(negations).union(openWords).union(openTargets).union(filler)
        guard words.allSatisfy(known.contains) else { return nil }
        let allowAt = words.firstIndex(where: allowWords.contains)
        let negationAt = words.firstIndex(where: negations.contains)
        let denies = words.contains(where: denyWords.contains)
        let opens = words.contains(where: openWords.contains)
        let targetsOpen = words.contains(where: openTargets.contains)

        if opens {
            return allowAt == nil && negationAt == nil && !denies ? .open : nil
        }
        guard !targetsOpen else { return nil }
        switch (allowAt, negationAt) {
        case (let allow?, let negation?):
            return negation < allow ? .deny : nil
        case (_?, nil):
            return denies ? nil : .allow
        case (nil, _?):
            return nil
        case (nil, nil):
            return denies ? .deny : nil
        }
    }

    static func normalized(_ utterance: String) -> [String] {
        var text = utterance.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        text = text.replacingOccurrences(of: "don't", with: "dont")
        text = String(text.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
        var words = text.split(separator: " ").map(String.init)
        var index = 0
        while index + 1 < words.count {
            if words[index] == "do", words[index + 1] == "not" {
                words.replaceSubrange(index...index + 1, with: ["dont"])
            }
            index += 1
        }
        return words
    }
}
