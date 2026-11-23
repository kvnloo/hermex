import Foundation

enum LiveCallEnd: String, Equatable, Sendable {
    case user
    case bar
    case liveActivity
    case limit
    case replaced
}

enum LiveActivityCommand: String, Equatable, Sendable {
    case returnToCall
    case end
}

enum LiveCallAction: Equatable, Sendable {
    case begin(String)
    case restore
    case minimize
    case end(LiveCallEnd)
}

struct LiveCallRoom: Equatable, Sendable {
    struct SwitchPrompt: Equatable, Sendable {
        let current: String
        let requested: String
    }

    private(set) var chat: String?
    private(set) var callID: String?
    private(set) var switchPrompt: SwitchPrompt?

    var isRunning: Bool { chat != nil }

    mutating func requestStart(_ key: String) -> [LiveCallAction] {
        guard let chat else { return begin(key) }
        if chat == key { return [.restore] }
        guard switchPrompt == nil else { return [] }
        switchPrompt = SwitchPrompt(current: chat, requested: key)
        return []
    }

    mutating func resolveSwitch(switching: Bool) -> [LiveCallAction] {
        guard let prompt = switchPrompt else { return [] }
        switchPrompt = nil
        guard switching else { return [] }
        guard chat == prompt.current else { return chat == nil ? begin(prompt.requested) : [] }
        return end(.replaced) + begin(prompt.requested)
    }

    mutating func dismiss() -> [LiveCallAction] {
        isRunning ? [.minimize] : []
    }

    mutating func present() -> [LiveCallAction] {
        isRunning ? [.restore] : []
    }

    mutating func end(_ reason: LiveCallEnd) -> [LiveCallAction] {
        guard isRunning else { return [] }
        chat = nil
        callID = nil
        switchPrompt = nil
        return [.end(reason)]
    }

    mutating func activity(_ command: LiveActivityCommand, callID id: String) -> [LiveCallAction] {
        guard isRunning, id == callID else { return [] }
        switch command {
        case .returnToCall: return [.restore]
        case .end: return end(.liveActivity)
        }
    }

    private mutating func begin(_ key: String) -> [LiveCallAction] {
        chat = key
        callID = UUID().uuidString
        return [.begin(key)]
    }
}
