import XCTest
@testable import HermesMobile

final class KitCardTests: XCTestCase {
    private func library() throws -> KitCardLibrary {
        KitCardLibrary(catalog: try ForkCardCatalog.parse(ForkVendoredEphemeralUI.data("catalog.json")))
    }

    func testACardFenceDecodesKindAppTitleAndInputAndIgnoresHostFields() throws {
        let program = try KitCardProgram.parseFence(#"""
        {"kind": "merge", "app": "github", "title": "Ship it", "ttl": "pinned", "render": {"brand": "full"},
         "input": {"number": 7, "title": "Fix login", "state": "open", "head": "fix", "base": "main", "checks": [], "conflicts": 0}}
        """#)
        XCTAssertEqual(program.cards.count, 1)
        let card = try XCTUnwrap(program.cards.first)
        XCTAssertEqual(card.kind, "merge")
        XCTAssertEqual(card.app, "github")
        XCTAssertEqual(card.title, "Ship it")
        guard case .object(let input)? = card.input else { return XCTFail("input should decode as an object") }
        XCTAssertEqual(input["number"], .number(7))
    }

    func testACardFenceAcceptsAListOfCardsAndRefusesUnreadableOnes() throws {
        let list = try KitCardProgram.parseFence(#"{"title": "Today", "cards": [{"kind": "inbox"}, {"kind": "player", "app": "spotify"}]}"#)
        XCTAssertEqual(list.title, "Today")
        XCTAssertEqual(list.cards.map(\.kind), ["inbox", "player"])
        XCTAssertNil(list.cards.first?.app)
        XCTAssertThrowsError(try KitCardProgram.parseFence("not json"))
        XCTAssertThrowsError(try KitCardProgram.parseFence(#"{"app": "gmail"}"#))
        XCTAssertThrowsError(try KitCardProgram.parseFence(#"{"kind": 4}"#))
        let many = "[" + Array(repeating: #"{"kind": "inbox"}"#, count: KitCardProgram.maxCards + 1).joined(separator: ",") + "]"
        XCTAssertThrowsError(try KitCardProgram.parseFence(many))
    }

    func testEveryCatalogKindResolvesToAKitCardAndNeverToAPlaceholder() throws {
        let library = try library()
        XCTAssertEqual(library.catalog.kinds.count, 100)
        for kind in library.catalog.kinds {
            guard case .card(let model) = library.resolve(KitCardSpec(kind: kind.kind)) else {
                XCTFail("\(kind.kind) did not resolve")
                continue
            }
            XCTAssertFalse(model.isPlaceholder, kind.kind)
            XCTAssertFalse(model.title.isEmpty, kind.kind)
            XCTAssertNil(model.unavailableReason, kind.kind)
            XCTAssertFalse(model.appName.isEmpty, kind.kind)
            for word in ["undefined", "NaN", "null"] {
                XCTAssertFalse(model.accessibilityText.contains(word), "\(kind.kind): \(word)")
            }
        }
    }

    func testEveryAvailableFixtureMapsToAKitLayout() throws {
        let library = try library()
        for kind in library.catalog.kinds {
            for fixture in kind.fixtures {
                let model = KitCardMapper.model(kind: kind, fixture: fixture)
                if fixture.isUnavailable {
                    XCTAssertEqual(model.layout, .unavailable, fixture.id)
                    XCTAssertNotNil(model.unavailableReason, fixture.id)
                } else {
                    XCTAssertNotEqual(model.layout, .unavailable, fixture.id)
                    XCTAssertFalse(model.isPlaceholder, fixture.id)
                }
            }
        }
    }

    func testUnknownKindsAndAppsAreRefusedInsteadOfDrawnAsPlaceholders() throws {
        let library = try library()
        XCTAssertEqual(library.resolve(KitCardSpec(kind: "orbit")), .unknownKind("orbit"))
        XCTAssertEqual(library.resolve(KitCardSpec(kind: "inbox", app: "myspace")), .unknownApp(kind: "inbox", app: "myspace"))
    }

    func testServiceKindsKeepTheirShape() throws {
        let library = try library()
        func card(_ kind: String, _ app: String? = nil, input: ForkJSON? = nil) throws -> KitCardModel {
            guard case .card(let model) = library.resolve(KitCardSpec(kind: kind, app: app, input: input)) else {
                XCTFail("\(kind) did not resolve")
                throw KitCardProgramError.invalid(kind)
            }
            return model
        }

        let inbox = try card("inbox", "gmail")
        XCTAssertEqual(inbox.layout, .list)
        XCTAssertEqual(inbox.app, "gmail")
        XCTAssertEqual(inbox.appName, "Gmail")
        XCTAssertTrue(inbox.title.contains("invoice"))
        XCTAssertEqual(inbox.rows.first?.title, "Invoice #4471 is due Nov 14")

        let receipt = try card("receipt", "stripe")
        XCTAssertEqual(receipt.layout, .hero)
        XCTAssertEqual(receipt.hero?.value, "$1,240.00")
        XCTAssertEqual(receipt.hero?.caption, "Wayne Freight")

        let metric = try card("metric", "npm")
        XCTAssertEqual(metric.hero?.value, "12,840")
        XCTAssertEqual(metric.hero?.trend, 15.3)
        XCTAssertEqual(metric.title, "Active users")

        let ride = try card("ride", "uber")
        XCTAssertEqual(ride.route?.from, "Ferry Building")
        XCTAssertEqual(ride.route?.to, "SFO")
        XCTAssertEqual(ride.rows.map(\.title), ["Standard", "Comfort", "XL"])
        XCTAssertEqual(ride.rows.first?.trailing, "$38.12")

        let route = try card("route")
        XCTAssertEqual(route.layout, .route)
        XCTAssertEqual(route.route?.detail, "24 min")

        let merge = try card("merge", "github", input: .object([
            "number": .number(42), "title": .string("Fix login"), "state": .string("conflict"), "head": .string("fix"),
            "base": .string("main"), "conflicts": .number(2),
            "checks": .array([.object(["name": .string("Tests"), "status": .string("fail"), "detail": .string("3 failed")])]),
        ]))
        XCTAssertEqual(merge.title, "Fix login")
        XCTAssertEqual(merge.subtitle, "#42 \u{00B7} fix \u{2192} main")
        XCTAssertEqual(merge.status?.tone, .critical)
        XCTAssertEqual(merge.rows.first?.title, "Tests")
        XCTAssertEqual(merge.rows.first?.tone, .critical)
    }

    func testATitleOnTheSpecReplacesTheCardTitle() throws {
        guard case .card(let model) = try library().resolve(KitCardSpec(kind: "player", app: "spotify", title: "Now playing")) else {
            return XCTFail("player did not resolve")
        }
        XCTAssertEqual(model.title, "Now playing")
    }

    func testServiceMonogramsMeetSmallTextContrastInBothAppearances() {
        for brand in KitServiceBrand.all.values.sorted(by: { $0.id < $1.id }) {
            for dark in [false, true] {
                let palette = brand.palette(dark: dark)
                XCTAssertGreaterThanOrEqual(KitPalette.contrast(palette.accentInk, palette.accent), 4.5,
                                            "\(brand.id) monogram, dark: \(dark)")
            }
        }
    }

    func testStyleDefaultsToTheAppThemeAndServiceStyleFallsBackForUnbrandedApps() throws {
        XCTAssertEqual(KitCardStyle.defaultValue, .appTheme)
        XCTAssertEqual(KitCardStyle(stored: nil), .appTheme)
        XCTAssertEqual(KitCardStyle(stored: "garbage"), .appTheme)
        XCTAssertEqual(KitCardStyle(stored: KitCardStyle.serviceNative.rawValue), .serviceNative)
        XCTAssertEqual(KitCardStyle.appTheme.skin(for: "github"), .appTheme)
        XCTAssertEqual(KitCardStyle.serviceNative.skin(for: "github"), .service(try XCTUnwrap(KitServiceBrand.brand(for: "github"))))
        XCTAssertEqual(KitCardStyle.serviceNative.skin(for: "blender"), .appTheme)
        for app in ["gmail", "github", "stripe", "spotify", "slack", "uber"] {
            let brand = try XCTUnwrap(KitServiceBrand.brand(for: app), app)
            XCTAssertGreaterThanOrEqual(brand.dark.textContrast, 4.5, app)
            XCTAssertGreaterThanOrEqual(brand.light.textContrast, 4.5, app)
        }
    }
}
