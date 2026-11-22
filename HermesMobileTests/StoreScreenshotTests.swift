import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import HermesMobile

@MainActor
final class StoreScreenshotTests: XCTestCase {
    private static let size = CGSize(width: 402, height: 874)
    private static let scale: CGFloat = 3
    private static let names = ["openui-board", "live-mode", "appearance-looks"]

    func testOpenUIBoard() async throws {
        let source = """
        root = Board("Release dashboard", "This week", [builds, reviews, checks])
        builds = Stat("Successful builds", 28, "Across all projects")
        reviews = BarChart("Reviews completed", "Reviews", [{label: "Mon", value: 5}, {label: "Tue", value: 8}, {label: "Wed", value: 12}])
        checks = Table("Release checklist", ["Check", "Status"], [["Unit tests", "Passed"], ["Accessibility", "Reviewed"], ["Release notes", "Ready"]])
        """
        guard case .ready(let board) = OpenUICatalog.inspect(source), board.isFullyRendered else {
            return XCTFail("The screenshot fixture must render as an OpenUI board.")
        }
        try await assertSnapshot("openui-board") {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: "Release planning").font(AppFont.largeTitle(weight: .bold))
                ForkOpenUIBoardView(source: source)
                Spacer()
            }
            .padding(24)
            .themedPageBackground()
        }
    }

    func testLiveMode() async throws {
        try await assertSnapshot("live-mode") {
            ForkLiveModeScreen(
                title: "Release planning", phase: .listening, level: 0,
                heard: "Summarize what’s ready to ship.", error: nil,
                orbStyle: .constant(.voice), onOrb: {}, onEnd: {}
            )
        }
    }

    func testAppearanceLooks() async throws {
        try await assertSnapshot("appearance-looks") {
            NavigationStack {
                AppList {
                    ForkAppearanceSections(lightTheme: .constant(.default), darkTheme: .constant(.default))
                }
                .settingsPage("Appearance")
            }
        }
    }

    private func assertSnapshot(
        _ name: String, @ViewBuilder content: () -> some View
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first)
        let defaultsName = "Hermex.StoreScreenshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let font = AppFontSettings.shared.family
        let storedFont = UserDefaults.standard.object(forKey: AppFontSettings.storageKey)
        if font != .sanFrancisco { AppFontSettings.shared.family = .sanFrancisco }
        defer {
            if font != .sanFrancisco {
                AppFontSettings.shared.family = font
                UserDefaults.standard.set(storedFont, forKey: AppFontSettings.storageKey)
            }
        }

        let appeared = expectation(description: "Screenshot surface appeared")
        let root = content()
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Color(.appCanvas))
            .environment(\.appAppearance, .default)
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.layoutDirection, .leftToRight)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.accessibilityReduceMotion, true)
            .defaultAppStorage(defaults)
            .transaction { $0.disablesAnimations = true }
            .onAppear { appeared.fulfill() }
        let host = UIHostingController(rootView: root)
        host.safeAreaRegions = []
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.size)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        await fulfillment(of: [appeared], timeout: 5)
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.scale
        format.opaque = true
        let bounds = CGRect(origin: .zero, size: Self.size)
        var rendered = false
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            rendered = host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered)
        let png = try XCTUnwrap(image.pngData())
        let actual = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertEqual(actual.width, 1206)
        XCTAssertEqual(actual.height, 2622)
        let pixels = try rgba(actual)
        let hasContent = pixels.withUnsafeBytes { storage in
            let words = storage.bindMemory(to: UInt32.self)
            return words.first.map { first in words.contains { $0 != first } } ?? false
        }
        XCTAssertTrue(hasContent, "\(name) rendered as a flat color")

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let environment = ProcessInfo.processInfo.environment
        if environment["HERMEX_RECORD_STORE_SCREENSHOTS"] == "1" { return }

        let bundle = Bundle(for: StoreScreenshotTests.self)
        let references = Self.names.compactMap {
            bundle.url(forResource: $0, withExtension: "png", subdirectory: "StoreScreenshotGoldens")
        }
        if references.isEmpty, environment["HERMEX_REQUIRE_STORE_GOLDENS"] != "1" {
            throw XCTSkip("Rendered \(name); comparison awaits reviewed PNGs. See docs/store-screenshot-goldens.md.")
        }
        XCTAssertEqual(references.count, Self.names.count, "Commit all three reviewed PNGs together.")
        let reference = try XCTUnwrap(references.first { $0.deletingPathExtension().lastPathComponent == name })
        let expected = try XCTUnwrap(UIImage(contentsOfFile: reference.path)?.cgImage)
        guard expected.width == actual.width, expected.height == actual.height else {
            return XCTFail("\(name) golden has the wrong dimensions")
        }
        let expectedPixels = try rgba(expected)
        if pixels != expectedPixels {
            let original = XCTAttachment(data: try Data(contentsOf: reference), uniformTypeIdentifier: UTType.png.identifier)
            original.name = "\(name)-expected"
            original.lifetime = .keepAlways
            add(original)
            XCTFail("\(name) differs from the reviewed golden. Inspect the actual and expected PNGs.")
        }
    }

    private func rgba(_ image: CGImage) throws -> Data {
        let width = image.width
        let height = image.height
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = Data(count: width * height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: width, height: height,
                                                 bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }
}
