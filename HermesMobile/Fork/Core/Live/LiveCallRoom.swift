import Foundation

struct LiveCall: Equatable, Sendable {
    let id: Int
    let chat: String
    var presentation: LiveOrbMode = .focus
    var chatOnScreen = true
}

enum LiveCallEnd: Equatable, Sendable {
    case user
    case background
    case accountChanged
}

struct LiveCallEnding: Equatable, Sendable {
    let call: LiveCall
    let reason: LiveCallEnd
    var releasesChat: Bool { !call.chatOnScreen }
}

struct LiveCallRoom: Equatable, Sendable {
    private(set) var call: LiveCall?
    private var lastID = 0

    mutating func start(chat: String) -> LiveCall? {
        guard call == nil else {
            expand()
            return nil
        }
        lastID += 1
        let begun = LiveCall(id: lastID, chat: chat)
        call = begun
        return begun
    }

    mutating func compact() { call?.presentation = .bubble }

    mutating func expand() { call?.presentation = .focus }

    mutating func chatLeft(_ chat: String) -> Bool {
        guard call?.chat == chat else { return false }
        call?.chatOnScreen = false
        return true
    }

    mutating func chatAppeared(_ chat: String) {
        guard call?.chat == chat else { return }
        call?.chatOnScreen = true
    }

    mutating func end(_ reason: LiveCallEnd) -> LiveCallEnding? {
        guard let call else { return nil }
        self.call = nil
        return LiveCallEnding(call: call, reason: reason)
    }
}
