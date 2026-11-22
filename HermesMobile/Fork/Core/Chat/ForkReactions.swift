import Foundation

struct ForkReaction: Equatable, Hashable, Sendable {
    static let userAuthor = "user"
    static let agentAuthor = "agent"

    let emoji: String
    let author: String

    init?(emoji: String?, author: String?) {
        guard let emoji, let author else { return nil }
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !author.isEmpty else { return nil }
        self.emoji = trimmed
        self.author = author
    }

    var isMine: Bool { author == Self.userAuthor }
}

enum ForkSkinTone: String, CaseIterable, Identifiable, Sendable {
    case none = ""
    case light = "\u{1F3FB}"
    case mediumLight = "\u{1F3FC}"
    case medium = "\u{1F3FD}"
    case mediumDark = "\u{1F3FE}"
    case dark = "\u{1F3FF}"

    var id: String { rawValue }

    var sample: String { "\u{270B}" + rawValue }

    static let storageKey = "fork.reactions.skinTone"

    init(stored: String?) {
        self = stored.flatMap(ForkSkinTone.init(rawValue:)) ?? .none
    }
}

enum ForkReactionCatalog {
    static let emoji = ["\u{1F44D}", "\u{1F44E}", "\u{2764}\u{FE0F}", "\u{1F602}", "\u{1F62E}", "\u{1F622}", "\u{1F64F}", "\u{1F389}"]
    static let toneModifiable: Set<String> = ["\u{1F44D}", "\u{1F44E}", "\u{1F64F}"]

    static func applying(_ tone: ForkSkinTone, to emoji: String) -> String {
        let base = withoutTone(emoji)
        return toneModifiable.contains(base) ? base + tone.rawValue : base
    }

    static func withoutTone(_ emoji: String) -> String {
        let tones = Set(ForkSkinTone.allCases.map(\.rawValue).filter { !$0.isEmpty }.flatMap(\.unicodeScalars))
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: emoji.unicodeScalars.filter { !tones.contains($0) })
        return String(scalars)
    }

    static func palette(_ tone: ForkSkinTone) -> [String] {
        emoji.map { applying(tone, to: $0) }
    }
}

struct ForkReactionChip: Equatable, Identifiable, Sendable {
    let emoji: String
    let count: Int
    let includesMine: Bool

    var id: String { emoji }
}

struct ForkReactionBook: Equatable, Sendable {
    private(set) var rows: [Int: [ForkReaction]] = [:]

    mutating func set(_ reactions: [ForkReaction], rowID: Int) {
        rows[rowID] = reactions
    }

    mutating func merge(reply reactions: [ForkReaction], rowID: Int, before: [ForkReaction]?) {
        if let latest = rows[rowID], latest != before {
            rows[rowID] = reactions.filter(\.isMine) + latest.filter { !$0.isMine }
        } else {
            rows[rowID] = reactions
        }
    }

    func reactions(rowID: Int?, seeded: [ForkReaction]) -> [ForkReaction] {
        guard let rowID, let live = rows[rowID] else { return seeded }
        return live
    }

    static func mine(in reactions: [ForkReaction]) -> ForkReaction? {
        reactions.last(where: \.isMine)
    }

    static func chips(_ reactions: [ForkReaction]) -> [ForkReactionChip] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        var mine: Set<String> = []
        for reaction in reactions {
            if counts[reaction.emoji] == nil { order.append(reaction.emoji) }
            counts[reaction.emoji, default: 0] += 1
            if reaction.isMine { mine.insert(reaction.emoji) }
        }
        return order.map { ForkReactionChip(emoji: $0, count: counts[$0] ?? 0, includesMine: mine.contains($0)) }
    }

    static func requestEmoji(choosing emoji: String?, current: ForkReaction?) -> String? {
        guard let emoji, !emoji.isEmpty, emoji != current?.emoji else { return nil }
        return emoji
    }
}
