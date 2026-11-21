import XCTest
@testable import HermesMobile

final class OpenUICatalogTests: XCTestCase {
    private let sample = """
    root = Board("Repo health", "Last 7 days", [users, bars, lines, table, tree, heat])
    users = Stat("Active users", 1284, "+12% week over week")
    bars = BarChart("PRs by author", "PRs", [{label: "kevin", value: 12}, {label: "bot", value: 30}])
    lines = LineChart("Builds", "runs", ["Mon", "Tue", "Wed"], [{name: "pass", values: [3, 5, 4]}, {name: "fail", values: [1, 0, 2]}])
    table = Table("Slowest tests", ["Test", "Seconds"], [["login", 12.5], ["sync", 9]])
    tree = Treemap("Code size", "Lines", "Churn", [{path: "lib/a.swift", size: 300, color: 2}, {path: "/lib/b.swift/", size: 100, color: 8}])
    heat = Heatmap("Commits", "commits", ["Mon", "Tue"], ["AM", "PM"], [[1, 2], [3, 4]])
    """

    private func board(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> OpenUIBoardModel? {
        guard case .ready(let board) = OpenUICatalog.inspect(source) else {
            XCTFail("not ready: \(OpenUICatalog.inspect(source))", file: file, line: line)
            return nil
        }
        return board
    }

    private func problem(_ source: String) -> String? {
        switch OpenUICatalog.inspect(source) {
        case .invalid(let problem), .incomplete(let problem): problem.message
        case .ready: nil
        }
    }

    func testSampleBoardProducesTypedPanels() throws {
        let board = try XCTUnwrap(board(sample))
        XCTAssertEqual(board.title, "Repo health")
        XCTAssertEqual(board.summary, "Last 7 days")
        XCTAssertTrue(board.isFullyRendered)
        XCTAssertEqual(board.panels.count, 6)
        XCTAssertEqual(board.panels[0], .stat(title: "Active users", value: .number(1284), detail: "+12% week over week"))
        XCTAssertEqual(board.panels[1], .bars(title: "PRs by author", unit: "PRs", bars: [("kevin", 12), ("bot", 30)]))
        XCTAssertEqual(board.panels[2], .series(.line, title: "Builds", unit: "runs", categories: ["Mon", "Tue", "Wed"], series: [
            OpenUISeries(name: "pass", values: [3, 5, 4]), OpenUISeries(name: "fail", values: [1, 0, 2]),
        ]))
        XCTAssertEqual(board.panels[3], .table(title: "Slowest tests", columns: ["Test", "Seconds"],
                                               rows: [[.text("login"), .number(12.5)], [.text("sync"), .number(9)]]))
        guard case .treemap(_, _, _, let rows) = board.panels[4] else { return XCTFail() }
        XCTAssertEqual(rows.map(\.path), ["lib/a.swift", "lib/b.swift"])
        XCTAssertEqual(board.panels[5], .heatmap(title: "Commits", unit: "commits", rows: ["Mon", "Tue"], columns: ["AM", "PM"],
                                                 counts: [[1, 2], [3, 4]]))
    }

    func testActionPanelsValidateButAreNotRendered() throws {
        let board = try XCTUnwrap(board("""
        root = Board("Mail", "", [MailList("is:unread", [{from: "a", subject: "s", snippet: "x", time: "now", unread: true}])])
        """))
        XCTAssertEqual(board.panels, [.unsupported(type: "MailList")])
        XCTAssertFalse(board.isFullyRendered)
    }

    func testCatalogRejectsMalformedBoards() {
        XCTAssertEqual(problem(#"root = Stat("x", 1)"#), "Expected Board component.")
        XCTAssertEqual(problem(#"root = Board("x", "y", [])"#), "Board panels has an invalid length.")
        XCTAssertEqual(problem(#"root = Board("x", "y", [Script("rm")])"#), "Unsupported or unknown component: Script")
        XCTAssertEqual(problem(#"root = Board("x", "y", [1])"#), "Chart board contains an unknown panel.")
        XCTAssertEqual(problem(#"root = Board("x", "y", [Table("t", ["a", "b"], [["only one"]])])"#),
                       "Table rows must match the declared columns.")
        XCTAssertEqual(problem(#"root = Board("x", "y", [LineChart("t", "u", ["a", "b"], [{name: "s", values: [1]}])])"#),
                       "LineChart series \"s\" needs 2 values.")
        XCTAssertEqual(problem(#"root = Board("x", "y", [BarChart("t", "u", [{label: "a", value: -1}])])"#), "value is out of range.")
        XCTAssertEqual(problem(#"root = Board("x", "y", [Treemap("t", "s", "c", [{path: "a", size: 1, color: 1}, {path: "a/b", size: 1, color: 1}])])"#),
                       "Treemap path \"a\" is both a file and a folder.")
        XCTAssertEqual(problem(#"root = Board("x", "y", [Heatmap("t", "u", ["r"], ["c1", "c2"], [[1]])])"#),
                       "Heatmap row \"r\" needs 2 counts.")
        XCTAssertEqual(problem(#"root = Board("x", "y", [PullRequest(1, "t", "ready", "h", "b", [{name: "ci", status: "fail", detail: ""}], 0)])"#),
                       "PullRequest ready needs every check passed or skipped.")
        XCTAssertEqual(problem(#"root = Board("x", "y", [Stat("t")])"#), "Stat has an invalid number of arguments.")
    }

    func testUnusedDeclarationsMayNotHideUnknownComponents() {
        XCTAssertEqual(problem("root = Board(\"x\", \"y\", [Stat(\"a\", 1)])\nside = Exec(\"x\")"), "Unsupported or unknown component: Exec")
    }

    func testIncompleteSourceStaysIncomplete() {
        guard case .incomplete = OpenUICatalog.inspect("root = Board(\"x\", \"y\", [Stat(\"a\", 1)") else { return XCTFail() }
    }

    func testTreemapTilesFillTheBoundsWithoutOverlap() {
        let rows = [6, 6, 4, 3, 2, 2, 1].enumerated().map { OpenUITreemapRow(path: "f\($0.offset)", size: Double($0.element), color: Double($0.offset)) }
        let bounds = OpenUIRect(x: 0, y: 0, width: 6, height: 4)
        let tiles = OpenUITreemapLayout.tiles(rows, in: bounds)
        XCTAssertEqual(tiles.count, rows.count)
        XCTAssertEqual(tiles.reduce(0) { $0 + $1.rect.area }, bounds.area, accuracy: 1e-9)
        for tile in tiles {
            XCTAssertEqual(tile.rect.area, tile.row.size, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(tile.rect.x, -1e-9)
            XCTAssertLessThanOrEqual(tile.rect.x + tile.rect.width, 6 + 1e-9)
            XCTAssertLessThanOrEqual(tile.rect.y + tile.rect.height, 4 + 1e-9)
        }
        XCTAssertEqual(tiles.first?.colorLevel, 0)
        XCTAssertEqual(tiles.last?.colorLevel, 1)
        XCTAssertTrue(OpenUITreemapLayout.tiles([OpenUITreemapRow(path: "z", size: 0, color: 0)], in: bounds).isEmpty)
    }
}
