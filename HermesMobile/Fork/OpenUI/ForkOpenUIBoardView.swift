import SwiftUI

enum ForkOpenUIFence {
    static func matches(_ language: String?) -> Bool {
        guard let language else { return false }
        return OpenUICatalog.fenceLanguages.contains(language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

struct ForkOpenUIBoardView: View {
    let source: String
    @State private var showsSource = false

    var body: some View {
        let result = ForkOpenUIBoardCache.result(for: source)
        Group {
            switch result {
            case .ready(let board) where board.isFullyRendered:
                boardBody(board)
            case .ready:
                notice(Text("This board uses panels Hermex can't show yet.", tableName: "Fork"), problem: nil)
            case .incomplete(let problem):
                notice(Text("This board is incomplete.", tableName: "Fork"), problem: problem)
            case .invalid(let problem):
                notice(Text("This board couldn't be shown.", tableName: "Fork"), problem: problem)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.appSurface), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(.appSeparator)))
        .padding(.vertical, 4)
    }

    private func boardBody(_ board: OpenUIBoardModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: board.title).font(AppFont.headline())
            if !board.summary.isEmpty {
                Text(verbatim: board.summary).font(AppFont.subheadline()).foregroundStyle(.appSecondary)
            }
            HStack {
                Text("Read-only board", tableName: "Fork").font(AppFont.caption()).foregroundStyle(.appTertiary)
                Spacer()
                Button { showsSource.toggle() } label: {
                    Label {
                        showsSource ? Text("Hide Source", tableName: "Fork") : Text("Show Source", tableName: "Fork")
                    } icon: {
                        Image(systemName: showsSource ? "chevron.left.forwardslash.chevron.right" : "curlybraces")
                    }
                    .font(AppFont.caption(weight: .semibold))
                }
                .buttonStyle(.borderless)
            }
            ForEach(Array(board.panels.enumerated()), id: \.offset) { _, panel in
                Divider()
                ForkOpenUIPanelView(panel: panel)
            }
            if showsSource { sourceView }
        }
    }

    private func notice(_ message: Text, problem: OpenUIProblem?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { message.font(AppFont.subheadline()) } icon: { Image(systemName: "chart.bar.xaxis") }
            if let problem {
                Text(verbatim: problem.description).font(AppFont.caption()).foregroundStyle(.appSecondary)
            }
            sourceView
        }
    }

    private var sourceView: some View {
        ScrollView(.horizontal) {
            Text(verbatim: source)
                .font(AppFont.mono(style: .footnote))
                .textSelection(.enabled)
                .padding(10)
        }
        .background(Color(.appCode), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum ForkOpenUIBoardCache {
    private final class Box {
        let result: OpenUICatalogResult
        init(_ result: OpenUICatalogResult) { self.result = result }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 32
        return cache
    }()

    static func result(for source: String) -> OpenUICatalogResult {
        let key = source as NSString
        if let hit = cache.object(forKey: key) { return hit.result }
        let result = OpenUICatalog.inspect(source)
        cache.setObject(Box(result), forKey: key)
        return result
    }
}
