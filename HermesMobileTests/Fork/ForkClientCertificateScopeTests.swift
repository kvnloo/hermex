import Foundation
import XCTest
@testable import HermesMobile

final class ForkClientCertificateScopeTests: XCTestCase {
    func testCertificateIsEligibleOnlyOnItsSecureHostAndEffectivePort() throws {
        let scope = try XCTUnwrap(ForkClientCertificateScope(server: XCTUnwrap(URL(string: "https://fixture"))))
        XCTAssertTrue(scope.matches(try XCTUnwrap(URL(string: "https://FIXTURE:443/status"))))
        XCTAssertTrue(scope.matches(try XCTUnwrap(URL(string: "wss://fixture/events"))))
        XCTAssertFalse(scope.matches(try XCTUnwrap(URL(string: "https://other"))))
        XCTAssertFalse(scope.matches(try XCTUnwrap(URL(string: "https://fixture:8443"))))
        XCTAssertFalse(scope.matches(try XCTUnwrap(URL(string: "http://fixture:443"))))
        XCTAssertFalse(scope.matches(try XCTUnwrap(URL(string: "ws://fixture:443"))))
        XCTAssertNil(ForkClientCertificateScope(server: try XCTUnwrap(URL(string: "http://fixture"))))
    }

    func testSeparateSavedServerIDsDoNotShareKeychainReference() throws {
        let a = try XCTUnwrap(ForkClientCertificateScope(server: XCTUnwrap(URL(string: "https://fixture"))))
        let b = try XCTUnwrap(ForkClientCertificateScope(server: XCTUnwrap(URL(string: "https://fixture:443"))))
        XCTAssertNotEqual(a.key, b.key)
    }
}
