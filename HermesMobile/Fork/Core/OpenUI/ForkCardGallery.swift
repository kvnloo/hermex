import Foundation

struct ForkCardCatalog: Decodable, Sendable {
    struct Count: Decodable, Sendable {
        let kinds: Int
        let fixtures: Int
    }

    struct Kind: Decodable, Sendable {
        let kind: String
        let label: String
        let fixtures: [Fixture]
    }

    struct Fixture: Decodable, Sendable {
        enum State: String, Decodable, Sendable {
            case sample, example, input, unavailable
        }

        struct Card: Decodable, Equatable, Sendable {
            let kind: String
            let app: String
            let input: ForkJSON?
        }

        let id: String
        let state: State
        let card: Card
        let props: [String: ForkJSON]
    }

    let v: Int
    let version: String
    let count: Count
    let kinds: [Kind]
}

struct ForkCardGallery: Sendable {
    enum Invalid: Error, Equatable {
        case version, coverage, fixture(String)
    }

    enum Content: Equatable, Sendable {
        case board(OpenUIBoardModel, props: [String: ForkJSON])
        case unsupported
        case unavailable

        var snapshotName: String {
            switch self {
            case .board: "board"
            case .unsupported: "unsupported"
            case .unavailable: "unavailable"
            }
        }
    }

    struct Cell: Identifiable, Sendable {
        let fixture: ForkCardCatalog.Fixture
        let content: Content
        var id: String { fixture.id }
    }

    struct Section: Identifiable, Sendable {
        let id: String
        let title: String
        let cells: [Cell]
    }

    let version: String
    let sections: [Section]
    var versionLabel: String { "ephemeral-ui · v" + version }

    static func parse(_ data: Data) throws -> ForkCardGallery {
        let catalog = try JSONDecoder().decode(ForkCardCatalog.self, from: data)
        return try ForkCardGallery(catalog)
    }

    init(_ catalog: ForkCardCatalog) throws {
        guard catalog.v == 0, !catalog.version.isEmpty else { throw Invalid.version }
        let fixtures = catalog.kinds.flatMap(\.fixtures)
        guard !catalog.kinds.isEmpty, catalog.count.kinds == catalog.kinds.count,
              catalog.count.fixtures == fixtures.count,
              Set(catalog.kinds.map(\.kind)).count == catalog.kinds.count,
              Set(fixtures.map(\.id)).count == fixtures.count else { throw Invalid.coverage }
        version = catalog.version
        sections = try catalog.kinds.map { kind in
            guard !kind.kind.isEmpty, !kind.label.isEmpty, !kind.fixtures.isEmpty else { throw Invalid.coverage }
            let cells = try kind.fixtures.map { fixture in
                guard !fixture.id.isEmpty, !fixture.card.app.isEmpty, fixture.card.kind == kind.kind,
                      !fixture.props.isEmpty, Self.hasValidAvailability(fixture) else {
                    throw Invalid.fixture(fixture.id)
                }
                return try Cell(fixture: fixture, content: Self.content(for: fixture))
            }
            return Section(id: kind.kind, title: kind.label, cells: cells)
        }
    }

    private static func hasValidAvailability(_ fixture: ForkCardCatalog.Fixture) -> Bool {
        let unavailable = fixture.props["unavailable"]
        if fixture.state == .unavailable {
            guard case .string(let reason)? = unavailable else { return false }
            return !reason.isEmpty
        }
        return unavailable == nil
    }

    private static func content(for fixture: ForkCardCatalog.Fixture) throws -> Content {
        if fixture.state == .unavailable { return .unavailable }
        let props = fixture.props
        switch fixture.card.kind {
        case "metric":
            guard props["kind"] == .string(fixture.card.kind), props["app"] == .string(fixture.card.app),
                  case .string(let label)? = props["label"], !label.isEmpty,
                  case .number(let value)? = props["value"], value.isFinite,
                  case .number(let delta)? = props["delta"], delta.isFinite else {
                throw Invalid.fixture(fixture.id)
            }
            let detail = delta.formatted(.number.sign(strategy: .always())) + "%"
            return .board(OpenUIBoardModel(title: label, summary: "",
                                           panels: [.stat(title: fixture.card.app, value: .number(value), detail: detail)]),
                          props: props)
        default:
            return .unsupported
        }
    }
}

struct ForkGalleryTheme: Decodable, Sendable {
    struct Palette: Decodable, Sendable {
        let bg: String
        let fg: String
        let card: String
        let border: String
    }

    struct Colors: Decodable, Sendable {
        let light: Palette
        let dark: Palette
    }

    struct Radius: Decodable, Sendable {
        let card: Double
    }

    let v: Int
    let color: Colors
    let radius: Radius

    static func parse(_ data: Data) throws -> ForkGalleryTheme {
        let theme = try JSONDecoder().decode(Self.self, from: data)
        guard theme.v == 0, theme.radius.card.isFinite, theme.radius.card > 0,
              [theme.color.light, theme.color.dark].allSatisfy({ palette in
                  [palette.bg, palette.fg, palette.card, palette.border].allSatisfy { ForkRGBA(hex: $0) != nil }
              }) else { throw ForkCardGallery.Invalid.version }
        return theme
    }
}
