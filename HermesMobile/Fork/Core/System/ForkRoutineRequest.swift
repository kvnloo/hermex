import Foundation

enum ForkRoutineRequest {
    static let storageKey = "fork.routines.requestedAt"
    static let freshness: Double = 60

    static func isFresh(_ requestedAt: Double, now: Double) -> Bool {
        requestedAt > 0 && now >= requestedAt && now - requestedAt <= freshness
    }

    static func record(now: Double, in defaults: UserDefaults) {
        defaults.set(now, forKey: storageKey)
    }

    static func isPending(now: Double, in defaults: UserDefaults) -> Bool {
        isFresh(defaults.double(forKey: storageKey), now: now)
    }

    @discardableResult
    static func take(now: Double, from defaults: UserDefaults) -> Bool {
        let requestedAt = defaults.double(forKey: storageKey)
        guard requestedAt > 0 else { return false }
        defaults.removeObject(forKey: storageKey)
        return isFresh(requestedAt, now: now)
    }
}
