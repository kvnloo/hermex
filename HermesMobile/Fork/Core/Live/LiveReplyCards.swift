import Foundation

enum LiveReplySegment: Equatable, Sendable {
    case text(String)
    case card(language: String, source: String)
    case pendingCard(language: String)

    var markdown: String {
        switch self {
        case .text(let text): text
        case .card(let language, let source): "```\(language)\n\(source)\n```"
        case .pendingCard: ""
        }
    }
}

struct LiveFocusCard: Equatable, Sendable, Identifiable {
    let id: String
    let language: String
    let source: String

    var markdown: String { LiveReplySegment.card(language: language, source: source).markdown }
}

enum LiveReplyCards {
    static let drawableLanguages: Set<String> = ["html", "svg", "mermaid"]

    static func isCardLanguage(_ language: String) -> Bool {
        OpenUICatalog.fenceLanguages.contains(language) || drawableLanguages.contains(language)
            || language == KitCardProgram.fenceLanguage
    }

    static func focusCards<Step>(_ turns: [LiveTurn<Step>]) -> [LiveFocusCard] {
        turns.flatMap { turn in
            segments(turn.reply).compactMap { segment -> (String, String)? in
                guard case .card(let language, let source) = segment,
                      OpenUICatalog.fenceLanguages.contains(language) || language == KitCardProgram.fenceLanguage else { return nil }
                return (language, source)
            }
            .enumerated().map { LiveFocusCard(id: "\(turn.id)-\($0.offset)", language: $0.element.0, source: $0.element.1) }
        }
    }

    static func segments(_ markdown: String) -> [LiveReplySegment] {
        var segments: [LiveReplySegment] = []
        var prose: [String] = []
        var fence: (marker: String, language: String, lines: [String], opening: String)?

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { segments.append(.text(text)) }
            prose = []
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var open = fence {
                if closes(trimmed, marker: open.marker) {
                    if isCardLanguage(open.language) {
                        flushProse()
                        segments.append(.card(language: open.language, source: open.lines.joined(separator: "\n")))
                    } else {
                        prose.append(open.opening)
                        prose.append(contentsOf: open.lines)
                        prose.append(line)
                    }
                    fence = nil
                } else {
                    open.lines.append(line)
                    fence = open
                }
                continue
            }
            if let marker = fenceMarker(trimmed) {
                let language = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                    .split(separator: " ").first.map { $0.lowercased() } ?? ""
                fence = (marker, language, [], line)
                continue
            }
            prose.append(line)
        }
        if let open = fence {
            if isCardLanguage(open.language) {
                flushProse()
                segments.append(.pendingCard(language: open.language))
            } else {
                prose.append(open.opening)
                prose.append(contentsOf: open.lines)
            }
        }
        flushProse()
        return segments
    }

    private static func closes(_ line: String, marker: String) -> Bool {
        guard let character = marker.first, line.count >= marker.count else { return false }
        return line.allSatisfy { $0 == character }
    }

    private static func fenceMarker(_ line: String) -> String? {
        for character in ["`", "~"] {
            let run = line.prefix { String($0) == character }
            if run.count >= 3 { return String(run) }
        }
        return nil
    }
}
