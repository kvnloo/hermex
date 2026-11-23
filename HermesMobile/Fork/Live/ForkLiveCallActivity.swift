import ActivityKit
import AppIntents
import Foundation

struct ForkLiveCallAttributes: ActivityAttributes {
    enum Status: String, Codable, Hashable {
        case listening
        case thinking
        case speaking
        case paused
        case failed
    }

    struct ContentState: Codable, Hashable {
        var status: Status
        var isMuted: Bool
        var needsAnswer: Bool
        var hasUnseenCard: Bool
    }

    let callID: String
    let title: String
}

enum ForkLiveCallCommand: String {
    case returnToCall
    case end
}

@MainActor
enum ForkLiveCallCommands {
    static var handler: (@MainActor (ForkLiveCallCommand, String) -> Void)?
}

struct ForkReturnToLiveCallIntent: LiveActivityIntent {
    static var title = LocalizedStringResource("Return to Live Call", table: "Fork")
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @Parameter(title: LocalizedStringResource("Call", table: "Fork"))
    var callID: String

    init() {}

    init(callID: String) {
        self.callID = callID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ForkLiveCallCommands.handler?(.returnToCall, callID)
        return .result()
    }
}

struct ForkEndLiveCallIntent: LiveActivityIntent {
    static var title = LocalizedStringResource("End Live Call", table: "Fork")
    static var isDiscoverable: Bool = false

    @Parameter(title: LocalizedStringResource("Call", table: "Fork"))
    var callID: String

    init() {}

    init(callID: String) {
        self.callID = callID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ForkLiveCallCommands.handler?(.end, callID)
        return .result()
    }
}
