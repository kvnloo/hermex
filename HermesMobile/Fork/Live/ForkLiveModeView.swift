import SwiftUI

extension View {
    func forkLiveMode(_ viewModel: ChatViewModel, title: String) -> some View {
        modifier(ForkLiveModeEntry(viewModel: viewModel, title: title))
    }
}

private struct ForkLiveModeEntry: ViewModifier {
    let viewModel: ChatViewModel
    let title: String
    @State private var isPresented = false
    @AppStorage(LiveModeRequest.storageKey) private var requestedAt: Double = 0

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresented = true } label: {
                        Label { Text("Live Mode", tableName: "Fork") } icon: { Image(systemName: "waveform") }
                    }
                    .disabled(viewModel.isViewingCachedData)
                }
            }
            .fullScreenCover(isPresented: $isPresented) {
                ForkLiveModeView(viewModel: viewModel, title: title)
            }
            .onAppear(perform: openIfRequested)
            .onChange(of: requestedAt) { openIfRequested() }
    }

    private func openIfRequested() {
        guard LiveModeRequest.isFresh(requestedAt, now: Date().timeIntervalSince1970) else { return }
        requestedAt = 0
        isPresented = true
    }
}

struct ForkLiveModeView: View {
    let title: String
    @State private var controller: ForkLiveModeController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fork.liveMode.orbStyle") private var orbStyle = ForkLiveOrbStyle.voice

    init(viewModel: ChatViewModel, title: String) {
        self.title = title
        _controller = State(initialValue: ForkLiveModeController(viewModel: viewModel))
    }

    var body: some View {
        ForkLiveModeScreen(
            title: title, phase: controller.phase, level: controller.level,
            heard: controller.heard, error: controller.errorMessage, orbStyle: $orbStyle,
            onOrb: controller.tapOrb, onEnd: controller.stop
        )
        .onAppear {
            controller.onClose = { dismiss() }
            controller.start()
        }
        .onDisappear { controller.stop() }
    }
}

struct ForkLiveModeScreen: View {
    let title: String
    let phase: LivePhase
    let level: Double
    let heard: String
    let error: String?
    @Binding var orbStyle: ForkLiveOrbStyle
    let onOrb: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            header
            Spacer(minLength: 12)
            Button(action: onOrb) {
                ForkLiveOrb(phase: phase, level: level, style: orbStyle)
                    .frame(width: 240, height: 240)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(statusText)
            .accessibilityHint(Text("Double-tap to pause, resume, or interrupt the reply.", tableName: "Fork"))
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
            Spacer(minLength: 12)
            controls
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedPageBackground()
    }

    private var header: some View {
        HStack {
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
        case .sending, .thinking: Text("Thinking…", tableName: "Fork")
        case .speaking: Text("Speaking · tap to interrupt", tableName: "Fork")
        case .failed: Text("Something went wrong · tap to retry", tableName: "Fork")
        }
    }
}
