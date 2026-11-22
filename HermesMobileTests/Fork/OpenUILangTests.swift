import XCTest
@testable import HermesMobile

final class OpenUILangTests: XCTestCase {
    private func ready(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> OpenUIProgram? {
        guard case .ready(let program) = OpenUILang.parse(source) else {
            XCTFail("not ready: \(OpenUILang.parse(source))", file: file, line: line)
            return nil
        }
        return program
    }

    func testResolvesReferencesCallsObjectsAndLiterals() throws {
        let program = try XCTUnwrap(ready("""
        # comment
        root = Board("T", 'S', [stat])
        stat = Stat("Users", -1.5e2, "since \\"June\\"") // trailing
        extra = {a: [true, false, null], "b c": 0}
        """))
        guard case .call("Board", let args, _) = program.root else { return XCTFail() }
        XCTAssertEqual(args.count, 3)
        guard case .array(let items, _) = args[2], case .call("Stat", let stat, _) = items.first else { return XCTFail() }
        guard case .number(let value, _) = stat[1], case .string(let detail, _) = stat[2] else { return XCTFail() }
        XCTAssertEqual(value, -150)
        XCTAssertEqual(detail, "since \"June\"")
        guard case .object(let fields, _) = program.assignments["extra"] else { return XCTFail() }
        XCTAssertEqual(Set(fields.keys), ["a", "b c"])
    }

    func testUnicodeEscapesIncludingSurrogatePairs() throws {
        let program = try XCTUnwrap(ready(#"root = "é😀\n""#))
        guard case .string(let text, _) = program.root else { return XCTFail() }
        XCTAssertEqual(text, "é😀\n")
    }

    func testMissingRootAndUnclosedInputAreIncomplete() {
        guard case .incomplete(let missing) = OpenUILang.parse("a = 1") else { return XCTFail() }
        XCTAssertEqual(missing.message, "Missing root assignment.")
        guard case .incomplete = OpenUILang.parse("root = Board(\"T\", ") else { return XCTFail() }
        guard case .incomplete = OpenUILang.parse("root = [1, 2") else { return XCTFail() }
        guard case .incomplete = OpenUILang.parse("root = \"open") else { return XCTFail() }
        guard case .incomplete(let unresolved) = OpenUILang.parse("root = later") else { return XCTFail() }
        XCTAssertEqual(unresolved.message, "Unresolved reference: later.")
    }

    func testInvalidProgramsReportLineAndColumn() {
        guard case .invalid(let cycle) = OpenUILang.parse("root = a\na = root") else { return XCTFail() }
        XCTAssertTrue(cycle.message.hasPrefix("Cyclic reference"), cycle.message)
        guard case .invalid(let duplicate) = OpenUILang.parse("root = 1\nroot = 2") else { return XCTFail() }
        XCTAssertEqual(duplicate.description, "2:1: Duplicate assignment: root")
        guard case .invalid(let character) = OpenUILang.parse("root = @") else { return XCTFail() }
        XCTAssertEqual(character.description, "1:8: Unexpected character \"@\".")
        guard case .invalid(let sameLine) = OpenUILang.parse("root = 1 a = 2") else { return XCTFail() }
        XCTAssertEqual(sameLine.message, "Expected a new assignment on a new line.")
        guard case .invalid(let literal) = OpenUILang.parse("true = 1") else { return XCTFail() }
        XCTAssertEqual(literal.message, "Literal cannot be an assignment name.")
        guard case .invalid(let number) = OpenUILang.parse("root = -x") else { return XCTFail() }
        XCTAssertEqual(number.message, "Invalid number.")
    }

    func testUnreferencedDeclarationsAreStillChecked() {
        guard case .incomplete(let problem) = OpenUILang.parse("root = 1\nside = missing") else { return XCTFail() }
        XCTAssertEqual(problem.message, "Unresolved reference: missing.")
    }

    func testSourceLimitIs64KiB() {
        let big = "root = \"" + String(repeating: "a", count: 65_536) + "\""
        guard case .invalid(let problem) = OpenUILang.parse(big) else { return XCTFail() }
        XCTAssertEqual(problem.message, "Chart board exceeds the 64 KiB limit.")
    }

    func testDepthLimit() {
        let deep = "root = " + String(repeating: "[", count: 90) + String(repeating: "]", count: 90)
        guard case .invalid(let problem) = OpenUILang.parse(deep) else { return XCTFail() }
        XCTAssertEqual(problem.message, "Nesting limit exceeded.")
    }

    func testCRLFLinesSeparateAssignments() {
        guard case .ready = OpenUILang.parse("root = a\r\na = 1\r\n") else { return XCTFail() }
    }
}
