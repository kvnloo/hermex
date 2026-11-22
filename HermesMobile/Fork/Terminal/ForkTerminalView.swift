import SwiftUI

struct ForkTerminalSettingsRow: View {
    let connection: BotConnection
    let server: URL

    var body: some View {
        NavigationLink {
            ForkTerminalView(connection: connection, server: server)
        } label: {
            SettingsLabel(title: String(localized: "Terminal", table: "Fork"), systemImage: "terminal")
        }
    }
}

struct ForkTerminalView: View {
    @State private var session: ForkHostTerminalSession
    @State private var input = ""
    @State private var grid: ForkTerminalGrid?
    @FocusState private var inputFocused: Bool
    private static let fontSize: CGFloat = 12
    private static let cell = CGSize(width: fontSize * 0.6, height: fontSize * 1.25)

    init(connection: BotConnection, server: URL, profile: String? = nil) {
        _session = State(initialValue: ForkHostTerminalSession(connection: connection, server: server, profile: profile))
    }

    var body: some View {
        VStack(spacing: 0) {
            output
            if case .open = session.state { keyBar; inputRow } else { statusBar }
        }
        .navigationTitle(session.screen.title ?? session.meta.shell ?? String(localized: "Terminal", table: "Fork"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { session.close() }
    }

    private var output: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView([.vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let lines = session.screen.scrollback + session.screen.lines
                        ForEach(lines.indices, id: \.self) { index in
                            Text(ForkTerminalLine.attributed(lines[index]))
                                .font(.system(size: Self.fontSize, design: .monospaced))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .id(index)
                        }
                    }
                    .padding(6)
                    .textSelection(.enabled)
                }
                .onChange(of: session.revision) {
                    reader.scrollTo(session.screen.scrollback.count + session.screen.lines.count - 1, anchor: .bottom)
                }
            }
            .onAppear { layout(proxy.size) }
            .onChange(of: proxy.size) { _, size in layout(size) }
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .onTapGesture { inputFocused = true }
        .accessibilityLabel(Text("Terminal output", tableName: "Fork"))
    }

    private var keyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ForkTerminalProtocol.keys, id: \.label) { key in
                    Button(key.label) { session.send(key.sequence) }
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField(text: $input) { Text("Type a command", tableName: "Fork") }
                .font(.system(size: 15, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(submit)
            Button(action: submit) { Image(systemName: "return") }
                .accessibilityLabel(Text("Send", tableName: "Fork"))
        }
        .padding(10)
        .background(.appMaterial(.bar))
    }

    @ViewBuilder
    private var statusBar: some View {
        HStack {
            switch session.state {
            case .idle, .connecting:
                ProgressView()
                Text("Connecting…", tableName: "Fork")
            case .unavailable:
                Text("This Hermes host doesn't offer a terminal to this sign-in.", tableName: "Fork")
            case .ended(let reason):
                Text(verbatim: reason)
                Spacer()
                Button { reopen() } label: { Text("Reopen", tableName: "Fork") }
            case .open:
                EmptyView()
            }
        }
        .font(AppFont.footnote())
        .foregroundStyle(.appSecondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.appMaterial(.bar))
    }

    private func submit() {
        session.send(input + "\r")
        input = ""
    }

    private func layout(_ size: CGSize) {
        let fitted = ForkTerminalProtocol.grid(width: size.width - 12, height: size.height - 12,
                                               cellWidth: Self.cell.width, cellHeight: Self.cell.height)
        let next = ForkTerminalGrid(columns: fitted.columns, rows: fitted.rows)
        guard next != grid else { return }
        let first = grid == nil
        grid = next
        if first { Task { await session.open(columns: next.columns, rows: next.rows) } }
        else { session.resize(columns: next.columns, rows: next.rows) }
    }

    private func reopen() {
        guard let grid else { return }
        Task { await session.open(columns: grid.columns, rows: grid.rows) }
    }
}

struct ForkTerminalGrid: Equatable {
    let columns: Int
    let rows: Int
}

enum ForkTerminalLine {
    static func attributed(_ cells: [ForkTerminalCell]) -> AttributedString {
        var result = AttributedString()
        var index = 0
        let end = (cells.lastIndex { $0.character != " " || $0.style.background != .standard } ?? -1) + 1
        while index < end {
            let style = cells[index].style
            var run = ""
            while index < end, cells[index].style == style {
                run.append(cells[index].character)
                index += 1
            }
            var piece = AttributedString(run)
            let foreground = color(style.inverse ? style.background : style.foreground, fallback: .white)
            let background = color(style.inverse ? style.foreground : style.background, fallback: nil)
            piece.foregroundColor = foreground
            if let background { piece.backgroundColor = background }
            if style.bold { piece.inlinePresentationIntent = .stronglyEmphasized }
            if style.underline { piece.underlineStyle = .single }
            result += piece
        }
        return result.characters.isEmpty ? AttributedString(" ") : result
    }

    private static func color(_ color: ForkTerminalColor, fallback: Color?) -> Color? {
        switch color {
        case .standard: return fallback
        case .palette(let index):
            let rgb = ForkTerminalPalette.rgb(index)
            return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
        case .rgb(let red, let green, let blue):
            return Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
        }
    }
}
