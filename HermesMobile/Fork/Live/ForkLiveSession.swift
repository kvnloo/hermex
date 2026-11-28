import Observation
import SwiftUI
import UIKit

extension View {
    func forkLiveSession(_ authManager: AuthManager) -> some View {
        modifier(ForkLiveRoot(authManager: authManager))
    }
}

@MainActor
@Observable
final class ForkLiveSession {
    static let shared = ForkLiveSession()

    private(set) var room = LiveCallRoom()
    private(set) var controller: ForkLiveModeController?
    private(set) var title = ""
    @ObservationIgnored private var model: ChatViewModel?
    @ObservationIgnored private var keptAwake = false

    var presentation: LiveOrbMode? { room.call?.presentation }

    func start(_ model: ChatViewModel, title: String) {
        if room.call == nil, model.isViewingCachedData { return }
        guard room.start(chat: Self.key(model)) != nil else { return }
        let controller = ForkLiveModeController(viewModel: model)
        self.model = model
        self.title = title
        self.controller = controller
        keptAwake = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        controller.start()
    }

    func compact() { room.compact() }

    func expand() { room.expand() }

    func chatLeft(_ model: ChatViewModel) -> Bool { room.chatLeft(Self.key(model)) }

    func chatAppeared(_ model: ChatViewModel) { room.chatAppeared(Self.key(model)) }

    func end(_ reason: LiveCallEnd) {
        guard let ending = room.end(reason) else { return }
        controller?.stop()
        if ending.releasesChat, let model {
            model.suspendStreamForNavigation()
            model.cleanupPollingTasks()
        }
        controller = nil
        model = nil
        UIApplication.shared.isIdleTimerDisabled = keptAwake
    }

    private static func key(_ model: ChatViewModel) -> String {
        String(describing: ObjectIdentifier(model))
    }
}

@MainActor
private struct ForkLiveRoot: ViewModifier {
    let authManager: AuthManager
    @State private var session = ForkLiveSession.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if session.presentation == .bubble, let controller = session.controller {
                    ForkLiveBubble(session: session, controller: controller)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.presentation == .focus },
                set: { if !$0 { session.compact() } }
            )) {
                if let controller = session.controller {
                    ForkLiveModeView(session: session, controller: controller)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { session.end(.background) }
            }
            .onChange(of: authManager.state) { session.end(.accountChanged) }
    }
}

private struct ForkLiveBubble: View {
    let session: ForkLiveSession
    let controller: ForkLiveModeController
    @AppStorage("fork.liveMode.orbStyle") private var orbStyle = ForkLiveOrbStyle.voice
    @State private var onLeadingEdge = false
    @State private var lift: Double = -80
    @GestureState private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = LiveOrbLayout.make(mode: .bubble, approvals: ForkLiveApprovals.ids(controller.chat), cards: [])
        let count = layout.badge
        GeometryReader { proxy in
            let reach = max(0, proxy.size.height / 2 - layout.diameter)
            Button { session.expand() } label: {
                ForkLiveOrb(phase: controller.phase, level: controller.level, style: orbStyle)
                    .frame(width: layout.diameter, height: layout.diameter)
                    .background(Circle().fill(Color(.appFillSecondary)))
                    .contentShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    .overlay(alignment: .topTrailing) {
                        if layout.badge > 0 {
                            Text(layout.badge, format: .number)
                                .font(AppFont.caption2(weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Color.red, in: Capsule())
                                .accessibilityHidden(true)
                        }
                    }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(action: controller.tapOrb) {
                    controller.phase == .listening ? Text("Pause Listening", tableName: "Fork") : Text("Listen", tableName: "Fork")
                }
                Button(role: .destructive) { session.end(.user) } label: { Text("End Live Mode", tableName: "Fork") }
            }
            .accessibilityLabel(Text("Live Mode", tableName: "Fork"))
            .accessibilityValue(count > 0 ? Text("\(count) approvals waiting", tableName: "Fork") : Text(verbatim: ""))
            .accessibilityHint(Text("Double-tap to open focus.", tableName: "Fork"))
            .accessibilityIdentifier("live-orb-floating")
            .offset(x: drag.width, y: min(max(lift + drag.height, -reach), reach))
            .gesture(
                DragGesture(minimumDistance: 8)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        lift = min(max(lift + value.translation.height, -reach), reach)
                        let across = onLeadingEdge ? value.predictedEndTranslation.width : -value.predictedEndTranslation.width
                        if across > proxy.size.width / 3 { onLeadingEdge.toggle() }
                    }
            )
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: onLeadingEdge ? .leading : .trailing)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: onLeadingEdge)
        }
    }
}
