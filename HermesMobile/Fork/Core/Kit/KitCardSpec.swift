import Foundation

struct KitCardSpec: Equatable, Sendable {
    let kind: String
    var app: String?
    var title: String?
    var input: ForkJSON?

    init(kind: String, app: String? = nil, title: String? = nil, input: ForkJSON? = nil) {
        self.kind = kind
        self.app = app
        self.title = title
        self.input = input
    }
}

enum KitCardProgramError: Error, Equatable {
    case invalid(String)
}

struct KitCardProgram: Equatable, Sendable {
    static let fenceLanguage = "ephemeral-ui"
    static let maxCards = 12
    static let maxTitle = 200

    let title: String?
    let cards: [KitCardSpec]

    static func matches(_ language: String?) -> Bool {
        language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: " ").first
            .map(String.init) == fenceLanguage
    }

    static func parseFence(_ source: String) throws -> KitCardProgram {
        let json: ForkJSON
        do { json = try JSONDecoder().decode(ForkJSON.self, from: Data(source.utf8)) } catch {
            throw KitCardProgramError.invalid("The card is not JSON.")
        }
        var title: String?
        let entries: [ForkJSON]
        switch json {
        case .array(let items): entries = items
        case .object(let fields):
            if case .array(let items)? = fields["cards"] {
                entries = items
                title = try text(fields["title"], "title")
            } else {
                entries = [json]
            }
        default: throw KitCardProgramError.invalid("A card must be a JSON object.")
        }
        guard !entries.isEmpty, entries.count <= maxCards else {
            throw KitCardProgramError.invalid("Send 1 to \(maxCards) cards.")
        }
        let cards = try entries.map(card)
        return KitCardProgram(title: title, cards: cards)
    }

    static func card(_ json: ForkJSON) throws -> KitCardSpec {
        guard case .object(let fields) = json else { throw KitCardProgramError.invalid("A card must be a JSON object.") }
        guard case .string(let kind)? = fields["kind"], !kind.isEmpty else {
            throw KitCardProgramError.invalid("A card needs a kind.")
        }
        return KitCardSpec(kind: kind, app: try text(fields["app"], "app"), title: try text(fields["title"], "title"),
                           input: fields["input"].flatMap { $0 == .null ? nil : $0 })
    }

    private static func text(_ value: ForkJSON?, _ label: String) throws -> String? {
        switch value {
        case nil, .null?: return nil
        case .string(let text)?:
            guard text.utf16.count <= maxTitle else { throw KitCardProgramError.invalid("The \(label) is too long.") }
            return text.isEmpty ? nil : text
        default: throw KitCardProgramError.invalid("The \(label) must be a string.")
        }
    }
}

enum KitCardResolution: Equatable, Sendable {
    case card(KitCardModel)
    case unknownKind(String)
    case unknownApp(kind: String, app: String)
}

struct KitCardLibrary: Equatable, Sendable {
    let catalog: ForkCardCatalog

    func kind(_ name: String) -> ForkCardKind? {
        catalog.kinds.first { $0.kind == name }
    }

    func resolve(_ spec: KitCardSpec) -> KitCardResolution {
        guard let kind = kind(spec.kind) else { return .unknownKind(spec.kind) }
        let apps = kind.appIDs
        let app: String
        if let requested = spec.app {
            guard apps.isEmpty || apps.contains(requested) else { return .unknownApp(kind: spec.kind, app: requested) }
            app = requested
        } else {
            app = apps.first ?? kind.fixtures.compactMap(\.appID).first ?? kind.kind
        }
        let usable = kind.fixtures.filter { !$0.isUnavailable }
        let fixture = usable.first { $0.id == "\(kind.kind)/\(app)" }
            ?? usable.first { $0.appID == app }
            ?? usable.first
        var props = fixture?.props ?? [:]
        props["app"] = .string(app)
        if let input = spec.input { props["input"] = input }
        var model = KitCardMapper.model(kind: kind, app: app, props: props, unavailable: nil)
        if let title = spec.title { model.title = title }
        return .card(model)
    }

    func resolve(_ program: KitCardProgram) -> [KitCardResolution] {
        program.cards.map(resolve)
    }
}

struct ForkCardApp: Equatable, Sendable, Decodable {
    let id: String
    let name: String?
}

extension ForkCardKind {
    var appIDs: [String] { (apps ?? []).map(\.id) }

    func appName(_ id: String) -> String {
        if let name = apps?.first(where: { $0.id == id })?.name, !name.isEmpty { return name }
        return KitFormat.title(id)
    }
}

extension ForkCardFixture {
    var appID: String? {
        if case .string(let app)? = props["app"], !app.isEmpty { return app }
        return nil
    }
}
