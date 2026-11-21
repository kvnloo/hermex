import XCTest
@testable import HermesMobile

final class ForkTurboCatalogTests: XCTestCase {
    private func group(_ provider: String, _ models: [String]) -> ModelCatalogGroup {
        ModelCatalogGroup(id: provider, name: provider, providerID: provider,
                          models: models.map { ModelCatalogOption(id: $0, displayName: $0, providerID: provider) })
    }

    func testTurboGroupLeadsWithFriendlyNamesInRouterOrder() {
        let payload: BotJSON = .object(["providers": .array([])])
        let arranged = ForkTurboCatalog.arrange(payload: payload, [
            group("anthropic", ["claude"]), group("vllm-sr", ["vllm-sr/free-public", "vllm-sr/turbo"]),
        ])
        XCTAssertEqual(arranged.map(\.id), ["vllm-sr", "anthropic"])
        XCTAssertEqual(arranged.first?.models.map(\.id), ["vllm-sr/turbo", "vllm-sr/free-public"])
        XCTAssertNotEqual(arranged.first?.models.first?.displayName, "vllm-sr/turbo")
        XCTAssertEqual(arranged.last, group("anthropic", ["claude"]))
    }

    func testAdvertisedRouterWithoutModelsGetsTheSixRoutes() {
        let payload: BotJSON = .object(["providers": .array([.object(["slug": .string("vllm-sr"), "models": .array([])])])])
        let arranged = ForkTurboCatalog.arrange(payload: payload, [group("openai", ["gpt"])])
        XCTAssertEqual(arranged.first?.models.map(\.id), ForkTurboModels.virtualModelIDs)
        XCTAssertEqual(arranged.first?.models.first?.providerID, "vllm-sr")
    }

    func testUnauthenticatedRouterIsNotOffered() {
        let payload: BotJSON = .object(["providers": .array([.object(["slug": .string("vllm-sr"), "authenticated": .bool(false)])])])
        XCTAssertEqual(ForkTurboCatalog.arrange(payload: payload, [group("openai", ["gpt"])]).map(\.id), ["openai"])
    }

    func testCatalogsWithoutTurboAreUnchanged() {
        let groups = [group("openai", ["gpt"]), group("anthropic", ["claude"])]
        XCTAssertEqual(ForkTurboCatalog.arrange(payload: .object([:]), groups), groups)
    }
}
