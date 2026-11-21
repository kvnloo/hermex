import XCTest
@testable import HermesMobile

final class ForkTerminalScreenTests: XCTestCase {
    func testPrintsWrapsAndScrollsIntoScrollback() {
        var screen = ForkTerminalScreen(columns: 5, rows: 2)
        screen.feed("hello world\r\nnext")
        XCTAssertEqual(screen.text, "hello\n worl\nd\nnext")
        XCTAssertEqual(screen.scrollback.count, 2)
        XCTAssertEqual(screen.cursorRow, 1)
    }

    func testCarriageReturnOverwritesAndEraseLineClears() {
        var screen = ForkTerminalScreen(columns: 20, rows: 2)
        screen.feed("progress 10%\rprogress 99%\r\n")
        screen.feed("abcdef\u{1B}[3D\u{1B}[K!")
        XCTAssertEqual(screen.text, "progress 99%\nabc!")
    }

    func testCursorAddressingAndClearScreen() {
        var screen = ForkTerminalScreen(columns: 10, rows: 3)
        screen.feed("junk\u{1B}[2J\u{1B}[2;3HX\u{1B}[1;1HY")
        XCTAssertEqual(screen.text, "Y\n  X")
        XCTAssertEqual(screen.cursorRow, 0)
        XCTAssertEqual(screen.cursorColumn, 1)
    }

    func testSGRColorsAndReset() {
        var screen = ForkTerminalScreen(columns: 10, rows: 1)
        screen.feed("\u{1B}[1;31mA\u{1B}[38;5;208mB\u{1B}[38;2;1;2;3mC\u{1B}[0mD")
        let cells = screen.lines[0]
        XCTAssertEqual(cells[0].style.foreground, .palette(1))
        XCTAssertTrue(cells[0].style.bold)
        XCTAssertEqual(cells[1].style.foreground, .palette(208))
        XCTAssertEqual(cells[2].style.foreground, .rgb(1, 2, 3))
        XCTAssertEqual(cells[3].style, ForkTerminalStyle())
    }

    func testOSCTitleIsReadAndNotPrinted() {
        var screen = ForkTerminalScreen(columns: 10, rows: 1)
        screen.feed("\u{1B}]0;user@host: ~\u{07}$ ")
        XCTAssertEqual(screen.title, "user@host: ~")
        XCTAssertEqual(screen.text, "$")
    }

    func testSplitUTF8AcrossChunks() {
        var screen = ForkTerminalScreen(columns: 10, rows: 1)
        let bytes = Array("é✓".utf8)
        screen.feed(Array(bytes.prefix(1)))
        screen.feed(Array(bytes.dropFirst().prefix(2)))
        screen.feed(Array(bytes.dropFirst(3)))
        XCTAssertEqual(screen.text, "é✓")
        XCTAssertEqual(ForkTerminalScreen.incompleteSuffix([]), 0)
    }

    func testBackspaceDeleteAndInsertCharacters() {
        var screen = ForkTerminalScreen(columns: 10, rows: 1)
        screen.feed("abcd\u{08}\u{08}\u{1B}[1P")
        XCTAssertEqual(screen.text, "abd")
        screen.feed("\u{1B}[2@")
        XCTAssertEqual(screen.text, "ab  d")
    }

    func testAlternateScreenClears() {
        var screen = ForkTerminalScreen(columns: 10, rows: 2)
        screen.feed("shell$ \u{1B}[?1049hvim")
        XCTAssertEqual(screen.text, "vim")
    }

    func testResizeKeepsTheCursorRowVisible() {
        var screen = ForkTerminalScreen(columns: 10, rows: 4)
        screen.feed("1\r\n2\r\n3\r\n4")
        screen.resize(columns: 4, rows: 2)
        XCTAssertEqual(screen.lines.map { String($0.map(\.character)).trimmingCharacters(in: .whitespaces) }, ["3", "4"])
        XCTAssertEqual(screen.cursorRow, 1)
        XCTAssertEqual(screen.columns, 4)
    }

    func testScrollbackIsBounded() {
        var screen = ForkTerminalScreen(columns: 4, rows: 1)
        screen.feed(String(repeating: "x\r\n", count: ForkTerminalScreen.scrollbackLimit + 50))
        XCTAssertEqual(screen.scrollback.count, ForkTerminalScreen.scrollbackLimit)
    }
}

final class ForkTerminalProtocolTests: XCTestCase {
    func testMetaFrames() {
        XCTAssertEqual(ForkTerminalProtocol.meta("\u{0}HERMES_TERMINAL_META:{\"shell\":\"zsh\",\"cwd\":\"/srv/work\",\"terminalId\":\"t1\"}"),
                       ForkTerminalMeta(shell: "zsh", cwd: "/srv/work", terminalID: "t1", closed: false))
        XCTAssertEqual(ForkTerminalProtocol.meta("\u{0}HERMES_TERMINAL_META:{\"terminalId\":\"t1\",\"closed\":true}")?.closed, true)
        XCTAssertEqual(ForkTerminalProtocol.meta("\u{0}HERMES_TERMINAL_META:nope"), ForkTerminalMeta())
        XCTAssertNil(ForkTerminalProtocol.meta("plain output"))
    }

    func testResizeAndTicket() {
        XCTAssertEqual(ForkTerminalProtocol.resizeFrame(columns: 120, rows: 40), "\u{1B}[RESIZE:120;40]")
        XCTAssertEqual(ForkTerminalProtocol.ticket(from: Data(#"{"ticket":" abc ","ttl_seconds":30}"#.utf8)), "abc")
        XCTAssertNil(ForkTerminalProtocol.ticket(from: Data(#"{"ticket":""}"#.utf8)))
    }

    func testURLsUseTheDashboardPathsAndWebSocketScheme() {
        let base = URL(string: "https://host.example:9119")!
        XCTAssertEqual(ForkTerminalProtocol.ticketURL(base: base)?.absoluteString,
                       "https://host.example:9119/api/webapp/socket-ticket?socket=host-terminal")
        XCTAssertEqual(ForkTerminalProtocol.socketURL(base: base, ticket: "t k", cwd: "", columns: 80, rows: 24, profile: "work")?.absoluteString,
                       "wss://host.example:9119/api/host-terminal?ticket=t%20k&cols=80&rows=24&profile=work")
        XCTAssertEqual(ForkTerminalProtocol.socketURL(base: URL(string: "http://host.example:9131")!, ticket: "t", cwd: "/tmp", columns: 10, rows: 5, profile: nil)?.absoluteString,
                       "ws://host.example:9131/api/host-terminal?ticket=t&cwd=/tmp&cols=10&rows=5")
    }

    func testGridFromViewSize() {
        XCTAssertEqual(ForkTerminalProtocol.grid(width: 390, height: 600, cellWidth: 7.2, cellHeight: 15).columns, 54)
        XCTAssertEqual(ForkTerminalProtocol.grid(width: 390, height: 600, cellWidth: 7.2, cellHeight: 15).rows, 40)
        XCTAssertEqual(ForkTerminalProtocol.grid(width: 10, height: 10, cellWidth: 7, cellHeight: 15).columns, 20)
    }
}

final class ForkTerminalPaletteTests: XCTestCase {
    func testXterm256Palette() {
        XCTAssertTrue(ForkTerminalPalette.rgb(1) == (205, 49, 49))
        XCTAssertTrue(ForkTerminalPalette.rgb(16) == (0, 0, 0))
        XCTAssertTrue(ForkTerminalPalette.rgb(196) == (255, 0, 0))
        XCTAssertTrue(ForkTerminalPalette.rgb(208) == (255, 135, 0))
        XCTAssertTrue(ForkTerminalPalette.rgb(232) == (8, 8, 8))
        XCTAssertTrue(ForkTerminalPalette.rgb(255) == (238, 238, 238))
        XCTAssertTrue(ForkTerminalPalette.rgb(999) == (238, 238, 238))
    }
}
