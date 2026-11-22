import UIKit
import SwiftUI
import XCTest
@testable import HermesMobile

@MainActor
final class ForkCardGalleryRenderingTests: XCTestCase {
    func testEveryFixtureRendersAndRepresentativeSnapshotsAreAttached() throws {
        let gallery = try XCTUnwrap(ForkEphemeralUI.gallery(), "the app bundles EphemeralUI/catalog.json and coverage.json")
        let representatives: Set<String> = ["metric/npm", "sculpt/blender", "fleet-hosts/k3s/unavailable"]
        var attached: Set<String> = []
        for cell in gallery.cells {
            let content = ForkCardCellView(cell: cell)
                .frame(width: 320, alignment: .leading)
                .padding()
            let renderer = ImageRenderer(content: content.environment(\.colorScheme, .light))
            let image = try XCTUnwrap(renderer.uiImage, cell.id)
            XCTAssertGreaterThan(image.size.height, 40, cell.id)
            if representatives.contains(cell.id) {
                attach(image, name: cell.id + " (light)")
                let dark = ImageRenderer(content: content.environment(\.colorScheme, .dark))
                attach(try XCTUnwrap(dark.uiImage, cell.id), name: cell.id + " (dark)")
                attached.insert(cell.id)
            }
        }
        XCTAssertEqual(attached, representatives)
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
