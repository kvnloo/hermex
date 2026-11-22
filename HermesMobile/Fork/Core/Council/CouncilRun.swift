import Foundation

enum CouncilMineral: String, CaseIterable, Sendable {
    case citrine, rose, smoky, clear, malachite, labradorite, moonstone, lapis

    var hex: String {
        switch self {
        case .citrine: "#DC9A32"
        case .rose: "#D99A9C"
        case .smoky: "#8B735B"
        case .clear: "#C9D2D0"
        case .malachite: "#2F8A5C"
        case .labradorite: "#3A424B"
        case .moonstone: "#C4C8D0"
        case .lapis: "#25418F"
        }
    }

    static func pool(family: String) -> [CouncilMineral] {
        switch family.trimmingCharacters(in: .whitespaces).lowercased() {
        case "anthropic": [.citrine, .rose, .smoky]
        case "openai": [.labradorite, .moonstone, .lapis]
        case "google": [.malachite]
        default: [.clear]
        }
    }
}

enum CouncilStance: String, CaseIterable, Sendable {
    case agree, dissent, abstain
}

struct CouncilSeat: Equatable, Sendable {
    let id: String
    let name: String
    let family: String
    let mineral: CouncilMineral
    let crew: [CouncilMineral]
}

enum CouncilEvent: Equatable, Sendable {
    case turn(seat: Int, round: Int, cites: [Int])
    case spawn(seat: Int)

    var isSpawn: Bool {
        if case .spawn = self { return true }
        return false
    }
}

struct CouncilVerdict: Equatable, Sendable {
    let seat: Int
    let stance: CouncilStance
    let text: String
}

struct CouncilRunError: Error, Equatable, CustomStringConvertible {
    let path: String
    let problem: String

    var description: String { "not a \(CouncilRun.schema) run (\(path): \(problem))" }
}

struct CouncilRun: Equatable, Sendable {
    static let schema = "glide.council-run/v1"

    let brief: String
    let constraints: [String]
    let rounds: Int
    let seats: [CouncilSeat]
    let events: [CouncilEvent]
    let verdicts: [CouncilVerdict]
    let outcome: String?

    func count(_ stance: CouncilStance) -> Int {
        verdicts.filter { $0.stance == stance }.count
    }

    var helpers: Int { events.filter(\.isSpawn).count }

    var carried: Bool { count(.agree) > count(.dissent) }

    func seatName(_ index: Int) -> String {
        seats.indices.contains(index) ? seats[index].name : "?"
    }

    func verdict(seat: Int) -> CouncilVerdict? {
        verdicts.first { $0.seat == seat }
    }

    static func parse(json: Data) throws -> CouncilRun {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: json)
        } catch {
            throw CouncilRunError(path: "run", problem: "expected JSON")
        }
        return try parse(object)
    }

    static func parse(_ raw: Any) throws -> CouncilRun {
        let run = try Reader.object(raw, "run")
        guard run["schema"] as? String == schema else {
            throw CouncilRunError(path: "schema", problem: "expected \"\(schema)\"")
        }
        let rounds = try Reader.integer(run["rounds"], "rounds", 1...8)
        var index: [String: Int] = [:]
        var used: [String: Int] = [:]
        let seats = try Reader.list(run["seats"], "seats", 2...6).enumerated().map { offset, value -> CouncilSeat in
            let path = "seats.\(offset)"
            let seat = try Reader.object(value, path)
            let id = try Reader.text(seat["id"], "\(path).id", 40)
            guard id.range(of: #"^[a-z0-9][a-z0-9._-]{0,39}$"#, options: .regularExpression) != nil else {
                throw CouncilRunError(path: "\(path).id", problem: "expected a lowercase id")
            }
            guard index[id] == nil else { throw CouncilRunError(path: "\(path).id", problem: "two seats share an id") }
            index[id] = offset
            let family = try Reader.text(seat["family"], "\(path).family", 24)
            let key = family.trimmingCharacters(in: .whitespaces).lowercased()
            let pool = CouncilMineral.pool(family: family)
            let nth = used[key, default: 0]
            used[key] = nth + 1
            let mineral = try seat["mineral"].map { try Reader.mineral($0, "\(path).mineral") } ?? pool[nth % pool.count]
            let crew = try seat["crew"].map { value in
                try Reader.list(value, "\(path).crew", 0...12).enumerated().map { try Reader.mineral($1, "\(path).crew.\($0)") }
            } ?? []
            return CouncilSeat(id: id, name: try Reader.text(seat["name"], "\(path).name", 24), family: family, mineral: mineral, crew: crew)
        }
        func seat(_ value: Any?, _ path: String) throws -> Int {
            guard let id = value as? String, let found = index[id] else {
                throw CouncilRunError(path: path, problem: "names an unknown seat")
            }
            return found
        }
        let events = try Reader.list(run["events"], "events", 0...400).enumerated().map { offset, value -> CouncilEvent in
            let path = "events.\(offset)"
            let event = try Reader.object(value, path)
            switch event["type"] as? String {
            case "spawn":
                return .spawn(seat: try seat(event["seat"], "\(path).seat"))
            case "turn":
                let cites = try event["cites"].map { value in
                    try Reader.list(value, "\(path).cites", 0...6).enumerated().map { try seat($1, "\(path).cites.\($0)") }
                } ?? []
                return .turn(seat: try seat(event["seat"], "\(path).seat"),
                             round: try Reader.integer(event["round"], "\(path).round", 1...rounds), cites: cites)
            default:
                throw CouncilRunError(path: "\(path).type", problem: "expected \"turn\" or \"spawn\"")
            }
        }
        var heard = Set<Int>()
        let verdicts = try Reader.list(run["verdicts"], "verdicts", 0...6).enumerated().map { offset, value -> CouncilVerdict in
            let path = "verdicts.\(offset)"
            let verdict = try Reader.object(value, path)
            let index = try seat(verdict["seat"], "\(path).seat")
            guard heard.insert(index).inserted else {
                throw CouncilRunError(path: "\(path).seat", problem: "seat already has a verdict")
            }
            guard let stance = (verdict["stance"] as? String).flatMap(CouncilStance.init(rawValue:)) else {
                throw CouncilRunError(path: "\(path).stance", problem: "expected agree, dissent or abstain")
            }
            return CouncilVerdict(seat: index, stance: stance, text: try Reader.text(verdict["text"], "\(path).text", 240))
        }
        let constraints = try run["constraints"].map { value in
            try Reader.list(value, "constraints", 0...8).enumerated().map { try Reader.text($1, "constraints.\($0)", 160) }
        } ?? []
        return CouncilRun(brief: try Reader.text(run["brief"], "brief", 280), constraints: constraints, rounds: rounds,
                          seats: seats, events: events, verdicts: verdicts,
                          outcome: try run["outcome"].map { try Reader.text($0, "outcome", 160) })
    }

    static func latest(in contents: [String]) -> CouncilRun? {
        for content in contents.reversed() {
            if let run = candidates(in: content).lazy.compactMap({ try? parse(json: Data($0.utf8)) }).first {
                return run
            }
        }
        return nil
    }

    static func candidates(in content: String) -> [String] {
        guard content.contains(schema) else { return [] }
        var blocks: [String] = []
        var fence: [String]?
        for line in content.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let open = fence {
                    blocks.append(open.joined(separator: "\n"))
                    fence = nil
                } else {
                    fence = []
                }
            } else if fence != nil {
                fence?.append(line)
            }
        }
        let whole = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if whole.hasPrefix("{") { blocks.append(whole) }
        return blocks.filter { $0.contains(schema) }
    }

    static let demo: CouncilRun = {
        let crew = ["clear", "clear", "clear", "clear", "clear", "moonstone", "moonstone", "smoky", "smoky"]
        let seats: [[String: Any]] = [
            ["id": "argon", "name": "Argon", "family": "Google", "crew": crew],
            ["id": "astra", "name": "Astra", "family": "OpenAI", "crew": crew],
            ["id": "fable", "name": "Fable", "family": "Anthropic", "mineral": "rose", "crew": crew],
            ["id": "opus", "name": "Opus", "family": "Anthropic", "mineral": "citrine", "crew": crew],
        ]
        let ids = ["argon", "astra", "fable", "opus"]
        var events: [[String: Any]] = []
        for id in ids { for _ in 0..<4 { events.append(["type": "spawn", "seat": id]) } }
        for round in 1...4 {
            for (offset, id) in ids.enumerated() {
                if round == 2 { for _ in 0..<3 { events.append(["type": "spawn", "seat": id]) } }
                let peers = ids.filter { $0 != id }
                let cites: [String] = round == 1 ? [] : round == 4 ? [peers[offset % 3]] : Array(peers.prefix(round == 2 ? 3 : 2))
                events.append(["type": "turn", "seat": id, "round": round, "cites": cites])
            }
        }
        for id in ids { for _ in 0..<2 { events.append(["type": "spawn", "seat": id]) } }
        let raw: [String: Any] = [
            "schema": schema,
            "brief": "Should a small team ship a plugin before its launcher?",
            "constraints": ["Keep the first release small.", "Use installation receipts to decide what comes next."],
            "rounds": 4,
            "seats": seats,
            "events": events,
            "verdicts": [
                ["seat": "argon", "stance": "agree", "text": "Ship the plugin; the launcher only wraps what already works."],
                ["seat": "astra", "stance": "dissent", "text": "Without the launcher nobody finds the plugin; ship both together."],
                ["seat": "fable", "stance": "agree", "text": "Ship it, and measure who installs it by hand before building more."],
                ["seat": "opus", "stance": "agree", "text": "Agree with Fable: the plugin first, the launcher once installs prove demand."],
            ],
            "outcome": "Ship the plugin first",
        ]
        do {
            return try parse(raw)
        } catch {
            preconditionFailure("demo council run: \(error)")
        }
    }()
}

private enum Reader {
    static func object(_ value: Any?, _ path: String) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw CouncilRunError(path: path, problem: "expected an object") }
        return object
    }

    static func text(_ value: Any?, _ path: String, _ limit: Int) throws -> String {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= limit else {
            throw CouncilRunError(path: path, problem: "expected text of 1-\(limit) characters")
        }
        return text
    }

    static func integer(_ value: Any?, _ path: String, _ range: ClosedRange<Int>) throws -> Int {
        guard let number = value as? NSNumber, let whole = Int(exactly: number.doubleValue), range.contains(whole) else {
            throw CouncilRunError(path: path, problem: "expected a whole number \(range.lowerBound)-\(range.upperBound)")
        }
        return whole
    }

    static func list(_ value: Any?, _ path: String, _ range: ClosedRange<Int>) throws -> [Any] {
        guard let list = value as? [Any], range.contains(list.count) else {
            throw CouncilRunError(path: path, problem: "expected a list of \(range.lowerBound)-\(range.upperBound)")
        }
        return list
    }

    static func mineral(_ value: Any, _ path: String) throws -> CouncilMineral {
        guard let mineral = (value as? String).flatMap(CouncilMineral.init(rawValue:)) else {
            throw CouncilRunError(path: path, problem: "not a known mineral")
        }
        return mineral
    }
}
