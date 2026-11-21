import XCTest
@testable import HermesMobile

final class ForkTurboModelsTests: XCTestCase {
    func testTurboRoutesAreRecognizedByProviderOrModelPrefix() {
        XCTAssertTrue(ForkTurboModels.isTurboRoute(provider: " VLLM-SR "))
        XCTAssertTrue(ForkTurboModels.isTurboRoute(provider: "openrouter", model: "vllm-sr/turbo"))
        XCTAssertFalse(ForkTurboModels.isTurboRoute(provider: "openrouter", model: "anthropic/claude"))
    }

    func testRoutesSortInTheRouterOrderThenAlphabetically() {
        let sorted = ForkTurboModels.sorted(["vllm-sr/zeta", "vllm-sr/free-public", "vllm-sr/turbo", "vllm-sr/alpha", "vllm-sr/free-quality"])
        XCTAssertEqual(sorted, ["vllm-sr/turbo", "vllm-sr/free-quality", "vllm-sr/free-public", "vllm-sr/alpha", "vllm-sr/zeta"])
    }

    func testAnAdvertisedProviderWithoutModelsGetsTheDocumentedRoutes() {
        XCTAssertEqual(ForkTurboModels.models(advertised: []), ForkTurboModels.virtualModelIDs)
        XCTAssertEqual(ForkTurboModels.models(advertised: ["vllm-sr/free-verify"]), ["vllm-sr/free-verify"])
        XCTAssertEqual(ForkTurboModels.virtualModelIDs.count, 6)
    }

    func testTurboProviderLeadsTheList() {
        XCTAssertEqual(ForkTurboModels.arrangedProviders(["anthropic", "vllm-sr", "openai"]), ["vllm-sr", "anthropic", "openai"])
        XCTAssertEqual(ForkTurboModels.alias("VLLM-SR/Free-LongCtx"), "free-longctx")
    }
}
