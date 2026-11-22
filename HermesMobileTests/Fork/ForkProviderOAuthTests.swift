import XCTest
@testable import HermesMobile

@MainActor
private final class ScriptedOAuthHost {
    var routes: [ForkOAuthRoute] = []
    var clock = Date(timeIntervalSince1970: 1_000)
    var answer: (ForkOAuthRoute) async throws -> ForkProviderSignInFlow.Reply = { _ in (Data(), 500) }

    func flow(profile: String = "work") -> ForkProviderSignInFlow {
        ForkProviderSignInFlow(profile: profile, send: { [unowned self] route in
            self.routes.append(route)
            return try await self.answer(route)
        }, sleep: { [unowned self] seconds in
            self.clock.addTimeInterval(seconds)
        }, now: { [unowned self] in self.clock })
    }

    static func json(_ object: Any, _ status: Int = 200) -> ForkProviderSignInFlow.Reply {
        ((try? JSONSerialization.data(withJSONObject: object)) ?? Data(), status)
    }

    static func catalog(loggedIn: Bool) -> ForkProviderSignInFlow.Reply {
        json(["providers": [
            ["id": "openai-codex", "name": "OpenAI Codex", "flow": "device_code", "status": ["logged_in": loggedIn]],
            ["id": "anthropic", "name": "Anthropic", "flow": "external", "status": ["logged_in": false]],
        ]])
    }

    static func started(_ id: String = "s1", url: String = "https://auth.example.com/device", expires: Double = 600,
                        interval: Double = 5) -> ForkProviderSignInFlow.Reply {
        json(["session_id": id, "flow": "device_code", "user_code": "ABCD-1234", "verification_url": url,
              "expires_in": expires, "poll_interval": interval])
    }

    static func polled(_ status: String, session: String = "s1", extra: [String: Any] = [:]) -> ForkProviderSignInFlow.Reply {
        json(["session_id": session, "status": status].merging(extra) { first, _ in first })
    }
}

private let codex = ForkOAuthProvider(id: "openai-codex", name: "OpenAI Codex", flow: "device_code", loggedIn: false)

@MainActor
final class ForkProviderOAuthTests: XCTestCase {
    private func isPoll(_ route: ForkOAuthRoute) -> Bool {
        if case .poll = route { return true }
        return false
    }

    private func isCatalog(_ route: ForkOAuthRoute) -> Bool {
        if case .catalog = route { return true }
        return false
    }

    func testApprovalReadsBackTheSameProfileCatalogOnceAndNeverRepolls() async {
        let host = ScriptedOAuthHost()
        var polls = 0
        var catalogs = 0
        host.answer = { route in
            switch route {
            case .catalog:
                catalogs += 1
                return ScriptedOAuthHost.catalog(loggedIn: catalogs > 1)
            case .start: return ScriptedOAuthHost.started()
            case .poll:
                polls += 1
                return polls == 1 ? ScriptedOAuthHost.polled("pending")
                    : ScriptedOAuthHost.polled("approved", extra: ["account_email": "someone@example.com"])
            case .cancel: return ScriptedOAuthHost.json(["ok": true])
            }
        }
        let flow = host.flow()
        await flow.load(profile: "work")
        XCTAssertEqual(flow.providers.first?.loggedIn, false)

        await flow.begin(flow.providers[0])

        XCTAssertEqual(flow.phase, .approved(provider: "openai-codex"))
        XCTAssertEqual(flow.providers.first?.loggedIn, true)
        XCTAssertEqual(host.routes, [
            .catalog(profile: "work"), .start(provider: "openai-codex", profile: "work"),
            .poll(provider: "openai-codex", session: "s1", profile: "work"),
            .poll(provider: "openai-codex", session: "s1", profile: "work"), .catalog(profile: "work"),
        ])
    }

    func testReadbackFailureKeepsTheApprovalOutcome() async {
        let host = ScriptedOAuthHost()
        host.answer = { route in
            switch route {
            case .start: return ScriptedOAuthHost.started()
            case .poll: return ScriptedOAuthHost.polled("approved")
            case .catalog: throw URLError(.notConnectedToInternet)
            case .cancel: return ScriptedOAuthHost.json(["ok": true])
            }
        }
        let flow = host.flow()

        await flow.begin(codex)

        XCTAssertEqual(flow.phase, .approved(provider: "openai-codex"))
        XCTAssertFalse(host.routes.contains(.cancel(session: "s1", profile: "work")))
    }

    func testLateReadbackAfterAProfileSwitchIsIgnored() async {
        let host = ScriptedOAuthHost()
        let flow = host.flow()
        var switched = false
        host.answer = { route in
            switch route {
            case .start: return ScriptedOAuthHost.started()
            case .poll: return ScriptedOAuthHost.polled("approved")
            case .catalog(let profile) where profile == "work" && !switched:
                switched = true
                await flow.load(profile: "home")
                return ScriptedOAuthHost.catalog(loggedIn: true)
            case .catalog:
                return ScriptedOAuthHost.json(["providers": [["id": "nous", "name": "Nous", "flow": "device_code"]]])
            case .cancel: return ScriptedOAuthHost.json(["ok": true])
            }
        }

        await flow.begin(codex)

        XCTAssertEqual(flow.profile, "home")
        XCTAssertEqual(flow.providers.map(\.id), ["nous"])
        XCTAssertEqual(flow.phase, .idle)
    }

    func testCancelWhileWaitingDeletesTheHostSessionAndStopsPolling() async {
        let host = ScriptedOAuthHost()
        let flow = host.flow()
        host.answer = { route in
            switch route {
            case .start: return ScriptedOAuthHost.started()
            case .poll:
                await flow.cancel()
                return ScriptedOAuthHost.polled("approved")
            case .cancel: return ScriptedOAuthHost.json(["ok": true, "session_id": "s1"])
            case .catalog: return ScriptedOAuthHost.catalog(loggedIn: true)
            }
        }

        await flow.begin(codex)

        XCTAssertEqual(flow.phase, .cancelled(provider: "openai-codex", confirmed: true))
        XCTAssertEqual(host.routes.filter(isPoll).count, 1)
        XCTAssertEqual(host.routes.last, .cancel(session: "s1", profile: "work"))
    }

    func testCancelThatTheHostDoesNotConfirmStaysUncertain() async {
        let host = ScriptedOAuthHost()
        let flow = host.flow()
        host.answer = { route in
            switch route {
            case .start: return ScriptedOAuthHost.started()
            case .poll:
                await flow.cancel()
                return ScriptedOAuthHost.polled("pending")
            case .cancel: throw URLError(.timedOut)
            case .catalog: return ScriptedOAuthHost.catalog(loggedIn: false)
            }
        }

        await flow.begin(codex)

        XCTAssertEqual(flow.phase, .cancelled(provider: "openai-codex", confirmed: false))
    }

    func testCancelDuringStartCancelsTheSessionTheHostReturns() async {
        let host = ScriptedOAuthHost()
        let flow = host.flow()
        host.answer = { route in
            switch route {
            case .start:
                await flow.cancel()
                return ScriptedOAuthHost.started("late")
            case .cancel: return ScriptedOAuthHost.json(["ok": true])
            default: return ScriptedOAuthHost.polled("pending", session: "late")
            }
        }

        await flow.begin(codex)

        XCTAssertEqual(flow.phase, .cancelled(provider: "openai-codex", confirmed: true))
        XCTAssertEqual(host.routes, [.start(provider: "openai-codex", profile: "work"), .cancel(session: "late", profile: "work")])
    }

    func testLeavingTheScreenDuringStartCancelsTheStaleSession() async {
        let host = ScriptedOAuthHost()
        let flow = host.flow()
        host.answer = { route in
            switch route {
            case .start:
                await flow.stop()
                return ScriptedOAuthHost.started("stale")
            case .cancel: return ScriptedOAuthHost.json(["ok": true])
            default: return ScriptedOAuthHost.polled("pending", session: "stale")
            }
        }

        await flow.begin(codex)

        XCTAssertEqual(flow.phase, .idle)
        XCTAssertEqual(host.routes.last, .cancel(session: "stale", profile: "work"))
        XCTAssertFalse(host.routes.contains(where: isPoll))
    }

    func testExpiryEndsTheSignInWithinTheHostSessionLifetime() async {
        let host = ScriptedOAuthHost()
        let started = host.clock
        host.answer = { route in
            switch route {
            case .start: return ScriptedOAuthHost.started(expires: 3_600, interval: 60)
            case .poll: return ScriptedOAuthHost.polled("pending")
            case .cancel: return ScriptedOAuthHost.json(["ok": true])
            case .catalog: return ScriptedOAuthHost.catalog(loggedIn: false)
            }
        }
        let flow = host.flow()

        await flow.begin(codex)

        XCTAssertEqual(flow.phase, .failed(provider: "openai-codex", .expired))
        XCTAssertEqual(host.clock.timeIntervalSince(started), ForkOAuthDeviceSession.hostSessionLifetime)
        XCTAssertEqual(host.routes.last, .cancel(session: "s1", profile: "work"))
    }

    func testPollsForAnotherSessionAreIgnoredAndDenialEndsTheSignIn() async {
        let host = ScriptedOAuthHost()
        var polls = 0
        host.answer = { route in
            switch route {
            case .start: return ScriptedOAuthHost.started()
            case .poll:
                polls += 1
                return polls == 1 ? ScriptedOAuthHost.polled("approved", session: "other") : ScriptedOAuthHost.polled("denied")
            default: return ScriptedOAuthHost.json(["ok": true])
            }
        }
        let flow = host.flow()

        await flow.begin(codex)

        XCTAssertEqual(flow.phase, .failed(provider: "openai-codex", .denied))
        XCTAssertFalse(host.routes.contains(where: isCatalog))
    }

    func testUnsafeVerificationURLIsRefusedAndItsSessionCancelled() async {
        let host = ScriptedOAuthHost()
        host.answer = { route in
            switch route {
            case .start: return ScriptedOAuthHost.started(url: "http://auth.example.com/device")
            default: return ScriptedOAuthHost.json(["ok": true])
            }
        }
        let flow = host.flow()

        await flow.begin(codex)

        XCTAssertEqual(flow.phase, .failed(provider: "openai-codex", .unsupportedSession))
        XCTAssertEqual(host.routes.last, .cancel(session: "s1", profile: "work"))
    }

    func testRejectedStartAndExternalProvidersNeverPoll() async {
        let host = ScriptedOAuthHost()
        host.answer = { _ in ScriptedOAuthHost.json(["detail": "Unknown provider"], 400) }
        let flow = host.flow()

        await flow.begin(ForkOAuthProvider(id: "anthropic", name: "Anthropic", flow: "external"))
        XCTAssertEqual(flow.phase, .idle)
        XCTAssertTrue(host.routes.isEmpty)

        await flow.begin(codex)
        XCTAssertEqual(flow.phase, .failed(provider: "openai-codex", .startRejected))
        XCTAssertFalse(host.routes.contains(where: isPoll))
    }

    func testRequestsCarryMethodPathAndProfile() throws {
        let base = try XCTUnwrap(URL(string: "https://host.example/hermes"))
        let start = try ForkOAuthRoute.start(provider: "openai-codex", profile: "work").endpoint(base: base)
        XCTAssertEqual(start.method, "POST")
        XCTAssertEqual(start.url.absoluteString, "https://host.example/hermes/api/providers/oauth/openai-codex/start?profile=work")
        let poll = try ForkOAuthRoute.poll(provider: "nous", session: "a_B-9", profile: "work").endpoint(base: base)
        XCTAssertEqual(poll.method, "GET")
        XCTAssertEqual(poll.url.path, "/hermes/api/providers/oauth/nous/poll/a_B-9")
        let cancel = try ForkOAuthRoute.cancel(session: "a_B-9", profile: "").endpoint(base: base)
        XCTAssertEqual(cancel.method, "DELETE")
        XCTAssertEqual(cancel.url.absoluteString, "https://host.example/hermes/api/providers/oauth/sessions/a_B-9")
        XCTAssertThrowsError(try ForkOAuthRoute.poll(provider: "nous", session: "../x", profile: "w").endpoint(base: base))
        XCTAssertThrowsError(try ForkOAuthRoute.start(provider: "a/b", profile: "w").endpoint(base: base))
    }

    func testCatalogKeepsValidRowsAndOnlyDeviceCodeSignsInFromTheApp() throws {
        let data = try JSONSerialization.data(withJSONObject: ["providers": [
            ["id": "nous", "name": "Nous Portal", "flow": "device_code", "status": ["logged_in": true]],
            ["id": "claude-code", "name": "Claude Code", "flow": "external"],
            ["id": "bad id", "name": "Bad", "flow": "device_code"],
            ["id": "nous", "name": "Duplicate", "flow": "device_code"],
            ["name": "Missing id", "flow": "device_code"],
        ]])
        let providers = try ForkOAuthProvider.catalog(data)
        XCTAssertEqual(providers.map(\.id), ["nous", "claude-code"])
        XCTAssertEqual(providers.map(\.signsInFromApp), [true, false])
        XCTAssertEqual(providers.map(\.loggedIn), [true, nil])
    }

    func testVerificationURLMustBePlainHTTPS() {
        XCTAssertNotNil(ForkOAuthURL.safe("https://auth.openai.com/codex/device"))
        XCTAssertNotNil(ForkOAuthURL.safe("https://portal.example:443/device?code=1"))
        for unsafe in ["http://auth.example/device", "https://user@auth.example/", "https://auth.example:8443/",
                       "https://auth.example/#x", "https://auth.example/ a", "javascript:alert(1)", "https://auth.example\\x"] {
            XCTAssertNil(ForkOAuthURL.safe(unsafe), unsafe)
        }
    }
}
