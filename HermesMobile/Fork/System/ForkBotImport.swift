import SwiftUI

extension View {
    func forkBotImport(_ authManager: AuthManager) -> some View {
        modifier(ForkBotImportHost(authManager: authManager))
    }
}

private struct ForkBotImportOffer: Identifiable {
    let id = UUID()
    let document: ForkBotDirectoryDocument?
}

private struct ForkBotImportHost: ViewModifier {
    let authManager: AuthManager
    @State private var offer: ForkBotImportOffer?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                guard url.isFileURL else { return }
                offer = ForkBotImportOffer(document: ForkBotImportFile.read(url))
            }
            .sheet(item: $offer) { offer in
                ForkBotImportSheet(document: offer.document, target: ForkBotImportTarget(authManager))
            }
    }
}

enum ForkBotImportFile {
    static func read(_ url: URL) -> ForkBotDirectoryDocument? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            removeInboxCopy(url)
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return try? ForkBotDirectoryDocument(data: data)
    }

    private static func removeInboxCopy(_ url: URL) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              url.deletingLastPathComponent().standardizedFileURL
                == documents.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

struct ForkBotImportTarget {
    let server: URL
    let connection: BotConnection

    @MainActor init?(_ authManager: AuthManager) {
        guard case .loggedIn(let server) = authManager.state, authManager.kind(of: server) == .hermes,
              let saved = try? BotConnectionStore().load(server: server) else { return nil }
        self.server = server
        connection = saved
    }

    func chatURL(profile: String) -> URL? {
        HermesDeepLink.botURL(for: BotDestination(server: server, connectionID: connection.id, profile: profile))
    }
}

@MainActor @Observable final class ForkBotImportRoster {
    enum State: Equatable { case loading, loaded(Set<String>), failed }

    private(set) var state = State.loading

    func load(_ target: ForkBotImportTarget) async {
        state = .loading
        let client = BotClient(saved: target.connection, server: target.server)
        defer { client.close() }
        do {
            try await client.connect()
            let reply = try await client.call(.profilesList(includeSessions: false))
            guard let rows = reply["profiles"].list else { throw BotFailure.unsupported }
            state = .loaded(Set(rows.compactMap { $0["name"].text }))
        } catch {
            state = .failed
        }
    }
}

private struct ForkBotImportSheet: View {
    let document: ForkBotDirectoryDocument?
    let target: ForkBotImportTarget?
    @State private var roster = ForkBotImportRoster()
    @State private var creator: BotCreator?
    @State private var createdProfile: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                if let document {
                    Section { preview(document) }
                    Section { action(document) }
                } else {
                    Text("This file isn’t a bot Hermex can import.", tableName: "Fork")
                        .foregroundStyle(.appSecondary)
                }
            }
            .navigationTitle(Text("Import Bot", tableName: "Fork"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label { Text("Close", tableName: "Fork") } icon: { Image(systemName: "xmark") } }
                }
            }
        }
        .task {
            guard document != nil, let target else { return }
            await roster.load(target)
        }
        .sheet(item: Binding(get: { creator.map(ForkBotImportCreation.init) }, set: { if $0 == nil { creator = nil } }),
               onDismiss: openCreatedChat) { creation in
            BotCreateView(creator: creation.creator)
        }
    }

    private func preview(_ document: ForkBotDirectoryDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: document.title ?? document.name).font(AppFont.title3())
            if document.title != nil {
                Text(verbatim: document.name).font(AppFont.caption()).foregroundStyle(.appSecondary)
            }
            if let description = document.description {
                Text(verbatim: description).font(AppFont.body()).padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func action(_ document: ForkBotDirectoryDocument) -> some View {
        if let target {
            switch roster.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .failed:
                Button { Task { await roster.load(target) } } label: { Text("Try Again", tableName: "Fork") }
            case .loaded(let names) where names.contains(document.name):
                Button { open(document.name, on: target) } label: { Text("Open Chat", tableName: "Fork") }
            case .loaded:
                Button { create(document, on: target) } label: { Text("Add Bot", tableName: "Fork") }
                    .disabled(!BotProfileName.isValid(document.name))
            }
            Text("Adds to \(target.connection.name)", tableName: "Fork")
                .font(AppFont.caption()).foregroundStyle(.appSecondary)
        } else {
            Text("Sign in to a Hermes server to add this bot.", tableName: "Fork")
                .foregroundStyle(.appSecondary)
        }
    }

    private func create(_ document: ForkBotDirectoryDocument, on target: ForkBotImportTarget) {
        let creator = BotCreator(server: target.server, connection: target.connection, roster: [], name: document.name,
                                 onCreated: { createdProfile = $0 })
        creator.setTitle(document.title ?? document.name)
        creator.setRole(document.description ?? "")
        self.creator = creator
    }

    private func openCreatedChat() {
        guard let profile = createdProfile, let target else { return }
        open(profile, on: target)
    }

    private func open(_ profile: String, on target: ForkBotImportTarget) {
        guard let url = target.chatURL(profile: profile) else { return }
        dismiss()
        openURL(url)
    }
}

private struct ForkBotImportCreation: Identifiable {
    let creator: BotCreator
    var id: ObjectIdentifier { ObjectIdentifier(creator) }
}
