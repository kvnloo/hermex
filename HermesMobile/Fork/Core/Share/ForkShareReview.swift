import Foundation

enum ForkShareAction: String, CaseIterable, Identifiable, Sendable {
    case useAsIs, summarize, explain, research, extractTasks, remember, fillFromDocument

    var id: String { rawValue }

    func prompt(for shared: String, hasAttachments: Bool, wording: (ForkShareAction, String?) -> String) -> String {
        let text = shared.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .useAsIs { return text }
        if text.isEmpty { return hasAttachments ? wording(self, nil) : "" }
        return wording(self, text)
    }
}

struct ForkShareProject: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let folder: String

    init?(id: String, name: String, folder: String?) {
        guard let folder = folder?.trimmingCharacters(in: .whitespacesAndNewlines), !folder.isEmpty, !id.isEmpty
        else { return nil }
        self.id = id
        self.name = name.isEmpty ? id : name
        self.folder = folder
    }
}

struct ForkShareChoice: Equatable, Sendable {
    var action: ForkShareAction = .useAsIs
    var project: ForkShareProject?
}

struct ForkShareReviewGate: Equatable {
    enum Step: Equatable {
        case pass
        case wait
        case review
        case move(ForkShareChoice)
    }

    private(set) var reviewing: String?
    private var decided: [String: ForkShareChoice] = [:]

    mutating func step(for reservation: String, fromShareSheet: Bool) -> Step {
        guard fromShareSheet else { return .pass }
        if let choice = decided.removeValue(forKey: reservation) { return .move(choice) }
        if reviewing == reservation { return .wait }
        reviewing = reservation
        return .review
    }

    mutating func decide(_ reservation: String, _ choice: ForkShareChoice) {
        guard reviewing == reservation else { return }
        reviewing = nil
        decided = [reservation: choice]
    }

    mutating func settle() -> String? {
        defer { reviewing = nil }
        return reviewing
    }
}
