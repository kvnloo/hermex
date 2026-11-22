import XCTest
@testable import HermesMobile

final class ForkBotDirectoryDocumentTests: XCTestCase {
    func testABotFileGivesItsNameTitleAndDescription() throws {
        let bot = try decode(#"{"name":"writer","title":" Writer ","description":"Edits drafts.","avatar":{"shape":"circle"}}"#)
        XCTAssertEqual(bot, ForkBotDirectoryDocument(name: "writer", title: "Writer", description: "Edits drafts."))
        XCTAssertEqual(try decode(#"{"name":"writer","title":"  "}"#), ForkBotDirectoryDocument(name: "writer"))
    }

    func testAFileWithoutAUsableProfileNameIsRefused() {
        for source in [#"{"title":"Writer"}"#, #"{"name":""}"#, #"{"name":"a/b"}"#, #"{"name":"Writer"}"#,
                       #"{"name":"-writer"}"#, "{\"name\":\"\(String(repeating: "a", count: 65))\"}"] {
            XCTAssertThrowsError(try decode(source), source) { XCTAssertEqual($0 as? ForkBotDirectoryDocument.Failure, .invalidName) }
        }
    }

    func testAMalformedFileIsRefused() {
        let cases: [(String, ForkBotDirectoryDocument.Failure)] = [
            ("[]", .notAnObject), ("{", .notJSON), (#"{"name":2}"#, .notText("name")),
            (#"{"name":"writer","title":true}"#, .notText("title")),
            (#"{"name":"writer","description":null}"#, .notText("description")),
        ]
        for (source, failure) in cases {
            XCTAssertThrowsError(try decode(source), source) { XCTAssertEqual($0 as? ForkBotDirectoryDocument.Failure, failure) }
        }
        let padded = Data(#"{"name":"writer"}"#.utf8) + Data(repeating: 0x20, count: ForkBotDirectoryDocument.byteLimit)
        XCTAssertThrowsError(try ForkBotDirectoryDocument(data: padded)) {
            XCTAssertEqual($0 as? ForkBotDirectoryDocument.Failure, .tooLarge)
        }
    }

    private func decode(_ source: String) throws -> ForkBotDirectoryDocument {
        try ForkBotDirectoryDocument(data: Data(source.utf8))
    }
}
