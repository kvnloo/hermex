import SwiftUI

struct ForkCardGalleryView: View {
    @Environment(\.forkSharedTheme) private var theme
    @State private var gallery: ForkCardGallery?
    @State private var isLoaded = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme?.spacing("3") ?? 12) {
                if let gallery {
                    Self.versionLabel(gallery.version)
                        .font(AppFont.footnote())
                        .foregroundStyle(.appSecondary)
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

private struct ForkCardCellView: View {
    let cell: ForkCardCell
    @Environment(\.forkSharedTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme?.corner("card") ?? 16, style: .continuous)
        VStack(alignment: .leading, spacing: theme?.spacing("1") ?? 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: cell.label).font(AppFont.body(weight: .semibold)).foregroundStyle(.appPrimary)
                Spacer(minLength: 8)
                Text(verbatim: cell.state).font(AppFont.mono(style: .footnote)).foregroundStyle(.appSecondary)
            }
            Text(verbatim: cell.id).font(AppFont.mono(style: .footnote)).foregroundStyle(.appSecondary)
            if let reason = cell.unavailableReason {
                Label { Text(verbatim: reason) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(AppFont.footnote())
                    .foregroundStyle(.appSecondary)
            }
            ForEach(cell.lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: line.key).font(AppFont.mono(style: .footnote)).foregroundStyle(.appSecondary)
                    Text(verbatim: line.value).font(AppFont.footnote()).foregroundStyle(.appPrimary).lineLimit(3)
                }
            }
        }
        .padding(theme?.spacing("3") ?? 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme?.material(glass: "card") ?? .regularMaterial, in: shape)
        .overlay(shape.strokeBorder(Color(.appSeparator)))
        .accessibilityElement(children: .combine)
    }
}
