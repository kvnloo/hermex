import SwiftUI

extension View {
    func forkServedBuildChip() -> some View {
        modifier(ForkServedBuildChipHost())
    }
}

struct ForkPreviewChannelSettingsRow: View {
    @State private var store = ForkPreviewChannelStore.shared

    var body: some View {
        Toggle(isOn: Binding(get: { store.isPreview }, set: { store.setPreview($0) })) {
            SettingsLabel(title: String(localized: "Preview channel", table: "Fork"),
                          systemImage: "shippingbox",
                          note: String(localized: "Follow the newest green staging build and show which build is running.",
                                       table: "Fork"))
        }
    }
}

private struct ForkServedBuildChipHost: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = ForkPreviewChannelStore.shared

    private struct PollKey: Equatable {
        let isPreview: Bool
        let isActive: Bool
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if store.model.isChipVisible {
                    ForkServedBuildChip(store: store)
                        .padding(.top, 4)
                }
            }
            .task(id: PollKey(isPreview: store.isPreview, isActive: scenePhase == .active)) {
                guard store.isPreview, scenePhase == .active else { return }
                while !Task.isCancelled {
                    store.refresh()
                    try? await Task.sleep(for: .seconds(ForkPreviewChannel.pollInterval))
                }
            }
    }
}

private struct ForkServedBuildChip: View {
    let store: ForkPreviewChannelStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let text = store.model.label(now: context.date)
            let newer = store.model.state == .newer
            Button {
                if let url = store.model.openOnTap {
                    openURL(url)
                } else {
                    store.hide()
                }
            } label: {
                Text(verbatim: text)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: 32)
                    .foregroundStyle(newer ? Color.white : Color.primary)
                    .background(newer ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(newer
                ? Text("Newer preview build served: \(text). Tap to open it.", tableName: "Fork")
                : Text("Running build \(text). Tap to hide.", tableName: "Fork"))
        }
    }
}
