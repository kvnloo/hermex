import Foundation

struct ForkMCPSummary: Equatable, Sendable {
    let name: String
    let transport: String
    var url: String?
    var command: String?
    var args: [String] = []
    var envKeys: [String] = []
    var auth: String?
    var enabled: Bool
    var source: String
    var plugin: String?
}

struct ForkMCPRuntime: Equatable, Sendable {
    let name: String
    let tools: Int
    let connected: Bool
    let disabled: Bool
    let status: String
    var needsAuth: Bool = false
}

enum ForkMCPHealth: Int, Comparable, Sendable {
    case failed, needsAuth, connecting, connected, idle, disabled

    static func < (lhs: ForkMCPHealth, rhs: ForkMCPHealth) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ForkMCPRow: Equatable, Identifiable, Sendable {
    let summary: ForkMCPSummary
    let runtime: ForkMCPRuntime?

    var id: String { summary.name }

    var health: ForkMCPHealth {
        if !summary.enabled || runtime?.disabled == true || runtime?.status == "disabled" { return .disabled }
        if runtime?.needsAuth == true { return .needsAuth }
        switch runtime?.status {
        case "failed": return .failed
        case "connecting": return .connecting
        case "connected": return .connected
        default: return runtime?.connected == true ? .connected : .idle
        }
    }

    var endpoint: String? {
        if let url = summary.url, !url.isEmpty { return url }
        guard let command = summary.command, !command.isEmpty else { return nil }
        return ([command] + summary.args).joined(separator: " ")
    }

    static func merge(_ summaries: [ForkMCPSummary], _ runtime: [ForkMCPRuntime]) -> [ForkMCPRow] {
        let byName = Dictionary(runtime.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return summaries.map { ForkMCPRow(summary: $0, runtime: byName[$0.name]) }
            .sorted { lhs, rhs in
                lhs.health != rhs.health
                    ? lhs.health < rhs.health
                    : lhs.summary.name.localizedCaseInsensitiveCompare(rhs.summary.name) == .orderedAscending
            }
    }
}

struct ForkMCPProbe: Equatable, Sendable {
    let ok: Bool
    let tools: [String]
    var error: String?
    var prompts: Int?
    var resources: Int?
    var oauthNeeded = false
}
