import UIKit

final class ForkThemeStore: @unchecked Sendable {
    static let jsonKey = "fork.theme.customJSON"
    static let maximumImportBytes = 256 * 1024

    private static let shared = ForkThemeStore()
    private let lock = NSLock()
    private var cached: Entry?

    private struct Entry {
        let source: String
        let revision: String
        let spec: ForkThemeSpec
        let light: ThemePalette
        let dark: ThemePalette
    }

    static var title: String { spec().name }

    static func spec(in defaults: UserDefaults = .standard) -> ForkThemeSpec { shared.entry(in: defaults).spec }

    static func palette(isDark: Bool, in defaults: UserDefaults = .standard) -> ThemePalette {
        let entry = shared.entry(in: defaults)
        return isDark ? entry.dark : entry.light
    }

    static func revision(light: ColorTheme, dark: ColorTheme, in defaults: UserDefaults = .standard) -> String {
        light == .custom || dark == .custom ? shared.entry(in: defaults).revision : ""
    }

    static func save(_ spec: ForkThemeSpec, in defaults: UserDefaults = .standard) {
        defaults.set(spec.encoded(), forKey: jsonKey)
    }

    static func exportJSON(for appearance: AppAppearance, in defaults: UserDefaults = .standard) -> String {
        if appearance.lightTheme == .custom, appearance.darkTheme == .custom { return spec(in: defaults).encoded() }
        let name = appearance.lightTheme == appearance.darkTheme
            ? appearance.lightTheme.title
            : "\(appearance.lightTheme.title) + \(appearance.darkTheme.title)"
        return ForkThemeSpec(name: name, lightRoles: roles(of: appearance.palette(isDark: false), isDark: false),
                             darkRoles: roles(of: appearance.palette(isDark: true), isDark: true)).encoded()
    }

    private static func roles(of palette: ThemePalette, isDark: Bool) -> ForkPaletteRoles {
        let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        func rgba(_ color: UIColor) -> ForkRGBA {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return ForkRGBA(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
        }
        return ForkPaletteRoles(
            canvas: rgba(palette.canvas), surface: rgba(palette.surface), raised: rgba(palette.raised),
            groupedCanvas: rgba(palette.groupedCanvas), groupedSurface: rgba(palette.groupedSurface),
            groupedRaised: rgba(palette.groupedRaised), text: rgba(palette.text), textSecondary: rgba(palette.textSecondary),
            textTertiary: rgba(palette.textTertiary), placeholder: rgba(palette.placeholder), separator: rgba(palette.separator),
            accent: rgba(palette.accent), onAccent: rgba(palette.onAccent), link: rgba(palette.link), code: rgba(palette.code),
            inlineCode: rgba(palette.inlineCode), userBubble: rgba(palette.userBubble)
        )
    }

    private func entry(in defaults: UserDefaults = .standard) -> Entry {
        let source = defaults.string(forKey: Self.jsonKey) ?? ""
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.source == source { return cached }
        let spec = (try? ForkThemeSpec.parse(source)) ?? .onyx
        let entry = Entry(source: source, revision: Self.digest(source), spec: spec,
                          light: ThemePalette(roles: spec.roles(isDark: false), isDark: false),
                          dark: ThemePalette(roles: spec.roles(isDark: true), isDark: true))
        cached = entry
        return entry
    }

    private static func digest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

extension ThemePalette {
    convenience init(roles: ForkPaletteRoles, isDark: Bool) {
        func color(_ value: ForkRGBA) -> UIColor {
            UIColor(red: CGFloat(value.red), green: CGFloat(value.green), blue: CGFloat(value.blue), alpha: CGFloat(value.alpha))
        }
        let text = color(roles.text)
        self.init(
            canvas: color(roles.canvas), surface: color(roles.surface), raised: color(roles.raised),
            groupedCanvas: color(roles.groupedCanvas), groupedSurface: color(roles.groupedSurface),
            groupedRaised: color(roles.groupedRaised),
            text: text, textSecondary: color(roles.textSecondary), textTertiary: color(roles.textTertiary),
            placeholder: color(roles.placeholder),
            separator: color(roles.separator),
            fill: text.withAlphaComponent(isDark ? 0.36 : 0.2),
            fillSecondary: text.withAlphaComponent(isDark ? 0.32 : 0.16),
            fillTertiary: text.withAlphaComponent(isDark ? 0.24 : 0.12),
            accent: color(roles.accent), onAccent: color(roles.onAccent), link: color(roles.link),
            code: color(roles.code), inlineCode: color(roles.inlineCode), userBubble: color(roles.userBubble)
        )
    }
}
