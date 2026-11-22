import SwiftUI

struct ForkShareReviewRequest: Identifiable {
    let share: SharedImportReservation
    var id: String { share.reservationID }
}

extension ForkShareAction {
    var title: String {
        switch self {
        case .useAsIs: String(localized: "Use as Is", table: "Fork")
        case .summarize: String(localized: "Summarize", table: "Fork")
        case .explain: String(localized: "Explain", table: "Fork")
        case .research: String(localized: "Research", table: "Fork")
        case .extractTasks: String(localized: "Extract Tasks", table: "Fork")
        case .remember: String(localized: "Remember", table: "Fork")
        case .fillFromDocument: String(localized: "Fill from Document", table: "Fork")
        }
    }

    var systemImage: String {
        switch self {
        case .useAsIs: "text.cursor"
        case .summarize: "text.append"
        case .explain: "lightbulb"
        case .research: "magnifyingglass"
        case .extractTasks: "checklist"
        case .remember: "brain"
        case .fillFromDocument: "doc.text"
        }
    }

    static func localizedPrompt(_ action: ForkShareAction, _ text: String?) -> String {
        guard let text else {
            return switch action {
            case .useAsIs: ""
            case .summarize: String(localized: "Summarize the attached content.", table: "Fork")
            case .explain: String(localized: "Explain the attached content clearly.", table: "Fork")
            case .research: String(localized: "Research the attached content, verify the important claims, and cite sources.", table: "Fork")
            case .extractTasks: String(localized: "Extract the decisions, deadlines, owners, and action items from the attached content.", table: "Fork")
            case .remember: String(localized: "Save the durable facts from the attached content to memory, then confirm what was kept.", table: "Fork")
            case .fillFromDocument: String(localized: "Use the attached content to fill the relevant document or form fields. Ask before submitting anything.", table: "Fork")
            }
        }
        return switch action {
        case .useAsIs: text
        case .summarize: String(localized: "Summarize this content:\n\n\(text)", table: "Fork")
        case .explain: String(localized: "Explain this content clearly:\n\n\(text)", table: "Fork")
        case .research: String(localized: "Research this content, verify the important claims, and cite sources:\n\n\(text)", table: "Fork")
        case .extractTasks: String(localized: "Extract the decisions, deadlines, owners, and action items from this content:\n\n\(text)", table: "Fork")
        case .remember: String(localized: "Save the durable facts from this content to memory, then confirm what was kept:\n\n\(text)", table: "Fork")
        case .fillFromDocument: String(localized: "Use this content to fill the relevant document or form fields. Ask before submitting anything:\n\n\(text)", table: "Fork")
        }
    }
}

extension ForkShareProject {
    init?(_ project: ProjectSummary) {
        guard let id = project.projectId else { return nil }
        self.init(id: id, name: project.name ?? id, folder: project.hermes?.folder)
    }
}

extension SharedImportReservation {
    func applying(_ choice: ForkShareChoice) -> SharedImportReservation {
        let shared = sharedImport
        let draft = choice.action.prompt(for: shared.draft, hasAttachments: !shared.attachments.isEmpty,
                                         wording: ForkShareAction.localizedPrompt)
        return SharedImportReservation(itemID: itemID, reservationID: reservationID, createdAt: createdAt,
                                       sharedImport: SharedImport(draft: draft, attachments: shared.attachments,
                                                                  shortcut: shared.shortcut, skipped: shared.skipped))
    }
}

extension HermesSessionChat {
    func applying(_ choice: ForkShareChoice) -> HermesSessionChat {
        guard let folder = choice.project?.folder, case .new(let profile, _, let model) = target else { return self }
        var chat = self
        chat.target = .new(profile: profile, cwd: folder, model: model)
        return chat
    }
}

struct ForkShareReviewSheet: View {
    let request: ForkShareReviewRequest
    let projects: [ForkShareProject]
    let decide: (ForkShareChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice = ForkShareChoice()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(ForkShareAction.allCases) { action in
                            actionChip(action)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Action", tableName: "Fork")
                }
                Section {
                    Picker(selection: $choice.project) {
                        Text("New Chat", tableName: "Fork").tag(ForkShareProject?.none)
                        ForEach(projects) { project in
                            Text(verbatim: project.name).tag(Optional(project))
                        }
                    } label: {
                        Text("Destination", tableName: "Fork")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Destination", tableName: "Fork")
                } footer: {
                    if projects.isEmpty {
                        Text("No Projects with a folder on this Profile. The share opens in a new chat.", tableName: "Fork")
                    } else {
                        Text("A Project chat starts in that Project’s folder.", tableName: "Fork")
                    }
                }
            }
            .navigationTitle(String(localized: "Share to Hermes", table: "Fork"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Not Now", table: "Fork")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Add to Chat", table: "Fork")) { decide(choice) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var preview: some View {
        let text = request.share.sharedImport.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = request.share.sharedImport.attachments.count
        if !text.isEmpty {
            Text(verbatim: text)
                .font(AppFont.footnote())
                .foregroundStyle(.appSecondary)
                .lineLimit(4)
        }
        if files > 0 {
            Label {
                Text("Attachments: \(files)", tableName: "Fork")
            } icon: {
                Image(systemName: "paperclip")
            }
            .font(AppFont.footnote())
        }
    }

    private func actionChip(_ action: ForkShareAction) -> some View {
        let isSelected = choice.action == action
        return Button {
            choice.action = action
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .font(AppFont.footnote(weight: isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.appFillTertiary))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
