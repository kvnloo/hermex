import Foundation
import Observation

@MainActor
@Observable
final class ForkHostTerminalSession {
    enum State: Equatable {
        case idle
        case connecting
        case open
        case ended(String)
        case unavailable
    }

    private(set) var state: State = .idle
    private(set) var screen = ForkTerminalScreen()
    private(set) var meta = ForkTerminalMeta()
    private(set) var revision = 0
    let profile: String?

    @ObservationIgnored private let http: HermesConnection
    @ObservationIgnored private var socket: ForkSocketBox?
    @ObservationIgnored private var receiver: Task<Void, Never>?

    init(connection: BotConnection, server: URL, profile: String?) {
        http = HermesConnections.shared.connection(for: connection, server: server)
        self.profile = profile
    }

    func open(columns: Int, rows: Int) async {
        close()
        state = .connecting
        screen = ForkTerminalScreen(columns: columns, rows: rows)
        meta = ForkTerminalMeta()
        let base = http.connection.address
        do {
            guard let ticketURL = ForkTerminalProtocol.ticketURL(base: base) else { throw BotFailure.invalidAddress }
            var mint = URLRequest(url: ticketURL)
            mint.httpMethod = "POST"
            let reply = try await http.reply(mint)
            if reply.status == 404 || reply.status == 400 { state = .unavailable; return }
            guard reply.status == 200, let ticket = ForkTerminalProtocol.ticket(from: reply.body),
                  let url = ForkTerminalProtocol.socketURL(base: base, ticket: ticket, cwd: nil, columns: columns, rows: rows,
                                                         profile: profile) else {
                state = .ended(String(localized: "Hermes didn't open a terminal (HTTP \(reply.status)).", table: "Fork"))
                return
            }
            let box = try await http.authorized(URLRequest(url: url)) { request, session in
                ForkSocketBox(task: session.webSocketTask(with: request))
            }
            box.task.maximumMessageSize = 16 * 1024 * 1024
            box.task.resume()
            socket = box
            state = .open
            receiver = Task { [weak self] in await self?.receive(from: box) }
        } catch {
            state = .ended(error.localizedDescription)
        }
    }

    func send(_ text: String) {
        guard state == .open, let task = socket?.task, !text.isEmpty else { return }
        task.send(.string(text)) { _ in }
    }

    func resize(columns: Int, rows: Int) {
        guard columns != screen.columns || rows != screen.rows else { return }
        screen.resize(columns: columns, rows: rows)
        revision &+= 1
        send(ForkTerminalProtocol.resizeFrame(columns: columns, rows: rows))
    }

    func close() {
        receiver?.cancel()
        receiver = nil
        socket?.task.cancel(with: .normalClosure, reason: nil)
        socket = nil
        if state == .open || state == .connecting { state = .idle }
    }

    private func receive(from box: ForkSocketBox) async {
        while !Task.isCancelled {
            do {
                switch try await box.task.receive() {
                case .string(let text):
                    if let meta = ForkTerminalProtocol.meta(text) {
                        if meta.closed { return end(String(localized: "The terminal closed.", table: "Fork")) }
                        self.meta = meta
                    } else {
                        screen.feed(text)
                    }
                case .data(let data):
                    screen.feed(Array(data))
                @unknown default:
                    break
                }
                revision &+= 1
            } catch {
                guard socket === box else { return }
                let exited = box.task.closeCode.rawValue == ForkTerminalProtocol.processExitedCloseCode
                return end(exited ? String(localized: "The shell exited.", table: "Fork") : error.localizedDescription)
            }
        }
    }

    private func end(_ reason: String) {
        socket = nil
        state = .ended(reason)
    }
}

final class ForkSocketBox: @unchecked Sendable {
    let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }
}
