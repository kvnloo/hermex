import SwiftUI

struct ForkMCPSettingsRow: View {
    let connection: BotConnection
    let server: URL

    var body: some View {
        NavigationLink {
            ForkMCPServersView(connection: connection, server: server)
        } label: {
            SettingsLabel(title: String(localized: "MCP Servers", table: "Fork"), systemImage: "server.rack")
        }
    }
}

struct ForkMCPServersView: View {
    private let client: ForkMCPClient
    @State private var profiles: [String] = []
    @State private var profile: String?
    @State private var rows: [ForkMCPRow]?
    @State private var failure: String?

    init(connection: BotConnection, server: URL) {
        client = ForkMCPClient(saved: connection, server: server)
    }

    var body: some View {
        AppList {
            if let profile {
                ServerProfileRow(profiles: profiles, selection: profile) { name in
                    self.profile = name
                    Task { await load() }
                }
            }
            if let failure {
                Section { Text(verbatim: failure).foregroundStyle(.appSecondary) }
            } else if let rows {
                if rows.isEmpty {
                    Section { Text("No MCP servers are configured for this Profile.", tableName: "Fork").foregroundStyle(.appSecondary) }
                } else {
                    Section {
                        ForEach(rows) { row in
                            NavigationLink {
                                ForkMCPServerDetail(row: row, client: client, profile: profile ?? "")
                            } label: {
                                ForkMCPServerRowView(row: row)
                            }
                        }
                    } footer: {
                        Text("Configured in the Profile's config.yaml or by plugins. Hermex shows them read-only.", tableName: "Fork")
                    }
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .settingsPage(String(localized: "MCP Servers", table: "Fork"))
        .refreshable { await load() }
        .task { await start() }
    }

    private func start() async {
        guard profile == nil else { return }
        do {
            let listed = try await client.profiles()
            profiles = listed.names
            profile = listed.initial
            await load()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func load() async {
        guard let profile else { return }
        do {
            rows = try await client.servers(profile: profile)
            failure = nil
        } catch BotFailure.rejected(-32601) {
            failure = String(localized: "This Hermes host doesn't list MCP servers yet. Update Hermes to see them here.", table: "Fork")
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct ForkMCPServerRowView: View {
    let row: ForkMCPRow

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(row.health.color).frame(width: 9, height: 9).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.summary.name).font(AppFont.body())
                HStack(spacing: 6) {
                    row.health.label
                    Text(verbatim: "·")
                    Text(verbatim: row.summary.transport)
                    if let tools = row.runtime?.tools, tools > 0 {
                        Text(verbatim: "·")
                        Text("\(tools) tools", tableName: "Fork")
                    }
                }
                .font(AppFont.caption())
                .foregroundStyle(.appSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ForkMCPServerDetail: View {
    let row: ForkMCPRow
    let client: ForkMCPClient
    let profile: String
    @State private var probe: ForkMCPProbe?
    @State private var isTesting = false
    @State private var failure: String?

    var body: some View {
        AppList {
            Section {
                LabeledContent { row.health.label } label: { Text("Status", tableName: "Fork") }
                LabeledContent { Text(verbatim: row.summary.transport) } label: { Text("Transport", tableName: "Fork") }
                if let endpoint = row.endpoint {
                    LabeledContent { Text(verbatim: endpoint).textSelection(.enabled).lineLimit(3) } label: { Text("Endpoint", tableName: "Fork") }
                }
                LabeledContent { Text(verbatim: row.summary.plugin ?? row.summary.source) } label: { Text("Source", tableName: "Fork") }
                if !row.summary.envKeys.isEmpty {
                    LabeledContent { Text(verbatim: row.summary.envKeys.joined(separator: ", ")) } label: { Text("Secrets", tableName: "Fork") }
                }
            }
            Section {
                Button { Task { await test() } } label: {
                    HStack {
                        Text("Test Connection", tableName: "Fork")
                        if isTesting { Spacer(); ProgressView() }
                    }
                }
                .disabled(isTesting || !row.summary.enabled)
                if let probe { probeRows(probe) }
                if let failure { Text(verbatim: failure).foregroundStyle(.red) }
            } footer: {
                Text("Connects to the server on the host, lists its tools, and disconnects.", tableName: "Fork")
            }
        }
        .settingsPage(row.summary.name)
    }

    @ViewBuilder
    private func probeRows(_ probe: ForkMCPProbe) -> some View {
        if probe.ok {
            Label { Text("Connected · \(probe.tools.count) tools", tableName: "Fork") } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if !probe.tools.isEmpty {
                Text(verbatim: probe.tools.joined(separator: ", ")).font(AppFont.footnote()).foregroundStyle(.appSecondary)
            }
        } else {
            Label {
                if probe.oauthNeeded { Text("Sign-in needed on the host", tableName: "Fork") }
                else { Text(verbatim: probe.error ?? String(localized: "Didn't connect", table: "Fork")) }
            } icon: {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        do {
            probe = try await client.test(row.summary.name, profile: profile)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

private extension ForkMCPHealth {
    var color: Color {
        switch self {
        case .failed: .red
        case .needsAuth: .orange
        case .connecting: .yellow
        case .connected: .green
        case .idle: Color(.appFill)
        case .disabled: Color(.appFillTertiary)
        }
    }

    var label: Text {
        switch self {
        case .failed: Text("Failed", tableName: "Fork")
        case .needsAuth: Text("Needs sign-in", tableName: "Fork")
        case .connecting: Text("Connecting", tableName: "Fork")
        case .connected: Text("Connected", tableName: "Fork")
        case .idle: Text("Starts when used", tableName: "Fork")
        case .disabled: Text("Off", tableName: "Fork")
        }
    }
}
