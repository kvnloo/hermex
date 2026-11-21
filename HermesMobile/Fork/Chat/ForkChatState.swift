import Foundation
import Observation

struct ForkReactionTarget: Identifiable, Equatable {
    let rowID: Int
    let current: ForkReaction?

    var id: Int { rowID }
}

@MainActor
@Observable
final class ForkChatState {
    @ObservationIgnored private weak var turn: HermesChatTurnCoordinator?
    private(set) var book = ForkReactionBook()
    private(set) var isUnavailable = false
    private(set) var sending: Set<Int> = []
    var picking: ForkReactionTarget?

    init(turn: HermesChatTurnCoordinator) {
        self.turn = turn
    }

    var canReact: Bool {
        guard !isUnavailable, let engine = turn?.engine else { return false }
        return engine.connectionState == .connected && engine.runtime != nil
    }

    func reactions(for message: ChatMessage) -> [ForkReaction] {
        book.reactions(rowID: message.rowID, seeded: ForkReactionRows.seeded(message))
    }

    func receive(rowID: Int, reactions: BotJSON) {
        book.set(ForkReactionRows.parse(reactions), rowID: rowID)
    }

    func pick(for message: ChatMessage) {
        guard canReact, let rowID = message.rowID else { return }
        picking = ForkReactionTarget(rowID: rowID, current: ForkReactionBook.mine(in: reactions(for: message)))
    }

    func choose(_ emoji: String?, for target: ForkReactionTarget) async {
        guard canReact, let engine = turn?.engine, let runtime = engine.runtime,
              sending.insert(target.rowID).inserted else { return }
        defer { sending.remove(target.rowID) }
        let before = book.rows[target.rowID]
        let call = ForkRPC.messageReact(sessionID: runtime, rowID: target.rowID,
                                        emoji: ForkReactionBook.requestEmoji(choosing: emoji, current: target.current))
        do {
            let reply = try await engine.request(.fork(call), attempt: engine.generation)
            guard let rowID = reply["row_id"].integer, case .array = reply["reactions"] else { return }
            book.merge(reply: ForkReactionRows.parse(reply["reactions"]), rowID: rowID, before: before)
        } catch BotFailure.rejected(-32601) {
            isUnavailable = true
        } catch {
            return
        }
    }
}
