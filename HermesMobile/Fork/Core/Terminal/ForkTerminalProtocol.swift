import Foundation

struct ForkTerminalMeta: Equatable, Sendable {
    var shell: String?
    var cwd: String?
    var terminalID: String?
    var closed = false
}

enum ForkTerminalProtocol {
    static let metaPrefix = "\u{0}HERMES_TERMINAL_META:"
    static let processExitedCloseCode = 4410
    static let ticketPath = "api/webapp/socket-ticket"
    static let socketPath = "api/host-terminal"
    static let socketName = "host-terminal"

    static func meta(_ text: String) -> ForkTerminalMeta? {
        guard text.hasPrefix(metaPrefix) else { return nil }
        let json = text.dropFirst(metaPrefix.count)
        guard let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ForkTerminalMeta() }
        return ForkTerminalMeta(shell: object["shell"] as? String, cwd: object["cwd"] as? String,
                                terminalID: object["terminalId"] as? String, closed: object["closed"] as? Bool ?? false)
    }

    static func resizeFrame(columns: Int, rows: Int) -> String {
        "\u{1B}[RESIZE:\(max(columns, 1));\(max(rows, 1))]"
    }

    static func ticket(from body: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let ticket = (object["ticket"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !ticket.isEmpty else { return nil }
        return ticket
    }

    static func socketURL(base: URL, ticket: String, cwd: String?, columns: Int, rows: Int, profile: String?) -> URL? {
        guard var parts = URLComponents(url: base.appendingPathComponent(socketPath), resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        var items = [URLQueryItem(name: "ticket", value: ticket)]
        if let cwd, !cwd.isEmpty { items.append(URLQueryItem(name: "cwd", value: cwd)) }
        items.append(URLQueryItem(name: "cols", value: String(max(columns, 1))))
        items.append(URLQueryItem(name: "rows", value: String(max(rows, 1))))
        if let profile, !profile.isEmpty { items.append(URLQueryItem(name: "profile", value: profile)) }
        parts.queryItems = items
        return parts.url
    }

    static func ticketURL(base: URL) -> URL? {
        guard var parts = URLComponents(url: base.appendingPathComponent(ticketPath), resolvingAgainstBaseURL: false) else { return nil }
        parts.queryItems = [URLQueryItem(name: "socket", value: socketName)]
        return parts.url
    }

    static func grid(width: Double, height: Double, cellWidth: Double, cellHeight: Double) -> (columns: Int, rows: Int) {
        guard cellWidth > 0, cellHeight > 0 else { return (80, 24) }
        return (min(max(Int(width / cellWidth), 20), 2000), min(max(Int(height / cellHeight), 5), 1000))
    }

    static let keys: [(label: String, sequence: String)] = [
        ("esc", "\u{1B}"), ("tab", "\t"), ("ctrl-c", "\u{03}"), ("ctrl-d", "\u{04}"),
        ("up", "\u{1B}[A"), ("down", "\u{1B}[B"), ("left", "\u{1B}[D"), ("right", "\u{1B}[C"),
    ]
}
