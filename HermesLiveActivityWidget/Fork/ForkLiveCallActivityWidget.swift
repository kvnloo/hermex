import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ForkLiveCallActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ForkLiveCallAttributes.self) { context in
            ForkLiveCallLockScreen(context: context)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ForkLiveCallGlyph(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: context.attributes.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        ForkLiveCallStatus(state: context.state).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ForkLiveCallButtons(callID: context.attributes.callID)
                }
            } compactLeading: {
                ForkLiveCallGlyph(state: context.state)
            } compactTrailing: {
                if context.state.needsAnswer {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
                } else if context.state.isMuted {
                    Image(systemName: "mic.slash.fill")
                } else {
                    Image(systemName: "mic.fill").foregroundStyle(.green)
                }
            } minimal: {
                ForkLiveCallGlyph(state: context.state)
            }
            .keylineTint(.accentColor)
        }
    }
}

private struct ForkLiveCallLockScreen: View {
    let context: ActivityViewContext<ForkLiveCallAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForkLiveCallGlyph(state: context.state).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: context.attributes.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    ForkLiveCallStatus(state: context.state).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ForkLiveCallButtons(callID: context.attributes.callID)
        }
        .padding(14)
    }
}

private struct ForkLiveCallGlyph: View {
    let state: ForkLiveCallAttributes.ContentState

    var body: some View {
        Image(systemName: state.needsAnswer ? "hand.raised.fill" : "waveform")
            .foregroundStyle(state.needsAnswer ? Color.yellow : Color.accentColor)
            .accessibilityHidden(true)
    }
}

private struct ForkLiveCallStatus: View {
    let state: ForkLiveCallAttributes.ContentState

    var body: some View {
        if state.needsAnswer {
            Text("Needs your OK", tableName: "Fork")
        } else if state.hasUnseenCard {
            Text("New card in chat", tableName: "Fork")
        } else if state.isMuted {
            Text("Muted", tableName: "Fork")
        } else {
            switch state.status {
            case .listening: Text("Listening…", tableName: "Fork")
            case .thinking: Text("Thinking…", tableName: "Fork")
            case .speaking: Text("Speaking", tableName: "Fork")
            case .paused: Text("Paused", tableName: "Fork")
            case .failed: Text("Something went wrong", tableName: "Fork")
            }
        }
    }
}

private struct ForkLiveCallButtons: View {
    let callID: String

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: ForkReturnToLiveCallIntent(callID: callID)) {
                Label { Text("Return", tableName: "Fork") } icon: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .frame(maxWidth: .infinity)
            }
            .tint(.accentColor)
            Button(intent: ForkEndLiveCallIntent(callID: callID)) {
                Label { Text("End", tableName: "Fork") } icon: { Image(systemName: "xmark") }
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .buttonStyle(.borderedProminent)
        .font(.footnote.weight(.semibold))
    }
}
