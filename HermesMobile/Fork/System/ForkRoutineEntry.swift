import SwiftUI

extension View {
    func forkRoutineTab(_ show: @escaping () -> Void) -> some View {
        modifier(ForkRoutineTab(show: show))
    }

    func forkRoutineRequest(isReady: Bool, open: @escaping () -> Void) -> some View {
        modifier(ForkRoutineOpen(isReady: isReady, open: open))
    }
}

private struct ForkRoutineTab: ViewModifier {
    let show: () -> Void
    @AppStorage(ForkRoutineRequest.storageKey) private var requestedAt: Double = 0

    func body(content: Content) -> some View {
        content.onChange(of: requestedAt, initial: true) {
            if ForkRoutineRequest.isPending(now: Date().timeIntervalSince1970, in: .standard) { show() }
        }
    }
}

private struct ForkRoutineOpen: ViewModifier {
    let isReady: Bool
    let open: () -> Void
    @AppStorage(ForkRoutineRequest.storageKey) private var requestedAt: Double = 0

    func body(content: Content) -> some View {
        content
            .onChange(of: requestedAt, initial: true, openIfRequested)
            .onChange(of: isReady, openIfRequested)
    }

    private func openIfRequested() {
        guard isReady, requestedAt > 0 else { return }
        if ForkRoutineRequest.take(now: Date().timeIntervalSince1970, from: .standard) { open() }
    }
}
