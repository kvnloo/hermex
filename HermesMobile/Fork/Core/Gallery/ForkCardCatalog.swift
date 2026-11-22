import Foundation

enum ForkCardCatalogError: Error, Equatable {
    case invalidJSON(String)
    case unsupportedShape(Int?)
}

struct ForkCardFixture: Equatable, Sendable, Decodable {
    let id: String
    let state: String
    let props: [String: ForkJSON]

    var isUnavailable: Bool { state == "unavailable" }
}

struct ForkCardKind: Equatable, Sendable, Decodable {
    let kind: String
    let label: String
    let group: String
    let fixtures: [ForkCardFixture]
}

struct ForkCardCatalog: Equatable, Sendable {
    static let readableShape = 0

    let version: String
    let kinds: [ForkCardKind]

    static func parse(_ data: Data) throws -> ForkCardCatalog {
        let decoder = JSONDecoder()
        let shape: Int?
        do { shape = try decoder.decode(Shape.self, from: data).v } catch { throw ForkCardCatalogError.invalidJSON("v") }
        guard shape == readableShape else { throw ForkCardCatalogError.unsupportedShape(shape) }
        do {
            let wire = try decoder.decode(Wire.self, from: data)
            return ForkCardCatalog(version: wire.version, kinds: wire.kinds)
        } catch {
            throw ForkCardCatalogError.invalidJSON(String(describing: error))
        }
    }

    private struct Shape: Decodable { let v: Int? }
    private struct Wire: Decodable {
        let version: String
        let kinds: [ForkCardKind]
    }
}

enum ForkCardSupport: String, Equatable, Sendable, Decodable {
    case native
    case props
}

struct ForkCardCoverage: Equatable, Sendable {
    let kinds: [String: ForkCardSupport]

    static func parse(_ data: Data) throws -> ForkCardCoverage {
        struct Wire: Decodable { let kinds: [String: ForkCardSupport] }
        do { return ForkCardCoverage(kinds: try JSONDecoder().decode(Wire.self, from: data).kinds) } catch {
            throw ForkCardCatalogError.invalidJSON(String(describing: error))
        }
    }
}

struct ForkCardLine: Equatable, Sendable, Identifiable {
    let key: String
    let value: String

    var id: String { key }
}

struct ForkCardCell: Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let label: String
    let state: String
    let support: ForkCardSupport?
    let unavailableReason: String?
    let lines: [ForkCardLine]
    let board: OpenUIBoardModel?

    var isUnavailable: Bool { unavailableReason != nil }
    var presentation: String { isUnavailable ? "unavailable" : board != nil ? "board" : "props" }
    var text: String { ([label, id, state] + lines.flatMap { [$0.key, $0.value] } + [unavailableReason ?? ""]).joined(separator: " ") }
}

struct ForkCardGallerySection: Equatable, Sendable, Identifiable {
    let group: String
    let cells: [ForkCardCell]

    var id: String { group }
}

struct ForkCardGallery: Equatable, Sendable {
    static let identityKeys: Set<String> = ["kind", "app", "unavailable"]

    let version: String
    let sections: [ForkCardGallerySection]
    let uncoveredKinds: [String]
    let extraKinds: [String]

    init(catalog: ForkCardCatalog, coverage: ForkCardCoverage) {
        version = catalog.version
        var order: [String] = []
        var cells: [String: [ForkCardCell]] = [:]
        for kind in catalog.kinds {
            if cells[kind.group] == nil { order.append(kind.group) }
            cells[kind.group, default: []] += kind.fixtures.map { Self.cell(kind, $0, coverage.kinds[kind.kind]) }
        }
        sections = order.map { ForkCardGallerySection(group: $0, cells: cells[$0] ?? []) }
        let listed = Set(catalog.kinds.map(\.kind))
        uncoveredKinds = catalog.kinds.map(\.kind).filter { coverage.kinds[$0] == nil }
        extraKinds = coverage.kinds.keys.filter { !listed.contains($0) }.sorted()
    }

    var cells: [ForkCardCell] { sections.flatMap(\.cells) }
    var kinds: Set<String> { Set(cells.map(\.kind)) }

    private static func cell(_ kind: ForkCardKind, _ fixture: ForkCardFixture, _ support: ForkCardSupport?) -> ForkCardCell {
        var reason: String?
        if fixture.isUnavailable {
            if case .string(let text)? = fixture.props["unavailable"], !text.isEmpty { reason = text } else { reason = fixture.state }
        }
        let lines = fixture.props.keys.sorted().filter { !identityKeys.contains($0) }
            .map { ForkCardLine(key: $0, value: summary(fixture.props[$0] ?? .null)) }
        return ForkCardCell(id: fixture.id, kind: kind.kind, label: kind.label, state: fixture.state, support: support,
                            unavailableReason: reason, lines: lines,
                            board: reason == nil && support == .native ? board(kind.kind, fixture.props) : nil)
    }

    static func board(_ kind: String, _ props: [String: ForkJSON]) -> OpenUIBoardModel? {
        guard kind == "metric", case .string(let app)? = props["app"], !app.isEmpty,
              case .string(let label)? = props["label"], !label.isEmpty,
              case .number(let value)? = props["value"], value.isFinite,
              case .number(let delta)? = props["delta"], delta.isFinite else { return nil }
        let detail = delta.formatted(.number.sign(strategy: .always())) + "%"
        return OpenUIBoardModel(title: label, summary: "", panels: [.stat(title: app, value: .number(value), detail: detail)])
    }

    static func summary(_ value: ForkJSON, depth: Int = 0) -> String {
        switch value {
        case .string(let text): return text.isEmpty ? "\u{2014}" : text
        case .number(let number): return number.rounded() == number && abs(number) < 1e15
            ? String(Int64(number)) : String(format: "%g", number)
        case .bool(let flag): return flag ? "true" : "false"
        case .null: return "\u{2014}"
        case .array(let items):
            guard depth == 0, items.allSatisfy(\.isScalar) else { return "[\(items.count)]" }
            return items.isEmpty ? "\u{2014}" : items.map { summary($0, depth: depth + 1) }.joined(separator: ", ")
        case .object(let fields):
            guard depth == 0 else { return "{\(fields.count)}" }
            return fields.keys.sorted().map { "\($0): \(summary(fields[$0] ?? .null, depth: depth + 1))" }.joined(separator: ", ")
        }
    }
}

extension ForkJSON {
    var isScalar: Bool {
        switch self {
        case .array, .object: false
        default: true
        }
    }
}
