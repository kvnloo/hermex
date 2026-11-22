import AppIntents
import Foundation

struct AskBotIntent: AppIntent {
    static var title = LocalizedStringResource("Ask a Bot", table: "Fork")
    static var description = IntentDescription(LocalizedStringResource(
        "Open Hermex on a new chat with this prompt in the composer. Nothing is sent until you send it.", table: "Fork"))
    static var openAppWhenRun: Bool = true

    @Parameter(title: LocalizedStringResource("Prompt", table: "Fork"), inputOptions: String.IntentInputOptions(multiline: true))
    var prompt: String

    @Parameter(title: LocalizedStringResource("Bot", table: "Fork"))
    var bot: ProfileEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        UsageReports.shared.record(.appIntents)
        try Self.ask(prompt, bot: bot, active: ProfileEntityProvider.savedServerURL(), servers: ServerRegistry.shared.servers)
        return .result()
    }

    @MainActor
    static func ask(_ prompt: String, bot: ProfileEntity?, active: URL?, servers: [ServerAccount],
                    router: AppIntentRouter = .shared, inbox: URL? = HermesShareDraft.containerURL()) throws {
        let destination = try NewChatWithContentIntent.destination(profile: bot, active: active, servers: servers)
        try router.openNewChat(prefilling: prompt, server: destination.server, profile: destination.profile, inbox: inbox)
    }
}

struct RunRoutineIntent: AppIntent {
    static var title = LocalizedStringResource("Run a Task", table: "Fork")
    static var description = IntentDescription(LocalizedStringResource(
        "Open Hermex on Tasks so you can choose one and tap Run Now. Nothing runs until you do.", table: "Fork"))
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UsageReports.shared.record(.appIntents)
        try Self.request(active: ProfileEntityProvider.savedServerURL(), servers: ServerRegistry.shared.servers)
        return .result()
    }

    static func request(active: URL?, servers: [ServerAccount], defaults: UserDefaults = .standard,
                        now: Double = Date().timeIntervalSince1970) throws {
        guard let active, servers.first(where: { $0.id == active.absoluteString })?.kind == .hermes else {
            throw RunRoutineError.noHermesServer
        }
        ForkRoutineRequest.record(now: now, in: defaults)
    }
}

enum RunRoutineError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case noHermesServer

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noHermesServer: LocalizedStringResource("Make a Hermes server active in Hermex to open its Tasks.", table: "Fork")
        }
    }
}
