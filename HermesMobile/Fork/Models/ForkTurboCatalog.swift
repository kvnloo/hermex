import Foundation

enum ForkTurboCatalog {
    static func arrange(payload: BotJSON, _ groups: [ModelCatalogGroup]) -> [ModelCatalogGroup] {
        var groups = groups
        let advertised = (payload["providers"].list ?? []).first {
            $0["slug"].text.map { ForkTurboModels.isTurboRoute(provider: $0) } == true && $0["authenticated"].flag != false
        }
        if let advertised, let slug = advertised["slug"].text, !groups.contains(where: { $0.providerID == slug }),
           (advertised["models"].list ?? []).isEmpty {
            groups.append(ModelCatalogGroup(id: slug, name: slug, providerID: slug, models: []))
        }
        return ForkTurboModels.arrangedProviders(groups.map(\.id)).compactMap { id in
            guard let group = groups.first(where: { $0.id == id }) else { return nil }
            guard ForkTurboModels.isTurboRoute(provider: group.providerID ?? id) else { return group }
            let ids = ForkTurboModels.models(advertised: group.models.map(\.id))
            let models = ids.map { ModelCatalogOption(id: $0, displayName: displayName(for: $0), providerID: group.providerID ?? id) }
            return ModelCatalogGroup(id: group.id, name: String(localized: "Turbo", table: "Fork"), providerID: group.providerID,
                                     models: models, extraModels: group.extraModels)
        }
    }

    static func displayName(for model: String) -> String {
        switch ForkTurboModels.alias(model) {
        case "turbo": String(localized: "Turbo · parallel fast free models", table: "Fork")
        case "free-quality": String(localized: "Free · quality-focused", table: "Fork")
        case "free-reasoning": String(localized: "Free · reasoning", table: "Fork")
        case "free-verify": String(localized: "Free · checking answers", table: "Fork")
        case "free-longctx": String(localized: "Free · long context", table: "Fork")
        case "free-public": String(localized: "Free · public pool", table: "Fork")
        default: model
        }
    }
}
