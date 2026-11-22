import Foundation

enum CouncilPhase: Equatable, Sendable {
    case seated, brief, sending, working, report, done
}

enum CouncilSeatState: Equatable, Sendable {
    case waiting, received, thinking, drafting, done
}

enum CouncilNarration: Equatable, Sendable {
    case seated(seats: Int, rounds: Int, helpers: Int)
    case writingBrief
    case sendingBrief
    case takingSeats
    case helper(seat: Int)
    case answersAlone(seat: Int)
    case questions(round: Int, seat: Int, cites: [Int])
    case closes(round: Int, seat: Int)
    case complete(rounds: Int, helpers: Int)
}

enum CouncilClause: Equatable, Sendable {
    case verdict(outcome: String?, recorded: Bool)
    case replies(CouncilStance, [CouncilVerdict])
    case receipts([CouncilReceipt])
}

struct CouncilReceipt: Equatable, Sendable {
    let round: Int
    let seat: Int
    let cites: [Int]
}

struct CouncilTiming: Equatable, Sendable {
    static let turn = 0.52
    static let spawn = 0.09
    static let delivery = 0.9
    static let clause = 0.65

    let starts: [Double]
    let sitting: Double
    let typing: Double
    let working: Double
    let report: Double
    let total: Double

    init(run: CouncilRun, reduceMotion: Bool) {
        var starts: [Double] = []
        var clock = 0.0
        for event in run.events {
            starts.append(clock)
            clock += event.isSpawn ? Self.spawn : Self.turn
        }
        self.starts = starts
        sitting = clock
        let characters = run.brief.count + run.constraints.joined().count
        typing = reduceMotion ? 0 : min(3.2, max(0.9, Double(characters) * 0.024))
        working = typing + (reduceMotion ? 0 : Self.delivery)
        report = working + sitting
        total = report + (reduceMotion ? 0 : Double(CouncilReport.clauses(run).count) * Self.clause)
    }
}

struct CouncilExchange: Equatable, Sendable {
    let phase: CouncilPhase
    let brief: String
    let constraints: [String]
    let delivery: Double
    let seats: [CouncilSeatState]
    let closed: Set<Int>
    let clauses: [CouncilClause]
    let narration: CouncilNarration
    let round: Int

    var playing: Bool { phase != .seated && phase != .done }

    init(run: CouncilRun, timing: CouncilTiming, elapsed t: Double?) {
        let elapsed = max(0, t ?? 0)
        let phase: CouncilPhase
        if t == nil {
            phase = .seated
        } else if elapsed < timing.typing {
            phase = .brief
        } else if elapsed < timing.working {
            phase = .sending
        } else if elapsed < timing.report {
            phase = .working
        } else if elapsed < timing.total {
            phase = .report
        } else {
            phase = .done
        }
        self.phase = phase
        let sitting: Double? = t == nil || elapsed < timing.working ? nil : min(timing.sitting, elapsed - timing.working)
        let finished = sitting.map { $0 >= timing.sitting } ?? false
        var current = -1
        if let sitting {
            for (index, start) in timing.starts.enumerated() where start <= sitting { current = index }
        }
        var lastTurn = Array(repeating: -1, count: run.seats.count)
        for (index, event) in run.events.enumerated() {
            if case .turn(let seat, _, _) = event { lastTurn[seat] = index }
        }
        var closed = Set<Int>()
        if let sitting {
            let since = current >= 0 ? sitting - timing.starts[current] : 0
            for seat in run.seats.indices {
                let last = lastTurn[seat]
                if finished || (last >= 0 && (current > last || (current == last && since >= CouncilTiming.turn))) {
                    closed.insert(seat)
                }
            }
        }
        self.closed = closed
        var round = 0
        if current >= 0 {
            for event in run.events[0...current] {
                if case .turn(_, let turnRound, _) = event { round = turnRound }
            }
        }
        self.round = round
        switch phase {
        case .sending: delivery = (elapsed - timing.typing) / CouncilTiming.delivery
        case .seated, .brief: delivery = 0
        case .working, .report, .done: delivery = 1
        }
        var typed = phase == .brief ? Int(Double(run.brief.count + run.constraints.joined().count) * elapsed / timing.typing) : Int.max
        brief = String(run.brief.prefix(max(0, typed)))
        typed = typed == Int.max ? typed : typed - run.brief.count
        constraints = run.constraints.map { line in
            let shown = String(line.prefix(max(0, typed)))
            if typed != Int.max { typed -= line.count }
            return shown
        }
        let delivery = self.delivery
        seats = run.seats.indices.map { seat in
            if closed.contains(seat) { return .done }
            if let sitting {
                let drafting = run.events.indices.contains { index in
                    guard case .turn(let speaker, _, _) = run.events[index], speaker == seat else { return false }
                    return sitting >= timing.starts[index] && sitting < timing.starts[index] + CouncilTiming.turn
                }
                return drafting ? .drafting : .thinking
            }
            return t != nil && delivery >= Double(seat + 1) / Double(run.seats.count) ? .received : .waiting
        }
        let all = CouncilReport.clauses(run)
        switch phase {
        case .done: clauses = all
        case .report: clauses = Array(all.prefix(1 + Int((elapsed - timing.report) / CouncilTiming.clause)))
        default: clauses = []
        }
        switch phase {
        case .seated: narration = .seated(seats: run.seats.count, rounds: run.rounds, helpers: run.helpers)
        case .brief: narration = .writingBrief
        case .sending: narration = .sendingBrief
        default:
            if finished {
                narration = .complete(rounds: run.rounds, helpers: run.helpers)
            } else if current < 0 {
                narration = .takingSeats
            } else {
                switch run.events[current] {
                case .spawn(let seat): narration = .helper(seat: seat)
                case .turn(let seat, 1, _): narration = .answersAlone(seat: seat)
                case .turn(let seat, let turnRound, _) where turnRound == run.rounds: narration = .closes(round: turnRound, seat: seat)
                case .turn(let seat, let turnRound, let cites): narration = .questions(round: turnRound, seat: seat, cites: cites)
                }
            }
        }
    }
}

enum CouncilReport {
    static func clauses(_ run: CouncilRun) -> [CouncilClause] {
        var clauses: [CouncilClause] = [.verdict(outcome: run.outcome, recorded: !run.verdicts.isEmpty)]
        for stance in CouncilStance.allCases {
            clauses.append(.replies(stance, run.verdicts.filter { $0.stance == stance }))
        }
        let receipts = run.seats.indices.compactMap { seat -> CouncilReceipt? in
            for event in run.events.reversed() {
                if case .turn(seat, let round, let cites) = event, !cites.isEmpty {
                    return CouncilReceipt(round: round, seat: seat, cites: cites)
                }
            }
            return nil
        }
        clauses.append(.receipts(receipts))
        return clauses
    }
}
