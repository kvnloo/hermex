import SwiftUI
import UIKit

extension View {
    func forkLiveMode(_ viewModel: ChatViewModel, title: String) -> some View {
        modifier(ForkLiveModeEntry(viewModel: viewModel, title: title))
    }
}

@MainActor
private struct ForkLiveModeEntry: ViewModifier {
    let viewModel: ChatViewModel
    let title: String
    @Environment(ForkLiveSession.self) private var environmentSession: ForkLiveSession?
    @AppStorage(LiveModeRequest.storageKey) private var requestedAt: Double = 0

    private var session: ForkLiveSession { environmentSession ?? .shared }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: present) {
                        Label { Text("Live Mode", tableName: "Fork") } icon: { Image(systemName: "waveform") }
                    }
                    .disabled(viewModel.isViewingCachedData)
                }
            }
            .confirmationDialog(
                Text("Switch the Live call?", tableName: "Fork"),
                isPresented: Binding(
                    get: { session.isAskingToSwitch(from: viewModel) },
                    set: { if !$0 { session.resolveSwitch(false) } }
                ),
                titleVisibility: .visible
            ) {
                Button { session.resolveSwitch(true) } label: { Text("Switch to This Chat", tableName: "Fork") }
                Button(role: .cancel) { session.resolveSwitch(false) } label: { Text("Keep Current Call", tableName: "Fork") }
            } message: {
                let name = session.title
                Text("A Live call is running in “\(name)”. Switching ends it.", tableName: "Fork")
            }
            .onAppear {
                session.chatAppeared(viewModel)
                openIfRequested()
            }
            .onChange(of: requestedAt) { openIfRequested() }
    }

    private func openIfRequested() {
        guard LiveModeRequest.isFresh(requestedAt, now: Date().timeIntervalSince1970) else { return }
        requestedAt = 0
        present()
    }

    private func present() {
        session.requestStart(viewModel, title: title)
    }
}

struct ForkLiveModeView: View {
    let session: ForkLiveSession
    let controller: ForkLiveModeController
    @AppStorage("fork.liveMode.orbStyle") private var orbStyle = ForkLiveOrbStyle.voice
    @State private var keptAwake = false

    var body: some View {
        ForkLiveModeScreen(
            title: session.title, phase: controller.phase, level: controller.level,
            heard: controller.heard, error: controller.errorMessage, orbStyle: $orbStyle,
            isReconnecting: controller.isReconnecting, transcript: controller.transcript,
            onOrb: controller.tapOrb, onEnd: { session.end(.user) },
            lanes: controller.supportsLanes ? ForkLiveLaneControls(controller: controller) : nil,
            onMinimize: { session.minimize() },
            ask: controller.pendingAsk.map { ask in
                ForkLiveAskControls(ask: ask, isAnswering: controller.answeringAskID != nil, onAnswer: session.answer)
            }
        )
        .accessibilityAction(.escape) { session.minimize() }
        .onAppear {
            keptAwake = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = keptAwake
        }
    }
}

struct ForkLiveModeScreen: View {
    let title: String
    let phase: LivePhase
    let level: Double
    let heard: String
    let error: String?
    @Binding var orbStyle: ForkLiveOrbStyle
    var isReconnecting = false
    var transcript: [LiveTurn<ToolCall>] = []
    let onOrb: () -> Void
    let onEnd: () -> Void
    var lanes: ForkLiveLaneControls? = nil
    var onMinimize: (() -> Void)? = nil
    var ask: ForkLiveAskControls? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Group {
            if transcript.isEmpty {
                GeometryReader { geometry in
                    ScrollView {
                        stackedContent.frame(minHeight: geometry.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                stackedContent.frame(maxHeight: .infinity)
            }
        }
        .themedPageBackground()
    }

    private var stackedContent: some View {
        VStack(spacing: 20) {
            header
            if transcript.isEmpty {
                Spacer(minLength: 12)
            } else {
                ForkLiveTranscriptView(turns: transcript)
            }
            if let ask { ask.row.padding(.horizontal, 20) }
            ZStack {
                if let lanes, lanes.hasOrbit {
                    lanes.orbit(reduceMotion: reduceMotion, layoutDirection: layoutDirection)
                }
                Button(action: onOrb) {
                    let side: CGFloat = transcript.isEmpty ? (lanes?.hasOrbit == true ? 158 : 240) : 140
                    ForkLiveOrb(phase: phase, level: level, style: orbStyle)
                        .frame(width: side, height: side)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(statusText)
                .accessibilityHint(Text("Double-tap to pause, resume, or interrupt the reply.", tableName: "Fork"))
            }
            statusText
                .font(AppFont.headline())
                .accessibilityHidden(true)
            Text(verbatim: heard.isEmpty ? " " : heard)
                .font(AppFont.body())
                .foregroundStyle(.appSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 24)
            if let error {
                Text(verbatim: error).font(AppFont.footnote()).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            if transcript.isEmpty { Spacer(minLength: 12) }
            if let lanes { lanes.actions }
            controls
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(spacing: 4) {
            if onMinimize != nil {
                Capsule()
                    .fill(Color(.appFillSecondary))
                    .frame(width: 36, height: 5)
                    .accessibilityHidden(true)
            }
            headerRow
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 16).onEnded { value in
                guard let onMinimize, value.translation.height > 60,
                      value.translation.height > abs(value.translation.width) else { return }
                onMinimize()
            }
        )
    }

    private var headerRow: some View {
        HStack {
            if let onMinimize {
                Button(action: onMinimize) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Minimize Live Mode", tableName: "Fork"))
                .accessibilityHint(Text("The call keeps running while you use the app.", tableName: "Fork"))
            }
            Text(verbatim: title).font(AppFont.subheadline(weight: .semibold)).lineLimit(1)
            Spacer()
            Picker(selection: $orbStyle) {
                ForEach(ForkLiveOrbStyle.allCases) { $0.label.tag($0) }
            } label: {
                Text("Avatar", tableName: "Fork")
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 20)
    }

    private var controls: some View {
        HStack(spacing: 40) {
            Button(action: onOrb) {
                Image(systemName: phase == .listening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .background(Color(.appFillSecondary), in: Circle())
            }
            .accessibilityLabel(phase == .listening ? Text("Pause Listening", tableName: "Fork") : Text("Listen", tableName: "Fork"))
            Button(action: onEnd) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.red, in: Circle())
            }
            .accessibilityLabel(Text("End Live Mode", tableName: "Fork"))
        }
        .buttonStyle(.plain)
    }

    private var statusText: Text {
        switch phase {
        case .idle, .paused: Text("Paused · tap to talk", tableName: "Fork")
        case .listening: Text("Listening…", tableName: "Fork")
        case .sending, .thinking:
            isReconnecting ? Text("Reconnecting…", tableName: "Fork") : Text("Thinking…", tableName: "Fork")
        case .speaking: Text("Speaking · tap to interrupt", tableName: "Fork")
        case .failed: Text("Something went wrong · tap to retry", tableName: "Fork")
        }
    }
}


@MainActor
struct ForkLiveLaneControls {
    let controller: ForkLiveModeController

    var hasOrbit: Bool { controller.router.lanes.count > 1 }

    func orbit(reduceMotion: Bool, layoutDirection: LayoutDirection) -> some View {
        let router = controller.router
        let selectedIndex = router.lanes.firstIndex(of: router.selected) ?? 0
        return ZStack {
            Circle()
                .strokeBorder(Color.accentColor.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                .frame(width: 222, height: 222)
                .accessibilityHidden(true)
            ForEach(router.lanes, id: \.self) { lane in
                let index = router.lanes.firstIndex(of: lane) ?? 0
                let position = Double(index - selectedIndex) * 2 * .pi / Double(router.lanes.count)
                let angle = layoutDirection == .rightToLeft ? .pi - position : position
                Button { controller.selectLane(lane) } label: {
                    Group {
                        if lane == LiveLaneRouter.root {
                            Image(systemName: "bubble.left")
                        } else {
                            Text(lane.formatted()).monospacedDigit()
                        }
                    }
                    .font(AppFont.subheadline(weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color.accentColor, lineWidth: router.selected == lane ? 3 : 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!controller.canChangeLane)
                .accessibilityLabel(label(lane))
                .accessibilityAddTraits(router.selected == lane ? .isSelected : [])
                .rotationEffect(.radians(-angle))
                .offset(x: 111)
                .rotationEffect(.radians(angle))
            }
        }
        .frame(width: 266, height: 266)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: router.selected)
    }

    var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack { laneButtons }
            VStack { laneButtons }
        }
        .buttonStyle(.bordered)
        .font(AppFont.footnote())
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var laneButtons: some View {
        if controller.isAddingLane {
            ProgressView().accessibilityLabel(Text("Add Live lane", tableName: "Fork"))
        }
        Button { controller.addLane() } label: {
            Label { Text("Add Live lane", tableName: "Fork") } icon: { Image(systemName: "plus") }
        }
        .disabled(!controller.canAddLane)
        if controller.router.selected != LiveLaneRouter.root {
            Button { controller.detachLane() } label: {
                Label { Text("Detach Live lane", tableName: "Fork") } icon: { Image(systemName: "minus") }
            }
            .disabled(!controller.canChangeLane)
        }
    }

    private func label(_ lane: Int) -> Text {
        if lane == LiveLaneRouter.root { Text("Main Live lane", tableName: "Fork") }
        else { Text("Live lane \(lane)", tableName: "Fork") }
    }
}
