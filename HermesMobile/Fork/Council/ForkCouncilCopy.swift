import Foundation

enum ForkCouncilCopy {
    static func seatList(_ seats: [Int], in run: CouncilRun) -> String {
        ListFormatter.localizedString(byJoining: seats.map(run.seatName))
    }

    static func narration(_ narration: CouncilNarration, run: CouncilRun) -> String {
        switch narration {
        case .seated(let seats, let rounds, let helpers):
            return String(localized: "\(seats) seats · \(rounds) rounds · \(helpers) helpers. Convene to watch it sit.", table: "Fork")
        case .writingBrief:
            return String(localized: "Writing the brief…", table: "Fork")
        case .sendingBrief:
            return String(localized: "Sending the brief to each seat…", table: "Fork")
        case .takingSeats:
            return String(localized: "The council takes its seats", table: "Fork")
        case .helper(let seat):
            let name = run.seatName(seat)
            return String(localized: "\(name) sends a helper out", table: "Fork")
        case .answersAlone(let seat):
            let name = run.seatName(seat)
            return String(localized: "Round 1 · \(name) answers the brief, alone", table: "Fork")
        case .questions(let round, let seat, let cites):
            let name = run.seatName(seat)
            let names = seatList(cites, in: run)
            return String(localized: "Round \(round) · \(name) questions \(names)", table: "Fork")
        case .closes(let round, let seat):
            let name = run.seatName(seat)
            return String(localized: "Round \(round) · \(name) closes", table: "Fork")
        case .complete(let rounds, let helpers):
            return String(localized: "Council complete · \(rounds) rounds · \(helpers) helpers", table: "Fork")
        }
    }

    static func tally(_ run: CouncilRun) -> String {
        let agree = run.count(.agree)
        let dissent = run.count(.dissent)
        let abstain = run.count(.abstain)
        let total = run.verdicts.count
        if abstain > 0 {
            return String(localized: "\(agree) of \(total) agree · \(dissent) dissent · \(abstain) abstain", table: "Fork")
        }
        return String(localized: "\(agree) of \(total) agree · \(dissent) dissent", table: "Fork")
    }

    static func sitting(_ run: CouncilRun) -> String {
        let seats = run.seats.count
        let rounds = run.rounds
        return String(localized: "\(seats) seats · \(rounds) rounds · verdicts appear as each seat closes", table: "Fork")
    }

    static func state(_ state: CouncilSeatState) -> String {
        switch state {
        case .waiting: String(localized: "Waiting", table: "Fork")
        case .received: String(localized: "Received", table: "Fork")
        case .thinking: String(localized: "Thinking", table: "Fork")
        case .drafting: String(localized: "Drafting", table: "Fork")
        case .done: String(localized: "Done", table: "Fork")
        }
    }

    static func stance(_ stance: CouncilStance) -> String {
        switch stance {
        case .agree: String(localized: "Agree", table: "Fork")
        case .dissent: String(localized: "Dissent", table: "Fork")
        case .abstain: String(localized: "Abstain", table: "Fork")
        }
    }

    static func label(_ clause: CouncilClause) -> String {
        switch clause {
        case .verdict: String(localized: "Verdict", table: "Fork")
        case .replies(.agree, _): String(localized: "Agreements", table: "Fork")
        case .replies(.dissent, _): String(localized: "Dissent", table: "Fork")
        case .replies(.abstain, _): String(localized: "Abstentions", table: "Fork")
        case .receipts: String(localized: "Receipts", table: "Fork")
        }
    }

    static func text(_ clause: CouncilClause, run: CouncilRun) -> String {
        switch clause {
        case .verdict(let outcome, let recorded):
            if let outcome { return outcome }
            return recorded ? String(localized: "Recorded seat replies", table: "Fork") : String(localized: "No verdict recorded", table: "Fork")
        case .replies(_, let verdicts):
            guard !verdicts.isEmpty else { return String(localized: "None recorded.", table: "Fork") }
            return verdicts.map { verdict in
                let name = run.seatName(verdict.seat)
                let text = verdict.text
                return String(localized: "\(name): \(text)", table: "Fork")
            }.joined(separator: " ")
        case .receipts(let receipts):
            guard !receipts.isEmpty else { return String(localized: "No citation receipts recorded.", table: "Fork") }
            return receipts.map { receipt in
                let round = receipt.round
                let name = run.seatName(receipt.seat)
                let names = seatList(receipt.cites, in: run)
                return String(localized: "Round \(round): \(name) cited \(names).", table: "Fork")
            }.joined(separator: " ")
        }
    }

    static func speech(_ reading: CouncilReading, run: CouncilRun) -> String {
        switch reading {
        case .brief:
            return ([run.brief] + run.constraints).joined(separator: " ")
        case .report:
            return CouncilReport.clauses(run).map { clause in
                let heading = label(clause)
                let body = text(clause, run: run)
                return heading.hasSuffix(".") ? "\(heading) \(body)" : "\(heading). \(body)"
            }.joined(separator: " ")
        }
    }
}
