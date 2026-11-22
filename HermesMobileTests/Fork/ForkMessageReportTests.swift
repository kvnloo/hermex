import XCTest
@testable import HermesMobile

final class ForkMessageReportTests: XCTestCase {
    private let repository = URL(string: "https://github.com/owner/app")!

    func testTheIssueIsPrefilledWithTheMessageID() throws {
        let url = try XCTUnwrap(ForkMessageReport(messageID: "msg+1 & co").issueURL(repository: repository))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/owner/app/issues/new")
        let body = try XCTUnwrap(components.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.hasPrefix("Message ID: msg+1 & co\n"), body)
        XCTAssertEqual(components.queryItems?.map(\.name), ["title", "body"])
        XCTAssertFalse(url.absoluteString.contains("+"), "GitHub reads a bare + as a space")
    }

    func testAMessageWithoutAnIDOffersNoReport() {
        XCTAssertNil(ForkMessageReport(messageID: "").issueURL(repository: repository))
    }
}
