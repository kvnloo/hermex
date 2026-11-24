import Foundation

extension OpenUICheck {
    static func panel(_ name: String, _ args: [OpenUIValue], _ at: OpenUIPosition) throws -> OpenUIPanel {
        let node = OpenUIValue.call(name, args, at)
        switch name {
        case "Stat":
            try arity(name, args, at, 2, 3)
            let title = try string(args[0], "title", max: 200)
            let value: OpenUICell
            if case .string = args[1] { value = .text(try string(args[1], "value", max: 100)) }
            else { value = .number(try number(args[1], "value", min: -OpenUICatalog.maxValue)) }
            let detail = args.count == 3 ? try string(args[2], "detail", max: 200) : nil
            return .stat(title: title, value: value, detail: detail)
        case "Table":
            try arity(name, args, at, 3)
            let title = try string(args[0], "title", max: 200)
            let columns = try array(args[1], "columns", min: 1, max: 10).map { try string($0, "column", min: 1, max: 100) }
            let rows = try array(args[2], "rows", max: 100).map { row -> [OpenUICell] in
                let cells = try array(row, "table cells", max: 10)
                guard cells.count == columns.count else { throw bad(row, "Table rows must match the declared columns.") }
                return try cells.map(cell)
            }
            return .table(title: title, columns: columns, rows: rows)
        case "Treemap":
            return try treemap(name, args, at, node)
        case "BarChart":
            try arity(name, args, at, 3)
            let title = try string(args[0], "title", max: 200)
            let unit = try string(args[1], "unit", max: 40)
            let bars = try array(args[2], "bars", min: 1, max: 30).map { entry -> (label: String, value: Double) in
                let bar = try object(entry, "bar")
                return (try text(bar, "label", entry, min: 1, max: 100), try number(bar, "value", entry))
            }
            return .bars(title: title, unit: unit, bars: bars)
        case "StackedArea", "StackedBar", "LineChart":
            try arity(name, args, at, 4)
            let title = try string(args[0], "title", max: 200)
            let unit = try string(args[1], "unit", max: 40)
            let categories = try array(args[2], "categories", min: 2, max: 60).map { try string($0, "category", min: 1, max: 100) }
            let series = try array(args[3], "series", min: 1, max: 8).map { entry -> OpenUISeries in
                let row = try object(entry, "series")
                let seriesName = try text(row, "name", entry, min: 1, max: 100)
                let values = try array(field(row, "values", entry), "values", max: 60)
                guard values.count == categories.count else {
                    throw bad(entry, "\(name) series \"\(seriesName)\" needs \(categories.count) values.")
                }
                return OpenUISeries(name: seriesName, values: try values.map { try number($0, "value") })
            }
            return .series(OpenUISeriesKind(rawValue: name)!, title: title, unit: unit, categories: categories, series: series)
        case "Heatmap":
            try arity(name, args, at, 5)
            let title = try string(args[0], "title", max: 200)
            let unit = try string(args[1], "unit", max: 40)
            let rows = try array(args[2], "rows", min: 1, max: 31).map { try string($0, "row label", min: 1, max: 100) }
            let columns = try array(args[3], "columns", min: 1, max: 48).map { try string($0, "column label", min: 1, max: 100) }
            let countRows = try array(args[4], "counts", max: 31)
            guard countRows.count == rows.count else { throw bad(node, "Heatmap needs \(rows.count) count rows.") }
            let counts = try countRows.enumerated().map { index, raw -> [Double] in
                let cells = try array(raw, "count row", max: 48)
                guard cells.count == columns.count else {
                    throw bad(raw, "Heatmap row \"\(rows[index])\" needs \(columns.count) counts.")
                }
                return try cells.map { try number($0, "count") }
            }
            return .heatmap(title: title, unit: unit, rows: rows, columns: columns, counts: counts)
        case "RideOptions":
            return .kit(title: "", cards: [.drawn(try rideOptions(name, args, at))])
        case "MailList":
            return .kit(title: "", cards: [.drawn(try mailList(name, args, at))])
        case "Route":
            return .kit(title: "", cards: [.drawn(try route(name, args, at))])
        case "PullRequest":
            return .kit(title: "", cards: [.drawn(try pullRequest(name, args, at, node))])
        case "EphemeralCards":
            try arity(name, args, at, 2)
            let title = try string(args[0], "title", max: 200)
            let cards = try array(args[1], "cards", min: 1, max: KitCardProgram.maxCards).map { try kitSpec($0) }
            return .kit(title: title, cards: cards.map(KitCardEntry.catalog))
        case "EphemeralCard":
            try arity(name, args, at, 1, 2)
            let kind = try string(args[0], "kind", min: 1, max: 100)
            let app = args.count == 2 ? try string(args[1], "app", min: 1, max: 100) : nil
            return .kit(title: "", cards: [.catalog(KitCardSpec(kind: kind, app: app))])
        default:
            throw bad(node, "Chart board contains an unknown panel.")
        }
    }

    private static func treemap(_ name: String, _ args: [OpenUIValue], _ at: OpenUIPosition, _ node: OpenUIValue) throws -> OpenUIPanel {
        try arity(name, args, at, 4)
        let title = try string(args[0], "title", max: 200)
        let sizeLabel = try string(args[1], "sizeLabel", min: 1, max: 100)
        let colorLabel = try string(args[2], "colorLabel", min: 1, max: 100)
        var seen: [String] = []
        var rows: [OpenUITreemapRow] = []
        for entry in try array(args[3], "Treemap rows", min: 1, max: 500) {
            let row = try object(entry, "Treemap row")
            let raw = try text(row, "path", entry, min: 1, max: 500)
            let size = try number(row, "size", entry)
            let color = try number(row, "color", entry)
            let path = raw.split(separator: "/").joined(separator: "/")
            if path.isEmpty { throw bad(entry, "Treemap rows need a non-empty path.") }
            if seen.contains(path) { throw bad(entry, "Treemap path \"\(path)\" appears twice.") }
            seen.append(path)
            rows.append(OpenUITreemapRow(path: path, size: size, color: color))
        }
        for path in seen where seen.contains(where: { $0.hasPrefix(path + "/") }) {
            throw bad(node, "Treemap path \"\(path)\" is both a file and a folder.")
        }
        return .treemap(title: title, sizeLabel: sizeLabel, colorLabel: colorLabel, rows: rows)
    }

    private static func rideOptions(_ name: String, _ args: [OpenUIValue], _ at: OpenUIPosition) throws -> KitCardModel {
        try arity(name, args, at, 4)
        let app = try choice(args[0], "app", ["uber", "lyft"])
        let pickup = try string(args[1], "pickup", min: 1, max: 200)
        let dropoff = try string(args[2], "dropoff", min: 1, max: 200)
        var seen: Set<String> = []
        var rows: [KitRow] = []
        for entry in try array(args[3], "ride options", min: 1, max: 8) {
            let row = try object(entry, "ride")
            let rideName = try text(row, "name", entry, min: 1)
            let minutes = try number(row, "minutes", entry, max: 100_000)
            let price = try text(row, "price", entry, min: 1, max: 24)
            let seats = try number(row, "seats", entry, min: 1, max: 20, integer: true)
            try optionalText(row, "arrival", 200)
            if !seen.insert(rideName).inserted { throw bad(entry, "RideOptions lists the same option twice.") }
            let arrival = row["arrival"].flatMap { if case .string(let text, _) = $0, !text.isEmpty { text } else { nil } }
            let detail = ["\(KitFormat.number(minutes)) min", KitFormat.count(Int(seats), "seat"), arrival].compactMap { $0 }
            rows.append(KitRow(id: rows.count, title: rideName, detail: detail.joined(separator: " \u{00B7} "), trailing: price))
        }
        var card = KitCardModel(kind: "ride", app: app, appName: KitFormat.title(app), label: "Ride options", group: "app",
                                title: "Ride options")
        card.route = KitRoute(from: pickup, to: dropoff)
        card.addRows(rows)
        return card
    }

    private static func mailList(_ name: String, _ args: [OpenUIValue], _ at: OpenUIPosition) throws -> KitCardModel {
        try arity(name, args, at, 2)
        let query = try string(args[0], "query", max: 200)
        var rows: [KitRow] = []
        for entry in try array(args[1], "messages", max: 20) {
            let row = try object(entry, "message")
            let from = try text(row, "from", entry, min: 1)
            let subject = try text(row, "subject", entry)
            let snippet = try text(row, "snippet", entry, max: 400)
            let time = try text(row, "time", entry)
            try boolean(field(row, "unread", entry), "unread")
            try optionalText(row, "attachment", 200)
            let unread = if case .boolean(true, _)? = row["unread"] { true } else { false }
            rows.append(KitRow(id: rows.count, title: subject.isEmpty ? from : subject,
                               detail: [from, snippet].filter { !$0.isEmpty }.joined(separator: " \u{2014} "),
                               trailing: time.isEmpty ? nil : time, isEmphasized: unread))
        }
        var card = KitCardModel(kind: "inbox", app: "mail", appName: "Mail", label: "Inbox", group: "app",
                                title: query.isEmpty ? "Inbox" : "\u{201C}\(query)\u{201D}")
        card.subtitle = KitFormat.count(rows.count, "message")
        card.addRows(rows)
        if rows.isEmpty { card.addFact("Messages", "0") }
        return card
    }

    private static func route(_ name: String, _ args: [OpenUIValue], _ at: OpenUIPosition) throws -> KitCardModel {
        try arity(name, args, at, 6, 9)
        let origin = try string(args[0], "origin", min: 1, max: 200)
        let destination = try string(args[1], "destination", min: 1, max: 200)
        let mode = try choice(args[2], "mode", ["drive", "walk", "transit", "bike"])
        let minutes = try number(args[3], "minutes", max: 100_000)
        let distance = try string(args[4], "distance", max: 200)
        let steps = try array(args[5], "steps", max: 20).map { try string($0, "step", min: 1, max: 200) }
        let via = args.count > 6 ? try string(args[6], "via", max: 200) : ""
        if args.count > 7 {
            for point in try array(args[7], "path", min: 2, max: 600) {
                let pair = try array(point, "coordinate", min: 2, max: 2)
                _ = try number(pair[0], "latitude", min: -90, max: 90)
                _ = try number(pair[1], "longitude", min: -180, max: 180)
            }
        }
        if args.count > 8 {
            let map = try object(args[8], "map")
            let url = try text(map, "image", args[8], min: 1, max: 2000)
            guard let parsed = URLComponents(string: url), ["https", "http"].contains(parsed.scheme ?? ""),
                  !(parsed.host ?? "").isEmpty else { throw bad(args[8], "Map image must be an HTTP(S) URL.") }
            let bounds = try array(field(map, "bounds", args[8]), "bounds", min: 4, max: 4)
            _ = try number(bounds[0], "south", min: -90, max: 90)
            _ = try number(bounds[1], "west", min: -180, max: 180)
            _ = try number(bounds[2], "north", min: -90, max: 90)
            _ = try number(bounds[3], "east", min: -180, max: 180)
        }
        var card = KitCardModel(kind: "route", app: "maps", appName: "Maps", label: "Route", group: "app",
                                title: KitFormat.capitalized(mode) + (via.isEmpty ? "" : " via \(via)"))
        card.route = KitRoute(from: origin, to: destination,
                              detail: ["\(KitFormat.number(minutes)) min", distance.isEmpty ? nil : distance].compactMap { $0 }
                                  .joined(separator: " \u{00B7} "))
        card.addRows(steps.map { KitRow(id: 0, title: $0) })
        return card
    }

    private static func pullRequest(_ name: String, _ args: [OpenUIValue], _ at: OpenUIPosition, _ node: OpenUIValue) throws -> KitCardModel {
        try arity(name, args, at, 7, 8)
        let prNumber = try number(args[0], "PR number", min: 1, max: .greatestFiniteMagnitude, integer: true)
        let title = try string(args[1], "title", min: 1, max: 200)
        let state = try choice(args[2], "state", ["open", "conflict", "ready", "merged", "closed"])
        let head = try string(args[3], "head", min: 1, max: 200)
        let base = try string(args[4], "base", min: 1, max: 200)
        var pending = false
        var checks: [ForkJSON] = []
        for entry in try array(args[5], "checks", max: 12) {
            let check = try object(entry, "check")
            let checkName = try text(check, "name", entry, min: 1)
            let status = try text(check, "status", entry, min: 1)
            guard ["pass", "fail", "running", "skip"].contains(status) else { throw bad(entry, "Invalid check status.") }
            pending = pending || status == "fail" || status == "running"
            let detail = try text(check, "detail", entry)
            checks.append(.object(["name": .string(checkName), "status": .string(status), "detail": .string(detail)]))
            try optionalNumber(check, "started", 6_000_000)
            try optionalNumber(check, "seconds", 6_000_000)
        }
        let conflicts = try number(args[6], "conflicts", max: 10_000, integer: true)
        if state == "conflict" && conflicts < 1 { throw bad(node, "PullRequest in conflict needs a conflict count.") }
        if state != "conflict" && state != "open" && conflicts > 0 { throw bad(node, "PullRequest \(state) cannot have conflicts.") }
        if state == "ready" && pending { throw bad(node, "PullRequest ready needs every check passed or skipped.") }
        if args.count > 7 {
            for entry in try array(args[7], "commits", max: 12) {
                let item = try object(entry, "commit")
                _ = try text(item, "title", entry, min: 1)
                _ = try text(item, "sha", entry, min: 4, max: 12)
                _ = try text(item, "author", entry, min: 1)
                _ = try text(item, "age", entry)
                let lane = try text(item, "lane", entry, min: 1)
                guard ["base", "head", "side"].contains(lane) else { throw bad(entry, "Invalid commit lane.") }
                try optionalText(item, "branch", 200)
                if let conflict = item["conflict"] { try boolean(conflict, "conflict") }
            }
        }
        let kind = ForkCardKind(kind: "merge", label: "Pull request", group: "app", fixtures: [])
        return KitCardMapper.model(kind: kind, app: "github", props: ["input": .object([
            "number": .number(prNumber), "title": .string(title), "state": .string(state), "head": .string(head),
            "base": .string(base), "conflicts": .number(conflicts), "checks": .array(checks),
        ])], unavailable: nil)
    }

    private static func kitSpec(_ node: OpenUIValue) throws -> KitCardSpec {
        let card = try object(node, "card")
        let kind = try text(card, "kind", node, min: 1, max: 100)
        let app = try card["app"].map { try string($0, "app", min: 1, max: 100) }
        let title = try card["title"].map { try string($0, "title", max: 200) }
        let input = try card["input"].map(json)
        return KitCardSpec(kind: kind, app: app, title: title, input: input)
    }

    static func json(_ node: OpenUIValue) throws -> ForkJSON {
        switch node {
        case .string(let text, _): return .string(text)
        case .number(let value, _): return .number(value)
        case .boolean(let flag, _): return .bool(flag)
        case .null: return .null
        case .array(let items, _): return .array(try items.map(json))
        case .object(let fields, _): return .object(try fields.mapValues(json))
        case .call, .reference: throw bad(node, "Card input must be plain data.")
        }
    }
}
