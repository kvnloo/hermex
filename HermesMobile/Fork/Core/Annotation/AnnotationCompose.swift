import Foundation

enum AnnotationCompose {
    static let schema = "dash.annotation.v1"

    static func jsRound(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        let scaled = value * scale
        guard scaled.isFinite else { return scaled }
        return (scaled + 0.5).rounded(.down) / scale
    }

    static func document(strokes: [AnnotationStroke], segments: [AnnotationSegment], screen: AnnotationScreen,
                         createdAt: Int) throws -> Data {
        let alignment = AnnotationAlign.transcript(strokes, segments)
        let document = AnnotationDocument(
            schema: schema, createdAt: createdAt, screen: screen,
            strokes: strokes.map { stroke in
                AnnotationDocument.Stroke(
                    id: stroke.id, tool: stroke.tool, color: stroke.color, pointer: stroke.pointer,
                    startedAt: stroke.startedAt, endedAt: stroke.endedAt, targets: stroke.targets,
                    segment: AnnotationAlign.segment(for: stroke, in: segments)?.id,
                    points: stroke.points.map {
                        [jsRound($0.x, places: 4), jsRound($0.y, places: 4), jsRound($0.pressure, places: 2),
                         Double($0.time - stroke.startedAt)]
                    }
                )
            },
            transcript: AnnotationDocument.Transcript(text: alignment.text, segments: segments)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    static func attachmentNames(createdAt: Int) -> (image: String, json: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = formatter.string(from: Date(timeIntervalSince1970: Double(createdAt) / 1000))
            .replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-")
        return ("annotation-\(stamp).png", "annotation-\(stamp).json")
    }

    static func center(_ points: [AnnotationPoint]) -> (x: Double, y: Double)? {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        return (jsRound((minX + maxX) * 50, places: 0), jsRound((minY + maxY) * 50, places: 0))
    }

    static func legend(_ strokes: [AnnotationStroke]) -> String {
        strokes.map { stroke in
            let place = center(stroke.points).map { " at \(Int($0.x))%,\(Int($0.y))%" } ?? ""
            let red = stroke.color == "red" ? " (red)" : ""
            let on = stroke.targets.isEmpty ? "" : " on \(stroke.targets.joined(separator: ", "))"
            return "\(AnnotationAlign.marker(stroke.id)) \(stroke.tool)\(red)\(place)\(on)"
        }.joined(separator: "\n")
    }

    static func message(strokes: [AnnotationStroke], segments: [AnnotationSegment], screen: AnnotationScreen,
                        typed: String?) -> String {
        let alignment = AnnotationAlign.transcript(strokes, segments)
        let note = typed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let said = [note, alignment.text].filter { !$0.isEmpty }.joined(separator: "\n")
        let head = "Annotated \(screen.route) (\(strokes.count) stroke\(strokes.count == 1 ? "" : "s")). "
            + "Screenshot with the marks and the strokes JSON are attached."
        let silent = alignment.unspoken.isEmpty
            ? "" : "\nAlso marked without speaking: " + alignment.unspoken.map(AnnotationAlign.marker).joined(separator: " ")
        let body = said.isEmpty ? "" : said + silent
        return [head, body, strokes.isEmpty ? "" : legend(strokes)].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func closedLoopRegion(_ stroke: AnnotationStroke, screen: AnnotationScreen, padding: Double = 12) -> AnnotationRegion? {
        guard stroke.pointer == "stylus", ["pen", "circle", "box"].contains(stroke.tool),
              screen.width.isFinite, screen.height.isFinite, screen.width > 0, screen.height > 0, padding >= 0,
              stroke.points.count >= (stroke.tool == "pen" ? 8 : 2),
              stroke.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              let minX = stroke.points.map(\.x).min(), let maxX = stroke.points.map(\.x).max(),
              let minY = stroke.points.map(\.y).min(), let maxY = stroke.points.map(\.y).max() else { return nil }
        let extentX = (maxX - minX) * screen.width
        let extentY = (maxY - minY) * screen.height
        guard extentX >= 32, extentY >= 32 else { return nil }
        if stroke.tool == "pen", let first = stroke.points.first, let last = stroke.points.last {
            let gap = hypot((first.x - last.x) * screen.width, (first.y - last.y) * screen.height)
            if gap > max(12, hypot(extentX, extentY) * 0.2) { return nil }
        }
        let x = max(0, Int((minX * screen.width - padding).rounded(.down)))
        let y = max(0, Int((minY * screen.height - padding).rounded(.down)))
        let right = min(Int(screen.width.rounded(.up)), Int((maxX * screen.width + padding).rounded(.up)))
        let bottom = min(Int(screen.height.rounded(.up)), Int((maxY * screen.height + padding).rounded(.up)))
        guard right > x, bottom > y else { return nil }
        return AnnotationRegion(x: x, y: y, width: right - x, height: bottom - y)
    }

    static func visibleText(in region: AnnotationRegion, boxes: [AnnotationTextBox]) -> String {
        boxes.compactMap { box -> String? in
            let text = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, box.width > 0, box.height > 0, box.x.isFinite, box.y.isFinite else { return nil }
            let cx = box.x + box.width / 2, cy = box.y + box.height / 2
            let inside = cx >= Double(region.x) && cx <= Double(region.x + region.width)
                && cy >= Double(region.y) && cy <= Double(region.y + region.height)
            return inside ? text : nil
        }.joined(separator: "\n")
    }
}

private struct AnnotationDocument: Encodable {
    struct Stroke: Encodable {
        let id: Int
        let tool: String
        let color: String
        let pointer: String
        let startedAt: Int
        let endedAt: Int
        let targets: [String]
        let segment: String?
        let points: [[Double]]
    }

    struct Transcript: Encodable {
        let text: String
        let segments: [AnnotationSegment]
    }

    let schema: String
    let createdAt: Int
    let screen: AnnotationScreen
    let strokes: [Stroke]
    let transcript: Transcript
}
