import XCTest
@testable import HermesMobile

final class ScreenShareConsentTests: XCTestCase {
    private let png = Data([0x89, 0x50, 0x4E, 0x47])

    private func offered(_ consent: inout ScreenShareConsent, at now: Double = 100) throws -> ScreenShareCapture {
        try consent.offer(png, filename: "Screenshot.png", typeIdentifier: "public.png", decodes: true, now: now)
    }

    func testACaptureIsHandedOffOnlyWhenItsOwnReviewApprovesIt() throws {
        var consent = ScreenShareConsent(maximumBytes: 1_024)
        let capture = try offered(&consent)

        XCTAssertNil(consent.approved(UUID(), now: 101), "Another review's approval hands off nothing")
        XCTAssertEqual(consent.approved(capture.id, now: 101), capture)
        consent.close(capture.id)
        XCTAssertNil(consent.approved(capture.id, now: 102), "One approval per capture")
        XCTAssertNil(consent.pending)
    }

    func testADiscardedCaptureCanNeverBeApproved() throws {
        var consent = ScreenShareConsent(maximumBytes: 1_024)
        let capture = try offered(&consent)
        consent.close(capture.id)
        XCTAssertNil(consent.pending)
        XCTAssertNil(consent.approved(capture.id, now: 101))
    }

    func testANewerCaptureReplacesAnOlderOneAwaitingReview() throws {
        var consent = ScreenShareConsent(maximumBytes: 1_024)
        let older = try offered(&consent)
        let newer = try offered(&consent, at: 110)
        XCTAssertNil(consent.approved(older.id, now: 111))
        consent.close(older.id)
        XCTAssertEqual(consent.pending, newer, "Closing the old review leaves the new one waiting")
    }

    func testAnExpiredCaptureCannotBeApproved() throws {
        var consent = ScreenShareConsent(maximumBytes: 1_024)
        let capture = try offered(&consent)
        XCTAssertNil(consent.approved(capture.id, now: 100 + ScreenShareConsent.lifetime + 1))
        XCTAssertNil(consent.approved(capture.id, now: 99), "A clock moved back can't revive it")
        XCTAssertTrue(consent.isExpired(capture, now: 100 + ScreenShareConsent.lifetime + 1))
    }

    func testEmptyOversizedOrUnreadableImagesAreRefusedWithoutReplacingTheReview() throws {
        var consent = ScreenShareConsent(maximumBytes: 3)
        XCTAssertThrowsError(try offered(&consent)) { XCTAssertEqual($0 as? ScreenShareRefusal, .tooLarge) }
        consent = ScreenShareConsent(maximumBytes: 1_024)
        let waiting = try offered(&consent)
        XCTAssertThrowsError(try consent.offer(Data(), filename: "a.png", typeIdentifier: nil, decodes: true, now: 101)) {
            XCTAssertEqual($0 as? ScreenShareRefusal, .empty)
        }
        XCTAssertThrowsError(try consent.offer(png, filename: "a.png", typeIdentifier: nil, decodes: false, now: 101)) {
            XCTAssertEqual($0 as? ScreenShareRefusal, .unreadable)
        }
        XCTAssertEqual(consent.pending, waiting)
    }
}
