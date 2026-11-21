import Foundation

extension ForkRPC {
    static func mcpServersList(profile: String) -> ForkRPC {
        ForkRPC(method: "mcp.servers.list", params: ["profile": .string(profile)], isAdmissible: !profile.isEmpty)
    }

    static func mcpServersStatus(profile: String) -> ForkRPC {
        ForkRPC(method: "mcp.servers.status", params: ["profile": .string(profile)], isAdmissible: !profile.isEmpty)
    }

    static func mcpServersTest(profile: String, name: String) -> ForkRPC {
        ForkRPC(method: "mcp.servers.test", params: ["profile": .string(profile), "name": .string(name)],
                isAdmissible: !profile.isEmpty && !name.isEmpty)
    }
}

@MainActor
final class ForkMCPClient {
    private let http: HermesConnection

    init(saved connection: BotConnection, server: URL) {
        http = HermesConnections.shared.connection(for: connection, server: server)
    }

    func profiles() async throws -> (names: [String], initial: String) {
        try await HermesEnvironmentClient(http: http).profiles()
    }

    func servers(profile: String) async throws -> [ForkMCPRow] {
        let client = BotClient(http: http)
        defer { client.close() }
        try await client.connect()
        let list = try await client.call(.fork(.mcpServersList(profile: profile)))
        let status = try? await client.call(.fork(.mcpServersStatus(profile: profile)))
        return ForkMCPRow.merge((list["servers"].list ?? []).compactMap(Self.summary),
                                (status?["servers"].list ?? []).compactMap(Self.runtime))
    }

    func test(_ name: String, profile: String) async throws -> ForkMCPProbe {
        let client = BotClient(http: http)
        defer { client.close() }
        try await client.connect()
        let reply = try await client.call(.fork(.mcpServersTest(profile: profile, name: name)))
        return ForkMCPProbe(
            ok: reply["ok"].flag ?? false,
            tools: (reply["tools"].list ?? []).compactMap { $0["name"].text ?? $0.text },
            error: reply["error"].text, prompts: reply["prompts"].integer, resources: reply["resources"].integer,
            oauthNeeded: reply["oauth_needed"].flag ?? false
        )
    }

    private static func summary(_ json: BotJSON) -> ForkMCPSummary? {
        guard let name = json["name"].text, !name.isEmpty else { return nil }
        return ForkMCPSummary(
            name: name, transport: json["transport"].text ?? "", url: json["url"].text, command: json["command"].text,
            args: (json["args"].list ?? []).compactMap(\.text), envKeys: (json["env"].list ?? []).compactMap(\.text),
            auth: json["auth"].text, enabled: json["enabled"].flag ?? true, source: json["source"].text ?? "config",
            plugin: json["plugin"].text
        )
    }

    private static func runtime(_ json: BotJSON) -> ForkMCPRuntime? {
        guard let name = json["name"].text, !name.isEmpty else { return nil }
        return ForkMCPRuntime(name: name, tools: json["tools"].integer ?? 0, connected: json["connected"].flag ?? false,
                              disabled: json["disabled"].flag ?? false, status: json["status"].text ?? "",
                              needsAuth: json["needs_auth"].flag ?? false)
    }
}
