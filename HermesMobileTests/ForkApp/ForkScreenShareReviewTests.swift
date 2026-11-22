import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import HermesMobile

@MainActor
final class ForkScreenShareReviewTests: XCTestCase {
    private var inbox: URL!

    override func setUp() async throws {
        try await super.setUp()
        inbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        AppIntentRouter.shared.pendingDeepLink = nil
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: inbox)
        AppIntentRouter.shared.pendingDeepLink = nil
        try await super.tearDown()
    }

    private var png: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    func testAttachingTheReviewedScreenshotQueuesItForANewChatWithoutSending() throws {
        let review = ForkScreenShareReview()
        let now = Date(timeIntervalSince1970: 1_000)
        try review.offer(png, filename: "Screenshot.png", type: .png, now: now)
        let capture = try XCTUnwrap(review.pending)
        XCTAssertNotNil(review.preview)
        XCTAssertNil(try HermesShareDraft.reserveNextPendingImport(from: inbox), "Nothing leaves the review before Attach")

        XCTAssertEqual(try review.attach(capture, inbox: inbox, now: now.addingTimeInterval(5)), .attached)

        XCTAssertNil(review.pending)
        XCTAssertEqual(AppIntentRouter.shared.pendingDeepLink, HermesShareDraft.openURL)
        let queued = try XCTUnwrap(try HermesShareDraft.reserveNextPendingImport(from: inbox))
        XCTAssertEqual(queued.sharedImport.attachments.map(\.data), [png])
        XCTAssertEqual(queued.sharedImport.draft, "")
    }

    func testDiscardingOrLettingTheScreenshotExpireQueuesNothing() throws {
        let review = ForkScreenShareReview()
        let now = Date(timeIntervalSince1970: 1_000)
        try review.offer(png, filename: "", type: .png, now: now)
        let expired = try XCTUnwrap(review.pending)
        XCTAssertEqual(expired.filename, "Screenshot.png")
        XCTAssertEqual(try review.attach(expired, inbox: inbox, now: now.addingTimeInterval(ScreenShareConsent.lifetime + 1)),
                       .expired)

        try review.offer(png, filename: "Screenshot.png", type: .png, now: now)
        let discarded = try XCTUnwrap(review.pending)
        review.discard(discarded)
        XCTAssertNil(review.pending)
        XCTAssertNil(review.preview)
        XCTAssertEqual(try review.attach(discarded, inbox: inbox, now: now), .expired)

        XCTAssertNil(try HermesShareDraft.reserveNextPendingImport(from: inbox))
        XCTAssertNil(AppIntentRouter.shared.pendingDeepLink)
    }

    func testAFileThatIsNotAnImageIsRefused() {
        let review = ForkScreenShareReview()
        XCTAssertThrowsError(try review.offer(Data("not an image".utf8), filename: "notes.png", type: .png)) {
            XCTAssertEqual($0 as? ScreenShareRefusal, .unreadable)
        }
        XCTAssertNil(review.pending)
    }
}
