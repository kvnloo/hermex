import Foundation

enum OpenUICheck {
    static func bad(_ node: OpenUIValue, _ message: String) -> OpenUIFault {
        OpenUIFault(message, node.position)
    }

    static func noUnsupportedCalls(_ node: OpenUIValue) throws {
        switch node {
        case .call(let name, let args, _):
            if name != "Board" && !OpenUICatalog.panelTypes.contains(name) {
                throw bad(node, "Unsupported or unknown component: \(name)")
            }
            try args.forEach(noUnsupportedCalls)
        case .array(let items, _): try items.forEach(noUnsupportedCalls)
        case .object(let fields, _): try fields.values.forEach(noUnsupportedCalls)
        default: break
        }
    }

    static func call(_ node: OpenUIValue, _ type: String) throws -> (String, [OpenUIValue], OpenUIPosition) {
        guard case .call(let name, let args, let at) = node, name == type else { throw bad(node, "Expected \(type) component.") }
        return (name, args, at)
    }

    static func arity(_ name: String, _ args: [OpenUIValue], _ at: OpenUIPosition, _ min: Int, _ max: Int? = nil) throws {
        guard args.count >= min, args.count <= (max ?? min) else {
            throw OpenUIFault("\(name) has an invalid number of arguments.", at)
        }
    }

    static func string(_ node: OpenUIValue, _ label: String, min: Int = 0, max: Int) throws -> String {
        guard case .string(let value, _) = node, value.utf16.count >= min, value.utf16.count <= max else {
            throw bad(node, "\(label) must be a string of \(min)–\(max) characters.")
        }
        return value
    }

    static func number(_ node: OpenUIValue, _ label: String, min: Double = 0, max: Double = OpenUICatalog.maxValue,
                       integer: Bool = false) throws -> Double {
        guard case .number(let value, _) = node, value.isFinite, value >= min, value <= max,
              !integer || value.rounded(.towardZero) == value else {
            throw bad(node, "\(label) is out of range.")
        }
        return value
    }

    static func boolean(_ node: OpenUIValue, _ label: String) throws {
        guard case .boolean = node else { throw bad(node, "\(label) must be boolean.") }
    }

    static func array(_ node: OpenUIValue, _ label: String, min: Int = 0, max: Int) throws -> [OpenUIValue] {
        guard case .array(let items, _) = node, items.count >= min, items.count <= max else {
            throw bad(node, "\(label) has an invalid length.")
        }
        return items
    }

    static func object(_ node: OpenUIValue, _ label: String) throws -> [String: OpenUIValue] {
        guard case .object(let fields, _) = node else { throw bad(node, "\(label) must be an object.") }
        return fields
    }

    static func field(_ object: [String: OpenUIValue], _ name: String, _ parent: OpenUIValue) throws -> OpenUIValue {
        guard let value = object[name] else { throw bad(parent, "Missing field: \(name).") }
        return value
    }

    static func text(_ object: [String: OpenUIValue], _ key: String, _ parent: OpenUIValue, min: Int = 0, max: Int = 200) throws -> String {
        try string(field(object, key, parent), key, min: min, max: max)
    }

    static func number(_ object: [String: OpenUIValue], _ key: String, _ parent: OpenUIValue, min: Double = 0,
                       max: Double = OpenUICatalog.maxValue, integer: Bool = false) throws -> Double {
        try number(field(object, key, parent), key, min: min, max: max, integer: integer)
    }

    static func optionalText(_ object: [String: OpenUIValue], _ key: String, _ max: Int) throws {
        if let value = object[key] { _ = try string(value, key, max: max) }
    }

    static func optionalNumber(_ object: [String: OpenUIValue], _ key: String, _ max: Double) throws {
        if let value = object[key] { _ = try number(value, key, max: max) }
    }

    static func choice(_ node: OpenUIValue, _ label: String, _ choices: Set<String>) throws -> String {
        let value = try string(node, label, max: 200)
        guard choices.contains(value) else { throw bad(node, "\(label) is not supported.") }
        return value
    }

    static func cell(_ node: OpenUIValue) throws -> OpenUICell {
        switch node {
        case .string: .text(try string(node, "cell", max: 400))
        case .number: .number(try number(node, "cell", min: -OpenUICatalog.maxValue))
        default: throw bad(node, "Table cells must be strings or numbers.")
        }
    }
}
