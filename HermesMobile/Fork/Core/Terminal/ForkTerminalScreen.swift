import Foundation

struct ForkTerminalStyle: Equatable, Hashable, Sendable {
    var foreground: ForkTerminalColor = .standard
    var background: ForkTerminalColor = .standard
    var bold = false
    var italic = false
    var underline = false
    var inverse = false
}

enum ForkTerminalColor: Equatable, Hashable, Sendable {
    case standard
    case palette(Int)
    case rgb(Int, Int, Int)
}

struct ForkTerminalCell: Equatable, Sendable {
    var character: Character = " "
    var style = ForkTerminalStyle()
}

struct ForkTerminalScreen: Sendable {
    static let scrollbackLimit = 2000

    private(set) var columns: Int
    private(set) var rows: Int
    private(set) var lines: [[ForkTerminalCell]]
    private(set) var scrollback: [[ForkTerminalCell]] = []
    private(set) var cursorRow = 0
    private(set) var cursorColumn = 0
    private(set) var title: String?
    private var style = ForkTerminalStyle()
    private var savedCursor: (Int, Int) = (0, 0)
    private var parser = Parser.ground
    private var parameters = ""
    private var osc = ""
    private var pendingBytes: [UInt8] = []
    private var wrapPending = false

    private enum Parser { case ground, escape, csi, osc, oscEscape, charset }

    init(columns: Int = 80, rows: Int = 24) {
        self.columns = max(columns, 2)
        self.rows = max(rows, 1)
        lines = Array(repeating: Array(repeating: ForkTerminalCell(), count: max(columns, 2)), count: max(rows, 1))
    }

    var text: String {
        (scrollback + lines).map { String($0.map(\.character)).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n").replacingOccurrences(of: #"\n+$"#, with: "", options: .regularExpression)
    }

    mutating func resize(columns newColumns: Int, rows newRows: Int) {
        let newColumns = max(newColumns, 2), newRows = max(newRows, 1)
        lines = lines.map { row in
            row.count >= newColumns ? Array(row.prefix(newColumns)) : row + Array(repeating: ForkTerminalCell(), count: newColumns - row.count)
        }
        scrollback = scrollback.map { Array($0.prefix(newColumns)) }
        while lines.count > newRows {
            if cursorRow > 0 { pushScrollback(lines.removeFirst()); cursorRow -= 1 } else { lines.removeLast() }
        }
        while lines.count < newRows { lines.append(blankLine(newColumns)) }
        columns = newColumns
        rows = newRows
        cursorRow = min(cursorRow, rows - 1)
        cursorColumn = min(cursorColumn, columns - 1)
    }

    mutating func feed(_ bytes: [UInt8]) {
        var data = pendingBytes + bytes
        pendingBytes = []
        let incomplete = Self.incompleteSuffix(data)
        if incomplete > 0 {
            pendingBytes = Array(data.suffix(incomplete))
            data.removeLast(incomplete)
        }
        feed(String(decoding: data, as: UTF8.self))
    }

    mutating func feed(_ text: String) {
        for scalar in text.unicodeScalars { consume(scalar) }
    }

    private mutating func consume(_ scalar: Unicode.Scalar) {
        switch parser {
        case .ground: ground(scalar)
        case .escape: escape(scalar)
        case .csi: csi(scalar)
        case .osc:
            if scalar == "\u{07}" { finishOSC() } else if scalar == "\u{1B}" { parser = .oscEscape } else { osc.unicodeScalars.append(scalar) }
        case .oscEscape:
            if scalar == "\\" { finishOSC() } else { parser = .osc; osc.unicodeScalars.append(scalar) }
        case .charset:
            parser = .ground
        }
    }

    private mutating func ground(_ scalar: Unicode.Scalar) {
        switch scalar {
        case "\u{1B}": parser = .escape
        case "\r": cursorColumn = 0; wrapPending = false
        case "\n", "\u{0B}", "\u{0C}": lineFeed()
        case "\u{08}": cursorColumn = max(cursorColumn - 1, 0); wrapPending = false
        case "\t": cursorColumn = min((cursorColumn / 8 + 1) * 8, columns - 1)
        case "\u{07}", "\u{00}", "\u{0E}", "\u{0F}": break
        default:
            guard scalar.value >= 0x20, scalar.value != 0x7F else { return }
            put(Character(scalar))
        }
    }

    private mutating func escape(_ scalar: Unicode.Scalar) {
        parser = .ground
        switch scalar {
        case "[": parser = .csi; parameters = ""
        case "]": parser = .osc; osc = ""
        case "(", ")", "*", "+": parser = .charset
        case "7": savedCursor = (cursorRow, cursorColumn)
        case "8": (cursorRow, cursorColumn) = savedCursor
        case "D": lineFeed()
        case "E": cursorColumn = 0; lineFeed()
        case "M": reverseIndex()
        case "c": self = ForkTerminalScreen(columns: columns, rows: rows)
        default: break
        }
    }

    private mutating func csi(_ scalar: Unicode.Scalar) {
        if (0x30...0x3F).contains(scalar.value) || (0x20...0x2F).contains(scalar.value) {
            parameters.unicodeScalars.append(scalar)
            return
        }
        parser = .ground
        let isPrivate = parameters.hasPrefix("?")
        let values = parameters.trimmingCharacters(in: CharacterSet(charactersIn: "?>= !")).split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) }
        func value(_ index: Int, _ fallback: Int = 1) -> Int {
            guard index < values.count, let number = values[index], number > 0 else { return fallback }
            return number
        }
        wrapPending = false
        switch scalar {
        case "A": cursorRow = max(cursorRow - value(0), 0)
        case "B", "e": cursorRow = min(cursorRow + value(0), rows - 1)
        case "C", "a": cursorColumn = min(cursorColumn + value(0), columns - 1)
        case "D": cursorColumn = max(cursorColumn - value(0), 0)
        case "E": cursorRow = min(cursorRow + value(0), rows - 1); cursorColumn = 0
        case "F": cursorRow = max(cursorRow - value(0), 0); cursorColumn = 0
        case "G", "`": cursorColumn = min(value(0) - 1, columns - 1)
        case "d": cursorRow = min(value(0) - 1, rows - 1)
        case "H", "f":
            cursorRow = min(value(0) - 1, rows - 1)
            cursorColumn = min(value(1) - 1, columns - 1)
        case "J": eraseDisplay(values.first.flatMap { $0 } ?? 0)
        case "K": eraseLine(values.first.flatMap { $0 } ?? 0)
        case "P": deleteCharacters(value(0))
        case "@": insertCharacters(value(0))
        case "X": for offset in 0..<min(value(0), columns - cursorColumn) { lines[cursorRow][cursorColumn + offset] = blank() }
        case "L": for _ in 0..<value(0) { lines.insert(blankLine(columns), at: cursorRow); lines.removeLast() }
        case "M": for _ in 0..<value(0) { lines.remove(at: cursorRow); lines.append(blankLine(columns)) }
        case "S": for _ in 0..<value(0) { scrollUp() }
        case "m": applySGR(values.map { $0 ?? 0 })
        case "s": savedCursor = (cursorRow, cursorColumn)
        case "u": (cursorRow, cursorColumn) = savedCursor
        case "h", "l":
            if isPrivate, values.contains(where: { [1049, 1047, 47].contains($0 ?? 0) }) {
                lines = Array(repeating: blankLine(columns), count: rows)
                cursorRow = 0
                cursorColumn = 0
            }
        default: break
        }
    }

    private mutating func finishOSC() {
        parser = .ground
        let parts = osc.split(separator: ";", maxSplits: 1)
        if parts.count == 2, ["0", "2"].contains(parts[0]) { title = String(parts[1]) }
        osc = ""
    }

    private mutating func put(_ character: Character) {
        if wrapPending {
            cursorColumn = 0
            lineFeed()
            wrapPending = false
        }
        lines[cursorRow][cursorColumn] = ForkTerminalCell(character: character, style: style)
        if cursorColumn == columns - 1 { wrapPending = true } else { cursorColumn += 1 }
    }

    private mutating func lineFeed() {
        wrapPending = false
        if cursorRow == rows - 1 { scrollUp() } else { cursorRow += 1 }
    }

    private mutating func reverseIndex() {
        if cursorRow == 0 { lines.insert(blankLine(columns), at: 0); lines.removeLast() } else { cursorRow -= 1 }
    }

    private mutating func scrollUp() {
        pushScrollback(lines.removeFirst())
        lines.append(blankLine(columns))
    }

    private mutating func pushScrollback(_ line: [ForkTerminalCell]) {
        scrollback.append(line)
        if scrollback.count > Self.scrollbackLimit { scrollback.removeFirst(scrollback.count - Self.scrollbackLimit) }
    }

    private mutating func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseLine(0)
            for row in (cursorRow + 1)..<rows { lines[row] = blankLine(columns) }
        case 1:
            eraseLine(1)
            for row in 0..<cursorRow { lines[row] = blankLine(columns) }
        case 3: scrollback = []
        default: lines = Array(repeating: blankLine(columns), count: rows)
        }
    }

    private mutating func eraseLine(_ mode: Int) {
        let range: Range<Int> = switch mode {
        case 0: cursorColumn..<columns
        case 1: 0..<(cursorColumn + 1)
        default: 0..<columns
        }
        for column in range { lines[cursorRow][column] = blank() }
    }

    private mutating func deleteCharacters(_ count: Int) {
        let count = min(count, columns - cursorColumn)
        lines[cursorRow].removeSubrange(cursorColumn..<(cursorColumn + count))
        lines[cursorRow].append(contentsOf: Array(repeating: blank(), count: count))
    }

    private mutating func insertCharacters(_ count: Int) {
        let count = min(count, columns - cursorColumn)
        lines[cursorRow].insert(contentsOf: Array(repeating: blank(), count: count), at: cursorColumn)
        lines[cursorRow].removeLast(count)
    }

    private mutating func applySGR(_ codes: [Int]) {
        var codes = codes.isEmpty ? [0] : codes
        while !codes.isEmpty {
            let code = codes.removeFirst()
            switch code {
            case 0: style = ForkTerminalStyle()
            case 1: style.bold = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 22: style.bold = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .palette(code - 30)
            case 39: style.foreground = .standard
            case 40...47: style.background = .palette(code - 40)
            case 49: style.background = .standard
            case 90...97: style.foreground = .palette(code - 90 + 8)
            case 100...107: style.background = .palette(code - 100 + 8)
            case 38, 48:
                guard let kind = codes.first else { break }
                var color: ForkTerminalColor?
                if kind == 5, codes.count >= 2 {
                    color = .palette(min(max(codes[1], 0), 255)); codes.removeFirst(2)
                } else if kind == 2, codes.count >= 4 {
                    color = .rgb(codes[1], codes[2], codes[3]); codes.removeFirst(4)
                } else {
                    codes.removeFirst()
                }
                if let color { if code == 38 { style.foreground = color } else { style.background = color } }
            default: break
            }
        }
    }

    private func blank() -> ForkTerminalCell { ForkTerminalCell(character: " ", style: ForkTerminalStyle(background: style.background)) }

    private func blankLine(_ count: Int) -> [ForkTerminalCell] { Array(repeating: ForkTerminalCell(), count: count) }

    static func incompleteSuffix(_ bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }
        for back in 1...min(3, bytes.count) {
            let byte = bytes[bytes.count - back]
            if byte & 0b1100_0000 == 0b1000_0000 { continue }
            let needed = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
            return needed > back ? back : 0
        }
        return 0
    }
}
