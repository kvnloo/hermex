import Foundation

@MainActor
final class ForkProviderSignInFlow {
    enum Phase: Equatable {
        case idle
        case starting(provider: String)
        case waiting(provider: String, session: ForkOAuthDeviceSession, expiresAt: Date)
        case approved(provider: String)
        case failed(provider: String, ForkOAuthFailure)
        case cancelled(provider: String, confirmed: Bool)

        var provider: String? {
            switch self {
            case .idle: nil
            case .starting(let provider), .waiting(let provider, _, _), .approved(let provider),
                 .failed(let provider, _), .cancelled(let provider, _): provider
            }
        }

        var isActive: Bool {
            switch self {
            case .starting, .waiting: true
            default: false
            }
        }
    }

    typealias Reply = (body: Data, status: Int)
    typealias Transport = @MainActor (ForkOAuthRoute) async throws -> Reply

    private(set) var profile: String
    private(set) var providers: [ForkOAuthProvider] = [] { didSet { didChange?() } }
    private(set) var catalogFailure: ForkOAuthFailure? { didSet { didChange?() } }
    private(set) var phase: Phase = .idle { didSet { didChange?() } }
    var didChange: (@MainActor () -> Void)?

    private let send: Transport
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private let now: @MainActor () -> Date
    private var generation = 0

    init(profile: String, send: @escaping Transport,
         sleep: @escaping @MainActor (TimeInterval) async throws -> Void,
         now: @escaping @MainActor () -> Date = { Date() }) {
        self.profile = profile
        self.send = send
        self.sleep = sleep
        self.now = now
    }

    func load(profile newProfile: String) async {
        if newProfile != profile {
            await stop()
            profile = newProfile
            providers = []
            catalogFailure = nil
        }
        let attempt = generation
        let profile = self.profile
        do {
            let reply = try await send(.catalog(profile: profile))
            guard attempt == generation, profile == self.profile else { return }
            guard reply.status == 200 else { catalogFailure = .unreadable; return }
            providers = try ForkOAuthProvider.catalog(reply.body)
            catalogFailure = nil
        } catch {
            guard attempt == generation, profile == self.profile else { return }
            catalogFailure = error as? ForkOAuthFailure ?? .unreachable
        }
    }

    func begin(_ provider: ForkOAuthProvider) async {
        guard provider.signsInFromApp, !phase.isActive else { return }
        generation += 1
        let attempt = generation
        let profile = self.profile
        phase = .starting(provider: provider.id)
        let reply: Reply
        do {
            reply = try await send(.start(provider: provider.id, profile: profile))
        } catch {
            guard attempt == generation else { return }
            phase = .failed(provider: provider.id, error as? ForkOAuthFailure ?? .unreachable)
            return
        }
        let startedID = reply.status == 200 ? ForkOAuthDeviceSession.sessionID(in: reply.body) : nil
        guard attempt == generation else {
            if let startedID { _ = await cancelHost(startedID, profile: profile) }
            return
        }
        if case .cancelled = phase {
            var confirmed = true
            if let startedID { confirmed = await cancelHost(startedID, profile: profile) }
            if attempt == generation { phase = .cancelled(provider: provider.id, confirmed: confirmed) }
            return
        }
        guard reply.status == 200 else {
            phase = .failed(provider: provider.id, .startRejected)
            return
        }
        guard let session = try? ForkOAuthDeviceSession(reply.body) else {
            if let startedID { _ = await cancelHost(startedID, profile: profile) }
            if attempt == generation { phase = .failed(provider: provider.id, .unsupportedSession) }
            return
        }
        let expiresAt = now().addingTimeInterval(session.lifetime)
        phase = .waiting(provider: provider.id, session: session, expiresAt: expiresAt)
        await poll(provider.id, session: session, expiresAt: expiresAt, attempt: attempt, profile: profile)
    }

    func cancel() async {
        switch phase {
        case .starting(let provider):
            phase = .cancelled(provider: provider, confirmed: false)
        case .waiting(let provider, let session, _):
            generation += 1
            let attempt = generation
            phase = .cancelled(provider: provider, confirmed: false)
            let confirmed = await cancelHost(session.id, profile: profile)
            if attempt == generation { phase = .cancelled(provider: provider, confirmed: confirmed) }
        default:
            return
        }
    }

    func stop() async {
        let pending = phase
        generation += 1
        if pending != .idle { phase = .idle }
        if case .waiting(_, let session, _) = pending { _ = await cancelHost(session.id, profile: profile) }
    }

    private func poll(_ provider: String, session: ForkOAuthDeviceSession, expiresAt: Date, attempt: Int,
                      profile: String) async {
        while attempt == generation {
            let left = expiresAt.timeIntervalSince(now())
            guard left > 0 else { return await expire(provider, session: session, attempt: attempt, profile: profile) }
            do {
                try await sleep(min(session.pollInterval, left))
            } catch {
                return
            }
            guard attempt == generation else { return }
            guard expiresAt > now() else { return await expire(provider, session: session, attempt: attempt, profile: profile) }
            guard let reply = try? await send(.poll(provider: provider, session: session.id, profile: profile)) else { continue }
            guard attempt == generation else { return }
            if reply.status == 404 {
                phase = .failed(provider: provider, .expired)
                return
            }
            guard reply.status == 200, let status = ForkOAuthStatus.parse(reply.body, session: session.id) else { continue }
            switch status {
            case .pending:
                continue
            case .approved:
                phase = .approved(provider: provider)
                await readBack(attempt: attempt, profile: profile)
            case .denied:
                phase = .failed(provider: provider, .denied)
            case .expired:
                phase = .failed(provider: provider, .expired)
            case .cancelled:
                phase = .cancelled(provider: provider, confirmed: true)
            case .error:
                phase = .failed(provider: provider, .hostError)
            }
            return
        }
    }

    private func expire(_ provider: String, session: ForkOAuthDeviceSession, attempt: Int, profile: String) async {
        phase = .failed(provider: provider, .expired)
        _ = await cancelHost(session.id, profile: profile)
    }

    private func readBack(attempt: Int, profile: String) async {
        guard let reply = try? await send(.catalog(profile: profile)),
              attempt == generation, profile == self.profile, reply.status == 200,
              let fresh = try? ForkOAuthProvider.catalog(reply.body) else { return }
        providers = fresh
        catalogFailure = nil
    }

    private func cancelHost(_ session: String, profile: String) async -> Bool {
        guard let reply = try? await send(.cancel(session: session, profile: profile)), reply.status == 200,
              let root = try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any] else { return false }
        return root["ok"] as? Bool == true
    }
}
