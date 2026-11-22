import Foundation
import XCTest
@testable import HermesMobile

final class ForkCardGalleryTests: XCTestCase {
    private func resource(_ name: String, ext: String, isSnapshot: Bool = false) throws -> Data {
        #if os(Linux)
        let repo = try XCTUnwrap(ProcessInfo.processInfo.environment["HERMEX_TEST_REPO"])
        let directory = isSnapshot ? "HermesMobileTests/Fork" : "HermesMobile/Resources/EphemeralGallery"
        let url = URL(fileURLWithPath: repo).appendingPathComponent(directory).appendingPathComponent(ext.isEmpty ? name : name + "." + ext)
        #else
        let bundle = isSnapshot ? Bundle(for: Self.self) : .main
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: ext.isEmpty ? nil : ext,
                                          subdirectory: isSnapshot ? nil : "EphemeralGallery"))
        #endif
        return try Data(contentsOf: url)
    }

    func testEveryFixtureIsCoveredAndMountsAValidPresentation() throws {
        let data = try resource("catalog", ext: "json")
        let catalog = try JSONDecoder().decode(ForkCardCatalog.self, from: data)
        let gallery = try ForkCardGallery.parse(data)
        XCTAssertEqual(gallery.sections.map(\.id), catalog.kinds.map(\.kind))
        XCTAssertEqual(gallery.sections.flatMap(\.cells).count, catalog.count.fixtures)
        XCTAssertEqual(gallery.version, try String(decoding: resource("VERSION", ext: ""), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines))
        for (section, kind) in zip(gallery.sections, catalog.kinds) {
            XCTAssertEqual(section.cells.map(\.id), kind.fixtures.map(\.id))
            for (cell, fixture) in zip(section.cells, kind.fixtures) {
                XCTAssertEqual(cell.fixture.card, fixture.card)
                XCTAssertEqual(cell.content == .unavailable, fixture.state == .unavailable, fixture.id)
                if case .board(let board, let props) = cell.content {
                    XCTAssertEqual(props, fixture.props)
                    XCTAssertTrue(board.isFullyRendered)
                    XCTAssertEqual(props["label"], .string(board.title))
                    guard case .stat(let title, .number(let value), let detail)? = board.panels.first,
                          case .number(let delta)? = props["delta"] else {
                        XCTFail("Expected a metric Stat: \(cell.id)")
                        continue
                    }
                    XCTAssertEqual(title, fixture.card.app)
                    XCTAssertEqual(props["value"], .number(value))
                    XCTAssertEqual(detail, delta.formatted(.number.sign(strategy: .always())) + "%")
                }
            }
        }
    }

    func testPresentationSnapshot() throws {
        let gallery = try ForkCardGallery.parse(resource("catalog", ext: "json"))
        var lines = [gallery.versionLabel]
        for section in gallery.sections {
            lines.append("[\(section.id)] \(section.title)")
            lines.append(contentsOf: section.cells.map { "\($0.id)\t\($0.fixture.state.rawValue)\t\($0.content.snapshotName)" })
        }
        let actual = lines.joined(separator: "\n") + "\n"
        XCTAssertFalse(actual.contains("undefined"))
        XCTAssertFalse(actual.contains("NaN"))
        XCTAssertEqual(actual, try String(decoding: resource("CardGallerySnapshot", ext: "txt", isSnapshot: true), as: UTF8.self))
    }

    func testUnsupportedSchemaAndMissingKindCoverageFail() throws {
        let data = try resource("catalog", ext: "json")
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        document["v"] = 1
        XCTAssertThrowsError(try ForkCardGallery.parse(JSONSerialization.data(withJSONObject: document))) {
            XCTAssertEqual($0 as? ForkCardGallery.Invalid, .version)
        }
        document["v"] = 0
        var kinds = try XCTUnwrap(document["kinds"] as? [[String: Any]])
        kinds[0]["fixtures"] = []
        document["kinds"] = kinds
        XCTAssertThrowsError(try ForkCardGallery.parse(JSONSerialization.data(withJSONObject: document))) {
            XCTAssertEqual($0 as? ForkCardGallery.Invalid, .coverage)
        }
    }

    func testPinnedGlideThemeLoads() throws {
        let theme = try ForkGalleryTheme.parse(resource("glide", ext: "json"))
        XCTAssertNotEqual(theme.color.light.card, theme.color.dark.card)
    }
}
