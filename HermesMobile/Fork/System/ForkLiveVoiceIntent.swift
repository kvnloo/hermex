import AppIntents
import Foundation

struct ForkStartLiveVoiceIntent: AppIntent {
    static var title = LocalizedStringResource("Start Live Voice", table: "Fork")
    static var description = IntentDescription(LocalizedStringResource("Open Hermex on a new chat in Live Mode.", table: "Fork"))
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        ForkLiveVoiceRequest.record(now: Date().timeIntervalSince1970, local: .standard,
                                    shared: ForkLiveVoiceRequest.sharedDefaults())
        return .result(opensIntent: OpenURLIntent(ForkSystemLinks.newChat))
    }
}

enum ForkSystemLinks {
    static var newChat: URL {
        HermesDeepLink.newChatURL ?? URL(string: "\(HermesDeepLink.scheme)://\(HermesDeepLink.newChatHost)")!
    }

    static var newVoiceChat: URL { HermesDeepLink.newChatVoiceURL ?? newChat }
}
