import Foundation
import Security
import XCTest
@testable import HermesMobile

final class ForkClientCertificateChallengeTests: XCTestCase {
    private func certificate() throws -> ForkClientCertificate {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "test-client", withExtension: "p12"))
        return ForkClientCertificate(archive: try Data(contentsOf: fixture), password: " test-only ")
    }

    func testMatchingClientCertificateChallengeReturnsImportedIdentity() throws {
        let certificate = try certificate()
        let expected = try XCTUnwrap(try certificate.credential().identity)
        var expectedLeaf: SecCertificate?
        XCTAssertEqual(SecIdentityCopyCertificate(expected, &expectedLeaf), errSecSuccess)

        let result = try answer(load: { certificate })
        XCTAssertEqual(result.0, .useCredential)
        let identity = try XCTUnwrap(result.1?.identity)
        var leaf: SecCertificate?
        XCTAssertEqual(SecIdentityCopyCertificate(identity, &leaf), errSecSuccess)
        XCTAssertEqual(SecCertificateCopyData(try XCTUnwrap(leaf)), SecCertificateCopyData(try XCTUnwrap(expectedLeaf)))
    }

    func testWrongPasswordAndMissingIdentityCannotAnswerClientCertificateChallenge() throws {
        let invalid = ForkClientCertificate(archive: try certificate().archive, password: "test-only")
        XCTAssertEqual(try answer(load: { invalid }).0, .cancelAuthenticationChallenge)
        XCTAssertEqual(try answer(load: { nil }).0, .cancelAuthenticationChallenge)
    }

    func testUnrelatedAndRepeatedChallengesCannotReadIdentity() throws {
        let neverLoad: @Sendable () -> ForkClientCertificate? = {
            XCTFail("An unrelated challenge tried to load a client certificate")
            return nil
        }
        XCTAssertEqual(try answer(host: "other", load: neverLoad).0, .cancelAuthenticationChallenge)
        XCTAssertEqual(try answer(port: 8443, load: neverLoad).0, .cancelAuthenticationChallenge)
        XCTAssertEqual(try answer(failures: 1, load: neverLoad).0, .cancelAuthenticationChallenge)
        XCTAssertEqual(try answer(method: NSURLAuthenticationMethodServerTrust, load: neverLoad).0, .performDefaultHandling)
        XCTAssertEqual(try answer(method: NSURLAuthenticationMethodHTTPBasic, load: neverLoad).0, .performDefaultHandling)
    }

    @MainActor
    func testRemovingOneServerLeavesTheOtherIdentityInKeychain() throws {
        let keychain = InMemoryKeychainStore()
        let a = try XCTUnwrap(ForkClientCertificateScope(server: XCTUnwrap(URL(string: "https://fixture"))))
        let b = try XCTUnwrap(ForkClientCertificateScope(server: XCTUnwrap(URL(string: "https://fixture:8443"))))
        let certificate = try certificate()
        try ForkClientCertificateStore.save(certificate, for: a, keychain: keychain)
        try ForkClientCertificateStore.save(certificate, for: b, keychain: keychain)
        try ForkClientCertificateStore.remove(a, keychain: keychain)
        XCTAssertNil(try ForkClientCertificateStore.load(a, keychain: keychain))
        let retained = try XCTUnwrap(ForkClientCertificateStore.load(b, keychain: keychain))
        XCTAssertNotNil(try retained.credential().identity)
    }

    private func answer(host: String = "fixture", port: Int = 443,
                        method: String = NSURLAuthenticationMethodClientCertificate, failures: Int = 0,
                        load: @escaping @Sendable () -> ForkClientCertificate?) throws
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let scope = try XCTUnwrap(ForkClientCertificateScope(server: XCTUnwrap(URL(string: "https://fixture"))))
        let delegate = ForkClientCertificateDelegate(scope: scope, load: load)
        let space = URLProtectionSpace(host: host, port: port, protocol: "https", realm: nil, authenticationMethod: method)
        let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil,
                                                   previousFailureCount: failures, failureResponse: nil,
                                                   error: nil, sender: ChallengeSender())
        var result: (URLSession.AuthChallengeDisposition, URLCredential?)?
        delegate.urlSession(.shared, didReceive: challenge) { result = ($0, $1) }
        return try XCTUnwrap(result)
    }
}

private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
