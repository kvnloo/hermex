import SwiftUI

struct ForkCardGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var contents: Result<Contents, Error>?

    struct Contents {
        let gallery: ForkCardGallery
        let theme: ForkGalleryTheme

        init(bundle: Bundle = .main) throws {
            func data(_ name: String) throws -> Data {
                guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "EphemeralGallery") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return try Data(contentsOf: url)
            }
            gallery = try ForkCardGallery.parse(data("catalog"))
            theme = try ForkGalleryTheme.parse(data("glide"))
        }
    }

    var body: some View {
        Group {
            switch contents {
            case .success(let contents):
                galleryView(contents)
            case .failure:
                Text("Card catalog couldn't be loaded.", tableName: "Fork")
            case nil:
                ProgressView()
            }
        }
        .navigationTitle(Text("Card Gallery", tableName: "Fork"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard contents == nil else { return }
            contents = Result { try Contents() }
        }
    }

    private func galleryView(_ contents: Contents) -> some View {
        let palette = contents.theme.palette(colorScheme)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(verbatim: contents.gallery.versionLabel)
                    .font(AppFont.caption())
                    .accessibilityIdentifier("card-gallery-version")
                ForEach(contents.gallery.sections) { section in
                    Text(verbatim: section.title)
                        .font(AppFont.headline())
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 8)
                    ForEach(section.cells) { cell in
                        ForkCardGalleryCellView(cell: cell, theme: contents.theme)
                    }
                }
            }
            .padding()
            .foregroundStyle(Color(galleryHex: palette.fg))
        }
        .background(Color(galleryHex: palette.bg).ignoresSafeArea())
    }
}

private extension ForkGalleryTheme {
    func palette(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? color.dark : color.light
    }
}

private extension Color {
    init(galleryHex hex: String) {
        if let rgb = ForkRGBA(hex: hex) {
            self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: rgb.alpha)
        } else {
            self = .primary
        }
    }
}

struct ForkCardGalleryCellView: View {
    let cell: ForkCardGallery.Cell
    let theme: ForkGalleryTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(colorScheme)
        let shape = RoundedRectangle(cornerRadius: CGFloat(theme.radius.card))
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: cell.id).font(AppFont.caption())
            switch cell.content {
            case .board(let board, _):
                ForkOpenUIBoardView(board: board)
            case .unsupported:
                Text("This card isn't supported in Hermex.", tableName: "Fork")
            case .unavailable:
                Text("No data available", tableName: "Fork")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color(galleryHex: palette.fg))
        .background(Color(galleryHex: palette.card), in: shape)
        .overlay(shape.strokeBorder(Color(galleryHex: palette.border)))
        .accessibilityIdentifier("card-gallery-" + cell.id)
    }
}
