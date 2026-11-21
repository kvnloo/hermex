import UIKit
import XCTest
@testable import HermesMobile

final class ForkThemeStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "ForkThemeStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testNothingStoredFallsBackToOnyx() {
        XCTAssertEqual(ForkThemeStore.spec(in: defaults), .onyx)
        XCTAssertEqual(ForkThemeStore.revision(light: .paper, dark: .iris, in: defaults), "")
    }

    func testSavingAThemeChangesTheRevisionOnlyForCustom() {
        let before = ForkThemeStore.revision(light: .custom, dark: .default, in: defaults)
        ForkThemeStore.save(.dashGold, in: defaults)
        XCTAssertEqual(ForkThemeStore.spec(in: defaults), .dashGold)
        XCTAssertNotEqual(ForkThemeStore.revision(light: .custom, dark: .default, in: defaults), before)
    }

    func testCustomPaletteUsesTheMappedRoles() {
        ForkThemeStore.save(.onyx, in: defaults)
        let palette = ForkThemeStore.palette(isDark: true, in: defaults)
        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 0
        palette.canvas.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual([red, green, blue, alpha], [0, 0, 0, 1])
        XCTAssertGreaterThanOrEqual(ColorContrast.ratio(palette.text, palette.canvas), ColorContrast.minimum)
    }

    func testCopyExportsABuiltInThemeAsImportableJSON() throws {
        let appearance = AppAppearance(lightTheme: .paper, darkTheme: .paper, accentHex: nil)
        let spec = try ForkThemeSpec.parse(ForkThemeStore.exportJSON(for: appearance, in: defaults))
        XCTAssertEqual(spec.name, ColorTheme.paper.title)
        XCTAssertEqual(spec.light["background"]?.hex, "#F8F4EC")
        XCTAssertEqual(spec.dark["background"]?.hex, "#1F1E1C")
    }
}
