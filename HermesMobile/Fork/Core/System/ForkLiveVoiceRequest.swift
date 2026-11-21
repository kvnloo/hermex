import Foundation

enum ForkLiveVoiceRequest {
    static let storageKey = "fork.liveMode.requestedAt"
    static let freshness: Double = 30
    static let appGroupInfoKey = "HermesAppGroupIdentifier"

    static func isFresh(_ requestedAt: Double, now: Double) -> Bool {
        requestedAt > 0 && now >= requestedAt && now - requestedAt <= freshness
    }

    static func record(now: Double, local: UserDefaults, shared: UserDefaults?) {
        local.set(now, forKey: storageKey)
        shared?.set(now, forKey: storageKey)
    }

    @discardableResult
    static func bridge(now: Double, local: UserDefaults, shared: UserDefaults?) -> Bool {
        guard let shared else { return false }
        let requestedAt = shared.double(forKey: storageKey)
        guard requestedAt > 0 else { return false }
        shared.removeObject(forKey: storageKey)
        guard isFresh(requestedAt, now: now), local.double(forKey: storageKey) < requestedAt else { return false }
        local.set(requestedAt, forKey: storageKey)
        return true
    }

    static func sharedDefaults(bundle: Bundle = .main) -> UserDefaults? {
        (bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String).flatMap(UserDefaults.init(suiteName:))
    }
}
