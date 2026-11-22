import XCTest
@testable import HermesMobile

final class ForkThemeSpecTests: XCTestCase {
    func testHexParsesRGBAndRGBAInCSSOrder() throws {
        let color = try XCTUnwrap(ForkRGBA(hex: "#E6CD9624"))
        XCTAssertEqual(color.hex, "#E6CD9624")
        XCTAssertEqual(ForkRGBA(hex: "#ffffff"), .white)
        XCTAssertEqual(ForkRGBA(hex: "#000000")?.hex, "#000000")
        XCTAssertNil(ForkRGBA(hex: "FFFFFF"))
        XCTAssertNil(ForkRGBA(hex: "#FFF"))
        XCTAssertNil(ForkRGBA(hex: "#GGGGGG"))
    }

    func testContrastMatchesWCAG() {
        XCTAssertEqual(ForkRGBA.white.contrast(with: .black), 21, accuracy: 0.001)
        XCTAssertEqual(ForkRGBA.white.contrast(with: .white), 1, accuracy: 0.001)
    }

    func testParseAcceptsANextGenThemeAndRoundTrips() throws {
        let source = """
        {"id": "night", "name": " Night ", "glow": true,
         "dark": {"background": "#000000", "text": "#FFFFFF", "accentSoft": "#8C8CFF24"},
         "light": {"accent": "#0000E8"}}
        """
        let spec = try ForkThemeSpec.parse(source)
        XCTAssertEqual(spec.id, "night")
        XCTAssertEqual(spec.name, "Night")
        XCTAssertEqual(spec.glow, true)
        XCTAssertEqual(spec.dark["accentSoft"]?.hex, "#8C8CFF24")
        XCTAssertTrue(spec.ownsAccent)
        XCTAssertEqual(try ForkThemeSpec.parse(spec.encoded()), spec)
    }

    func testParseDefaultsTheIDToCustom() throws {
        XCTAssertEqual(try ForkThemeSpec.parse(#"{"name": "Mine"}"#).id, "custom")
        XCTAssertEqual(try ForkThemeSpec.parse(#"{"name": "Mine", "id": ""}"#).id, "custom")
    }

    func testParseIsStrictSoAnImportNeverHalfApplies() {
        XCTAssertThrowsError(try ForkThemeSpec.parse("not json")) { XCTAssertEqual($0 as? ForkThemeError, .invalidJSON) }
        XCTAssertThrowsError(try ForkThemeSpec.parse("[1]")) { XCTAssertEqual($0 as? ForkThemeError, .notAnObject) }
        XCTAssertThrowsError(try ForkThemeSpec.parse(#"{"name": "  "}"#)) { XCTAssertEqual($0 as? ForkThemeError, .missingName) }
        XCTAssertThrowsError(try ForkThemeSpec.parse(#"{"name": "A", "dark": []}"#)) {
            XCTAssertEqual($0 as? ForkThemeError, .rolesNotAnObject("dark"))
        }
        XCTAssertThrowsError(try ForkThemeSpec.parse(##"{"name": "A", "dark": {"glowy": "#000000"}}"##)) {
            XCTAssertEqual($0 as? ForkThemeError, .unknownRole("glowy"))
        }
        XCTAssertThrowsError(try ForkThemeSpec.parse(#"{"name": "A", "light": {"text": 12}}"#)) {
            XCTAssertEqual($0 as? ForkThemeError, .notAHexString("text"))
        }
        XCTAssertThrowsError(try ForkThemeSpec.parse(#"{"name": "A", "light": {"text": "red"}}"#)) {
            XCTAssertEqual($0 as? ForkThemeError, .badColor("text", "red"))
        }
        XCTAssertThrowsError(try ForkThemeSpec.parse(#"{"name": "A", "glow": 1}"#)) { XCTAssertEqual($0 as? ForkThemeError, .badGlow) }
    }

    func testEncodedJSONKeepsRoleOrderAndEscapesNames() throws {
        let spec = ForkThemeSpec(id: "x", name: "Say \"hi\" / bye", dark: ["text": .white, "background": .black])
        let text = spec.encoded()
        XCTAssertTrue(text.contains(#""name": "Say \"hi\" / bye""#), text)
        let background = try XCTUnwrap(text.range(of: "background"))
        let foreground = try XCTUnwrap(text.range(of: "\"text\""))
        XCTAssertLessThan(background.lowerBound, foreground.lowerBound)
        XCTAssertEqual(try ForkThemeSpec.parse(text), spec)
    }

    func testEveryPresetAndAnEmptyThemeMeetTheContrastFloor() {
        let specs = ForkThemeSpec.presets + [ForkThemeSpec(id: "empty", name: "Empty")]
        for spec in specs {
            for isDark in [false, true] {
                let roles = spec.roles(isDark: isDark)
                for background in roles.textBackgrounds {
                    for foreground in roles.foregrounds {
                        XCTAssertGreaterThanOrEqual(foreground.contrast(with: background), 4.5, "\(spec.id) dark=\(isDark)")
                    }
                }
                XCTAssertGreaterThanOrEqual(roles.onAccent.contrast(with: roles.accent), 4.5, "\(spec.id) dark=\(isDark)")
                XCTAssertGreaterThanOrEqual(roles.text.contrast(with: roles.userBubble), 4.5, "\(spec.id) dark=\(isDark)")
            }
        }
    }

    func testUnreadableImportedColorsAreMovedToTheFloor() {
        let spec = ForkThemeSpec(id: "bad", name: "Bad", dark: [
            "background": ForkRGBA(hex: "#202020")!, "text": ForkRGBA(hex: "#303030")!, "accent": ForkRGBA(hex: "#222244")!,
        ])
        let roles = spec.roles(isDark: true)
        XCTAssertGreaterThanOrEqual(roles.text.contrast(with: roles.canvas), 4.5)
        XCTAssertGreaterThanOrEqual(roles.accent.contrast(with: roles.canvas), 4.5)
        XCTAssertEqual(roles.canvas.hex, "#202020")
    }

    func testTranslucentBackgroundsAreFlattened() {
        let spec = ForkThemeSpec(id: "t", name: "T", light: ["background": ForkRGBA(hex: "#00000080")!])
        let canvas = spec.roles(isDark: false).canvas
        XCTAssertEqual(canvas.alpha, 1)
        XCTAssertEqual(canvas.hex, "#7F7F7F")
    }

    func testDashGoldLightKeepsReadableBubbles() {
        let roles = ForkThemeSpec.dashGold.roles(isDark: false)
        XCTAssertNotEqual(roles.userBubble.hex, "#7A5C14")
        XCTAssertEqual(roles.accent.hex, "#7A5C14")
    }

    func testRolesExportRoundTripsThroughJSON() throws {
        let spec = ForkThemeSpec(name: "Export", lightRoles: ForkThemeSpec.onyx.roles(isDark: false),
                                 darkRoles: ForkThemeSpec.onyx.roles(isDark: true))
        let parsed = try ForkThemeSpec.parse(spec.encoded())
        XCTAssertEqual(parsed.roles(isDark: true).canvas, ForkThemeSpec.onyx.roles(isDark: true).canvas)
        XCTAssertEqual(parsed.roles(isDark: false).text, ForkThemeSpec.onyx.roles(isDark: false).text)
    }
}
