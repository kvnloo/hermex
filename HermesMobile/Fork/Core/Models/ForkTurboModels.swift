import Foundation

enum ForkTurboModels {
    static let provider = "vllm-sr"
    static let order = ["turbo", "free-quality", "free-reasoning", "free-verify", "free-longctx", "free-public"]
    static let virtualModelIDs = order.map { "\(provider)/\($0)" }

    static func isTurboRoute(provider: String, model: String = "") -> Bool {
        provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == self.provider
            || model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(self.provider + "/")
    }

    static func alias(_ model: String) -> String {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix(provider + "/") ? String(normalized.dropFirst(provider.count + 1)) : normalized
    }

    static func sorted(_ models: [String]) -> [String] {
        models.sorted { left, right in
            let leftRank = order.firstIndex(of: alias(left)) ?? order.count
            let rightRank = order.firstIndex(of: alias(right)) ?? order.count
            return leftRank != rightRank ? leftRank < rightRank : left < right
        }
    }

    static func models(advertised: [String]) -> [String] {
        sorted(advertised.isEmpty ? virtualModelIDs : advertised)
    }

    static func arrangedProviders(_ providers: [String]) -> [String] {
        providers.filter { isTurboRoute(provider: $0) } + providers.filter { !isTurboRoute(provider: $0) }
    }
}
