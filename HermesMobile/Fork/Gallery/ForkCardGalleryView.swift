import SwiftUI

struct ForkCardGalleryView: View {
    @Environment(\.forkSharedTheme) private var theme
    @State private var gallery: ForkCardGallery?
    @State private var isLoaded = false
    @AppStorage(KitCardStyle.storageKey) private var style = KitCardStyle.defaultValue

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme?.spacing("3") ?? 12) {
                if let gallery {
                    Self.versionLabel(gallery.version)
                        .font(AppFont.footnote())
                        .foregroundStyle(.appSecondary)
                    ForkKitStylePicker(style: $style)
                    ForEach(gallery.sections) { section in
                        Text(verbatim: section.group)
                            .font(AppFont.footnote(weight: .semibold))
                            .foregroundStyle(.appSecondary)
                            .padding(.top, theme?.spacing("2") ?? 8)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.cells) { ForkCardCellView(cell: $0) }
                    }
                } else if isLoaded {
                    ContentUnavailableView(String(localized: "Catalog Unavailable", table: "Fork"), systemImage: "square.grid.2x2")
                }
            }
            .padding(theme?.spacing("pad") ?? 16)
        }
        .navigationTitle(Text("Card Gallery", tableName: "Fork"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !isLoaded else { return }
            gallery = ForkEphemeralUI.gallery()
            isLoaded = true
        }
    }

    static func versionLabel(_ version: String) -> Text {
        Text("Catalog \(version)", tableName: "Fork")
    }
}

struct ForkCardCellView: View {
    let cell: ForkCardCell

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: cell.id).font(AppFont.mono(style: .caption)).foregroundStyle(.appSecondary)
                Spacer(minLength: 8)
                Text(verbatim: cell.state).font(AppFont.mono(style: .caption)).foregroundStyle(.appTertiary)
            }
            .accessibilityHidden(true)
            ForkKitCardView(model: cell.kit)
        }
        .accessibilityIdentifier("card-gallery-" + cell.id)
    }
}

struct ForkKitStylePicker: View {
    @Binding var style: KitCardStyle

    var body: some View {
        Picker(selection: $style) {
            Text("App theme", tableName: "Fork").tag(KitCardStyle.appTheme)
            Text("Service style", tableName: "Fork").tag(KitCardStyle.serviceNative)
        } label: {
            Text("Card style", tableName: "Fork")
        }
        .pickerStyle(.segmented)
    }
}
