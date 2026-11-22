import XCTest
@testable import HermesMobile

final class ForkMCPServersTests: XCTestCase {
    private func summary(_ name: String, enabled: Bool = true, url: String? = nil, command: String? = nil, args: [String] = []) -> ForkMCPSummary {
        ForkMCPSummary(name: name, transport: url == nil ? "stdio" : "http", url: url, command: command, args: args,
                       enabled: enabled, source: "config")
    }

    func testRowsSortProblemsFirstThenByName() {
        let rows = ForkMCPRow.merge(
            [summary("zeta"), summary("alpha"), summary("github"), summary("off", enabled: false), summary("linear")],
            [ForkMCPRuntime(name: "zeta", tools: 3, connected: true, disabled: false, status: "connected"),
             ForkMCPRuntime(name: "github", tools: 0, connected: false, disabled: false, status: "failed"),
             ForkMCPRuntime(name: "linear", tools: 0, connected: false, disabled: false, status: "configured", needsAuth: true)]
        )
        XCTAssertEqual(rows.map(\.id), ["github", "linear", "zeta", "alpha", "off"])
        XCTAssertEqual(rows.map(\.health), [.failed, .needsAuth, .connected, .idle, .disabled])
    }

    func testLazyAndConfiguredServersAreIdleUnlessConnected() {
        let lazy = ForkMCPRow(summary: summary("a"), runtime: ForkMCPRuntime(name: "a", tools: 0, connected: false, disabled: false, status: "lazy"))
        XCTAssertEqual(lazy.health, .idle)
        let unknown = ForkMCPRow(summary: summary("b"), runtime: ForkMCPRuntime(name: "b", tools: 2, connected: true, disabled: false, status: "new"))
        XCTAssertEqual(unknown.health, .connected)
        let disabledAtRuntime = ForkMCPRow(summary: summary("c"), runtime: ForkMCPRuntime(name: "c", tools: 0, connected: false, disabled: true, status: "disabled"))
        XCTAssertEqual(disabledAtRuntime.health, .disabled)
    }

    func testEndpointPrefersURLThenCommandLine() {
        XCTAssertEqual(ForkMCPRow(summary: summary("a", url: "https://mcp.example/sse"), runtime: nil).endpoint, "https://mcp.example/sse")
        XCTAssertEqual(ForkMCPRow(summary: summary("b", command: "npx", args: ["-y", "server"]), runtime: nil).endpoint, "npx -y server")
        XCTAssertNil(ForkMCPRow(summary: summary("c"), runtime: nil).endpoint)
    }

    func testDuplicateRuntimeNamesKeepTheFirst() {
        let rows = ForkMCPRow.merge([summary("a")], [
            ForkMCPRuntime(name: "a", tools: 1, connected: true, disabled: false, status: "connected"),
            ForkMCPRuntime(name: "a", tools: 9, connected: false, disabled: false, status: "failed"),
        ])
        XCTAssertEqual(rows.first?.runtime?.tools, 1)
    }
}
