import XCTest
@testable import HermesMobile

final class ForkShareReviewTests: XCTestCase {
    private let project = ForkShareProject(id: "p1", name: "Launch", folder: "/srv/launch")

    private func wording(_ action: ForkShareAction, _ text: String?) -> String {
        text.map { "\(action.rawValue): \($0)" } ?? "\(action.rawValue) attached"
    }

    func testColdShareIsReviewedOnceWhileTheHomeSettlesThenMovesWithTheChoice() {
        var gate = ForkShareReviewGate()
        XCTAssertEqual(gate.step(for: "r1", fromShareSheet: true), .review)
        XCTAssertEqual(gate.step(for: "r1", fromShareSheet: true), .wait)
        XCTAssertEqual(gate.step(for: "r1", fromShareSheet: true), .wait)

        let choice = ForkShareChoice(action: .summarize, project: project)
        gate.decide("r1", choice)
        XCTAssertNil(gate.settle())
        XCTAssertEqual(gate.step(for: "r1", fromShareSheet: true), .move(choice))
        XCTAssertEqual(gate.step(for: "r1", fromShareSheet: true), .review)
    }

    func testWarmShareArrivingLaterGetsItsOwnReviewAndNotNowLetsItWait() {
        var gate = ForkShareReviewGate()
        XCTAssertEqual(gate.step(for: "r1", fromShareSheet: true), .review)
        gate.decide("r1", ForkShareChoice())
        _ = gate.settle()
        XCTAssertEqual(gate.step(for: "r1", fromShareSheet: true), .move(ForkShareChoice()))

        XCTAssertEqual(gate.step(for: "r2", fromShareSheet: true), .review)
        XCTAssertEqual(gate.settle(), "r2")
        XCTAssertEqual(gate.step(for: "r2", fromShareSheet: true), .review)
    }

    func testShortcutTextsSkipTheReviewAndLeaveAnOpenOneAlone() {
        var gate = ForkShareReviewGate()
        XCTAssertEqual(gate.step(for: "r1", fromShareSheet: true), .review)
        XCTAssertEqual(gate.step(for: "s1", fromShareSheet: false), .pass)
        XCTAssertEqual(gate.reviewing, "r1")
    }

    func testADecisionForAShareNotUnderReviewIsIgnored() {
        var gate = ForkShareReviewGate()
        XCTAssertEqual(gate.step(for: "r1", fromShareSheet: true), .review)
        gate.decide("r2", ForkShareChoice(action: .remember))
        XCTAssertEqual(gate.settle(), "r1")
        XCTAssertEqual(gate.step(for: "r2", fromShareSheet: true), .review)
    }

    func testActionsWrapTheSharedTextAndUseAsIsKeepsIt() {
        XCTAssertEqual(ForkShareAction.summarize.prompt(for: "  a link \n", hasAttachments: false, wording: wording),
                       "summarize: a link")
        XCTAssertEqual(ForkShareAction.useAsIs.prompt(for: " a link ", hasAttachments: true, wording: wording), "a link")
        XCTAssertEqual(ForkShareAction.extractTasks.prompt(for: " ", hasAttachments: true, wording: wording),
                       "extractTasks attached")
        XCTAssertEqual(ForkShareAction.useAsIs.prompt(for: "", hasAttachments: true, wording: wording), "")
        XCTAssertEqual(ForkShareAction.explain.prompt(for: "", hasAttachments: false, wording: wording), "")
    }

    func testOnlyProjectsWithAFolderCanBeAShareDestination() {
        XCTAssertNil(ForkShareProject(id: "p2", name: "No folder", folder: nil))
        XCTAssertNil(ForkShareProject(id: "p3", name: "Blank", folder: "  "))
        XCTAssertEqual(ForkShareProject(id: "p4", name: "", folder: "/srv/x")?.name, "p4")
    }
}
