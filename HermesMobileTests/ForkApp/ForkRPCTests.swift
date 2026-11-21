import XCTest
@testable import HermesMobile

final class ForkRPCTests: XCTestCase {
    func testForkCallSendsItsMethodAndParams() throws {
        let call = HermesCall.fork(ForkRPC(method: "mcp.servers.list", params: ["profile": .string("default")]))
        XCTAssertEqual(call.method, "mcp.servers.list")
        XCTAssertEqual(try call.params(), ["profile": .string("default")])
    }

    func testInadmissibleForkCallIsRefusedBeforeSending() {
        XCTAssertThrowsError(try HermesCall.fork(ForkRPC(method: "message.react", isAdmissible: false)).params())
        XCTAssertThrowsError(try HermesCall.fork(ForkRPC(method: "")).params())
    }
}
