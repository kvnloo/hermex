import Observation
import SwiftUI

struct ForkBotSessionRoutes {
    let open: (_ profile: String, _ key: String) -> Void
    let newSession: (_ profile: String) -> Void
    let showAll: (_ profile: String) -> Void
}

extension BotLiveStatus {
    static func sessionStatuses(_ items: [BotJSON]) -> [String: BotLiveStatus] {
        var result: [String: BotLiveStatus] = [:]
        for item in items {
            guard let status = BotLiveStatus(wire: item["status"].text), let key = item["session_key"].text,
                  !key.isEmpty else { continue }
            result[key] = max(result[key] ?? status, status)
        }
        return result
    }
}

extension ForkBotSessionRow {
    init(_ row: HermesSessionRow) {
        self.init(id: row.id, identity: row.identity, title: MessageAttachment.hermesTitle(row.title),
                  preview: MessageAttachment.hermesTitle(row.preview),
                  activity: (row.lastActive ?? row.startedAt).map(Date.init(timeIntervalSince1970:)),
                  unread: row.unread == true, hidden: row.hidden == true || row.isRoomSession,
                  archived: row.archived == true)
    }
}

extension ForkBotSessionBranch {
    init(_ page: HermesSessionPage) {
        self.init(rows: page.rows.map(ForkBotSessionRow.init), pageIsFull: page.count >= HermesREST.sessionPageSize)
    }
}

@MainActor @Observable final class ForkBotSessionTreeStore {
    private(set) var state = ForkBotSessionTreeState()
    private var connectionID: UUID?

    func phase(_ profile: String, connectionID: UUID) -> ForkBotSessionTreeState.Phase? {
        self.connectionID == connectionID ? state.phase(profile) : nil
    }

    func load(_ profile: String, connectionID: UUID, roster: [BotProfile],
              using read: (String) async throws -> HermesSessionPage) async {
        if self.connectionID != connectionID {
            state = ForkBotSessionTreeState()
            self.connectionID = connectionID
        }
        state.retain(Set(roster.map(\.id)).union([profile]))
        let serial = state.begin(profile)
        let page = try? await read(profile)
        guard self.connectionID == connectionID else { return }
        state.finish(profile, serial: serial, branch: page.map(ForkBotSessionBranch.init))
    }
}

struct ForkBotSessionDisclosureSlot: ViewModifier {
    let server: URL
    let connectionID: UUID?
    let profile: BotProfile
    let isOffered: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if isOffered, let connectionID {
            HStack(spacing: 0) {
                content
                ForkBotSessionDisclosure(key: ForkBotSessionExpansion.key(server: server, connectionID: connectionID,
                                                                         profile: profile.id))
            }
        } else {
            content
        }
    }
}

private struct ForkBotSessionDisclosure: View {
    @AppStorage private var isExpanded: Bool

    init(key: String) {
        _isExpanded = AppStorage(wrappedValue: false, key)
    }

    var body: some View {
        Button { isExpanded.toggle() } label: {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.appSecondary)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? Text("Hide sessions", tableName: "Fork") : Text("Show sessions", tableName: "Fork"))
    }
}

struct ForkBotSessionBranchRows: View {
    @AppStorage private var isExpanded: Bool
    @State private var retry = 0
    let profile: BotProfile
    let connectionID: UUID
    let inbox: BotInbox
    let store: ForkBotSessionTreeStore
    let routes: ForkBotSessionRoutes

    init(profile: BotProfile, connectionID: UUID, inbox: BotInbox, store: ForkBotSessionTreeStore,
         routes: ForkBotSessionRoutes) {
        self.profile = profile
        self.connectionID = connectionID
        self.inbox = inbox
        self.store = store
        self.routes = routes
        _isExpanded = AppStorage(wrappedValue: false, ForkBotSessionExpansion.key(server: inbox.server, connectionID: connectionID,
                                                                                 profile: profile.id))
    }

    var body: some View {
        if isExpanded {
            switch store.phase(profile.id, connectionID: connectionID) {
            case .loaded(let branch)?:
                ForEach(branch.preview) { session in sessionRow(session) }
                if branch.offersShowAll { showAllRow(branch) }
                if branch.isEmpty { note(Text("No sessions yet.", tableName: "Fork")) }
            case .failed?:
                Button { retry += 1 } label: {
                    Text("Couldn't load sessions. Tap to try again.", tableName: "Fork")
                        .font(AppFont.footnote()).foregroundStyle(.appSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).modifier(BranchRowLayout())
            case .loading?, nil:
                if inbox.link != .disconnected { note(Text("Loading sessions…", tableName: "Fork")) }
            }
            newSessionRow
                .task(id: [inbox.rosterRevision, retry, inbox.link == .live ? 1 : 0]) {
                    guard inbox.link == .live else { return }
                    await store.load(profile.id, connectionID: connectionID, roster: inbox.profiles,
                                     using: inbox.firstSessionPage)
                }
        }
    }

    private func sessionRow(_ session: ForkBotSessionRow) -> some View {
        Button { routes.open(profile.id, session.id) } label: {
            HStack(spacing: 8) {
                Group {
                    if let title = session.displayTitle { Text(verbatim: title) } else { Text("Untitled session", tableName: "Fork") }
                }
                .font(AppFont.subheadline()).lineLimit(1)
                Spacer(minLength: 8)
                if let status = inbox.sessionStatuses[session.id] ?? inbox.sessionStatuses[session.identity] {
                    statusLabel(status)
                } else if let activity = session.activity {
                    Text(verbatim: activity.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        .font(AppFont.footnote()).foregroundStyle(.appSecondary).lineLimit(1)
                }
                if session.unread {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8).accessibilityLabel(Text("Unread"))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .modifier(BranchRowLayout())
    }

    private func statusLabel(_ status: BotLiveStatus) -> some View {
        let (word, tint) = switch status {
        case .working: (String(localized: "Working"), Color("AttentionWorking"))
        case .waiting: (String(localized: "Waiting for you"), Color("AttentionApproval"))
        }
        return Text(verbatim: word).font(AppFont.footnote(weight: .semibold)).lineLimit(1)
            .foregroundStyle(inbox.liveStatusesAreStale ? AnyShapeStyle(.appSecondary) : AnyShapeStyle(tint))
    }

    private func showAllRow(_ branch: ForkBotSessionBranch) -> some View {
        let count = branch.rows.count
        return Button { routes.showAll(profile.id) } label: {
            Group {
                if branch.isPartial { Text("Show all (\(count)+)", tableName: "Fork") } else { Text("Show all (\(count))", tableName: "Fork") }
            }
            .font(AppFont.footnote(weight: .semibold)).foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(BranchRowLayout())
    }

    private var newSessionRow: some View {
        Button { routes.newSession(profile.id) } label: {
            Label { Text("New session", tableName: "Fork") } icon: { Image(systemName: "plus") }
                .font(AppFont.footnote(weight: .semibold)).foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(inbox.link != .live)
        .modifier(BranchRowLayout())
    }

    private func note(_ text: Text) -> some View {
        text.font(AppFont.footnote()).foregroundStyle(.appSecondary).modifier(BranchRowLayout())
    }
}

private struct BranchRowLayout: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.leading, 58)
            .padding(.vertical, 2)
            .listRowSeparator(.hidden)
    }
}
