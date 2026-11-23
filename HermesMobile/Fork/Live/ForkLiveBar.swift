import SwiftUI

extension View {
    func forkLiveSession() -> some View {
        modifier(ForkLiveRoot())
    }
}

@MainActor
private struct ForkLiveRoot: ViewModifier {
    @State private var session = ForkLiveSession.shared
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if session.showsBar, let controller = session.controller {
                    ForkLiveBar(session: session, controller: controller)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isFullScreen },
                set: { if !$0 { session.minimize() } }
            )) {
                if let controller = session.controller {
                    ForkLiveModeView(session: session, controller: controller)
                }
            }
            .environment(session)
            .onAppear {
                session.openLink = { url in openURL(url) }
            }
    }
}

struct ForkLiveBar: View {
    let session: ForkLiveSession
    let controller: ForkLiveModeController
    @AppStorage("fork.liveMode.orbStyle") private var orbStyle = ForkLiveOrbStyle.voice

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { session.restore() } label: {
                    HStack(spacing: 10) {
                        ForkLiveOrb(phase: controller.phase, level: controller.level, style: orbStyle)
                            .frame(width: 32, height: 32)
                            .overlay(alignment: .topTrailing) {
                                if controller.hasUnseenCard {
                                    Circle().fill(Color.accentColor).frame(width: 9, height: 9)
                                        .overlay(Circle().strokeBorder(Color(.appCanvas), lineWidth: 1.5))
                                        .accessibilityHidden(true)
                                }
                            }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: session.title)
                                .font(AppFont.caption(weight: .semibold))
                                .lineLimit(1)
                            status
                                .font(AppFont.caption())
                                .foregroundStyle(.appSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(barLabel)
                .accessibilityHint(Text("Returns to Live Mode.", tableName: "Fork"))

                Button { session.toggleMute() } label: {
                    Image(systemName: controller.isHearing ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color(.appFillSecondary), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(controller.isHearing
                    ? Text("Mute Live Mode", tableName: "Fork") : Text("Unmute Live Mode", tableName: "Fork"))

                Button { session.end(.bar) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.red, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("End Live Mode", tableName: "Fork"))
            }
            if let ask = controller.pendingAsk {
                ForkLiveAskControls(ask: ask, isAnswering: controller.answeringAskID != nil, onAnswer: session.answer).strip
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var status: Text {
        if controller.pendingAsk != nil { return Text("Needs your OK", tableName: "Fork") }
        if controller.hasUnseenCard { return Text("New card in chat", tableName: "Fork") }
        if controller.isMuted { return Text("Muted", tableName: "Fork") }
        return switch controller.phase {
        case .listening: Text("Listening…", tableName: "Fork")
        case .sending, .thinking:
            controller.isReconnecting ? Text("Reconnecting…", tableName: "Fork") : Text("Thinking…", tableName: "Fork")
        case .speaking: Text("Speaking", tableName: "Fork")
        case .idle, .paused: Text("Paused · tap the mic to talk", tableName: "Fork")
        case .failed: Text("Something went wrong", tableName: "Fork")
        }
    }

    private var barLabel: Text {
        let name = session.title
        return Text("Live call, \(name)", tableName: "Fork") + Text(verbatim: ", ") + status
    }
}

struct ForkLiveAskControls {
    let ask: LiveAsk
    let isAnswering: Bool
    let onAnswer: @MainActor (LiveApprovalCommand) -> Void

    private var heading: Text {
        ask.kind == .approval ? Text("Needs OK", tableName: "Fork") : Text("Question", tableName: "Fork")
    }

    private var summary: String {
        ask.summary.isEmpty ? String(localized: "Open the chat to answer.", table: "Fork") : ask.summary
    }

    var strip: some View {
        HStack(spacing: 6) {
            (heading.foregroundStyle(.yellow).bold() + Text(verbatim: " · ") + Text(verbatim: summary))
                .font(AppFont.caption())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            buttons.controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }

    var row: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { heading.bold() } icon: { Image(systemName: "hand.raised.fill").foregroundStyle(.yellow) }
                .font(AppFont.subheadline())
            Text(verbatim: summary)
                .font(AppFont.footnote())
                .foregroundStyle(.appSecondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack { buttons }
            hint
                .font(AppFont.caption())
                .foregroundStyle(.appTertiary)
        }
        .padding(12)
        .background(Color(.appSurface), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var hint: Text {
        ask.offers.contains(.allow)
            ? Text("Or say “allow”, “deny” or “open it”.", tableName: "Fork")
            : Text("Or say “open it”.", tableName: "Fork")
    }

    @ViewBuilder private var buttons: some View {
        if ask.offers.contains(.deny) {
            Button { onAnswer(.deny) } label: { Text("Deny", tableName: "Fork") }
                .buttonStyle(.bordered)
                .disabled(isAnswering)
        }
        if ask.offers.contains(.allow) {
            Button { onAnswer(.allow) } label: { Text("Allow Once", tableName: "Fork") }
                .buttonStyle(.borderedProminent)
                .disabled(isAnswering)
        }
        Button { onAnswer(.open) } label: { Text("Open", tableName: "Fork") }
            .buttonStyle(.bordered)
    }
}
