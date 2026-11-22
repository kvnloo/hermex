import AppIntents
import SwiftUI
import WidgetKit

struct ForkNewChatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "HermexNewChatControl") {
            ControlWidgetButton(action: OpenURLIntent(ForkSystemLinks.newChat)) {
                Label { Text("New Chat", tableName: "Fork") } icon: { Image(systemName: "square.and.pencil") }
            }
        }
        .displayName(LocalizedStringResource("New Chat", table: "Fork"))
        .description(LocalizedStringResource("Open Hermex on a new chat.", table: "Fork"))
    }
}

struct ForkLiveVoiceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "HermexLiveVoiceControl") {
            ControlWidgetButton(action: ForkStartLiveVoiceIntent()) {
                Label { Text("Live Voice", tableName: "Fork") } icon: { Image(systemName: "waveform") }
            }
        }
        .displayName(LocalizedStringResource("Live Voice", table: "Fork"))
        .description(LocalizedStringResource("Open Hermex in Live Mode on a new chat.", table: "Fork"))
    }
}

struct ForkActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HermexActionsWidget", provider: ForkActionsTimeline()) { _ in
            ForkActionsWidgetView()
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(Text("Agent Actions", tableName: "Fork"))
        .description(Text("New Chat and Live Voice.", tableName: "Fork"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ForkActionsEntry: TimelineEntry {
    let date: Date
}

struct ForkActionsTimeline: TimelineProvider {
    func placeholder(in context: Context) -> ForkActionsEntry { ForkActionsEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (ForkActionsEntry) -> Void) {
        completion(ForkActionsEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ForkActionsEntry>) -> Void) {
        completion(Timeline(entries: [ForkActionsEntry(date: .now)], policy: .never))
    }
}

private struct ForkActionsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let layout = family == .systemSmall ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Link(destination: ForkSystemLinks.newChat) {
                tile(Text("New Chat", tableName: "Fork"), systemImage: "square.and.pencil")
            }
            Button(intent: ForkStartLiveVoiceIntent()) {
                tile(Text("Live Voice", tableName: "Fork"), systemImage: "waveform")
            }
            .buttonStyle(.plain)
        }
    }

    private func tile(_ title: Text, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.title3.weight(.semibold))
            title.font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
