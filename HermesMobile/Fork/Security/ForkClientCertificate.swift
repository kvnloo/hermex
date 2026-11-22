import CryptoKit
import Foundation
import Security

enum ForkClientCertificateError: LocalizedError {
    case invalidFile, unavailable

    var errorDescription: String? {
        switch self {
        case .invalidFile: String(localized: "Check the PKCS#12 file and password.")
        case .unavailable: String(localized: "Could not access the client certificate in Keychain.")
        }
    }
}

struct ForkClientCertificate: Codable, Sendable {
    let archive: Data
    let password: String

    func credential() throws -> URLCredential {
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password,
            kSecImportToMemoryOnly as String: true
        ]
        var result: CFArray?
        guard SecPKCS12Import(archive as CFData, options as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { throw ForkClientCertificateError.invalidFile }
        let identities = items.filter { $0[kSecImportItemIdentity as String] != nil }
        guard identities.count == 1, let identity = identities[0][kSecImportItemIdentity as String],
              CFGetTypeID(identity as CFTypeRef) == SecIdentityGetTypeID() else {
            throw ForkClientCertificateError.invalidFile
        }
        let chain = identities[0][kSecImportItemCertChain as String] as? [SecCertificate]
        let issuers = chain.map { Array($0.dropFirst()) } ?? []
        return URLCredential(identity: identity as! SecIdentity,
                             certificates: issuers.isEmpty ? nil : issuers, persistence: .forSession)
    }
}

enum ForkClientCertificateStore {
    static func load(_ scope: ForkClientCertificateScope, keychain: any KeychainStoring = KeychainStore())
        throws -> ForkClientCertificate? {
        do {
            guard let value = try keychain.load(.clientCertificate, scope: reference(for: scope)) else { return nil }
            guard let data = Data(base64Encoded: value) else { throw ForkClientCertificateError.unavailable }
            return try PropertyListDecoder().decode(ForkClientCertificate.self, from: data)
        } catch {
            throw ForkClientCertificateError.unavailable
        }
    }

    @MainActor static func save(_ certificate: ForkClientCertificate, for scope: ForkClientCertificateScope,
                                keychain: any KeychainStoring = KeychainStore()) throws {
        _ = try certificate.credential()
        do {
            let data = try PropertyListEncoder().encode(certificate)
            try keychain.save(data.base64EncodedString(), forKey: .clientCertificate, scope: reference(for: scope))
        } catch {
            throw ForkClientCertificateError.unavailable
        }
        changed(scope)
    }

    @MainActor static func remove(_ scope: ForkClientCertificateScope,
                                  keychain: any KeychainStoring = KeychainStore()) throws {
        do {
            try keychain.delete(.clientCertificate, scope: reference(for: scope))
        } catch {
            throw ForkClientCertificateError.unavailable
        }
        changed(scope)
    }

    @MainActor private static let connections = NSHashTable<HermesConnection>.weakObjects()

    @MainActor static func observe(_ connection: HermesConnection) { connections.add(connection) }

    @MainActor private static func changed(_ scope: ForkClientCertificateScope) {
        for connection in connections.allObjects where ForkClientCertificateScope(server: connection.connection.address) == scope {
            connection.clientCertificateChanged()
        }
    }

    private static func reference(for scope: ForkClientCertificateScope) -> String {
        SHA256.hash(data: Data(scope.key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

final class ForkClientCertificateDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let scope: ForkClientCertificateScope
    private let load: @Sendable () throws -> ForkClientCertificate?

    init(scope: ForkClientCertificateScope, load: @escaping @Sendable () throws -> ForkClientCertificate?) {
        self.scope = scope
        self.load = load
    }

    static func saved(for scope: ForkClientCertificateScope, staged: ForkClientCertificate? = nil) -> ForkClientCertificateDelegate? {
        guard let certificate = staged ?? (try? ForkClientCertificateStore.load(scope)) else { return nil }
        return ForkClientCertificateDelegate(scope: scope) { certificate }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodClientCertificate else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard space.proxyType == nil, challenge.previousFailureCount == 0,
              scope.matches(host: space.host, port: space.port, scheme: space.protocol),
              let certificate = try? load(), let credential = try? certificate.credential() else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, credential)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(scope.matches) == true ? request : nil)
    }
}
