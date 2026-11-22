import Foundation

enum ForkSharedThemeError: Error, Equatable {
    case invalidJSON(String)
    case unsupportedShape(Int?)
    case badColor(String, String)
    case badEasing(String, String)
    case badTracking(String, String)
}

struct ForkBrand: Equatable, Sendable {
    let name: String
    let appID: String
    let tagline: String
    let mark: ForkRGBA
    let accent: ForkRGBA
    let accentInk: ForkRGBA
}

struct ForkTypeScale: Equatable, Sendable {
    let families: [String: String]
    let baseSize: Double
    let lineHeight: Double
    let sizes: [String: Double]
    let trackingEm: [String: Double]
}

struct ForkCubicBezier: Equatable, Sendable {
    let x1, y1, x2, y2: Double
}

struct ForkSpringTokens: Equatable, Sendable, Decodable {
    let stiffness: Double
    let damping: Double
}

struct ForkMotionSpeed: Equatable, Sendable, Decodable {
    let `default`: Double
    let min: Double
    let max: Double
    let turbo: Double

    func clamped(_ speed: Double) -> Double { Swift.min(Swift.max(speed, min), max) }
}

struct ForkMotionTokens: Equatable, Sendable {
    let durationsMS: [String: Double]
    let easings: [String: ForkCubicBezier]
    let springs: [String: ForkSpringTokens]
    let speed: ForkMotionSpeed
    let reducedMotionIsZero: Bool

    func seconds(_ name: String, speed requested: Double? = nil, reduceMotion: Bool = false) -> Double? {
        guard let milliseconds = durationsMS[name] else { return nil }
        if reduceMotion, reducedMotionIsZero { return 0 }
        return milliseconds / 1000 / speed.clamped(requested ?? speed.default)
    }
}

struct ForkGlassLevel: Equatable, Sendable, Decodable {
    let blur: Double
    let saturate: Double
    let tint: Double?
}

struct ForkSharedTheme: Equatable, Sendable {
    static let readableShape = 0

    let id: String
    let name: String
    let version: String
    let brand: ForkBrand
    let light: [String: ForkRGBA]
    let dark: [String: ForkRGBA]
    let radius: [String: Double]
    let space: [String: Double]
    let type: ForkTypeScale
    let motion: ForkMotionTokens
    let glass: [String: ForkGlassLevel]

    func palette(isDark: Bool) -> [String: ForkRGBA] { isDark ? dark : light }

    var glassLevels: [(name: String, level: ForkGlassLevel)] {
        glass.map { (name: $0.key, level: $0.value) }.sorted { ($0.level.blur, $0.name) < ($1.level.blur, $1.name) }
    }

    static func parse(_ data: Data) throws -> ForkSharedTheme {
        let decoder = JSONDecoder()
        let shape: Int?
        do { shape = try decoder.decode(Shape.self, from: data).v } catch { throw ForkSharedThemeError.invalidJSON("v") }
        guard shape == readableShape else { throw ForkSharedThemeError.unsupportedShape(shape) }
        let wire: Wire
        do { wire = try decoder.decode(Wire.self, from: data) } catch {
            throw ForkSharedThemeError.invalidJSON(String(describing: error))
        }
        return try ForkSharedTheme(wire)
    }

    private init(_ wire: Wire) throws {
        func color(_ path: String, _ text: String) throws -> ForkRGBA {
            guard let value = ForkRGBA(hex: text) else { throw ForkSharedThemeError.badColor(path, text) }
            return value
        }
        func palette(_ scheme: String) throws -> [String: ForkRGBA] {
            var out: [String: ForkRGBA] = [:]
            for (token, text) in wire.color[scheme] ?? [:] { out[token] = try color("color.\(scheme).\(token)", text) }
            return out
        }
        var easings: [String: ForkCubicBezier] = [:]
        for (name, text) in wire.motion.easing {
            guard let curve = Self.cubicBezier(text) else { throw ForkSharedThemeError.badEasing(name, text) }
            easings[name] = curve
        }
        var tracking: [String: Double] = [:]
        for (name, text) in wire.type.tracking {
            guard text.hasSuffix("em"), let value = Double(text.dropLast(2)) else {
                throw ForkSharedThemeError.badTracking(name, text)
            }
            tracking[name] = value
        }
        id = wire.id
        name = wire.name
        version = wire.version
        brand = ForkBrand(name: wire.brand.name, appID: wire.brand.appId, tagline: wire.brand.tagline,
                          mark: try color("brand.mark", wire.brand.mark), accent: try color("brand.accent", wire.brand.accent),
                          accentInk: try color("brand.accentInk", wire.brand.accentInk))
        light = try palette("light")
        dark = try palette("dark")
        radius = wire.radius
        space = wire.space
        type = ForkTypeScale(families: wire.type.family, baseSize: wire.type.base.size, lineHeight: wire.type.base.lineHeight,
                             sizes: wire.type.size, trackingEm: tracking)
        motion = ForkMotionTokens(durationsMS: wire.motion.duration, easings: easings, springs: wire.motion.spring,
                                  speed: wire.motion.speed, reducedMotionIsZero: wire.motion.reducedMotion == "zero")
        glass = wire.glass
    }

    static func cubicBezier(_ text: String) -> ForkCubicBezier? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("cubic-bezier("), trimmed.hasSuffix(")") else { return nil }
        let numbers = trimmed.dropFirst("cubic-bezier(".count).dropLast()
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4 else { return nil }
        return ForkCubicBezier(x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3])
    }

    private struct Shape: Decodable { let v: Int? }

    private struct Wire: Decodable {
        struct Brand: Decodable { let name, appId, tagline, mark, accent, accentInk: String }
        struct TypeWire: Decodable {
            struct Base: Decodable { let size, lineHeight: Double }
            let family: [String: String]
            let base: Base
            let size: [String: Double]
            let tracking: [String: String]
        }
        struct Motion: Decodable {
            let duration: [String: Double]
            let easing: [String: String]
            let spring: [String: ForkSpringTokens]
            let speed: ForkMotionSpeed
            let reducedMotion: String?
        }
        let id, name, version: String
        let brand: Brand
        let color: [String: [String: String]]
        let radius: [String: Double]
        let space: [String: Double]
        let type: TypeWire
        let motion: Motion
        let glass: [String: ForkGlassLevel]
    }
}

extension ForkSharedTheme {
    static let roleSources: [(role: String, tokens: [String])] = [
        ("background", ["bg"]), ("surface", ["card"]), ("surface2", ["accent", "muted"]),
        ("surface3", ["secondary", "accent"]), ("well", ["muted"]), ("sheet", ["popover", "card"]),
        ("sidebar", ["sidebar"]), ("userBubble", ["message"]), ("onUserBubble", ["fg"]),
        ("text", ["fg"]), ("text2", ["mutedFg"]), ("text3", ["faint", "mutedFg"]), ("textMuted", ["mutedFg"]),
        ("accent", ["primary"]), ("onAccent", ["primaryFg"]), ("accentText", ["primary"]),
        ("stroke", ["border"]), ("danger", ["danger"]), ("success", ["success"]), ("warning", ["warning"]),
    ]

    func roles(of palette: [String: ForkRGBA]) -> [String: ForkRGBA] {
        var out: [String: ForkRGBA] = [:]
        for (role, tokens) in Self.roleSources {
            if let color = tokens.lazy.compactMap({ palette[$0] }).first { out[role] = color }
        }
        return out
    }

    var spec: ForkThemeSpec {
        ForkThemeSpec(id: id, name: brand.name, dark: roles(of: dark), light: roles(of: light))
    }
}
