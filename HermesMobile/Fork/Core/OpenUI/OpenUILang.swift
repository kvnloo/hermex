import Foundation

struct OpenUIProblem: Equatable, Sendable, CustomStringConvertible {
    let message: String
    let line: Int
    let column: Int

    var description: String { "\(line):\(column): \(message)" }
}

indirect enum OpenUIValue: Equatable, Sendable {
    case string(String, OpenUIPosition)
    case number(Double, OpenUIPosition)
    case boolean(Bool, OpenUIPosition)
    case null(OpenUIPosition)
    case array([OpenUIValue], OpenUIPosition)
    case object([String: OpenUIValue], OpenUIPosition)
    case call(String, [OpenUIValue], OpenUIPosition)
    case reference(String, OpenUIPosition)

    var position: OpenUIPosition {
        switch self {
        case .string(_, let at), .number(_, let at), .boolean(_, let at), .null(let at), .array(_, let at),
             .object(_, let at), .call(_, _, let at), .reference(_, let at): at
        }
    }
}

struct OpenUIPosition: Equatable, Hashable, Sendable {
    let line: Int
    let column: Int
}

struct OpenUIProgram: Equatable, Sendable {
    let assignments: [String: OpenUIValue]
    let root: OpenUIValue
}

enum OpenUIParseResult: Equatable, Sendable {
    case ready(OpenUIProgram)
    case incomplete(OpenUIProblem)
    case invalid(OpenUIProblem)
}

enum OpenUILang {
    static let maxSourceBytes = 65_536
    static let maxDepth = 80

    static func parse(_ source: String) -> OpenUIParseResult {
        guard source.utf8.count <= maxSourceBytes else {
            return .invalid(OpenUIProblem(message: "Chart board exceeds the 64 KiB limit.", line: 1, column: 1))
        }
        do {
            var scanner = OpenUIScanner(source)
            var reader = OpenUIReader(tokens: try scanner.scan())
            let declarations = try reader.read()
            guard declarations["root"] != nil else {
                return .incomplete(OpenUIProblem(message: "Missing root assignment.", line: 1, column: 1))
            }
            var resolved: [String: OpenUIValue] = [:]
            func resolve(_ value: OpenUIValue, _ stack: Set<String>) throws -> OpenUIValue {
                switch value {
                case .reference(let name, let at):
                    if stack.count >= maxDepth { throw OpenUIFault("Reference depth exceeded.", at) }
                    if stack.contains(name) { throw OpenUIFault("Cyclic reference: \(name).", at) }
                    guard let raw = declarations[name] else {
                        throw OpenUIFault("Unresolved reference: \(name).", at, incomplete: true)
                    }
                    if let cached = resolved[name] { return cached }
                    let result = try resolve(raw, stack.union([name]))
                    resolved[name] = result
                    return result
                case .array(let items, let at):
                    return .array(try items.map { try resolve($0, stack) }, at)
                case .object(let fields, let at):
                    return .object(try fields.mapValues { try resolve($0, stack) }, at)
                case .call(let name, let args, let at):
                    return .call(name, try args.map { try resolve($0, stack) }, at)
                default:
                    return value
                }
            }
            for key in declarations.keys.sorted() where resolved[key] == nil {
                resolved[key] = try resolve(declarations[key]!, [key])
            }
            return .ready(OpenUIProgram(assignments: resolved, root: resolved["root"]!))
        } catch let fault as OpenUIFault {
            let problem = OpenUIProblem(message: fault.message, line: fault.at.line, column: fault.at.column)
            return fault.incomplete ? .incomplete(problem) : .invalid(problem)
        } catch {
            return .invalid(OpenUIProblem(message: "Unreadable board.", line: 1, column: 1))
        }
    }
}

struct OpenUIFault: Error {
    let message: String
    let at: OpenUIPosition
    let incomplete: Bool

    init(_ message: String, _ at: OpenUIPosition, incomplete: Bool = false) {
        self.message = message
        self.at = at
        self.incomplete = incomplete
    }
}

private enum OpenUIKind: Equatable {
    case name, string, number, equal, lParen, rParen, lBracket, rBracket, lBrace, rBrace, comma, colon, separator, eof
}

private struct OpenUIToken {
    let kind: OpenUIKind
    let text: String
    let at: OpenUIPosition
}

private struct OpenUIScanner {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var line = 1
    private var column = 1

    init(_ source: String) {
        scalars = Array(source.unicodeScalars)
    }

    private var atEnd: Bool { index == scalars.count }
    private var current: Unicode.Scalar { scalars[index] }
    private var here: OpenUIPosition { OpenUIPosition(line: line, column: column) }

    @discardableResult
    private mutating func advance() -> Unicode.Scalar {
        let scalar = scalars[index]
        index += 1
        if scalar == "\n" { line += 1; column = 1 } else { column += 1 }
        return scalar
    }

    private func peek(_ offset: Int) -> Unicode.Scalar? {
        index + offset < scalars.count ? scalars[index + offset] : nil
    }

    private static let punctuation: [Unicode.Scalar: OpenUIKind] = [
        "=": .equal, "(": .lParen, ")": .rParen, "[": .lBracket, "]": .rBracket, "{": .lBrace, "}": .rBrace,
        ",": .comma, ":": .colon, "\n": .separator, ";": .separator,
    ]

    private static func isNameStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar)
    }

    private static func isDigit(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return ("0"..."9").contains(scalar)
    }

    mutating func scan() throws -> [OpenUIToken] {
        var tokens: [OpenUIToken] = []
        while !atEnd {
            let at = here
            let scalar = current
            if scalar == " " || scalar == "\t" || scalar == "\r" { advance(); continue }
            if scalar == "#" || (scalar == "/" && peek(1) == "/") {
                while !atEnd && current != "\n" { advance() }
                continue
            }
            if scalar == "\"" || scalar == "'" {
                tokens.append(OpenUIToken(kind: .string, text: try string(scalar, at), at: at))
                continue
            }
            if let kind = Self.punctuation[scalar] {
                advance()
                tokens.append(OpenUIToken(kind: kind, text: String(scalar), at: at))
                continue
            }
            if Self.isNameStart(scalar) {
                var word = ""
                while !atEnd, Self.isNameStart(current) || Self.isDigit(current) { word.unicodeScalars.append(advance()) }
                tokens.append(OpenUIToken(kind: .name, text: word, at: at))
                continue
            }
            if scalar == "-" || Self.isDigit(scalar) {
                tokens.append(OpenUIToken(kind: .number, text: try number(at), at: at))
                continue
            }
            throw OpenUIFault("Unexpected character \"\(scalar)\".", at)
        }
        tokens.append(OpenUIToken(kind: .eof, text: "", at: here))
        return tokens
    }

    private mutating func number(_ at: OpenUIPosition) throws -> String {
        var length = 0
        func digits(from start: Int) -> Int {
            var end = start
            while Self.isDigit(peek(end)) { end += 1 }
            return end
        }
        if peek(length) == "-" { length += 1 }
        if peek(length) == "0" {
            length += 1
        } else if Self.isDigit(peek(length)) {
            length = digits(from: length)
        } else {
            throw OpenUIFault("Invalid number.", at)
        }
        if peek(length) == ".", Self.isDigit(peek(length + 1)) { length = digits(from: length + 1) }
        if peek(length) == "e" || peek(length) == "E" {
            var exponent = length + 1
            if peek(exponent) == "+" || peek(exponent) == "-" { exponent += 1 }
            if Self.isDigit(peek(exponent)) { length = digits(from: exponent) }
        }
        var text = ""
        for _ in 0..<length { text.unicodeScalars.append(advance()) }
        return text
    }

    private mutating func string(_ quote: Unicode.Scalar, _ at: OpenUIPosition) throws -> String {
        advance()
        var out = String.UnicodeScalarView()
        while !atEnd {
            let scalar = advance()
            if scalar == quote { return String(out) }
            if scalar == "\n" { throw OpenUIFault("Newline inside string.", at) }
            guard scalar == "\\" else { out.append(scalar); continue }
            guard !atEnd else { throw OpenUIFault("Unterminated string.", at, incomplete: true) }
            let escape = advance()
            switch escape {
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "\"", "'", "/", "\\": out.append(escape)
            case "u": out.append(try unicodeEscape(at))
            default: throw OpenUIFault("Invalid string escape.", at)
            }
        }
        throw OpenUIFault("Unterminated string.", at, incomplete: true)
    }

    private mutating func hexQuad(_ at: OpenUIPosition) throws -> UInt32 {
        guard index + 4 <= scalars.count else { throw OpenUIFault("Incomplete Unicode escape.", at, incomplete: true) }
        var text = ""
        for _ in 0..<4 { text.unicodeScalars.append(advance()) }
        guard text.allSatisfy(\.isHexDigit), let value = UInt32(text, radix: 16) else {
            throw OpenUIFault("Invalid Unicode escape.", at)
        }
        return value
    }

    private mutating func unicodeEscape(_ at: OpenUIPosition) throws -> Unicode.Scalar {
        let high = try hexQuad(at)
        if (0xD800...0xDBFF).contains(high), peek(0) == "\\", peek(1) == "u" {
            advance(); advance()
            let low = try hexQuad(at)
            if (0xDC00...0xDFFF).contains(low), let scalar = Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)) {
                return scalar
            }
        }
        guard let scalar = Unicode.Scalar(high) else { throw OpenUIFault("Invalid Unicode escape.", at) }
        return scalar
    }
}

private struct OpenUIReader {
    let tokens: [OpenUIToken]
    private var index = 0

    init(tokens: [OpenUIToken]) {
        self.tokens = tokens
    }

    private var current: OpenUIToken { tokens[index] }

    private mutating func take() -> OpenUIToken {
        defer { index += 1 }
        return tokens[index]
    }

    private mutating func skipLines() {
        while current.kind == .separator { index += 1 }
    }

    @discardableResult
    private mutating func expect(_ kind: OpenUIKind, _ label: String) throws -> OpenUIToken {
        skipLines()
        if current.kind == kind { return take() }
        throw OpenUIFault("Expected \(label).", current.at, incomplete: current.kind == .eof)
    }

    mutating func read() throws -> [String: OpenUIValue] {
        var result: [String: OpenUIValue] = [:]
        skipLines()
        while current.kind != .eof {
            let key = try expect(.name, "assignment name")
            if ["true", "false", "null"].contains(key.text) {
                throw OpenUIFault("Literal cannot be an assignment name.", key.at)
            }
            try expect(.equal, "\"=\"")
            let value = try self.value(depth: 0)
            if result[key.text] != nil { throw OpenUIFault("Duplicate assignment: \(key.text)", key.at) }
            result[key.text] = value
            if current.kind != .separator && current.kind != .eof {
                throw OpenUIFault("Expected a new assignment on a new line.", current.at)
            }
            skipLines()
        }
        return result
    }

    private mutating func value(depth: Int) throws -> OpenUIValue {
        if depth > OpenUILang.maxDepth { throw OpenUIFault("Nesting limit exceeded.", current.at) }
        skipLines()
        let token = take()
        switch token.kind {
        case .string:
            return .string(token.text, token.at)
        case .number:
            guard let number = Double(token.text), number.isFinite else {
                throw OpenUIFault("Invalid finite number.", token.at)
            }
            return .number(number, token.at)
        case .name:
            if token.text == "true" || token.text == "false" { return .boolean(token.text == "true", token.at) }
            if token.text == "null" { return .null(token.at) }
            guard current.kind == .lParen else { return .reference(token.text, token.at) }
            index += 1
            return .call(token.text, try sequence(depth: depth, closer: .rParen), token.at)
        case .lBracket:
            return .array(try sequence(depth: depth, closer: .rBracket), token.at)
        case .lBrace:
            var fields: [String: OpenUIValue] = [:]
            skipLines()
            while current.kind != .rBrace {
                if current.kind == .eof { throw OpenUIFault("Unclosed object.", current.at, incomplete: true) }
                let key = current
                guard key.kind == .name || key.kind == .string else { throw OpenUIFault("Expected object key.", key.at) }
                index += 1
                try expect(.colon, "\":\"")
                if fields[key.text] != nil { throw OpenUIFault("Duplicate object key: \(key.text)", key.at) }
                fields[key.text] = try value(depth: depth + 1)
                skipLines()
                if current.kind == .rBrace { break }
                try expect(.comma, "\",\"")
                skipLines()
            }
            index += 1
            return .object(fields, token.at)
        case .eof:
            throw OpenUIFault("Incomplete expression.", token.at, incomplete: true)
        default:
            throw OpenUIFault("Expected a literal, reference or call.", token.at)
        }
    }

    private mutating func sequence(depth: Int, closer: OpenUIKind) throws -> [OpenUIValue] {
        var items: [OpenUIValue] = []
        skipLines()
        while current.kind != closer {
            if current.kind == .eof { throw OpenUIFault("Unclosed call or array.", current.at, incomplete: true) }
            items.append(try value(depth: depth + 1))
            skipLines()
            if current.kind == closer { break }
            try expect(.comma, "\",\"")
            skipLines()
        }
        index += 1
        return items
    }
}
