import XCTest
@testable import HermesMobile

final class ForkMCPRPCTests: XCTestCase {
    func testMCPCallsMatchTheGatewayContract() throws {
        XCTAssertEqual(HermesCall.fork(.mcpServersList(profile: "default")).method, "mcp.servers.list")
        XCTAssertEqual(try HermesCall.fork(.mcpServersStatus(profile: "default")).params(), ["profile": .string("default")])
        XCTAssertEqual(try HermesCall.fork(.mcpServersTest(profile: "work", name: "github")).params(),
                       ["profile": .string("work"), "name": .string("github")])
        XCTAssertThrowsError(try HermesCall.fork(.mcpServersTest(profile: "work", name: "")).params())
        XCTAssertThrowsError(try HermesCall.fork(.mcpServersList(profile: "")).params())
    }
}
