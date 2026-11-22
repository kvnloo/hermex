import SwiftUI

enum ForkEphemeralUI {
    static let subdirectory = "EphemeralUI"

    static func data(_ name: String, in bundle: Bundle = .main) -> Data? {
        bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory).flatMap { try? Data(contentsOf: $0) }
    }

    static let theme: ForkSharedTheme? = data("glide").flatMap { try? ForkSharedTheme.parse($0) }

    static func gallery(in bundle: Bundle = .main) -> ForkCardGallery? {
        guard let catalog = data("catalog", in: bundle).flatMap({ try? ForkCardCatalog.parse($0) }),
              let coverage = data("coverage", in: bundle).flatMap({ try? ForkCardCoverage.parse($0) }) else { return nil }
        return ForkCardGallery(catalog: catalog, coverage: coverage)
    }
}

private struct ForkSharedThemeKey: EnvironmentKey {
    static let defaultValue: ForkSharedTheme? = ForkEphemeralUI.theme
}

extension EnvironmentValues {
    var forkSharedTheme: ForkSharedTheme? {
        get { self[ForkSharedThemeKey.self] }
        set { self[ForkSharedThemeKey.self] = newValue }
    }
}

extension ForkSharedTheme {
    func animation(_ duration: String, easing: String = "out", speed: Double? = nil, reduceMotion: Bool) -> Animation? {
        guard let seconds = motion.seconds(duration, speed: speed, reduceMotion: reduceMotion), seconds > 0 else { return nil }
        guard let curve = motion.easings[easing] else { return .easeOut(duration: seconds) }
        return .timingCurve(curve.x1, curve.y1, curve.x2, curve.y2, duration: seconds)
    }

    func corner(_ name: String) -> CGFloat? { radius[name].map { CGFloat($0) } }

    func spacing(_ name: String) -> CGFloat? { space[name].map { CGFloat($0 * (space["density"] ?? 1)) } }

    func material(glass name: String) -> Material? {
        guard let blur = glass[name]?.blur, blur > 0 else { return nil }
        switch blur {
        case ..<8: return .ultraThinMaterial
        case ..<20: return .thinMaterial
        case ..<32: return .regularMaterial
        default: return .thickMaterial
        }
    }
}
