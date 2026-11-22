import XCTest
@testable import HermesMobile

final class AnnotationComposeTests: XCTestCase {
    private let screen = AnnotationScreen(id: "chat", route: "Chat · Studio", width: 400, height: 800)

    private func stroke(_ id: Int, start: Int, end: Int, pointer: String = "touch", tool: String = "pen",
                        color: String = "red", points: [AnnotationPoint]? = nil) -> AnnotationStroke {
        AnnotationStroke(id: id, tool: tool, color: color, pointer: pointer,
                         points: points ?? [AnnotationPoint(x: 0.1, y: 0.2, pressure: 0.5, time: start),
                                            AnnotationPoint(x: 0.3, y: 0.4, pressure: 0.5, time: end)],
                         startedAt: start, endedAt: end)
    }

    func testMarkersLandAfterTheWordBeingSpokenWhenTheStrokeStarted() {
        let segment = AnnotationSegment(id: "s1", text: "move this button over there", start: 1000, end: 6000, source: "speech")
        let alignment = AnnotationAlign.transcript([stroke(1, start: 2100, end: 2500), stroke(2, start: 6000, end: 6400)], [segment])
        XCTAssertEqual(alignment.text, "move this ⟦stroke 1⟧ button over there ⟦stroke 2⟧")
        XCTAssertEqual(alignment.unspoken, [])
    }

    func testStrokesFarFromSpeechAreUnspoken() {
        let segment = AnnotationSegment(id: "s1", text: "hello", start: 1000, end: 2000, source: "speech")
        let alignment = AnnotationAlign.transcript([stroke(1, start: 2500, end: 2600), stroke(2, start: 9000, end: 9100)], [segment])
        XCTAssertEqual(alignment.text, "hello ⟦stroke 1⟧")
        XCTAssertEqual(alignment.unspoken, [2])
    }

    func testBlankSegmentsAreIgnoredAndOthersSortByStart() {
        let late = AnnotationSegment(id: "b", text: "second", start: 5000, end: 6000, source: "speech")
        let blank = AnnotationSegment(id: "x", text: "  ", start: 0, end: 9000, source: "speech")
        let early = AnnotationSegment(id: "a", text: "first", start: 1000, end: 2000, source: "speech")
        XCTAssertEqual(AnnotationAlign.transcript([], [late, blank, early]).text, "first second")
    }

    func testMessageMatchesTheDashShape() {
        let segment = AnnotationSegment(id: "s1", text: "make this bigger", start: 0, end: 3000, source: "speech")
        let message = AnnotationCompose.message(strokes: [stroke(1, start: 2900, end: 3100), stroke(2, start: 20000, end: 20100, color: "yellow")],
                                                segments: [segment], screen: screen, typed: " please ")
        XCTAssertEqual(message, """
        Annotated Chat · Studio (2 strokes). Screenshot with the marks and the strokes JSON are attached.

        please
        make this bigger ⟦stroke 1⟧
        Also marked without speaking: ⟦stroke 2⟧

        ⟦stroke 1⟧ pen (red) at 20%,30%
        ⟦stroke 2⟧ pen at 20%,30%
        """)
    }

    func testMessageWithoutWordsHasOnlyTheHeadAndLegend() {
        let message = AnnotationCompose.message(strokes: [stroke(1, start: 0, end: 1)], segments: [], screen: screen, typed: nil)
        XCTAssertEqual(message, "Annotated Chat · Studio (1 stroke). Screenshot with the marks and the strokes JSON are attached.\n\n⟦stroke 1⟧ pen (red) at 20%,30%")
    }

    func testDocumentRoundsLikeJavaScriptAndUsesRelativeTimes() throws {
        let points = [AnnotationPoint(x: 0.123456, y: 0.98765, pressure: 0.125, time: 1000),
                      AnnotationPoint(x: 0.5, y: 0.5, pressure: 1, time: 1040)]
        let data = try AnnotationCompose.document(strokes: [stroke(1, start: 1000, end: 1040, points: points)], segments: [],
                                                  screen: screen, createdAt: 1_763_750_000_000)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schema"] as? String, "dash.annotation.v1")
        let strokes = try XCTUnwrap(json["strokes"] as? [[String: Any]])
        let first = try XCTUnwrap(strokes.first?["points"] as? [[Double]])
        XCTAssertEqual(first[0], [0.1235, 0.9877, 0.13, 0])
        XCTAssertEqual(first[1], [0.5, 0.5, 1, 40])
        XCTAssertNil(strokes.first?["segment"])
        XCTAssertEqual(AnnotationCompose.jsRound(-2.5, places: 0), -2)
    }

    func testAttachmentNamesUseTheUTCMillisecondStamp() {
        let names = AnnotationCompose.attachmentNames(createdAt: 1_763_750_000_123)
        XCTAssertEqual(names.image, "annotation-2025-11-21T18-33-20-123Z.png")
        XCTAssertEqual(names.json, "annotation-2025-11-21T18-33-20-123Z.json")
    }

    func testClosedStylusLoopGivesAPaddedRegionAndItsText() throws {
        let loop = (0..<12).map { index -> AnnotationPoint in
            let angle = Double(index) / 11 * 2 * .pi
            return AnnotationPoint(x: 0.5 + 0.1 * cos(angle), y: 0.5 + 0.05 * sin(angle), pressure: 0.5, time: index)
        }
        let circled = stroke(1, start: 0, end: 11, pointer: "stylus", points: loop)
        let region = try XCTUnwrap(AnnotationCompose.closedLoopRegion(circled, screen: screen))
        XCTAssertEqual(region, AnnotationRegion(x: 149, y: 348, width: 103, height: 104))
        let boxes = [AnnotationTextBox(x: 180, y: 390, width: 40, height: 20, text: " Deploy "),
                     AnnotationTextBox(x: 0, y: 0, width: 40, height: 20, text: "Elsewhere")]
        XCTAssertEqual(AnnotationCompose.visibleText(in: region, boxes: boxes), "Deploy")
        XCTAssertNil(AnnotationCompose.closedLoopRegion(stroke(2, start: 0, end: 11, pointer: "touch", points: loop), screen: screen))
        let open = Array(loop.prefix(7)) + [AnnotationPoint(x: 0.4, y: 0.5, pressure: 0.5, time: 8)]
        XCTAssertNil(AnnotationCompose.closedLoopRegion(stroke(3, start: 0, end: 8, pointer: "stylus", points: open), screen: screen))
    }
}
