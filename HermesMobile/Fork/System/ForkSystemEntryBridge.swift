import SwiftUI

extension View {
    func forkSystemEntryBridge() -> some View {
        modifier(ForkSystemEntryBridge())
    }
}

private struct ForkSystemEntryBridge: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear(perform: bridge)
            .onChange(of: scenePhase) { _, phase in if phase == .active { bridge() } }
            .onOpenURL { _ in bridge() }
    }

    private func bridge() {
        ForkLiveVoiceRequest.bridge(now: Date().timeIntervalSince1970, local: .standard,
                                    shared: ForkLiveVoiceRequest.sharedDefaults())
    }
}
