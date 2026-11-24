import Foundation

enum KitTone: String, Equatable, Sendable {
    case neutral
    case positive
    case warning
    case critical
    case info
}

enum KitLayout: String, Equatable, Sendable {
    case hero
    case route
    case list
    case facts
    case unavailable
}

struct KitHero: Equatable, Sendable {
    let value: String
    var caption: String?
    var trend: Double?
    var progress: Double?
}

struct KitRoute: Equatable, Sendable {
    let from: String
    let to: String
    var detail: String?
}

struct KitRow: Equatable, Sendable, Identifiable {
    let id: Int
    let title: String
    var detail: String?
    var trailing: String?
    var tone: KitTone?
    var isEmphasized = false
}

struct KitFact: Equatable, Sendable, Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

struct KitStatus: Equatable, Sendable {
    let text: String
    let tone: KitTone
}

struct KitCardModel: Equatable, Sendable, Identifiable {
    static let maxRows = 8
    static let maxFacts = 8
    static let maxChips = 8

    let kind: String
    let app: String
    let appName: String
    let label: String
    let group: String
    var title: String
    var subtitle: String?
    var hero: KitHero?
    var route: KitRoute?
    var rows: [KitRow] = []
    var facts: [KitFact] = []
    var chips: [String] = []
    var status: KitStatus?
    var unavailableReason: String?

    var id: String { "\(kind)/\(app)/\(title)" }

    var layout: KitLayout {
        if unavailableReason != nil { return .unavailable }
        if hero != nil { return .hero }
        if route != nil { return .route }
        if !rows.isEmpty { return .list }
        return .facts
    }

    var isPlaceholder: Bool {
        unavailableReason == nil && hero == nil && route == nil && rows.isEmpty && facts.isEmpty && chips.isEmpty
    }

    var accessibilityText: String {
        var parts = [appName, title]
        if let subtitle { parts.append(subtitle) }
        if let hero { parts += [hero.value, hero.caption].compactMap { $0 } }
        if let route { parts += [route.from, route.to, route.detail].compactMap { $0 } }
        parts += rows.flatMap { [$0.title, $0.detail, $0.trailing].compactMap { $0 } }
        parts += facts.map { "\($0.label) \($0.value)" }
        parts += chips
        if let status { parts.append(status.text) }
        if let unavailableReason { parts.append(unavailableReason) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    mutating func addRows(_ new: [KitRow]) {
        let start = rows.count
        rows += new.prefix(max(Self.maxRows - start, 0)).enumerated().map { offset, row in
            var row = row
            row = KitRow(id: start + offset, title: row.title, detail: row.detail, trailing: row.trailing, tone: row.tone,
                         isEmphasized: row.isEmphasized)
            return row
        }
    }

    mutating func addFact(_ label: String, _ value: String?) {
        guard let value, !value.isEmpty, facts.count < Self.maxFacts, !facts.contains(where: { $0.label == label }) else { return }
        facts.append(KitFact(label: label, value: value))
    }
}

enum KitCardMapper {
    static let hiddenKeys: Set<String> = ["kind", "app", "unavailable", "v", "actions", "seed", "ttl", "previewAsset"]

    static func model(kind: ForkCardKind, fixture: ForkCardFixture) -> KitCardModel {
        let app = fixture.appID ?? kind.appIDs.first ?? kind.kind
        var reason: String?
        if fixture.isUnavailable {
            if case .string(let text)? = fixture.props["unavailable"], !text.isEmpty { reason = text } else { reason = fixture.state }
        }
        return model(kind: kind, app: app, props: fixture.props, unavailable: reason)
    }

    static func model(kind: ForkCardKind, app: String, props: [String: ForkJSON], unavailable: String?) -> KitCardModel {
        var card = KitCardModel(kind: kind.kind, app: app, appName: kind.appName(app), label: kind.label, group: kind.group,
                                title: kind.label)
        if let unavailable {
            card.unavailableReason = unavailable
            return card
        }
        let p = KitProps(props)
        if !special(&card, p) { generic(&card, p) }
        if card.isPlaceholder { card.addFact(KitFormat.title("app"), card.appName) }
        return card
    }

    static func generic(_ card: inout KitCardModel, _ p: KitProps) {
        for key in p.keys where !hiddenKeys.contains(key) {
            walk(&card, key: key, value: p.raw[key] ?? .null, depth: 0)
        }
    }

    private static func walk(_ card: inout KitCardModel, key: String, value: ForkJSON, depth: Int) {
        let label = KitFormat.title(key)
        switch value {
        case .string, .number, .bool:
            card.addFact(label, KitFormat.scalar(value, key: key))
        case .array(let items) where items.allSatisfy(\.isScalar):
            let words = items.compactMap { KitFormat.scalar($0, key: key) }.filter { !$0.isEmpty }
            if words.count <= 3 && words.allSatisfy({ $0.count <= 24 }) || card.chips.isEmpty && words.count <= KitCardModel.maxChips && words.allSatisfy({ $0.count <= 24 }) {
                if card.chips.isEmpty { card.chips = Array(words.prefix(KitCardModel.maxChips)) } else { card.addFact(label, words.joined(separator: ", ")) }
            } else {
                card.addRows(words.map { KitRow(id: 0, title: $0) })
            }
        case .array(let items):
            card.addRows(items.compactMap(row))
        case .object(let fields):
            guard depth < 3 else { return }
            for inner in fields.keys.sorted() where !hiddenKeys.contains(inner) {
                walk(&card, key: inner, value: fields[inner] ?? .null, depth: depth + 1)
            }
        case .null:
            break
        }
    }

    static func row(_ value: ForkJSON) -> KitRow? {
        switch value {
        case .array(let cells):
            let words = cells.compactMap { KitFormat.scalar($0, key: "") }.filter { !$0.isEmpty }
            guard let first = words.first else { return nil }
            let rest = Array(words.dropFirst())
            return KitRow(id: 0, title: first, detail: rest.count > 1 ? rest.dropLast().joined(separator: " \u{00B7} ") : rest.first,
                          trailing: rest.count > 1 ? rest.last : nil)
        case .object(let fields):
            let p = KitProps(fields)
            let titleKeys = ["title", "name", "label", "subject", "text", "line", "who", "from", "id", "path"]
            guard let titleKey = titleKeys.first(where: { p.string($0) != nil }), let title = p.string(titleKey) else {
                let words = p.keys.compactMap { key in fields[key].flatMap { KitFormat.scalar($0, key: key) }.map { "\(KitFormat.title(key)) \($0)" } }
                return words.isEmpty ? nil : KitRow(id: 0, title: words[0], detail: words.dropFirst().prefix(3).joined(separator: " \u{00B7} "))
            }
            let detailKeys = ["detail", "snippet", "summary", "text", "role", "status", "state", "brush", "region", "line", "unit", "kind"]
            let detail = detailKeys.first { $0 != titleKey && p.string($0) != nil }.flatMap { p.string($0) }
            let trailingKeys = ["price", "value", "amount", "time", "age", "eta", "score", "count", "minutes", "size"]
            let trailing = trailingKeys.first { fields[$0]?.isScalar == true }.flatMap { key in fields[key].flatMap { KitFormat.scalar($0, key: key) } }
            let tone = (p.string("status") ?? p.string("state")).flatMap(KitFormat.tone)
            return KitRow(id: 0, title: title, detail: detail, trailing: trailing, tone: tone, isEmphasized: p.bool("unread") == true)
        case .string, .number, .bool:
            return KitFormat.scalar(value, key: "").map { KitRow(id: 0, title: $0) }
        case .null:
            return nil
        }
    }

    private static func special(_ card: inout KitCardModel, _ p: KitProps) -> Bool {
        switch card.kind {
        case "inbox":
            card.title = p.string("query").map { "\u{201C}\($0)\u{201D}" } ?? card.label
            card.subtitle = p.array("results").map { KitFormat.count($0.count, "result") }
            card.addRows((p.array("results") ?? []).compactMap(row))
        case "thread":
            card.title = p.string("subject") ?? card.label
            card.subtitle = p.string("summary")
            card.chips = p.strings("entities")
        case "approve":
            card.title = card.label
            card.status = KitStatus(text: "Needs approval", tone: .warning)
            card.addRows(p.strings("scopes").map { KitRow(id: 0, title: $0, tone: .info) })
            card.addFact("Expires", p.string("expires"))
        case "chat":
            card.title = p.string("channel").map { "#\($0)" } ?? card.label
            card.addRows((p.array("messages") ?? []).compactMap { message in
                let m = KitProps(message.objectValue ?? [:])
                guard let who = m.string("who") ?? m.string("from") else { return row(message) }
                return KitRow(id: 0, title: who, detail: m.string("text"))
            })
        case "notify":
            card.title = card.label
            card.addRows((p.array("items") ?? []).compactMap(row))
        case "receipt":
            guard let amount = p.number("amount") else { return false }
            card.title = card.label
            card.hero = KitHero(value: KitFormat.money(amount, currency: p.string("currency") ?? "USD"), caption: p.string("payee"))
            card.status = KitStatus(text: "Paid", tone: .positive)
        case "metric":
            guard let value = p.number("value") else { return false }
            card.title = p.string("label") ?? card.label
            card.hero = KitHero(value: KitFormat.number(value), caption: card.appName, trend: p.number("delta"))
        case "crm":
            card.title = p.string("company") ?? card.label
            if let amount = p.number("amount") { card.hero = KitHero(value: KitFormat.money(amount, currency: "USD"), caption: p.string("stage")) }
            card.addFact("Stage", p.string("stage"))
        case "context":
            guard let used = p.number("used"), let limit = p.number("limit"), limit > 0 else { return false }
            card.title = card.label
            card.hero = KitHero(value: KitFormat.percent(used / limit), caption: "\(KitFormat.number(used)) of \(KitFormat.number(limit)) tokens",
                                progress: min(max(used / limit, 0), 1))
            card.status = used / limit >= 0.8 ? KitStatus(text: "Near limit", tone: .warning) : nil
        case "workout":
            guard let distance = p.number("distance_km") else { return false }
            card.title = card.label
            card.hero = KitHero(value: "\(KitFormat.number(distance)) km", caption: card.appName)
        case "home":
            card.title = p.string("device").map(KitFormat.capitalized) ?? card.label
            if let value = p.number("value") { card.hero = KitHero(value: "\(KitFormat.number(value))\u{00B0}", caption: card.label) }
        case "ride":
            card.title = card.label
            if let from = p.string("from"), let to = p.string("to") { card.route = KitRoute(from: from, to: to) }
            card.addRows((p.array("options") ?? []).compactMap { option in
                let o = KitProps(option.objectValue ?? [:])
                guard let name = o.string("name") else { return nil }
                return KitRow(id: 0, title: name, detail: o.string("eta") ?? o.number("minutes").map { "\(KitFormat.number($0)) min" },
                              trailing: o.number("price").map { KitFormat.money($0, currency: "USD") } ?? o.string("price"))
            })
        case "route":
            guard let from = p.string("from"), let to = p.string("to") else { return false }
            card.title = card.label
            card.route = KitRoute(from: from, to: to, detail: p.number("eta_min").map { "\(KitFormat.number($0)) min" })
        case "boarding":
            guard let from = p.string("from"), let to = p.string("to") else { return false }
            card.title = p.string("flight") ?? card.label
            card.route = KitRoute(from: from, to: to, detail: p.string("flight"))
            card.addFact("Seat", p.string("seat"))
        case "track":
            card.title = p.string("status") ?? card.label
            card.status = KitStatus(text: p.string("status") ?? card.label, tone: .info)
            card.addFact("ETA", p.string("eta"))
        case "player":
            card.title = p.string("title") ?? card.label
            card.subtitle = p.string("artist")
            card.addFact("Artist", p.string("artist"))
        case "merge":
            merge(&card, p)
        case "ci":
            let failing = p.strings("failing")
            card.title = card.label
            card.status = failing.isEmpty ? KitStatus(text: "All passing", tone: .positive)
                : KitStatus(text: KitFormat.count(failing.count, "failing job"), tone: .critical)
            card.addRows(failing.map { KitRow(id: 0, title: $0, detail: "failed", tone: .critical) })
            card.addFact("Jobs", p.number("jobs").map(KitFormat.number))
        case "deploy":
            card.title = p.string("target").map { "Deploy to \($0)" } ?? card.label
            card.subtitle = p.string("ref")
            card.addFact("Ref", p.string("ref"))
            card.addFact("Target", p.string("target"))
        case "incident":
            card.title = p.string("service") ?? card.label
            let severity = p.number("severity").map { Int($0) }
            card.status = severity.map { KitStatus(text: "SEV\($0)", tone: $0 <= 2 ? .critical : .warning) }
            card.addFact("Service", p.string("service"))
        default:
            if card.kind.hasPrefix("health-") { return health(&card, p) }
            return false
        }
        if card.isPlaceholder { generic(&card, p) }
        return true
    }

    private static func merge(_ card: inout KitCardModel, _ p: KitProps) {
        let input = KitProps(p.object("input") ?? [:])
        let source = input.raw.isEmpty ? p : input
        let number = source.number("number") ?? source.number("pr")
        let head = source.string("head"), base = source.string("base")
        card.title = input.string("title") ?? number.map { "Pull request #\(KitFormat.number($0))" } ?? card.label
        let branches = head.flatMap { h in base.map { "\(h) \u{2192} \($0)" } }
        card.subtitle = [number.map { "#\(KitFormat.number($0))" }, branches].compactMap { $0 }.joined(separator: " \u{00B7} ")
        let checks = source.array("checks") ?? []
        card.addRows(checks.compactMap(row))
        let state = input.string("state")
        let conflicts = input.number("conflicts") ?? 0
        let tones = card.rows.compactMap(\.tone)
        switch state {
        case "merged": card.status = KitStatus(text: "Merged", tone: .info)
        case "closed": card.status = KitStatus(text: "Closed", tone: .neutral)
        case "conflict": card.status = KitStatus(text: KitFormat.count(Int(conflicts), "conflict"), tone: .critical)
        case "ready": card.status = KitStatus(text: "Ready to merge", tone: .positive)
        default:
            if tones.contains(.critical) { card.status = KitStatus(text: "Checks failing", tone: .critical) }
            else if tones.contains(.warning) { card.status = KitStatus(text: "Checks running", tone: .warning) }
            else if state != nil { card.status = KitStatus(text: "Open", tone: .positive) }
        }
        if checks.isEmpty, let count = source.number("checks") { card.addFact("Checks", KitFormat.number(count)) }
        card.addFact("Head", head)
        card.addFact("Base", base)
    }

    private static func health(_ card: inout KitCardModel, _ p: KitProps) -> Bool {
        let headline = KitProps(p.object("headline") ?? [:])
        if let value = headline.number("value") {
            let unit = headline.string("unit").map { " \($0)" } ?? ""
            let goal = headline.number("goal")
            card.hero = KitHero(value: KitFormat.number(value) + unit,
                                caption: [headline.string("label"), goal.map { "goal \(KitFormat.number($0))\(unit)" }].compactMap { $0 }.joined(separator: " \u{00B7} "),
                                progress: goal.flatMap { $0 > 0 ? min(max(value / $0, 0), 1) : nil })
        }
        card.subtitle = p.string("day")
        card.addRows((p.array("metrics") ?? []).compactMap { metric in
            let m = KitProps(metric.objectValue ?? [:])
            guard let label = m.string("label") else { return nil }
            return KitRow(id: 0, title: label, trailing: m.number("value").map { KitFormat.number($0) + (m.string("unit").map { " \($0)" } ?? "") })
        })
        return !card.isPlaceholder
    }
}

struct KitProps {
    let raw: [String: ForkJSON]

    init(_ raw: [String: ForkJSON]) { self.raw = raw }

    var keys: [String] { raw.keys.sorted() }

    func string(_ key: String) -> String? {
        if case .string(let text)? = raw[key], !text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
        return nil
    }

    func number(_ key: String) -> Double? {
        if case .number(let value)? = raw[key], value.isFinite { return value }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if case .bool(let flag)? = raw[key] { return flag }
        return nil
    }

    func array(_ key: String) -> [ForkJSON]? {
        if case .array(let items)? = raw[key] { return items }
        return nil
    }

    func object(_ key: String) -> [String: ForkJSON]? {
        raw[key]?.objectValue
    }

    func strings(_ key: String) -> [String] {
        (array(key) ?? []).compactMap { KitFormat.scalar($0, key: key) }.filter { !$0.isEmpty }
    }
}

extension ForkJSON {
    var objectValue: [String: ForkJSON]? {
        if case .object(let fields) = self { return fields }
        return nil
    }
}

enum KitFormat {
    static func title(_ key: String) -> String {
        var words: [String] = []
        var current = ""
        for character in key {
            if character == "_" || character == "-" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, !current.isEmpty, current.last?.isLowercase == true {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        guard let first = words.first else { return key }
        return ([capitalized(first)] + words.dropFirst().map { $0.lowercased() }).joined(separator: " ")
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static func number(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return grouped(Int64(value)) }
        let fixed = String(format: "%.2f", value)
        var trimmed = fixed
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        let parts = trimmed.split(separator: ".", maxSplits: 1)
        let whole = Int64(parts[0]) ?? 0
        let sign = value < 0 && whole == 0 ? "-" : ""
        return sign + grouped(whole) + (parts.count > 1 ? "." + parts[1] : "")
    }

    static func grouped(_ value: Int64) -> String {
        let digits = String(value.magnitude)
        var out = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(character)
        }
        return (value < 0 ? "-" : "") + out
    }

    static func money(_ value: Double, currency: String) -> String {
        let symbols = ["USD": "$", "EUR": "\u{20AC}", "GBP": "\u{00A3}", "JPY": "\u{00A5}", "CAD": "CA$", "AUD": "A$"]
        let cents = (abs(value) * 100).rounded()
        let whole = grouped(Int64(cents / 100))
        let fraction = String(format: "%02d", Int(cents.truncatingRemainder(dividingBy: 100)))
        let amount = currency == "JPY" ? whole : "\(whole).\(fraction)"
        let prefix = symbols[currency.uppercased()] ?? "\(currency.uppercased()) "
        return (value < 0 ? "-" : "") + prefix + amount
    }

    static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    static func count(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    static func scalar(_ value: ForkJSON, key: String) -> String? {
        switch value {
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .number(let number):
            guard number.isFinite else { return nil }
            if key.hasSuffix("At"), number > 1e12 {
                return timestamp(Date(timeIntervalSince1970: number / 1000))
            }
            return self.number(number)
        case .bool(let flag): return flag ? "Yes" : "No"
        default: return nil
        }
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: date)
    }

    static func tone(_ status: String) -> KitTone? {
        switch status.lowercased() {
        case "pass", "passed", "ok", "ready", "done", "success", "succeeded", "healthy", "online", "merged": .positive
        case "running", "pending", "queued", "working", "building", "in progress", "warn", "warning", "degraded": .warning
        case "fail", "failed", "error", "blocked", "down", "offline", "critical", "conflict": .critical
        case "skip", "skipped", "idle", "closed": .neutral
        default: nil
        }
    }
}
