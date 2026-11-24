import SwiftUI
import UniformTypeIdentifiers

struct ForkAppearanceSections: View {
    @Binding var lightTheme: ColorTheme
    @Binding var darkTheme: ColorTheme
    @AppStorage(ForkThemeStore.jsonKey) private var customJSON = ""
    @AppStorage(GlassPreference.isEnabledKey) private var isGlassEnabled = GlassPreference.defaultIsEnabled
    @AppStorage(ForkTurboMotion.storageKey) private var isTurboEnabled = ForkTurboMotion.defaultIsEnabled
    @AppStorage(KitCardStyle.storageKey) private var kitCardStyle = KitCardStyle.defaultValue
    @Environment(\.appAppearance) private var appearance
    @Environment(\.forkSharedTheme) private var sharedTheme
    @State private var isImportingFile = false
    @State private var notice: ForkThemeNotice?

    var body: some View {
        Section {
            Toggle(isOn: $isTurboEnabled) {
                SettingsLabel(title: String(localized: "Turbo mode", table: "Fork"), systemImage: "bolt.fill")
            }
        } footer: {
            Text("Shortens chat and session list animations.", tableName: "Fork")
        }

        Section {
            ForEach(looks, id: \.id) { look in
                Button { apply(look) } label: { ForkLookRow(look: look, isSelected: isApplied(look)) }
                    .buttonStyle(.plain)
            }
        } header: {
            Text("Looks", tableName: "Fork")
        } footer: {
            if let version = sharedTheme?.version {
                Text("Glide comes from the shared theme file, version \(version).", tableName: "Fork")
            }
        }

        Section {
            ForkKitStylePicker(style: $kitCardStyle)
            NavigationLink {
                ForkCardGalleryView()
            } label: {
                SettingsLabel(title: String(localized: "Card Gallery", table: "Fork"), systemImage: "square.grid.2x2")
            }
        } header: {
            Text("Agent cards", tableName: "Fork")
        } footer: {
            Text("Service style draws a card in the colors of the service it comes from, such as Gmail, GitHub or Stripe.", tableName: "Fork")
                + Text(verbatim: " ")
                + Text("Every card kind in the shared ephemeral-ui catalog, drawn from its sample data.", tableName: "Fork")
        }

        Section {
            PasteButton(payloadType: String.self) { strings in
                Task { @MainActor in importJSON(strings.first ?? "") }
            }
            Button { isImportingFile = true } label: {
                SettingsLabel(title: String(localized: "Import Theme File", table: "Fork"), systemImage: "doc.badge.plus")
            }
            Button { copyCurrentTheme() } label: {
                SettingsLabel(title: String(localized: "Copy Theme JSON", table: "Fork"), systemImage: "doc.on.doc")
            }
        } header: {
            Text("Theme JSON", tableName: "Fork")
        } footer: {
            Text("Paste or import a NextGen theme: a JSON object with a name and light and dark color roles. Colors that would be hard to read are adjusted. Copy exports the current theme in the same format.", tableName: "Fork")
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.json, .plainText]) { result in
            if case .success(let url) = result { importFile(url) }
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: notice.message.map { Text($0) })
        }

        if GlassPreference.isLiquidGlassSupported {
            Section {
                Picker(selection: $isGlassEnabled) {
                    Text("Glass", tableName: "Fork").tag(true)
                    Text("Solid", tableName: "Fork").tag(false)
                } label: {
                    Text("Surfaces", tableName: "Fork")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Surfaces", tableName: "Fork")
            } footer: {
                Text("Solid replaces Liquid Glass on bars and buttons with a frosted material.", tableName: "Fork")
            }
        }
    }

    private var looks: [ForkThemeSpec] {
        (sharedTheme.map { [$0.spec] } ?? []) + ForkThemeSpec.presets
    }

    private func isApplied(_ look: ForkThemeSpec) -> Bool {
        lightTheme == .custom && darkTheme == .custom && (try? ForkThemeSpec.parse(customJSON))?.id == look.id
    }

    private func apply(_ spec: ForkThemeSpec) {
        ForkThemeStore.save(spec)
        lightTheme = .custom
        darkTheme = .custom
        AppAppearanceSettings.applyStoredToConnectedScenes()
    }

    private func importJSON(_ source: String) {
        do {
            let spec = try ForkThemeSpec.parse(source)
            apply(spec)
            notice = ForkThemeNotice(title: String(localized: "Imported \(spec.name)", table: "Fork"), message: nil)
        } catch {
            notice = ForkThemeNotice(title: String(localized: "Couldn't Import Theme", table: "Fork"),
                                     message: ForkThemeNotice.describe(error))
        }
    }

    private func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= ForkThemeStore.maximumImportBytes else {
            notice = ForkThemeNotice(title: String(localized: "Couldn't Import Theme", table: "Fork"),
                                     message: String(localized: "The file couldn't be read, or it is larger than 256 KB.", table: "Fork"))
            return
        }
        importJSON(String(decoding: data, as: UTF8.self))
    }

    private func copyCurrentTheme() {
        UIPasteboard.general.string = ForkThemeStore.exportJSON(for: appearance)
        notice = ForkThemeNotice(title: String(localized: "Theme JSON Copied", table: "Fork"), message: nil)
    }
}

private struct ForkLookRow: View {
    let look: ForkThemeSpec
    let isSelected: Bool
    @Environment(\.forkSharedTheme) private var sharedTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -6) {
                swatch(look.roles(isDark: false))
                swatch(look.roles(isDark: true))
            }
            Text(verbatim: look.name).foregroundStyle(.appPrimary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .animation(sharedTheme?.animation("quick", reduceMotion: reduceMotion), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func swatch(_ roles: ForkPaletteRoles) -> some View {
        Circle()
            .fill(color(roles.canvas))
            .overlay(Circle().inset(by: 7).fill(color(roles.accent)))
            .overlay(Circle().strokeBorder(Color(.appSeparator)))
            .frame(width: 26, height: 26)
    }

    private func color(_ value: ForkRGBA) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}

struct ForkThemeNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String?

    static func describe(_ error: Error) -> String {
        switch error as? ForkThemeError {
        case .invalidJSON?: String(localized: "That isn't valid JSON.", table: "Fork")
        case .notAnObject?: String(localized: "A theme is a JSON object.", table: "Fork")
        case .missingName?: String(localized: "A theme needs a \"name\".", table: "Fork")
        case .rolesNotAnObject(let key)?: String(localized: "\"\(key)\" must be an object of color roles.", table: "Fork")
        case .unknownRole(let role)?: String(localized: "Unknown color role \"\(role)\".", table: "Fork")
        case .notAHexString(let role)?: String(localized: "\"\(role)\" must be a hex string.", table: "Fork")
        case .badColor(let role, let value)?: String(localized: "\"\(role)\" is \(value), not a #RRGGBB or #RRGGBBAA color.", table: "Fork")
        case .badGlow?: String(localized: "\"glow\" must be true or false.", table: "Fork")
        case nil: error.localizedDescription
        }
    }
}
