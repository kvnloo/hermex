import XCTest
@testable import HermesMobile

@MainActor
final class ForkShareReviewDraftTests: XCTestCase {
    private let hermes = URL(string: "https://studio.example:9119")!

    func testAReviewedShareLandsAsTheActionPromptInTheProjectFoldersNewSessionDraft() async throws {
        let connection = BotConnection(id: UUID(uuidString: "00000000-0000-0000-0000-000000000076")!, name: "Host",
                                       address: hermes, username: "me", password: "secret")
        let entry = HermesSessionListEntry(server: hermes, connection: connection, profile: nil)
        let share = SharedImportReservation(itemID: "item", reservationID: "res", createdAt: Date(timeIntervalSince1970: 0),
                                            sharedImport: SharedImport(draft: "  https://example.com/post  ", attachments: []))
        guard case .chat(let chat)? = share.hermesOpening(on: entry, listed: "default", isLive: true) else {
            return XCTFail("A share opens a new session")
        }
        let project = try XCTUnwrap(ForkShareProject(id: "p1", name: "Launch", folder: "/srv/launch"))
        let choice = ForkShareChoice(action: .summarize, project: project)
        let store = ChatDraftStore(persistence: BotMemoryDrafts(), attachmentStore: BotAttachmentCopies(),
                                   debounceDuration: .seconds(3600))

        let reviewed = share.applying(choice)
        try await reviewed.moveIntoDraft(of: chat.applying(choice), drafts: store)

        XCTAssertEqual(reviewed.occurrenceID, share.occurrenceID)
        let key = ChatDraftKey.hermesSession(server: hermes, connectionID: connection.id, profile: "default", key: nil,
                                             cwd: "/srv/launch")
        let draft = await store.draft(for: key)
        XCTAssertEqual(draft?.text, ForkShareAction.localizedPrompt(.summarize, "https://example.com/post") + "\n")
        let plain = await store.draft(for: .hermesSession(server: hermes, connectionID: connection.id, profile: "default", key: nil))
        XCTAssertNil(plain)
    }
}
