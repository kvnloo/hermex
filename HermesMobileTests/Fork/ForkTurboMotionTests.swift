import XCTest
@testable import HermesMobile

final class ForkTurboMotionTests: XCTestCase {
    func testTurboShortensDifferentAnimationsByTheSameFactor() {
        XCTAssertEqual(ForkTurboMotion.duration(0.20, isEnabled: true, reduceMotion: false), 0.11, accuracy: 0.000_001)
        XCTAssertEqual(ForkTurboMotion.duration(0.28, isEnabled: true, reduceMotion: false), 0.154, accuracy: 0.000_001)
    }

    func testTurningTurboOffRestoresStandardTiming() {
        XCTAssertEqual(ForkTurboMotion.duration(0.28, isEnabled: false, reduceMotion: false), 0.28)
    }

    func testTurboLeavesReducedMotionFallbackTimingAlone() {
        XCTAssertEqual(ForkTurboMotion.duration(0.12, isEnabled: true, reduceMotion: true), 0.12)
    }
}
