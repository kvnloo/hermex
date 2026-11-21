import Foundation

struct AnnotationPoint: Equatable, Sendable {
    let x: Double
    let y: Double
    let pressure: Double
    let time: Int
}

struct AnnotationStroke: Equatable, Sendable {
    let id: Int
    let tool: String
    let color: String
    let pointer: String
    let points: [AnnotationPoint]
    let startedAt: Int
    let endedAt: Int
    var targets: [String] = []
}

struct AnnotationSegment: Equatable, Sendable, Encodable {
    let id: String
    let text: String
    let start: Int
    let end: Int
    let source: String
}

struct AnnotationScreen: Equatable, Sendable, Encodable {
    let id: String
    let route: String
    let width: Double
    let height: Double
}

struct AnnotationRegion: Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct AnnotationTextBox: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let text: String
}

struct AnnotationAlignment: Equatable, Sendable {
    let text: String
    let unspoken: [Int]
}

enum AnnotationAlign {
    static let slackMilliseconds = 3000

    static func marker(_ id: Int) -> String { "\u{27E6}stroke \(id)\u{27E7}" }

    static func segment(for stroke: AnnotationStroke, in segments: [AnnotationSegment]) -> AnnotationSegment? {
        if let containing = segments.first(where: { stroke.startedAt >= $0.start && stroke.startedAt <= $0.end }) {
            return containing
        }
        var best: AnnotationSegment?
        var bestGap = Int.max
        for segment in segments {
            let gap = max(0, max(segment.start - stroke.endedAt, stroke.startedAt - segment.end))
            if gap <= slackMilliseconds && gap < bestGap {
                best = segment
                bestGap = gap
            }
        }
        return best
    }

    static func wordSlot(_ segment: AnnotationSegment, words: Int, at time: Int) -> Int {
        guard words > 0 else { return 0 }
        let span = segment.end - segment.start
        let fraction = span <= 0 ? 1 : Double(time - segment.start) / Double(span)
        let slot = Int((min(max(fraction, 0), 1) * Double(words)).rounded(.up))
        return min(max(slot, 1), words)
    }

    static func transcript(_ strokes: [AnnotationStroke], _ segments: [AnnotationSegment]) -> AnnotationAlignment {
        let usable = segments.enumerated()
            .filter { !$0.element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset }
            .map(\.element)
        var bySegment: [String: [AnnotationStroke]] = [:]
        var unspoken: [Int] = []
        for stroke in strokes {
            if let segment = segment(for: stroke, in: usable) {
                bySegment[segment.id, default: []].append(stroke)
            } else {
                unspoken.append(stroke.id)
            }
        }
        let parts = usable.map { segment -> String in
            let words = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            var after: [Int: [Int]] = [:]
            for stroke in bySegment[segment.id] ?? [] {
                after[wordSlot(segment, words: words.count, at: stroke.startedAt), default: []].append(stroke.id)
            }
            var marked: [String] = []
            for (index, word) in words.enumerated() {
                marked.append(word)
                marked.append(contentsOf: (after[index + 1] ?? []).map(marker))
            }
            return marked.joined(separator: " ")
        }
        return AnnotationAlignment(text: parts.joined(separator: " "), unspoken: unspoken)
    }
}
