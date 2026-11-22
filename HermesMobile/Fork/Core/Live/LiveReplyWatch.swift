import Foundation

struct LiveReplyWatch: Equatable, Sendable {
    struct Observation: Equatable, Sendable {
        var hasStream: Bool
        var isConnected: Bool
    }

    enum Action: Equatable, Sendable {
        case wait
        case reconnect
        case refresh
        case fail
    }

    static let retryDelays: [Double] = [1, 2, 4, 8, 15, 30]
    static let disconnectedLimit: Double = 300
    static let refreshAfterStreamEnds: Double = 3
    static let endedWithoutReplyLimit: Double = 20
    static let neverStartedLimit: Double = 300

    private(set) var isReconnecting = false
    private(set) var attempts = 0
    private let sentAt: Double
    private var sawStream = false
    private var disconnectedSince: Double?
    private var nextAttemptAt: Double = 0
    private var streamEndedAt: Double?
    private var refreshed = false

    init(sentAt: Double) {
        self.sentAt = sentAt
    }

    mutating func observe(_ observation: Observation, at time: Double) -> Action {
        if observation.hasStream {
            sawStream = true
            streamEndedAt = nil
            refreshed = false
            guard !observation.isConnected else {
                isReconnecting = false
                attempts = 0
                disconnectedSince = nil
                nextAttemptAt = 0
                return .wait
            }
            isReconnecting = true
            let since = disconnectedSince ?? time
            disconnectedSince = since
            if time - since >= Self.disconnectedLimit { return .fail }
            guard time >= nextAttemptAt else { return .wait }
            nextAttemptAt = time + Self.retryDelays[min(attempts, Self.retryDelays.count - 1)]
            attempts += 1
            return .reconnect
        }
        isReconnecting = false
        guard sawStream else {
            return time - sentAt >= Self.neverStartedLimit ? .fail : .wait
        }
        let ended = streamEndedAt ?? time
        streamEndedAt = ended
        if !refreshed, time - ended >= Self.refreshAfterStreamEnds {
            refreshed = true
            return .refresh
        }
        return time - ended >= Self.endedWithoutReplyLimit ? .fail : .wait
    }
}
