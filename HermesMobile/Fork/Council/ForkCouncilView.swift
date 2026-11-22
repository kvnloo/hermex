import SwiftUI
import UIKit

extension View {
    func forkCouncil(_ viewModel: ChatViewModel) -> some View {
        modifier(ForkCouncilEntry(viewModel: viewModel))
    }
}

private struct ForkCouncilEntry: ViewModifier {
    let viewModel: ChatViewModel
    @State private var presented: ForkCouncilSource?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: open) {
                        Label { Text("Council", tableName: "Fork") } icon: { Image(systemName: "person.3") }
                    }
                }
            }
            .sheet(item: $presented) { source in
                ForkCouncilView(run: source.run, live: source.live)
            }
    }

    private func open() {
        let replies = viewModel.messages.filter { $0.role == "assistant" }.compactMap(\.content)
        if let run = CouncilRun.latest(in: replies) {
            presented = ForkCouncilSource(run: run, live: true)
        } else {
            presented = ForkCouncilSource(run: .demo, live: false)
        }
    }
}

private struct ForkCouncilSource: Identifiable {
    let id = UUID()
    let run: CouncilRun
    let live: Bool
}

struct ForkCouncilView: View {
    @State private var controller: ForkCouncilController
    @Environment(\.dismiss) private var dismiss

    init(run: CouncilRun, live: Bool) {
        _controller = State(initialValue: ForkCouncilController(run: run, live: live, reduceMotion: UIAccessibility.isReduceMotionEnabled))
    }

    var body: some View {
        NavigationStack {
            Group {
                if controller.reader.reading != nil {
                    ForkCouncilSpeakingCard(caption: controller.caption) { controller.handle(.returnToCard) }
                } else {
                    ForkCouncilCard(controller: controller)
                }
            }
            .navigationTitle(Text("Socratic council", tableName: "Fork"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Close", tableName: "Fork") }
                }
            }
        }
        .onDisappear { controller.handle(.close) }
    }
}

private struct ForkCouncilSpeakingCard: View {
    let caption: String
    let onReturn: () -> Void

    var body: some View {
        Button(action: onReturn) {
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                ForkLiveOrb(phase: .speaking, level: 0.6, style: .thinking)
                    .frame(width: 220, height: 220)
                Text(verbatim: caption.isEmpty ? " " : caption)
                    .font(AppFont.title3())
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 24)
                Text("Tap to return to the council", tableName: "Fork")
                    .font(AppFont.footnote())
                    .foregroundStyle(.appSecondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: caption))
        .accessibilityHint(Text("Stops reading and returns to the council.", tableName: "Fork"))
    }
}

private struct ForkCouncilCard: View {
    let controller: ForkCouncilController

    var body: some View {
        let run = controller.run
        let exchange = controller.exchange
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                brief(run: run, exchange: exchange)
                verdict(run: run, exchange: exchange)
                Text(verbatim: ForkCouncilCopy.narration(exchange.narration, run: run))
                    .font(AppFont.callout())
                    .italic()
                    .foregroundStyle(.appSecondary)
                controls(exchange: exchange)
                VStack(spacing: 0) {
                    ForEach(run.seats.indices, id: \.self) { index in
                        ForkCouncilSeatRow(run: run, seat: index, state: exchange.seats[index], open: exchange.closed.contains(index))
                    }
                }
                if !exchange.clauses.isEmpty { report(run: run, clauses: exchange.clauses) }
                Text(verbatim: controller.live
                     ? String(localized: "Read from the latest council run in this chat. This view draws it and computes nothing.", table: "Fork")
                     : String(localized: "Demo run with synthetic seats and brief. A reply that quotes a glide.council-run/v1 run replaces it.", table: "Fork"))
                    .font(AppFont.caption())
                    .foregroundStyle(.appTertiary)
            }
            .padding(20)
        }
    }

    private func brief(run: CouncilRun, exchange: CouncilExchange) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("The Brief", tableName: "Fork")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(.appSecondary)
                Spacer()
                Text(verbatim: controller.live ? String(localized: "From this chat", table: "Fork") : String(localized: "Demo", table: "Fork"))
                    .font(AppFont.caption2(weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(controller.live ? Color.green.opacity(0.6) : Color.secondary.opacity(0.5)))
            }
            Text(verbatim: exchange.brief.isEmpty ? " " : exchange.brief)
                .font(AppFont.body())
            ForEach(Array(exchange.constraints.enumerated()), id: \.offset) { _, line in
                if !line.isEmpty {
                    Text(verbatim: "· \(line)").font(AppFont.footnote()).foregroundStyle(.appSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func verdict(run: CouncilRun, exchange: CouncilExchange) -> some View {
        let done = exchange.phase == .done
        let tint: Color = done ? (run.carried ? .green : .red) : .secondary
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Group {
                    if done, let outcome = run.outcome {
                        Text(verbatim: outcome)
                    } else if done {
                        Text("The council has spoken", tableName: "Fork")
                    } else if exchange.phase == .seated {
                        Text("The council is seated", tableName: "Fork")
                    } else {
                        Text("The council is sitting", tableName: "Fork")
                    }
                }
                .font(AppFont.title3(weight: .semibold))
            }
            Text(verbatim: done ? ForkCouncilCopy.tally(run) : ForkCouncilCopy.sitting(run))
                .font(AppFont.footnote())
                .foregroundStyle(.appSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).stroke(done ? tint.opacity(0.5) : Color.secondary.opacity(0.3)))
        .accessibilityElement(children: .combine)
    }

    private func controls(exchange: CouncilExchange) -> some View {
        VStack(spacing: 10) {
            Button { controller.handle(.convene) } label: {
                Group {
                    if !controller.reader.canConvene {
                        Text("Convening…", tableName: "Fork")
                    } else if exchange.phase == .seated {
                        Text("Convene Council", tableName: "Fork")
                    } else {
                        Text("Replay the Council", tableName: "Fork")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controller.reader.canConvene)
            HStack {
                Toggle(isOn: Binding(get: { controller.reader.readAloud }, set: { _ in controller.handle(.toggleReadAloud) })) {
                    Text("Read Aloud", tableName: "Fork")
                }
                Button { controller.handle(.toggleMute) } label: {
                    if controller.reader.muted {
                        Label { Text("Unmute", tableName: "Fork") } icon: { Image(systemName: "speaker.slash") }
                    } else {
                        Label { Text("Mute", tableName: "Fork") } icon: { Image(systemName: "speaker.wave.2") }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!controller.reader.readAloud)
            }
        }
    }

    private func report(run: CouncilRun, clauses: [CouncilClause]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(clauses.enumerated()), id: \.offset) { _, clause in
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: ForkCouncilCopy.label(clause))
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.appSecondary)
                    Text(verbatim: ForkCouncilCopy.text(clause, run: run))
                        .font(AppFont.footnote())
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 8)
    }
}

private struct ForkCouncilSeatRow: View {
    let run: CouncilRun
    let seat: Int
    let state: CouncilSeatState
    let open: Bool

    var body: some View {
        let info = run.seats[seat]
        let verdict = run.verdict(seat: seat)
        HStack(alignment: .top, spacing: 10) {
            Group {
                if state == .thinking || state == .drafting {
                    ForkLiveOrb(phase: .thinking, level: 0, style: .thinking)
                } else {
                    Circle().fill(Self.color(info.mineral)).overlay(Circle().stroke(Color.yellow.opacity(0.5), lineWidth: 1.5))
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: info.name).font(AppFont.body(weight: .semibold))
                    Text(verbatim: info.family).font(AppFont.caption()).foregroundStyle(.appTertiary)
                    Text(verbatim: ForkCouncilCopy.state(state)).font(AppFont.caption()).foregroundStyle(.appSecondary)
                    Spacer(minLength: 0)
                    if open, let verdict {
                        Text(verbatim: ForkCouncilCopy.stance(verdict.stance))
                            .font(AppFont.caption(weight: .semibold))
                            .foregroundStyle(Self.tint(verdict.stance))
                    }
                }
                if open, let verdict {
                    Text(verbatim: verdict.text).font(AppFont.footnote()).foregroundStyle(.appSecondary)
                } else if verdict == nil {
                    Text("No verdict recorded", tableName: "Fork").font(AppFont.footnote()).foregroundStyle(.appTertiary)
                } else {
                    Text(verbatim: "…").font(AppFont.footnote()).foregroundStyle(.appTertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private static func color(_ mineral: CouncilMineral) -> Color {
        let rgba = ForkRGBA(hex: mineral.hex) ?? .white
        return Color(red: rgba.red, green: rgba.green, blue: rgba.blue)
    }

    private static func tint(_ stance: CouncilStance) -> Color {
        switch stance {
        case .agree: .green
        case .dissent: .red
        case .abstain: .secondary
        }
    }
}
