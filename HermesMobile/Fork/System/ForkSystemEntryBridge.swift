import SwiftUI

extension View {
    func forkSystemEntryBridge() -> some View {
        modifier(ForkSystemEntryBridge())
    }
}

private struct ForkSystemEntryBridge: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var screenShare = ForkScreenShareReview.shared

    func body(content: Content) -> some View {
        content
            .onAppear(perform: bridge)
            .onChange(of: scenePhase) { _, phase in if phase == .active { bridge() } }
            .onOpenURL { _ in bridge() }
            .sheet(item: Binding(get: { screenShare.pending },
                                 set: { if $0 == nil, let open = screenShare.pending { screenShare.discard(open) } })) { capture in
                ForkScreenShareReviewView(capture: capture, review: screenShare)
            }
    }

    private func bridge() {
        ForkLiveVoiceRequest.bridge(now: Date().timeIntervalSince1970, local: .standard,
                                    shared: ForkLiveVoiceRequest.sharedDefaults())
    }
}
