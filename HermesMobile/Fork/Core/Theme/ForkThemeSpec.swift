import Foundation

enum ForkThemeError: Error, Equatable {
    case invalidJSON
    case notAnObject
    case missingName
    case rolesNotAnObject(String)
    case unknownRole(String)
    case notAHexString(String)
    case badColor(String, String)
    case badGlow
}

struct ForkThemeSpec: Equatable, Sendable {
    static let roles: [String] = [
        "background", "surface", "surface2", "surface3", "well", "thumb", "sheet", "input", "sidebar",
        "userBubble", "onUserBubble", "text", "text2", "text3", "textMuted", "accent", "onAccent", "accentText",
        "accentSoft", "inverse", "onInverse", "stroke", "strokeStrong", "danger", "success", "warning",
        "dangerSoft", "successSoft", "warningSoft",
    ]
    static let customID = "custom"

    let id: String
    let name: String
    let dark: [String: ForkRGBA]
    let light: [String: ForkRGBA]
    let glow: Bool?

    init(id: String, name: String, dark: [String: ForkRGBA] = [:], light: [String: ForkRGBA] = [:], glow: Bool? = nil) {
        self.id = id
        self.name = name
        self.dark = dark
        self.light = light
        self.glow = glow
    }

    func tokens(isDark: Bool) -> [String: ForkRGBA] { isDark ? dark : light }

    var ownsAccent: Bool { dark["accent"] != nil || light["accent"] != nil }

    static func parse(_ source: String) throws -> ForkThemeSpec {
        guard let data = source.data(using: .utf8), let json = try? JSONDecoder().decode(ForkJSON.self, from: data) else {
            throw ForkThemeError.invalidJSON
        }
        return try ForkThemeSpec(json: json)
    }

    init(json: ForkJSON) throws {
        guard case .object(let object) = json else { throw ForkThemeError.notAnObject }
        guard case .string(let rawName)? = object["name"],
              !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ForkThemeError.missingName
        }
        let glow: Bool?
        switch object["glow"] {
        case nil, .null?: glow = nil
        case .bool(let value)?: glow = value
        default: throw ForkThemeError.badGlow
        }
        var id = Self.customID
        if case .string(let raw)? = object["id"], !raw.isEmpty { id = raw }
        self.init(id: id, name: rawName.trimmingCharacters(in: .whitespacesAndNewlines),
                  dark: try Self.tokens(object, "dark"), light: try Self.tokens(object, "light"), glow: glow)
    }

    func encoded() -> String {
        func block(_ tokens: [String: ForkRGBA]) -> String {
            let ordered = Self.roles.filter { tokens[$0] != nil }
            guard !ordered.isEmpty else { return "{}" }
            let lines = ordered.map { "    \(Self.quote($0)): \(Self.quote(tokens[$0]!.hex))" }
            return "{\n" + lines.joined(separator: ",\n") + "\n  }"
        }
        var fields = ["  \"id\": \(Self.quote(id))", "  \"name\": \(Self.quote(name))"]
        if let glow { fields.append("  \"glow\": \(glow)") }
        fields.append("  \"dark\": \(block(dark))")
        fields.append("  \"light\": \(block(light))")
        return "{\n" + fields.joined(separator: ",\n") + "\n}"
    }

    private static func tokens(_ object: [String: ForkJSON], _ key: String) throws -> [String: ForkRGBA] {
        guard let raw = object[key], raw != .null else { return [:] }
        guard case .object(let map) = raw else { throw ForkThemeError.rolesNotAnObject(key) }
        var out: [String: ForkRGBA] = [:]
        for (role, value) in map {
            guard roles.contains(role) else { throw ForkThemeError.unknownRole(role) }
            guard case .string(let text) = value else { throw ForkThemeError.notAHexString(role) }
            guard let color = ForkRGBA(hex: text) else { throw ForkThemeError.badColor(role, text) }
            out[role] = color
        }
        return out
    }

    private static func quote(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

indirect enum ForkJSON: Decodable, Equatable, Sendable {
    case object([String: ForkJSON]), array([ForkJSON]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([ForkJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: ForkJSON].self)) }
    }
}
