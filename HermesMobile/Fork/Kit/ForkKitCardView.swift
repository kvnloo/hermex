import SwiftUI

enum ForkKitCards {
    static let library: KitCardLibrary? = ForkEphemeralUI.data("catalog")
        .flatMap { try? ForkCardCatalog.parse($0) }
        .map(KitCardLibrary.init)

    static func resolve(_ spec: KitCardSpec) -> Result<KitCardModel, ForkKitCardProblem> {
        guard let library else { return .failure(.catalogMissing) }
        switch library.resolve(spec) {
        case .card(let model): return .success(model)
        case .unknownKind(let kind): return .failure(.unknownKind(kind))
        case .unknownApp(let kind, let app): return .failure(.unknownApp(kind: kind, app: app))
        }
    }
}

enum ForkKitCardProblem: Error, Equatable {
    case catalogMissing
    case unknownKind(String)
    case unknownApp(kind: String, app: String)
    case unreadable(String)

    var message: Text {
        switch self {
        case .catalogMissing: Text("The card catalog is missing from this build.", tableName: "Fork")
        case .unknownKind(let name): Text("Hermex doesn't know the card kind “\(name)”.", tableName: "Fork")
        case .unknownApp(let name, let value): Text("The \(name) card doesn't come in \(value).", tableName: "Fork")
        case .unreadable(let reason): Text(verbatim: reason)
        }
    }
}

struct ForkKitFenceView: View {
    let source: String

    var body: some View {
        switch ForkKitFenceCache.result(for: source) {
        case .success(let program):
            VStack(alignment: .leading, spacing: 10) {
                if let title = program.title {
                    Text(verbatim: title).font(AppFont.subheadline(weight: .semibold))
                }
                ForEach(Array(program.cards.enumerated()), id: \.offset) { _, spec in
                    ForkKitEntryView(entry: .catalog(spec))
                }
            }
            .padding(.vertical, 4)
        case .failure(let problem):
            ForkKitProblemView(problem: problem)
        }
    }
}

struct ForkKitEntryView: View {
    let entry: KitCardEntry

    var body: some View {
        switch entry {
        case .drawn(let model): ForkKitCardView(model: model)
        case .catalog(let spec):
            switch ForkKitCards.resolve(spec) {
            case .success(let model): ForkKitCardView(model: model)
            case .failure(let problem): ForkKitProblemView(problem: problem)
            }
        }
    }
}

struct ForkKitProblemView: View {
    let problem: ForkKitCardProblem

    var body: some View {
        Label { problem.message.font(AppFont.footnote()) } icon: { Image(systemName: "rectangle.on.rectangle.slash") }
            .foregroundStyle(.appSecondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.appSurface), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ForkKitCardView: View {
    let model: KitCardModel
    var style: KitCardStyle?
    @AppStorage(KitCardStyle.storageKey) private var storedStyle = KitCardStyle.defaultValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.forkSharedTheme) private var theme

    var body: some View {
        let look = ForkKitLook((style ?? storedStyle).skin(for: model.app), dark: colorScheme == .dark, theme: theme)
        let shape = RoundedRectangle(cornerRadius: look.corner, style: .continuous)
        VStack(alignment: .leading, spacing: look.spacing) {
            header(look)
            if model.layout != .unavailable { titleBlock(look) }
            switch model.layout {
            case .hero: if let hero = model.hero { heroBlock(hero, look) }
            case .route: if let route = model.route { routeBlock(route, look) }
            case .unavailable:
                Label { Text(verbatim: model.unavailableReason ?? "") } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(AppFont.footnote())
                    .foregroundStyle(look.secondary)
            case .list, .facts: EmptyView()
            }
            if !model.rows.isEmpty { rowsBlock(look) }
            if !model.facts.isEmpty { factsBlock(look) }
            if !model.chips.isEmpty { chipsBlock(look) }
        }
        .fontDesign(look.design)
        .padding(look.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(look.card, in: shape)
        .overlay(shape.strokeBorder(look.border))
        .environment(\.colorScheme, look.scheme ?? colorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.accessibilityText))
        .accessibilityIdentifier("kit-card-" + model.kind)
    }

    private func header(_ look: ForkKitLook) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: look.monogram ?? String(model.appName.prefix(1)).uppercased())
                .font(AppFont.caption2(weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(look.accentInk)
                .frame(width: 22, height: 22)
                .background(look.accent, in: RoundedRectangle(cornerRadius: min(look.corner / 2, 6), style: .continuous))
            Text(verbatim: model.appName)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(look.text)
            Text(verbatim: model.label)
                .font(AppFont.caption())
                .foregroundStyle(look.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let status = model.status {
                Text(verbatim: status.text)
                    .font(AppFont.caption2(weight: .semibold))
                    .foregroundStyle(look.tone(status.tone))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(look.tone(status.tone).opacity(0.14), in: Capsule())
                    .lineLimit(1)
            }
        }
    }

    private func titleBlock(_ look: ForkKitLook) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: model.title)
                .font(AppFont.headline())
                .foregroundStyle(look.text)
                .lineLimit(3)
            if let subtitle = model.subtitle, !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(AppFont.footnote())
                    .foregroundStyle(look.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func heroBlock(_ hero: KitHero, _ look: ForkKitLook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: hero.value)
                    .font(AppFont.title(weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(look.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let trend = hero.trend {
                    Label {
                        Text(verbatim: KitFormat.number(abs(trend)) + "%")
                    } icon: {
                        Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                    }
                    .font(AppFont.footnote(weight: .semibold))
                    .foregroundStyle(look.tone(trend >= 0 ? .positive : .critical))
                }
            }
            if let caption = hero.caption, !caption.isEmpty {
                Text(verbatim: caption).font(AppFont.footnote()).foregroundStyle(look.secondary)
            }
            if let progress = hero.progress {
                ProgressView(value: progress).tint(look.accent)
            }
        }
    }

    private func routeBlock(_ route: KitRoute, _ look: ForkKitLook) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 2) {
                Circle().fill(look.accent).frame(width: 8, height: 8)
                Rectangle().fill(look.border).frame(width: 2, height: 18)
                Circle().strokeBorder(look.accent, lineWidth: 2).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: route.from).font(AppFont.subheadline()).foregroundStyle(look.text).lineLimit(1)
                Text(verbatim: route.to).font(AppFont.subheadline(weight: .semibold)).foregroundStyle(look.text).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let detail = route.detail {
                Text(verbatim: detail).font(AppFont.subheadline(weight: .semibold)).monospacedDigit().foregroundStyle(look.accent)
            }
        }
        .padding(10)
        .background(look.raised, in: RoundedRectangle(cornerRadius: max(look.corner - 6, 4), style: .continuous))
    }

    private func rowsBlock(_ look: ForkKitLook) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.rows) { row in
                if row.id > 0 { Rectangle().fill(look.border).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let tone = row.tone {
                        Circle().fill(look.tone(tone)).frame(width: 7, height: 7)
                    } else if row.isEmphasized {
                        Circle().fill(look.accent).frame(width: 7, height: 7)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: row.title)
                            .font(AppFont.subheadline(weight: row.isEmphasized ? .semibold : .regular))
                            .foregroundStyle(look.text)
                            .lineLimit(2)
                        if let detail = row.detail, !detail.isEmpty {
                            Text(verbatim: detail).font(AppFont.footnote()).foregroundStyle(look.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                    if let trailing = row.trailing {
                        Text(verbatim: trailing).font(AppFont.footnote(weight: .semibold)).monospacedDigit().foregroundStyle(look.text)
                    }
                }
                .padding(.vertical, look.rowPadding)
            }
        }
    }

    private func factsBlock(_ look: ForkKitLook) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(model.facts) { fact in
                GridRow {
                    Text(verbatim: fact.label).font(AppFont.footnote()).foregroundStyle(look.secondary)
                    Text(verbatim: fact.value).font(AppFont.footnote(weight: .medium)).foregroundStyle(look.text).lineLimit(3)
                }
            }
        }
    }

    private func chipsBlock(_ look: ForkKitLook) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(model.chips.enumerated()), id: \.offset) { _, chip in
                    Text(verbatim: chip)
                        .font(AppFont.caption(weight: .medium))
                        .foregroundStyle(look.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(look.raised, in: RoundedRectangle(cornerRadius: look.pill ? 100 : 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: look.pill ? 100 : 6, style: .continuous).strokeBorder(look.border))
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct ForkKitLook {
    let card: Color
    let raised: Color
    let text: Color
    let secondary: Color
    let border: Color
    let accent: Color
    let accentInk: Color
    let corner: CGFloat
    let spacing: CGFloat
    let padding: CGFloat
    let rowPadding: CGFloat
    let design: Font.Design
    let pill: Bool
    let monogram: String?
    let scheme: ColorScheme?

    init(_ skin: KitCardSkin, dark: Bool, theme: ForkSharedTheme?) {
        switch skin {
        case .appTheme:
            card = Color(.appSurface)
            raised = Color(.appFillSecondary)
            text = Color(.appText)
            secondary = Color(.appTextSecondary)
            border = Color(.appSeparator)
            accent = .accentColor
            accentInk = .white
            corner = theme?.corner("card") ?? 16
            spacing = theme?.spacing("2") ?? 8
            padding = theme?.spacing("3") ?? 12
            rowPadding = 6
            design = .default
            pill = true
            monogram = nil
            scheme = nil
        case .service(let brand):
            let palette = brand.palette(dark: dark)
            card = Color(kitRGB: palette.card)
            raised = Color(kitRGB: palette.raised)
            text = Color(kitRGB: palette.text)
            secondary = Color(kitRGB: palette.secondary)
            border = Color(kitRGB: palette.border)
            accent = Color(kitRGB: palette.accent)
            accentInk = Color(kitRGB: palette.accentInk)
            corner = brand.corner
            spacing = brand.rowSpacing
            padding = max(brand.rowSpacing + 6, 12)
            rowPadding = brand.rowSpacing / 2 + 2
            design = switch brand.font {
            case .standard: .default
            case .rounded: .rounded
            case .monospaced: .monospaced
            }
            pill = brand.pillButtons
            monogram = brand.monogram
            scheme = KitPalette.luminance(palette.card) < 0.4 ? .dark : .light
        }
    }

    func tone(_ tone: KitTone) -> Color {
        switch tone {
        case .neutral: secondary
        case .positive: .green
        case .warning: .orange
        case .critical: .red
        case .info: accent
        }
    }
}

private extension Color {
    init(kitRGB rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

private enum ForkKitFenceCache {
    private final class Box {
        let result: Result<KitCardProgram, ForkKitCardProblem>
        init(_ result: Result<KitCardProgram, ForkKitCardProblem>) { self.result = result }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 32
        return cache
    }()

    static func result(for source: String) -> Result<KitCardProgram, ForkKitCardProblem> {
        let key = source as NSString
        if let hit = cache.object(forKey: key) { return hit.result }
        let result: Result<KitCardProgram, ForkKitCardProblem>
        do { result = .success(try KitCardProgram.parseFence(source)) } catch KitCardProgramError.invalid(let reason) {
            result = .failure(.unreadable(reason))
        } catch {
            result = .failure(.unreadable(String(describing: error)))
        }
        cache.setObject(Box(result), forKey: key)
        return result
    }
}
