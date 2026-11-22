import Foundation

struct ForkClientCertificateScope: Equatable, Sendable {
    let host: String
    let port: Int
    let key: String

    init?(server: URL) {
        guard server.scheme?.lowercased() == "https", let host = server.host, !host.isEmpty,
              server.user == nil, server.password == nil else { return nil }
        self.host = host.lowercased()
        port = server.port ?? 443
        key = server.absoluteString
    }

    func matches(host: String, port: Int, scheme: String?) -> Bool {
        let scheme = scheme?.lowercased()
        return (scheme == "https" || scheme == "wss") && self.host == host.lowercased() && self.port == port
    }

    func matches(_ url: URL) -> Bool {
        guard let host = url.host, url.user == nil, url.password == nil else { return false }
        return matches(host: host, port: url.port ?? 443, scheme: url.scheme)
    }
}
