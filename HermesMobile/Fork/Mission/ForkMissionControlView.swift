import SwiftUI

struct ForkMissionControlEntry: Identifiable {
    let id = UUID()
    let server: URL
    let connection: BotConnection
}

extension View {
    func forkMissionControl(_ entry: Binding<ForkMissionControlEntry?>) -> some View {
        sheet(item: entry) { entry in
            ForkMissionControlView(connection: entry.connection, server: entry.server)
        }
    }
}

struct ForkMissionControlSidebarRow: View {
    let action: () -> Void

    var body: some View {
        HapticButton(action: action) {
            HStack(spacing: 18) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(.appText))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text("Mission Control", tableName: "Fork")
                    .font(AppFont.body(weight: .semibold))
                    .foregroundStyle(.appPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ForkMissionControlView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ForkMissionControlModel

    init(connection: BotConnection, server: URL) {
        _model = State(initialValue: ForkMissionControlModel(client: ForkMissionClient(saved: connection, server: server)))
    }

    var body: some View {
        NavigationStack {
            AppList {
                if let board = model.board {
                    if let actionError = model.actionError {
                        Section { Text(verbatim: actionError).foregroundStyle(.red) }
                    }
                    ForEach(board.sections) { section in
                        ForkMissionSectionView(section: section, model: model)
                    }
                } else {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .settingsPage(String(localized: "Mission Control", table: "Fork"))
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
        .task { await model.follow() }
    }
}

private struct ForkMissionSectionView: View {
    let section: ForkMissionSection
    let model: ForkMissionControlModel

    var body: some View {
        Section {
            switch section.notice {
            case .unsupported:
                Text("This host doesn't report this.", tableName: "Fork").foregroundStyle(.appSecondary)
            case .failed(let message):
                Text(verbatim: message).foregroundStyle(.appSecondary)
            case nil:
                ForEach(section.nodes) { node in
                    NavigationLink {
                        ForkMissionDetailView(missionID: node.mission.id, model: model)
                    } label: {
                        ForkMissionRow(mission: node.mission)
                            .padding(.leading, CGFloat(min(node.depth, 6)) * 16)
                    }
                }
                if section.nodes.allSatisfy({ $0.mission.kind == .delegation }) {
                    section.kind.emptyText.foregroundStyle(.appSecondary)
                }
            }
        } header: {
            section.kind.header
        } footer: {
            if section.kind == .subagent, section.notice == nil {
                Text("Pausing stops new workers from starting. Running workers carry on.", tableName: "Fork")
            }
        }
    }
}

private struct ForkMissionRow: View {
    let mission: ForkMission

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(mission.stateColor).frame(width: 9, height: 9).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                mission.titleText.font(AppFont.body()).lineLimit(2)
                HStack(spacing: 6) {
                    mission.stateText
                    if let detail = mission.detail {
                        Text(verbatim: "·")
                        Text(verbatim: detail).lineLimit(1)
                    }
                }
                .font(AppFont.caption())
                .foregroundStyle(.appSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ForkMissionDetailView: View {
    let missionID: String
    let model: ForkMissionControlModel

    var body: some View {
        AppList {
            if let mission = model.board?.mission(missionID) {
                Section {
                    LabeledContent { mission.stateText } label: { Text("Status") }
                    if let detail = mission.detail {
                        LabeledContent { Text(verbatim: detail).textSelection(.enabled).lineLimit(3) } label: {
                            mission.kind == .task ? Text("Schedule") : Text("Model")
                        }
                    }
                    if let tools = mission.toolCount {
                        Text("\(tools) tools", tableName: "Fork")
                    }
                    if let uptime = mission.uptime {
                        Text(verbatim: Duration.seconds(uptime).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
                    }
                    if let lastError = mission.lastError {
                        Text(verbatim: lastError).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                Section {
                    ForEach(ForkMissionCommand.allCases, id: \.self) { command in
                        ForkMissionCommandRow(command: command, mission: mission, model: model)
                    }
                    if let actionError = model.actionError {
                        Text(verbatim: actionError).foregroundStyle(.red)
                    }
                } header: {
                    Text("Controls", tableName: "Fork")
                }
            } else {
                Section { Text("This item is no longer listed.", tableName: "Fork").foregroundStyle(.appSecondary) }
            }
        }
        .settingsPage(model.board?.mission(missionID).map { $0.titleString } ?? String(localized: "Mission Control", table: "Fork"))
    }
}

private struct ForkMissionCommandRow: View {
    let command: ForkMissionCommand
    let mission: ForkMission
    let model: ForkMissionControlModel

    var body: some View {
        let state = model.availability(command, for: mission)
        VStack(alignment: .leading, spacing: 4) {
            Button { Task { await model.perform(command, on: mission) } } label: {
                HStack {
                    command.label
                    if model.busyMission == mission.id { Spacer(); ProgressView() }
                }
            }
            .disabled(!state.isEnabled)
            .accessibilityHint(state.block.map { mission.reason($0, for: command) } ?? Text(verbatim: ""))
            if let block = state.block {
                mission.reason(block, for: command)
                    .font(AppFont.caption())
                    .foregroundStyle(.appSecondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

private extension ForkMissionKind {
    var header: Text {
        switch self {
        case .delegation, .subagent: Text("Agents and subagents", tableName: "Fork")
        case .task: Text("Tasks")
        case .process: Text("Background processes", tableName: "Fork")
        }
    }

    var emptyText: Text {
        switch self {
        case .delegation, .subagent: Text("No workers running.", tableName: "Fork")
        case .task: Text("No Tasks on this host.", tableName: "Fork")
        case .process: Text("No background processes.", tableName: "Fork")
        }
    }
}

private extension ForkMissionCommand {
    var label: Text {
        switch self {
        case .pause: Text("Pause")
        case .resume: Text("Resume")
        case .stop: Text("Stop")
        case .retry: Text("Retry")
        }
    }
}

private extension ForkMission {
    var titleString: String {
        switch kind {
        case .delegation: String(localized: "New workers", table: "Fork")
        case .subagent: title.isEmpty ? String(localized: "Delegated worker") : title
        case .task, .process: title
        }
    }

    var titleText: Text { Text(verbatim: titleString) }

    var stateText: Text {
        switch state {
        case .running: kind == .delegation ? Text("Allowed", tableName: "Fork") : Text("Running")
        case .pending: Text("Waiting")
        case .paused: Text("Paused")
        case .blocked: Text("Blocked")
        case .done: Text("Done")
        case .failed: Text("Failed")
        case .cancelled: Text("Cancelled")
        }
    }

    var stateColor: Color {
        switch state {
        case .running: kind == .delegation ? Color.green : Color.blue
        case .pending: Color(.appFill)
        case .paused, .blocked: .orange
        case .done: .green
        case .failed: .red
        case .cancelled: Color(.appFillTertiary)
        }
    }

    func reason(_ block: ForkMissionBlock, for command: ForkMissionCommand) -> Text {
        switch block {
        case .ownedByChat: Text("Only the chat that started this can stop it.", tableName: "Fork")
        case .alreadyPaused: Text("Already paused.", tableName: "Fork")
        case .notPaused: Text("Not paused.", tableName: "Fork")
        case .notRunning: Text("Not running.", tableName: "Fork")
        case .nothingToRetry: Text("The last run didn't fail.", tableName: "Fork")
        case .runningNow: Text("It's running now.", tableName: "Fork")
        case .busy: Text("Wait for the current action to finish.", tableName: "Fork")
        case .hostHasNoControl: hostReason(command)
        }
    }

    private func hostReason(_ command: ForkMissionCommand) -> Text {
        switch (kind, command) {
        case (.subagent, .pause), (.subagent, .resume):
            Text("The host can pause new workers, not a running one.", tableName: "Fork")
        case (.process, .pause), (.process, .resume):
            Text("The host can't pause a background process.", tableName: "Fork")
        case (.task, .stop):
            Text("The host can't stop a Task run once it starts.", tableName: "Fork")
        case (.delegation, .stop):
            Text("The host can't stop every worker at once.", tableName: "Fork")
        default:
            Text("The host has no retry for this.", tableName: "Fork")
        }
    }
}
