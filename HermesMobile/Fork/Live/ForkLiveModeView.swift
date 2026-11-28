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
    @AppStorage(LiveModeRequest.storageKey) private var requestedAt: Double = 0

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
            .onAppear {
                ForkLiveSession.shared.chatAppeared(viewModel)
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
        ForkLiveSession.shared.start(viewModel, title: title)
    }
}

struct ForkLiveModeView: View {
    let session: ForkLiveSession
    let controller: ForkLiveModeController
    @AppStorage("fork.liveMode.orbStyle") private var orbStyle = ForkLiveOrbStyle.voice
    @State private var orbMode = LiveOrbMode.focus

    var body: some View {
        ForkLiveModeScreen(
            title: session.title, phase: controller.phase, level: controller.level,
            heard: controller.heard, error: controller.errorMessage, orbStyle: $orbStyle,
            isReconnecting: controller.isReconnecting, transcript: controller.transcript,
            onOrb: controller.tapOrb, onEnd: { session.end(.user) },
            lanes: controller.supportsLanes ? ForkLiveLaneControls(controller: controller) : nil,
            orbMode: $orbMode,
            approvalIDs: ForkLiveApprovals.ids(controller.chat),
            approval: controller.chat.map { ForkLiveApprovalCard(viewModel: $0) },
            onMinimize: session.compact
        )
        .accessibilityAction(.escape) { session.compact() }
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
    var orbMode: Binding<LiveOrbMode> = .constant(.focus)
    var approvalIDs: [String] = []
    var approval: ForkLiveApprovalCard? = nil
    var onMinimize: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let cards = LiveReplyCards.focusCards(transcript)
        let layout = LiveOrbLayout.make(mode: orbMode.wrappedValue, approvals: approvalIDs, cards: cards.map(\.id))
        VStack(spacing: 16) {
            header(layout)
            switch layout.mode {
            case .focus: focus(layout, cards: cards)
            case .bubble: docked(layout)
            }
            if let lanes { lanes.actions }
            controls
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedPageBackground()
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: layout.mode)
    }

    private func focus(_ layout: LiveOrbLayout, cards: [LiveFocusCard]) -> some View {
        let hasOrbit = lanes?.hasOrbit == true
        return VStack(spacing: 12) {
            ZStack {
                if let lanes, hasOrbit {
                    lanes.orbit(reduceMotion: reduceMotion, layoutDirection: layoutDirection)
                }
                orbButton(side: hasOrbit ? 158 : layout.diameter, action: onOrb)
                    .accessibilityHint(Text("Double-tap to pause, resume, or interrupt the reply.", tableName: "Fork"))
            }
            statusText.font(AppFont.headline()).accessibilityHidden(true)
            caption.lineLimit(3).padding(.horizontal, 24)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(layout.items) { item in
                        switch item {
                        case .approval: approval
                        case .card(let id):
                            if let card = cards.first(where: { $0.id == id }) {
                                MarkdownRenderer(content: card.markdown).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom)
            .accessibilityIdentifier("live-focus-cards")
        }
    }

    private func docked(_ layout: LiveOrbLayout) -> some View {
        VStack(spacing: 12) {
            if transcript.isEmpty {
                Spacer(minLength: 12)
                Text("Your conversation shows here. Tap the orb to open focus.", tableName: "Fork")
                    .font(AppFont.subheadline())
                    .foregroundStyle(.appSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer(minLength: 12)
            } else {
                ForkLiveTranscriptView(turns: transcript)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    statusText.font(AppFont.subheadline(weight: .semibold))
                    caption.lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                orbButton(side: layout.diameter) { orbMode.wrappedValue = .focus }
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
                    .contextMenu {
                        Button(action: onOrb) {
                            phase == .listening ? Text("Pause Listening", tableName: "Fork") : Text("Listen", tableName: "Fork")
                        }
                        Button(role: .destructive, action: onEnd) { Text("End Live Mode", tableName: "Fork") }
                    }
                    .accessibilityHint(Text("Double-tap to open focus.", tableName: "Fork"))
                    .accessibilityValue(Self.badgeValue(layout.badge))
            }
            .padding(.horizontal, 20)
        }
    }

    private static func badgeValue(_ count: Int) -> Text {
        count > 0 ? Text("\(count) approvals waiting", tableName: "Fork") : Text(verbatim: "")
    }

    private func orbButton(side: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ForkLiveOrb(phase: phase, level: level, style: orbStyle)
                .frame(width: side, height: side)
                .background {
                    if side < 100 { Circle().fill(Color(.appFillSecondary)) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(statusText)
        .accessibilityIdentifier(side < 100 ? "live-orb-bubble" : "live-orb-focus")
    }

    private var caption: some View {
        VStack(spacing: 4) {
            Text(verbatim: heard.isEmpty ? " " : heard)
                .font(AppFont.body())
                .foregroundStyle(.appSecondary)
                .multilineTextAlignment(orbMode.wrappedValue == .focus ? .center : .leading)
            if let error {
                Text(verbatim: error).font(AppFont.footnote()).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
    }

    private func header(_ layout: LiveOrbLayout) -> some View {
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
            if layout.mode == .focus {
                Button { orbMode.wrappedValue = .bubble } label: {
                    Image(systemName: "rectangle.bottomhalf.inset.filled")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Show Transcript", tableName: "Fork"))
            }
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
