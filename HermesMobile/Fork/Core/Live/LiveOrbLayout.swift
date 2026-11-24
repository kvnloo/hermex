import Foundation

enum LiveOrbMode: String, Equatable, Sendable {
    case bubble
    case focus
}

enum LiveFocusItem: Equatable, Hashable, Sendable, Identifiable {
    case approval(String)
    case card(String)

    var id: String {
        switch self {
        case .approval(let id): "approval-\(id)"
        case .card(let id): "card-\(id)"
        }
    }
}

struct LiveOrbLayout: Equatable, Sendable {
    static let bubbleDiameter = 58.0
    static let focusDiameter = 188.0
    static let maxFocusCards = 6

    let mode: LiveOrbMode
    let diameter: Double
    let showsTranscript: Bool
    let items: [LiveFocusItem]
    let badge: Int

    var cardsBelowOrb: Bool { mode == .focus && !items.isEmpty }

    static func make(mode: LiveOrbMode, approvals: [String], cards: [String]) -> LiveOrbLayout {
        switch mode {
        case .bubble:
            return LiveOrbLayout(mode: .bubble, diameter: bubbleDiameter, showsTranscript: true, items: [], badge: approvals.count)
        case .focus:
            var seen: Set<String> = []
            let unique = cards.filter { seen.insert($0).inserted }
            let newest = unique.suffix(maxFocusCards)
            return LiveOrbLayout(mode: .focus, diameter: focusDiameter, showsTranscript: false,
                                 items: approvals.map(LiveFocusItem.approval) + newest.map(LiveFocusItem.card), badge: 0)
        }
    }
}
