import Foundation

struct ForkRGBA: Equatable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let white = ForkRGBA(red: 1, green: 1, blue: 1)
    static let black = ForkRGBA(red: 0, green: 0, blue: 0)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
              let value = UInt64(digits, radix: 16) else { return nil }
        let rgb = digits.count == 8 ? value >> 8 : value
        let alpha = digits.count == 8 ? Double(value & 0xFF) / 255 : 1
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, alpha: alpha)
    }

    var hex: String {
        func byte(_ value: Double) -> String { String(format: "%02X", Int((value * 255).rounded())) }
        let rgb = "#" + byte(red) + byte(green) + byte(blue)
        return alpha >= 1 ? rgb : rgb + byte(alpha)
    }

    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(with other: ForkRGBA) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func over(_ background: ForkRGBA) -> ForkRGBA {
        guard alpha < 1 else { return self }
        return ForkRGBA(red: red * alpha + background.red * (1 - alpha),
                        green: green * alpha + background.green * (1 - alpha),
                        blue: blue * alpha + background.blue * (1 - alpha))
    }

    func mixed(toward target: ForkRGBA, amount: Double) -> ForkRGBA {
        ForkRGBA(red: red + (target.red - red) * amount, green: green + (target.green - green) * amount,
                 blue: blue + (target.blue - blue) * amount, alpha: alpha)
    }

    func withAlpha(_ value: Double) -> ForkRGBA {
        ForkRGBA(red: red, green: green, blue: blue, alpha: value)
    }

    var readableForeground: ForkRGBA {
        Self.white.contrast(with: self) >= Self.black.contrast(with: self) ? .white : .black
    }

    func readable(on backgrounds: [ForkRGBA], minimum: Double, toward target: ForkRGBA) -> ForkRGBA {
        for step in 0...20 {
            let candidate = mixed(toward: target, amount: Double(step) / 20).withAlpha(1)
            if backgrounds.allSatisfy({ candidate.contrast(with: $0) >= minimum }) { return candidate }
        }
        return target
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
