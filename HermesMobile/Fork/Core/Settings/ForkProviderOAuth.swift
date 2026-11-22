import Foundation

struct ForkOAuthProvider: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let flow: String
    var loggedIn: Bool?

    var signsInFromApp: Bool { flow == "device_code" }

    static func isValidID(_ value: String) -> Bool {
        ForkOAuthRoute.isSegment(value, maximum: 128)
    }

    static func catalog(_ data: Data) throws -> [ForkOAuthProvider] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["providers"] as? [Any] else { throw ForkOAuthFailure.unreadable }
        var seen: Set<String> = []
        return rows.compactMap { row in
            guard let row = row as? [String: Any], let id = row["id"] as? String, isValidID(id), !seen.contains(id),
                  let flow = row["flow"] as? String else { return nil }
            seen.insert(id)
            let name = (row["name"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            let status = row["status"] as? [String: Any]
            return ForkOAuthProvider(id: id, name: name ?? id, flow: flow, loggedIn: status?["logged_in"] as? Bool)
        }
    }
}

struct ForkOAuthDeviceSession: Equatable, Sendable {
    static let hostSessionLifetime: TimeInterval = 15 * 60

    let id: String
    let userCode: String
    let verificationURL: URL
    let lifetime: TimeInterval
    let pollInterval: TimeInterval

    static func isValidID(_ value: String) -> Bool {
        ForkOAuthRoute.isSegment(value, maximum: 256)
    }

    static func sessionID(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = root["session_id"] as? String, isValidID(id) else { return nil }
        return id
    }

    init(id: String, userCode: String, verificationURL: URL, lifetime: TimeInterval, pollInterval: TimeInterval) {
        self.id = id
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.lifetime = lifetime
        self.pollInterval = pollInterval
    }

    init(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = root["session_id"] as? String, Self.isValidID(id),
              root["flow"] as? String == "device_code",
              let code = root["user_code"] as? String, !code.isEmpty, code.count <= 256,
              let rawURL = root["verification_url"] as? String, let url = ForkOAuthURL.safe(rawURL),
              let expires = (root["expires_in"] as? NSNumber)?.doubleValue, expires.isFinite, expires > 0,
              let interval = (root["poll_interval"] as? NSNumber)?.doubleValue, interval.isFinite, interval > 0
        else { throw ForkOAuthFailure.unsupportedSession }
        self.init(id: id, userCode: code, verificationURL: url,
                  lifetime: min(expires, Self.hostSessionLifetime), pollInterval: min(max(interval, 1), 30))
    }
}

enum ForkOAuthStatus: String, Equatable, Sendable {
    case pending, approved, denied, expired, cancelled, error

    static func parse(_ data: Data, session: String) -> ForkOAuthStatus? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["session_id"] as? String == session, let raw = root["status"] as? String else { return nil }
        return ForkOAuthStatus(rawValue: raw)
    }
}

enum ForkOAuthURL {
    static func safe(_ raw: String) -> URL? {
        guard !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0)
                  || CharacterSet.controlCharacters.contains($0) || $0 == "\\" }),
              let parts = URLComponents(string: raw), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443, parts.fragment == nil
        else { return nil }
        return parts.url
    }
}

enum ForkOAuthFailure: Error, Equatable, Sendable {
    case unreadable
    case unsupportedSession
    case invalidIdentifier
    case startRejected
    case denied
    case expired
    case hostError
    case unreachable
}

enum ForkOAuthRoute: Equatable, Sendable {
    case catalog(profile: String)
    case start(provider: String, profile: String)
    case poll(provider: String, session: String, profile: String)
    case cancel(session: String, profile: String)

    var profile: String {
        switch self {
        case .catalog(let profile), .start(_, let profile), .poll(_, _, let profile), .cancel(_, let profile): profile
        }
    }

    func endpoint(base: URL) throws -> (method: String, url: URL) {
        let method: String, path: String
        switch self {
        case .catalog:
            method = "GET"; path = "api/providers/oauth"
        case .start(let provider, _):
            guard ForkOAuthProvider.isValidID(provider) else { throw ForkOAuthFailure.invalidIdentifier }
            method = "POST"; path = "api/providers/oauth/\(provider)/start"
        case .poll(let provider, let session, _):
            guard ForkOAuthProvider.isValidID(provider), ForkOAuthDeviceSession.isValidID(session)
            else { throw ForkOAuthFailure.invalidIdentifier }
            method = "GET"; path = "api/providers/oauth/\(provider)/poll/\(session)"
        case .cancel(let session, _):
            guard ForkOAuthDeviceSession.isValidID(session) else { throw ForkOAuthFailure.invalidIdentifier }
            method = "DELETE"; path = "api/providers/oauth/sessions/\(session)"
        }
        guard var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw ForkOAuthFailure.invalidIdentifier }
        if !profile.isEmpty { parts.queryItems = [URLQueryItem(name: "profile", value: profile)] }
        guard let url = parts.url else { throw ForkOAuthFailure.invalidIdentifier }
        return (method, url)
    }

    static func isSegment(_ value: String, maximum: Int) -> Bool {
        (1...maximum).contains(value.count) && value.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-"
        }
    }
}
