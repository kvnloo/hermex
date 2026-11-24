import Foundation

enum OpenUICell: Equatable, Sendable {
    case text(String)
    case number(Double)
}

struct OpenUISeries: Equatable, Sendable {
    let name: String
    let values: [Double]
}

struct OpenUITreemapRow: Equatable, Sendable {
    let path: String
    let size: Double
    let color: Double
}

enum OpenUISeriesKind: String, Equatable, Sendable {
    case stackedArea = "StackedArea"
    case stackedBar = "StackedBar"
    case line = "LineChart"
}

enum KitCardEntry: Equatable, Sendable {
    case catalog(KitCardSpec)
    case drawn(KitCardModel)
}

enum OpenUIPanel: Equatable, Sendable {
    case stat(title: String, value: OpenUICell, detail: String?)
    case bars(title: String, unit: String, bars: [(label: String, value: Double)])
    case series(OpenUISeriesKind, title: String, unit: String, categories: [String], series: [OpenUISeries])
    case table(title: String, columns: [String], rows: [[OpenUICell]])
    case treemap(title: String, sizeLabel: String, colorLabel: String, rows: [OpenUITreemapRow])
    case heatmap(title: String, unit: String, rows: [String], columns: [String], counts: [[Double]])
    case kit(title: String, cards: [KitCardEntry])

    static func == (lhs: OpenUIPanel, rhs: OpenUIPanel) -> Bool {
        switch (lhs, rhs) {
        case let (.bars(a, b, c), .bars(x, y, z)):
            a == x && b == y && c.map(\.label) == z.map(\.label) && c.map(\.value) == z.map(\.value)
        case let (.stat(a, b, c), .stat(x, y, z)): a == x && b == y && c == z
        case let (.series(k, a, b, c, d), .series(l, w, x, y, z)): k == l && a == w && b == x && c == y && d == z
        case let (.table(a, b, c), .table(x, y, z)): a == x && b == y && c == z
        case let (.treemap(a, b, c, d), .treemap(w, x, y, z)): a == w && b == x && c == y && d == z
        case let (.heatmap(a, b, c, d, e), .heatmap(v, w, x, y, z)): a == v && b == w && c == x && d == y && e == z
        case let (.kit(a, b), .kit(x, y)): a == x && b == y
        default: false
        }
    }

    var title: String {
        switch self {
        case .stat(let title, _, _), .bars(let title, _, _), .series(_, let title, _, _, _), .table(let title, _, _),
             .treemap(let title, _, _, _), .heatmap(let title, _, _, _, _): title
        case .kit(let title, _): title
        }
    }
}

struct OpenUIBoardModel: Equatable, Sendable {
    let title: String
    let summary: String
    let panels: [OpenUIPanel]

    var isFullyRendered: Bool { !panels.isEmpty }
}

enum OpenUICatalogResult: Equatable, Sendable {
    case ready(OpenUIBoardModel)
    case incomplete(OpenUIProblem)
    case invalid(OpenUIProblem)
}

enum OpenUICatalog {
    static let maxPanels = 8
    static let maxValue = 1e12
    static let panelTypes: Set<String> = [
        "Treemap", "BarChart", "StackedArea", "Heatmap", "Stat", "StackedBar", "LineChart", "Table",
        "RideOptions", "MailList", "Route", "PullRequest", "EphemeralCards", "EphemeralCard",
    ]
    static let fenceLanguages: Set<String> = ["openui-v2", "openui"]

    static func inspect(_ source: String) -> OpenUICatalogResult {
        switch OpenUILang.parse(source) {
        case .incomplete(let problem): return .incomplete(problem)
        case .invalid(let problem): return .invalid(problem)
        case .ready(let program): return validate(program)
        }
    }

    static func validate(_ program: OpenUIProgram) -> OpenUICatalogResult {
        do {
            for value in program.assignments.values { try OpenUICheck.noUnsupportedCalls(value) }
            let (_, args, at) = try OpenUICheck.call(program.root, "Board")
            try OpenUICheck.arity("Board", args, at, 3)
            let title = try OpenUICheck.string(args[0], "Board title", max: 200)
            let summary = try OpenUICheck.string(args[1], "Board summary", max: 4000)
            let nodes = try OpenUICheck.array(args[2], "Board panels", min: 1, max: maxPanels)
            let panels = try nodes.map { node -> OpenUIPanel in
                guard case .call(let name, let args, let at) = node else {
                    throw OpenUIFault("Chart board contains an unknown panel.", node.position)
                }
                return try OpenUICheck.panel(name, args, at)
            }
            return .ready(OpenUIBoardModel(title: title, summary: summary, panels: panels))
        } catch let fault as OpenUIFault {
            return .invalid(OpenUIProblem(message: fault.message, line: fault.at.line, column: fault.at.column))
        } catch {
            return .invalid(OpenUIProblem(message: "Unreadable board.", line: 1, column: 1))
        }
    }
}
