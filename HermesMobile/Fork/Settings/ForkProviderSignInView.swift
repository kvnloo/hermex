import AuthenticationServices
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ForkProviderSignInRow: View {
    let connection: BotConnection
    let server: URL

    var body: some View {
        NavigationLink {
            ForkProviderSignInView(connection: connection, server: server)
        } label: {
            SettingsLabel(title: String(localized: "Provider Sign-In", table: "Fork"), systemImage: "person.badge.key")
        }
    }
}

struct ForkProviderSignInView: View {
    @State private var model: ForkProviderSignInModel
    @State private var page = ForkVerificationPage()

    init(connection: BotConnection, server: URL) {
        _model = State(initialValue: ForkProviderSignInModel(client: ForkProviderOAuthClient(saved: connection, server: server)))
    }

    var body: some View {
        AppList {
            if let profile = model.profile {
                ServerProfileRow(profiles: model.profiles, selection: profile) { name in
                    Task { await model.select(profile: name) }
                }
            }
            progressSection
            if let failure = model.failure {
                Section { Text(verbatim: failure).foregroundStyle(.appSecondary) }
            } else if let providers = model.providers {
                if providers.isEmpty {
                    Section { Text("This host lists no sign-in providers.", tableName: "Fork").foregroundStyle(.appSecondary) }
                } else {
                    Section {
                        ForEach(providers) { provider in
                            ForkProviderSignInProviderRow(provider: provider, isLocked: model.phase.isActive) {
                                model.begin(provider)
                            }
                        }
                    } footer: {
                        Text("Sign-in runs on the host: the provider’s credentials are saved there, never on this iPhone. Providers marked “Set up on host” need the Hermes CLI.", tableName: "Fork")
                    }
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .settingsPage(String(localized: "Provider Sign-In", table: "Fork"))
        .refreshable { await model.refresh() }
        .task { await model.start() }
        .onDisappear {
            page.close()
            Task { await model.stop() }
        }
        .onChange(of: model.phase) { _, phase in
            if case .waiting = phase { return }
            page.close()
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .starting(let provider):
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Starting sign-in…", tableName: "Fork")
                }
                cancelButton
            } header: {
                Text(verbatim: name(of: provider))
            }
        case .waiting(let provider, let session, let expiresAt):
            Section {
                Text("Enter this code on the provider’s page:", tableName: "Fork")
                Text(verbatim: session.userCode)
                    .font(AppFont.fixed(size: 24, weight: .semibold))
                    .textSelection(.enabled)
                    .accessibilityLabel(Text("Code \(session.userCode)", tableName: "Fork"))
                Button {
                    open(session, until: expiresAt)
                } label: {
                    Label(String(localized: "Copy Code and Open Page", table: "Fork"), systemImage: "safari")
                }
                Text("Waiting for approval. The code expires at \(expiresAt, style: .time).", tableName: "Fork")
                    .font(AppFont.footnote())
                    .foregroundStyle(.appSecondary)
                cancelButton
            } header: {
                Text(verbatim: name(of: provider))
            }
        case .approved(let provider):
            outcome(provider, systemImage: "checkmark.circle.fill", tint: .green,
                    text: String(localized: "Approval received. The host saved the credentials; Hermex can’t verify which account they belong to.", table: "Fork"))
        case .failed(let provider, let failure):
            outcome(provider, systemImage: "exclamationmark.triangle.fill", tint: .orange,
                    text: ForkProviderSignInModel.message(failure))
        case .cancelled(let provider, let confirmed):
            outcome(provider, systemImage: "xmark.circle", tint: .secondary,
                    text: confirmed ? String(localized: "Sign-in cancelled.", table: "Fork")
                        : String(localized: "Hermex couldn’t confirm the host stopped this sign-in. It ends when the code expires.", table: "Fork"))
        }
    }

    private var cancelButton: some View {
        Button(String(localized: "Cancel Sign-In", table: "Fork"), role: .destructive) {
            page.close()
            Task { await model.cancel() }
        }
    }

    private func outcome(_ provider: String, systemImage: String, tint: Color, text: String) -> some View {
        Section {
            Label {
                Text(verbatim: text)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
        } header: {
            Text(verbatim: name(of: provider))
        }
    }

    private func name(of provider: String) -> String {
        model.providers?.first { $0.id == provider }?.name ?? provider
    }

    private func open(_ session: ForkOAuthDeviceSession, until expiresAt: Date) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: session.userCode]],
                                      options: [.localOnly: true, .expirationDate: expiresAt])
        page.open(session.verificationURL)
    }
}

@MainActor
final class ForkVerificationPage: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func open(_ url: URL) {
        close()
        let session = ASWebAuthenticationSession(url: url, callback: .customScheme(HermesConnectedAppsClient.returnScheme)) { _, _ in }
        session.presentationContextProvider = self
        self.session = session
        session.start()
    }

    func close() {
        session?.cancel()
        session = nil
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.compactMap(\.keyWindow)
            return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
        }
    }
}

private struct ForkProviderSignInProviderRow: View {
    let provider: ForkOAuthProvider
    let isLocked: Bool
    let signIn: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if ProviderGlyphKind.resolve(providerID: provider.id) != nil {
                ProviderGlyph(providerID: provider.id).frame(width: 17, height: 17)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: provider.name)
                status.font(AppFont.footnote()).foregroundStyle(.appSecondary)
            }
            Spacer(minLength: 8)
            if provider.signsInFromApp {
                Button(provider.loggedIn == true ? String(localized: "Sign In Again", table: "Fork")
                                                  : String(localized: "Sign In", table: "Fork"), action: signIn)
                    .buttonStyle(.bordered)
                    .disabled(isLocked)
            } else {
                Text("Set up on host", tableName: "Fork")
                    .font(AppFont.caption())
                    .foregroundStyle(.appSecondary)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch provider.loggedIn {
        case true?: Text("Credentials saved on the host", tableName: "Fork")
        case false?: Text("Not signed in", tableName: "Fork")
        case nil: Text("Status unknown", tableName: "Fork")
        }
    }
}
