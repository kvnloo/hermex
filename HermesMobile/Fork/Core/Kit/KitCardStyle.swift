import Foundation

enum KitCardStyle: String, CaseIterable, Equatable, Sendable {
    case appTheme
    case serviceNative

    static let storageKey = "fork.kitCards.style"
    static let defaultValue = KitCardStyle.appTheme

    init(stored: String?) {
        self = stored.flatMap(KitCardStyle.init(rawValue:)) ?? Self.defaultValue
    }

    func skin(for app: String) -> KitCardSkin {
        guard self == .serviceNative, let brand = KitServiceBrand.brand(for: app) else { return .appTheme }
        return .service(brand)
    }
}

enum KitCardSkin: Equatable, Sendable {
    case appTheme
    case service(KitServiceBrand)
}

struct KitPalette: Equatable, Sendable {
    let card: UInt32
    let raised: UInt32
    let text: UInt32
    let secondary: UInt32
    let border: UInt32
    let accent: UInt32
    let accentInk: UInt32

    var textContrast: Double { KitPalette.contrast(text, card) }
    var secondaryContrast: Double { KitPalette.contrast(secondary, card) }

    static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((rgb >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

enum KitFontDesign: String, Equatable, Sendable {
    case standard
    case rounded
    case monospaced
}

struct KitServiceBrand: Equatable, Sendable {
    let id: String
    let monogram: String
    let light: KitPalette
    let dark: KitPalette
    let corner: Double
    let rowSpacing: Double
    let font: KitFontDesign
    let pillButtons: Bool

    func palette(dark isDark: Bool) -> KitPalette { isDark ? dark : light }

    static func brand(for app: String) -> KitServiceBrand? {
        if let brand = all[app] { return brand }
        return aliases[app].flatMap { all[$0] }.map { $0.renamed(app) }
    }

    private func renamed(_ app: String) -> KitServiceBrand {
        KitServiceBrand(id: app, monogram: monogram, light: light, dark: dark, corner: corner, rowSpacing: rowSpacing, font: font,
                        pillButtons: pillButtons)
    }

    static let aliases: [String: String] = ["github-actions": "github", "outlook": "gmail", "proton-mail": "gmail",
                                            "youtube": "spotify", "apple-music": "spotify", "lyft": "uber", "bolt": "uber"]

    static let all: [String: KitServiceBrand] = Dictionary(uniqueKeysWithValues: [
        KitServiceBrand(id: "gmail", monogram: "M",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xF2F6FC, text: 0x1F1F1F, secondary: 0x444746, border: 0xE0E3E7,
                                          accent: 0x0B57D0, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x1F1F1F, raised: 0x2D2F31, text: 0xE3E3E3, secondary: 0xC4C7C5, border: 0x444746,
                                         accent: 0xA8C7FA, accentInk: 0x062E6F),
                        corner: 20, rowSpacing: 10, font: .standard, pillButtons: true),
        KitServiceBrand(id: "github", monogram: "GH",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xF6F8FA, text: 0x1F2328, secondary: 0x59636E, border: 0xD1D9E0,
                                          accent: 0x0969DA, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x0D1117, raised: 0x161B22, text: 0xF0F6FC, secondary: 0x9198A1, border: 0x30363D,
                                         accent: 0x58A6FF, accentInk: 0x0D1117),
                        corner: 6, rowSpacing: 6, font: .standard, pillButtons: false),
        KitServiceBrand(id: "gitlab", monogram: "GL",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xFBFAFD, text: 0x28272D, secondary: 0x626168, border: 0xDCDCDE,
                                          accent: 0x1F75CB, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x18171D, raised: 0x28272D, text: 0xECECEF, secondary: 0xBFBFC3, border: 0x434248,
                                         accent: 0x63A6E9, accentInk: 0x18171D),
                        corner: 4, rowSpacing: 6, font: .standard, pillButtons: false),
        KitServiceBrand(id: "stripe", monogram: "S",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xF6F9FC, text: 0x0A2540, secondary: 0x425466, border: 0xE3E8EE,
                                          accent: 0x635BFF, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x191D30, raised: 0x22263C, text: 0xF3F1FF, secondary: 0xB9BFDB, border: 0x3C4260,
                                         accent: 0xB9A7FF, accentInk: 0x211448),
                        corner: 12, rowSpacing: 8, font: .standard, pillButtons: false),
        KitServiceBrand(id: "spotify", monogram: "\u{266B}",
                        light: KitPalette(card: 0x121212, raised: 0x202020, text: 0xFFFFFF, secondary: 0xB3B3B3, border: 0x333333,
                                          accent: 0x1ED760, accentInk: 0x101410),
                        dark: KitPalette(card: 0x121212, raised: 0x202020, text: 0xFFFFFF, secondary: 0xB3B3B3, border: 0x333333,
                                         accent: 0x1ED760, accentInk: 0x101410),
                        corner: 12, rowSpacing: 8, font: .standard, pillButtons: true),
        KitServiceBrand(id: "slack", monogram: "#",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xF8F8F8, text: 0x1D1C1D, secondary: 0x616061, border: 0xDDDDDD,
                                          accent: 0x4A154B, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x1A1D21, raised: 0x222529, text: 0xD1D2D3, secondary: 0xABABAD, border: 0x35373B,
                                         accent: 0x1D9BD1, accentInk: 0xFFFFFF),
                        corner: 8, rowSpacing: 6, font: .standard, pillButtons: false),
        KitServiceBrand(id: "uber", monogram: "U",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xF3F3F3, text: 0x000000, secondary: 0x5E5E5E, border: 0xE2E2E2,
                                          accent: 0x000000, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x000000, raised: 0x1F1F1F, text: 0xFFFFFF, secondary: 0xAFAFAF, border: 0x333333,
                                         accent: 0xFFFFFF, accentInk: 0x000000),
                        corner: 12, rowSpacing: 10, font: .standard, pillButtons: true),
        KitServiceBrand(id: "linear", monogram: "L",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xF4F5F8, text: 0x282A30, secondary: 0x6B6F76, border: 0xE6E6E6,
                                          accent: 0x5E6AD2, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x151516, raised: 0x1C1C1F, text: 0xF7F8F8, secondary: 0x9C9DA1, border: 0x2E2E32,
                                         accent: 0x8B93F2, accentInk: 0x151516),
                        corner: 8, rowSpacing: 6, font: .standard, pillButtons: false),
        KitServiceBrand(id: "npm", monogram: "n",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xF7F7F7, text: 0x111111, secondary: 0x555555, border: 0xE5E5E5,
                                          accent: 0xC12127, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x1A1A1A, raised: 0x262626, text: 0xF5F5F5, secondary: 0xB0B0B0, border: 0x3A3A3A,
                                         accent: 0xFF6B6F, accentInk: 0x1A1A1A),
                        corner: 4, rowSpacing: 6, font: .monospaced, pillButtons: false),
        KitServiceBrand(id: "figma", monogram: "F",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xF5F5F5, text: 0x1E1E1E, secondary: 0x5C5C5C, border: 0xE6E6E6,
                                          accent: 0x0D99FF, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x2C2C2C, raised: 0x383838, text: 0xFFFFFF, secondary: 0xB3B3B3, border: 0x444444,
                                         accent: 0x0D99FF, accentInk: 0xFFFFFF),
                        corner: 8, rowSpacing: 6, font: .standard, pillButtons: false),
        KitServiceBrand(id: "pagerduty", monogram: "P",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xF4F6F6, text: 0x121212, secondary: 0x4F5658, border: 0xDADEE0,
                                          accent: 0x06AC38, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x0F1A14, raised: 0x18261E, text: 0xEEF4F0, secondary: 0xA9BDB1, border: 0x2D3F34,
                                         accent: 0x4DD47A, accentInk: 0x0F1A14),
                        corner: 6, rowSpacing: 6, font: .standard, pillButtons: false),
        KitServiceBrand(id: "shopify", monogram: "S",
                        light: KitPalette(card: 0xFFFFFF, raised: 0xF7F7F7, text: 0x303030, secondary: 0x616161, border: 0xE3E3E3,
                                          accent: 0x008060, accentInk: 0xFFFFFF),
                        dark: KitPalette(card: 0x1A1A1A, raised: 0x262626, text: 0xF1F1F1, secondary: 0xB5B5B5, border: 0x3B3B3B,
                                         accent: 0x36C28F, accentInk: 0x0B1F18),
                        corner: 12, rowSpacing: 8, font: .standard, pillButtons: false),
    ].map { ($0.id, $0) })
}
