import Foundation
import Observation

@MainActor
final class ForkProviderOAuthClient {
    private let http: HermesConnection

    init(saved connection: BotConnection, server: URL) {
        http = HermesConnections.shared.connection(for: connection, server: server)
    }

    func profiles() async throws -> (names: [String], initial: String) {
        try await HermesEnvironmentClient(http: http).profiles()
    }

    func send(_ route: ForkOAuthRoute) async throws -> ForkProviderSignInFlow.Reply {
        let endpoint = try route.endpoint(base: http.connection.address)
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.method
        return try await http.reply(request)
    }

    func flow(profile: String) -> ForkProviderSignInFlow {
        ForkProviderSignInFlow(profile: profile, send: { [weak self] route in
            guard let self else { throw CancellationError() }
            return try await self.send(route)
        }, sleep: { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        })
    }
}

@MainActor
@Observable
final class ForkProviderSignInModel {
    private(set) var profiles: [String] = []
    private(set) var profile: String?
    private(set) var providers: [ForkOAuthProvider]?
    private(set) var phase: ForkProviderSignInFlow.Phase = .idle
    private(set) var failure: String?

    private let client: ForkProviderOAuthClient
    private var flow: ForkProviderSignInFlow?
    private var signIn: Task<Void, Never>?

    init(client: ForkProviderOAuthClient) {
        self.client = client
    }

    func start() async {
        guard flow == nil else { return await refresh() }
        do {
            let listed = try await client.profiles()
            profiles = listed.names
            let flow = client.flow(profile: listed.initial)
            flow.didChange = { [weak self, weak flow] in
                guard let self, let flow else { return }
                self.mirror(flow)
            }
            self.flow = flow
            profile = listed.initial
            await refresh()
        } catch {
            failure = error.localizedDescription
        }
    }

    func refresh() async {
        guard let flow, let profile else { return }
        await flow.load(profile: profile)
        mirror(flow)
    }

    func select(profile name: String) async {
        signIn?.cancel()
        profile = name
        providers = nil
        await refresh()
    }

    func begin(_ provider: ForkOAuthProvider) {
        guard let flow, !phase.isActive else { return }
        signIn = Task { await flow.begin(provider) }
    }

    func cancel() async {
        await flow?.cancel()
    }

    func stop() async {
        signIn?.cancel()
        await flow?.stop()
    }

    private func mirror(_ flow: ForkProviderSignInFlow) {
        guard flow.profile == profile else { return }
        phase = flow.phase
        if let catalogFailure = flow.catalogFailure, flow.providers.isEmpty {
            failure = Self.message(catalogFailure)
            providers = nil
        } else {
            failure = nil
            providers = flow.providers
        }
    }

    static func message(_ failure: ForkOAuthFailure) -> String {
        switch failure {
        case .unreadable:
            String(localized: "This Hermes host didn’t return its sign-in providers. Update Hermes and try again.", table: "Fork")
        case .hostError:
            String(localized: "The host reported an error while finishing this sign-in.", table: "Fork")
        case .unreachable:
            String(localized: "Couldn’t reach the Hermes host.", table: "Fork")
        case .startRejected:
            String(localized: "The host couldn’t start this sign-in. Try again, or set the provider up on the host.", table: "Fork")
        case .unsupportedSession, .invalidIdentifier:
            String(localized: "The host offered a sign-in Hermex can’t open safely.", table: "Fork")
        case .denied:
            String(localized: "The provider declined the sign-in.", table: "Fork")
        case .expired:
            String(localized: "The code expired before it was approved. Start again for a new code.", table: "Fork")
        }
    }
}
