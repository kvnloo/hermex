import Foundation

enum LiveModeRequest {
    static let storageKey = "fork.liveMode.requestedAt"
    static let freshness: Double = 30

    static func isFresh(_ requestedAt: Double, now: Double) -> Bool {
        requestedAt > 0 && now >= requestedAt && now - requestedAt <= freshness
    }
}
