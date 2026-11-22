import Foundation

struct ForkPaletteRoles: Equatable, Sendable {
    var canvas, surface, raised, groupedCanvas, groupedSurface, groupedRaised: ForkRGBA
    var text, textSecondary, textTertiary, placeholder: ForkRGBA
    var separator, accent, onAccent, link, code, inlineCode, userBubble: ForkRGBA

    static let minimumContrast = 4.5

    var foregrounds: [ForkRGBA] { [text, textSecondary, textTertiary, placeholder, accent] }
    var textBackgrounds: [ForkRGBA] { [canvas, surface, code] }
}

extension ForkThemeSpec {
    static let baseDark: [String: ForkRGBA] = hexes([
        "background": "#121214", "surface": "#1C1C1F", "surface2": "#26262A", "surface3": "#303035",
        "text": "#F2F2F3", "text2": "#C4C4C9", "text3": "#9A9AA0", "textMuted": "#8A8A90",
        "accent": "#8FA2FF", "stroke": "#FFFFFF1F",
    ])

    static let baseLight: [String: ForkRGBA] = hexes([
        "background": "#FFFFFF", "surface": "#F4F4F5", "surface2": "#E9E9EB", "surface3": "#DEDEE1",
        "text": "#1C1C1E", "text2": "#3C3C43", "text3": "#5F5F66", "textMuted": "#66666D",
        "accent": "#3050D8", "stroke": "#0000001F",
    ])

    func roles(isDark: Bool) -> ForkPaletteRoles {
        let own = tokens(isDark: isDark)
        let fallback = isDark ? Self.baseDark : Self.baseLight
        func pick(_ names: String...) -> ForkRGBA? { names.lazy.compactMap { own[$0] }.first }
        func base(_ name: String) -> ForkRGBA { fallback[name]! }

        let canvas = (pick("background") ?? base("background")).over(isDark ? .black : .white)
        func solid(_ color: ForkRGBA) -> ForkRGBA { color.over(canvas) }
        let surface = solid(pick("surface", "sheet") ?? base("surface"))
        let raised = solid(pick("surface2", "surface3", "surface") ?? base("surface2"))
        let code = solid(pick("well", "surface2", "input") ?? base("surface2"))
        let inlineCode = solid(pick("surface2", "input", "surface") ?? base("surface2"))
        let separator = pick("stroke", "strokeStrong") ?? base("stroke")

        let backgrounds = [canvas, surface, code]
        let toward: ForkRGBA = isDark ? .white : .black
        func readable(_ color: ForkRGBA) -> ForkRGBA {
            color.over(canvas).readable(on: backgrounds, minimum: ForkPaletteRoles.minimumContrast, toward: toward)
        }
        let text = readable(pick("text") ?? base("text"))
        let textSecondary = readable(pick("text2", "text3") ?? base("text2"))
        let textTertiary = readable(pick("text3", "text2") ?? base("text3"))
        let placeholder = readable(pick("textMuted", "text3") ?? base("textMuted"))
        let accent = readable(pick("accent", "accentText") ?? base("accent"))
        let link = readable(pick("accentText", "accent") ?? base("accent"))
        let bubble = solid(pick("userBubble", "surface3", "surface2") ?? base("surface3"))
        let userBubble = bubble.contrast(with: text) >= ForkPaletteRoles.minimumContrast ? bubble : raised
        var onAccent = (pick("onAccent") ?? accent.readableForeground).over(accent)
        if onAccent.contrast(with: accent) < ForkPaletteRoles.minimumContrast { onAccent = accent.readableForeground }

        return ForkPaletteRoles(
            canvas: canvas, surface: surface, raised: raised,
            groupedCanvas: canvas, groupedSurface: surface, groupedRaised: raised,
            text: text, textSecondary: textSecondary, textTertiary: textTertiary, placeholder: placeholder,
            separator: separator, accent: accent, onAccent: onAccent, link: link,
            code: code, inlineCode: inlineCode, userBubble: userBubble
        )
    }

    init(id: String = customID, name: String, lightRoles: ForkPaletteRoles, darkRoles: ForkPaletteRoles) {
        func tokens(_ roles: ForkPaletteRoles) -> [String: ForkRGBA] {
            [
                "background": roles.canvas, "surface": roles.surface, "surface2": roles.raised,
                "well": roles.code, "input": roles.inlineCode, "userBubble": roles.userBubble,
                "text": roles.text, "text2": roles.textSecondary, "text3": roles.textTertiary,
                "textMuted": roles.placeholder, "accent": roles.accent, "onAccent": roles.onAccent,
                "accentText": roles.link, "stroke": roles.separator,
            ]
        }
        self.init(id: id, name: name, dark: tokens(darkRoles), light: tokens(lightRoles))
    }

    static let presets: [ForkThemeSpec] = [onyx, dashGold]

    static let onyx = ForkThemeSpec(id: "onyx", name: "Onyx", dark: hexes([
        "background": "#000000", "surface": "#0F0F0F", "surface2": "#1A1A1A", "surface3": "#242424",
        "well": "#0A0A0A", "sheet": "#141414", "input": "#141414", "userBubble": "#242424",
        "text": "#FFFFFF", "text2": "#D6D6D6", "text3": "#8C8C8C", "textMuted": "#8C8C8C",
        "accent": "#FFFFFF", "onAccent": "#000000", "accentText": "#FFFFFF", "stroke": "#FFFFFF14",
    ]), light: hexes([
        "background": "#FFFFFF", "surface": "#F7F7F7", "surface2": "#F0F0F0", "surface3": "#E6E6E6",
        "well": "#F5F5F5", "input": "#F4F4F4", "userBubble": "#F0F0F0",
        "text": "#0A0A0A", "text2": "#2A2A2A", "text3": "#5E5E5E", "textMuted": "#5E5E5E",
        "accent": "#0A0A0A", "onAccent": "#FFFFFF", "accentText": "#0A0A0A", "stroke": "#0A0A0A14",
    ]), glow: false)

    static let dashGold = ForkThemeSpec(id: "dash", name: "Dash Gold", dark: hexes([
        "background": "#000000", "surface": "#121212", "surface2": "#1C1C1C", "surface3": "#262626",
        "sheet": "#121212", "input": "#121212", "userBubble": "#1F1F1F", "onUserBubble": "#ECE8DF",
        "text": "#F2F2F2", "text2": "#B4AFA3", "text3": "#8B8B8B", "textMuted": "#8B8B8B",
        "accent": "#E6CD96", "onAccent": "#000000", "accentText": "#E6CD96", "accentSoft": "#E6CD9624",
        "stroke": "#ECE8DF1A", "strokeStrong": "#ECE8DF29",
        "danger": "#FF6B6B", "success": "#34C759", "warning": "#FFB020",
    ]), light: hexes([
        "accent": "#7A5C14", "onAccent": "#FFFFFF", "accentText": "#7A5C14", "accentSoft": "#7A5C141A",
        "userBubble": "#7A5C14", "onUserBubble": "#FFFFFF",
    ]))

    private static func hexes(_ raw: [String: String]) -> [String: ForkRGBA] {
        raw.compactMapValues(ForkRGBA.init(hex:))
    }
}
