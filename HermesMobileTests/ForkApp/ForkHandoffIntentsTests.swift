import XCTest
@testable import HermesMobile

final class ForkHandoffIntentsTests: XCTestCase {
    private let hermes = URL(string: "https://hermes.example")!
    private let studio = URL(string: "https://studio.example:9119")!
    private let webui = URL(string: "https://webui.example")!

    private func account(_ server: URL, _ kind: ServerKind) -> ServerAccount {
        ServerAccount(id: server.absoluteString, urlString: server.absoluteString, displayName: "", initials: "",
                      headerLogoColorHex: HeaderLogoColor.defaultHex, createdAt: Date(timeIntervalSince1970: 0),
                      updatedAt: Date(timeIntervalSince1970: 0), kind: kind)
    }

    private var servers: [ServerAccount] { [account(hermes, .hermes), account(studio, .hermes), account(webui, .webui)] }

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { AppIntentRouter.shared.pendingDeepLink = nil }
    }

    override func tearDown() async throws {
        await MainActor.run { AppIntentRouter.shared.pendingDeepLink = nil }
        try await super.tearDown()
    }

    @MainActor
    func testAskBotStagesThePromptForTheBotsProfileWithoutSending() throws {
        let inbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: inbox) }
        let bot = ProfileEntity(hermesServer: studio, profile: "dev", title: "Dev")

        try AskBotIntent.ask("What failed overnight?", bot: bot, active: webui, servers: servers, inbox: inbox)

        XCTAssertEqual(AppIntentRouter.shared.pendingDeepLink, HermesShareDraft.openURL)
        let queued = try XCTUnwrap(try HermesShareDraft.reserveNextPendingImport(from: inbox))
        XCTAssertEqual(queued.sharedImport.draft, "What failed overnight?")
        XCTAssertEqual(queued.sharedImport.shortcut, SharedShortcutDestination(server: studio, profile: "dev"))
    }

    @MainActor
    func testAskBotRefusesWithoutAHermesDestination() {
        let inbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: inbox) }
        XCTAssertThrowsError(try AskBotIntent.ask("hi", bot: nil, active: webui, servers: servers, inbox: inbox)) {
            XCTAssertEqual($0 as? NewChatWithContentError, .noHermesServer)
        }
        XCTAssertThrowsError(try AskBotIntent.ask("  ", bot: nil, active: hermes, servers: servers, inbox: inbox)) {
            XCTAssertEqual($0 as? NewChatWithContentError, .empty)
        }
        XCTAssertNil(AppIntentRouter.shared.pendingDeepLink)
    }

    func testRunRoutineAsksTheActiveHermesServerToOpenTasks() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ForkHandoffIntentsTests"))
        defaults.removeObject(forKey: ForkRoutineRequest.storageKey)
        defer { defaults.removeObject(forKey: ForkRoutineRequest.storageKey) }

        XCTAssertThrowsError(try RunRoutineIntent.request(active: webui, servers: servers, defaults: defaults, now: 100)) {
            XCTAssertEqual($0 as? RunRoutineError, .noHermesServer)
        }
        XCTAssertThrowsError(try RunRoutineIntent.request(active: nil, servers: servers, defaults: defaults, now: 100))
        XCTAssertFalse(ForkRoutineRequest.isPending(now: 100, in: defaults))

        try RunRoutineIntent.request(active: hermes, servers: servers, defaults: defaults, now: 100)
        XCTAssertTrue(ForkRoutineRequest.take(now: 101, from: defaults))
    }
}
