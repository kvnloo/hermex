import SwiftUI

extension EnvironmentValues {
    @Entry var forkTurboEnabled = ForkTurboMotion.defaultIsEnabled
}

struct ForkTurboPresentation: ViewModifier {
    @AppStorage(ForkTurboMotion.storageKey) private var isEnabled = ForkTurboMotion.defaultIsEnabled

    func body(content: Content) -> some View {
        content
            .environment(\.forkTurboEnabled, isEnabled)
            .safeAreaInset(edge: .top, spacing: 0) {
                if isEnabled {
                    Label {
                        Text("Turbo mode", tableName: "Fork")
                    } icon: {
                        Image(systemName: "bolt.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("fork-turbo-badge")
                }
            }
    }
}
