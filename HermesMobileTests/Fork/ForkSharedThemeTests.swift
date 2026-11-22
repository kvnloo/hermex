import XCTest
@testable import HermesMobile

enum ForkVendoredEphemeralUI {
    static var directory: URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HermesMobile/Fork/Vendor/EphemeralUI", isDirectory: true)
    }

    static func data(_ name: String) throws -> Data {
        #if os(iOS)
        let url = try XCTUnwrap(Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "json",
                                                subdirectory: "EphemeralUI"), "the app bundles EphemeralUI/\(name)")
        return try Data(contentsOf: url)
        #else
        return try Data(contentsOf: directory.appendingPathComponent(name))
        #endif
    }

    static func pinnedVersion(_ name: String) throws -> String {
        let pin = try JSONSerialization.jsonObject(with: data("PIN.json")) as? [String: Any]
        let files = pin?["files"] as? [String: [String: Any]]
        return try XCTUnwrap(files?[name]?["version"] as? String)
    }
}

final class ForkSharedThemeTests: XCTestCase {
    private func vendored() throws -> ForkSharedTheme {
        try ForkSharedTheme.parse(ForkVendoredEphemeralUI.data("glide.json"))
    }

    func testTheVendoredThemeIsThePinnedVersionAndCarriesTheGlideBrand() throws {
        let theme = try vendored()
        XCTAssertEqual(theme.version, try ForkVendoredEphemeralUI.pinnedVersion("glide.json"))
        XCTAssertEqual(theme.brand.name, "Glide")
        XCTAssertFalse(theme.brand.tagline.isEmpty)
        XCTAssertEqual(theme.spec.name, theme.brand.name)
    }

    func testAFileShapeThisAppCannotReadIsRefusedBeforeAnythingApplies() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: ForkVendoredEphemeralUI.data("glide.json")) as? [String: Any])
        object["v"] = 1
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try ForkSharedTheme.parse(data)) { error in
            XCTAssertEqual(error as? ForkSharedThemeError, .unsupportedShape(1))
        }
        object["v"] = 0
        object["color"] = ["light": ["bg": "white"], "dark": [:]]
        XCTAssertThrowsError(try ForkSharedTheme.parse(JSONSerialization.data(withJSONObject: object))) { error in
            XCTAssertEqual(error as? ForkSharedThemeError, .badColor("color.light.bg", "white"))
        }
    }

    func testEveryKitTokenTheAppMapsLandsOnItsRoleInBothSchemes() throws {
        let theme = try vendored()
        for isDark in [false, true] {
            let palette = theme.palette(isDark: isDark)
            let roles = theme.spec.tokens(isDark: isDark)
            XCTAssertEqual(roles["background"], palette["bg"])
            XCTAssertEqual(roles["text"], palette["fg"])
            XCTAssertEqual(roles["accent"], palette["primary"])
            XCTAssertEqual(roles["onAccent"], palette["primaryFg"])
            XCTAssertEqual(roles["userBubble"], palette["message"])
            XCTAssertEqual(roles["stroke"], palette["border"])
            XCTAssertTrue(Set(roles.keys).isSubset(of: Set(ForkThemeSpec.roles)))
        }
    }

    func testTheGlideLookStaysReadableAndRoundTripsAsThemeJSON() throws {
        let spec = try vendored().spec
        for isDark in [false, true] {
            let roles = spec.roles(isDark: isDark)
            for foreground in roles.foregrounds {
                for background in roles.textBackgrounds {
                    XCTAssertGreaterThanOrEqual(foreground.contrast(with: background), ForkPaletteRoles.minimumContrast - 0.01)
                }
            }
        }
        XCTAssertEqual(try ForkThemeSpec.parse(spec.encoded()), spec)
    }

    func testTurboHalvesEveryDurationAndSpeedStaysInItsRange() throws {
        let motion = try vendored().motion
        XCTAssertEqual(motion.speed.turbo, 2)
        for name in motion.durationsMS.keys {
            let normal = try XCTUnwrap(motion.seconds(name))
            XCTAssertEqual(try XCTUnwrap(motion.seconds(name, speed: motion.speed.turbo)), normal / 2, accuracy: 1e-9)
            XCTAssertEqual(motion.seconds(name, speed: 100), motion.seconds(name, speed: motion.speed.max))
            XCTAssertEqual(motion.seconds(name, speed: 0), motion.seconds(name, speed: motion.speed.min))
            XCTAssertEqual(motion.seconds(name, reduceMotion: true), 0)
        }
        XCTAssertNil(motion.seconds("missing"))
    }

    func testEasingsTrackingAndGlassLevelsParseIntoNumbers() throws {
        let theme = try vendored()
        XCTAssertEqual(theme.motion.easings.count, 5)
        XCTAssertEqual(ForkSharedTheme.cubicBezier("cubic-bezier(.2, .7, .2, 1)"), ForkCubicBezier(x1: 0.2, y1: 0.7, x2: 0.2, y2: 1))
        XCTAssertNil(ForkSharedTheme.cubicBezier("ease-in"))
        XCTAssertEqual(theme.type.trackingEm["tight"], -0.01)
        XCTAssertEqual(theme.glassLevels.first?.name, "none")
        XCTAssertEqual(theme.glassLevels.last?.name, "max")
        XCTAssertEqual(theme.glassLevels.map(\.level.blur), theme.glassLevels.map(\.level.blur).sorted())
    }
}
