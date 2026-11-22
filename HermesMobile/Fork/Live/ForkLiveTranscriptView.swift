import SwiftUI

extension ToolCall: LiveStepStatus {
    var liveStepIsRunning: Bool { !isCompleted }
    var liveStepIsFailed: Bool { isError == true }
}

@MainActor
enum ForkLiveTranscriptSource {
    static func baseline(_ viewModel: ChatViewModel) -> Set<String> {
        Set(viewModel.messages.map(\.id))
    }

    static func turns(in viewModel: ChatViewModel, excluding baseline: Set<String>) -> [LiveTurn<ToolCall>] {
        var messages: [LiveTranscriptMessage<ToolCall>] = []
        var seen: Set<String> = []
        for (index, message) in viewModel.messages.enumerated() where !baseline.contains(message.id) {
            if TranscriptTurnClassifier.isTurnBoundary(message), message.role == "user" {
                messages.append(LiveTranscriptMessage(id: message.id, isUser: true, text: message.content ?? "", steps: []))
            } else if message.role == "assistant" {
                let anchor = TranscriptTurnClassifier.anchorID(for: message, at: index, messageOffset: viewModel.messagesOffset)
                let steps = viewModel.completedToolCallGroupsForAnchor(anchor).flatMap(\.toolCalls)
                seen.formUnion(steps.map(\.id))
                messages.append(LiveTranscriptMessage(id: message.id, isUser: false, text: message.content ?? "", steps: steps))
            }
        }
        let live = messages.isEmpty ? [] : viewModel.liveToolCalls.filter { !seen.contains($0.id) }
        return LiveTranscript.turns(messages, liveSteps: live)
    }
}

struct ForkLiveTranscriptView: View {
    let turns: [LiveTurn<ToolCall>]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(turns) { turn in
                    ForkLiveTurnView(turn: turn)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
    }
}

private struct ForkLiveTurnView: View {
    let turn: LiveTurn<ToolCall>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let said = turn.said {
                Text(verbatim: said)
                    .font(AppFont.body())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.appFillSecondary), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if !turn.steps.isEmpty {
                ForkLiveProgressRow(steps: turn.steps)
            }
            if !turn.replies.isEmpty {
                ForkLiveReplyView(reply: turn.reply)
            }
        }
    }
}

struct ForkLiveProgressRow: View {
    let steps: [ToolCall]
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let summary = LiveProgressSummary(steps)
        let entries = ToolCallSummaryFormatter.entries(for: steps, isLive: summary.isWorking)
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                header(summary: summary, latest: entries.last)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: entries.last?.row.summary ?? ""))
            .accessibilityValue(Text(verbatim: entries.last?.row.statusText ?? ""))
            .accessibilityHint(isExpanded ? Text("Hide Steps", tableName: "Fork") : Text("Show Steps", tableName: "Fork"))
            if isExpanded {
                ForEach(entries) { entry in
                    ToolCallLogRowView(entry: entry)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.appSurface), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func header(summary: LiveProgressSummary, latest: ToolCallLogEntry?) -> some View {
        HStack(spacing: 8) {
            statusIcon(summary)
                .frame(width: 18, height: 18)
            Text(verbatim: latest?.row.summary ?? "")
                .font(AppFont.subheadline())
                .foregroundStyle(.appSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(summary.count, format: .number)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.appTertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.appTertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusIcon(_ summary: LiveProgressSummary) -> some View {
        if summary.isWorking {
            ProgressView().controlSize(.small)
        } else if summary.failed > 0 {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}
