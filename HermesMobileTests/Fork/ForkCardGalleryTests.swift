import XCTest
@testable import HermesMobile

final class ForkCardGalleryTests: XCTestCase {
    private func vendored() throws -> (ForkCardCatalog, ForkCardGallery) {
        let catalog = try ForkCardCatalog.parse(ForkVendoredEphemeralUI.data("catalog.json"))
        let coverage = try ForkCardCoverage.parse(ForkVendoredEphemeralUI.data("coverage.json"))
        return (catalog, ForkCardGallery(catalog: catalog, coverage: coverage))
    }

    func testTheGalleryCoversExactlyTheCatalogKinds() throws {
        let (catalog, gallery) = try vendored()
        XCTAssertEqual(gallery.kinds, Set(catalog.kinds.map(\.kind)))
        XCTAssertEqual(gallery.uncoveredKinds, [])
        XCTAssertEqual(gallery.extraKinds, [])
        XCTAssertTrue(gallery.cells.allSatisfy { $0.support != nil })
    }

    func testANewKindWithoutACoverageDecisionIsCountedAsUncovered() throws {
        let (catalog, _) = try vendored()
        let added = ForkCardKind(kind: "orbit", label: "Orbit", group: "studio",
                                 fixtures: [ForkCardFixture(id: "orbit/a", state: "sample", props: [:])])
        let coverage = try ForkCardCoverage.parse(ForkVendoredEphemeralUI.data("coverage.json"))
        let gallery = ForkCardGallery(catalog: ForkCardCatalog(version: catalog.version, kinds: catalog.kinds + [added]),
                                      coverage: coverage)
        XCTAssertEqual(gallery.uncoveredKinds, ["orbit"])
        XCTAssertTrue(gallery.cells.contains { $0.id == "orbit/a" && $0.support == nil })
    }

    func testEveryFixtureMountsOneCellWithReadableTextAndEveryProp() throws {
        let (catalog, gallery) = try vendored()
        let fixtures = catalog.kinds.flatMap(\.fixtures)
        let cells = Dictionary(gallery.cells.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(gallery.cells.count, fixtures.count)
        XCTAssertEqual(Set(cells.keys), Set(fixtures.map(\.id)))
        for fixture in fixtures {
            let cell = try XCTUnwrap(cells[fixture.id])
            XCTAssertFalse(cell.label.isEmpty, cell.id)
            for word in ["undefined", "NaN"] { XCTAssertFalse(cell.text.contains(word), "\(cell.id): \(word)") }
            XCTAssertEqual(cell.lines.map(\.key), fixture.props.keys.sorted().filter { !ForkCardGallery.identityKeys.contains($0) })
            XCTAssertTrue(cell.lines.allSatisfy { !$0.value.isEmpty }, cell.id)
        }
    }

    func testOnlyUnavailableFixturesShowTheUnavailableState() throws {
        let (catalog, gallery) = try vendored()
        let unavailable = Set(catalog.kinds.flatMap(\.fixtures).filter { $0.state == "unavailable" }.map(\.id))
        XCTAssertFalse(unavailable.isEmpty)
        XCTAssertEqual(Set(gallery.cells.filter(\.isUnavailable).map(\.id)), unavailable)
        XCTAssertTrue(gallery.cells.filter { ["example", "input"].contains($0.state) }.allSatisfy { !$0.isUnavailable })
    }

    func testTheGalleryCarriesThePinnedCatalogVersionAndRefusesOtherShapes() throws {
        let (_, gallery) = try vendored()
        XCTAssertEqual(gallery.version, try ForkVendoredEphemeralUI.pinnedVersion("catalog.json"))
        XCTAssertThrowsError(try ForkCardCatalog.parse(Data(#"{"v": 1, "version": "9.0.0", "kinds": []}"#.utf8))) { error in
            XCTAssertEqual(error as? ForkCardCatalogError, .unsupportedShape(1))
        }
    }

    func testPropValuesSummarizeWithoutLosingNumbers() {
        XCTAssertEqual(ForkCardGallery.summary(.number(3)), "3")
        XCTAssertEqual(ForkCardGallery.summary(.number(0.71)), "0.71")
        XCTAssertEqual(ForkCardGallery.summary(.array([.string("a"), .number(2)])), "a, 2")
        XCTAssertEqual(ForkCardGallery.summary(.array([.object([:])])), "[1]")
        XCTAssertEqual(ForkCardGallery.summary(.object(["b": .bool(true), "a": .null])), "a: \u{2014}, b: true")
    }
}
