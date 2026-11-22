import PencilKit
import SwiftUI

extension View {
    func forkAnnotate(
        _ viewModel: ChatViewModel, title: String, isLive: Binding<Bool>, startLive: @escaping () -> Void
    ) -> some View {
        modifier(ForkAnnotateEntry(viewModel: viewModel, title: title, isLive: isLive, startLive: startLive))
    }
}

struct ForkSnapshot: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ForkAnnotateEntry: ViewModifier {
    let viewModel: ChatViewModel
    let title: String
    @Binding var isLive: Bool
    let startLive: () -> Void
    @State private var snapshot: ForkSnapshot?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isLive {
                        Button { isLive = false } label: {
                            Label("Stop Circling", systemImage: "xmark.circle")
                        }
                        .tint(.red)
                    } else {
                        Menu {
                            Button(action: startLive) {
                                Label("Circle Text to Draft", systemImage: "lasso")
                            }
                            Button {
                                if let image = ForkAnnotationInk.captureKeyWindow() { snapshot = ForkSnapshot(image: image) }
                            } label: {
                                Label("Annotate Screenshot", systemImage: "pencil.tip.crop.circle")
                            }
                        } label: {
                            Label("Annotate", systemImage: "pencil.tip.crop.circle")
                        }
                        .disabled(viewModel.isViewingCachedData)
                    }
                }
            }
            .fullScreenCover(item: $snapshot) { snapshot in
                ForkAnnotationView(snapshot: snapshot.image, viewModel: viewModel, route: title)
            }
    }
}

struct ForkAnnotationView: View {
    let snapshot: UIImage
    let viewModel: ChatViewModel
    let route: String
    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var colors: [String] = []
    @State private var usesMarker = false
    @State private var note = ""
    @State private var narration = ForkNarration()
    @State private var isSending = false
    @State private var failure: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Image(uiImage: snapshot).resizable().frame(width: proxy.size.width, height: proxy.size.height)
                ForkInkCanvas(drawing: $drawing, tool: tool)
                    .onChange(of: drawing.strokes.count) { _, count in syncColors(count) }
                controls(size: proxy.size)
            }
        }
        .ignoresSafeArea()
        .onDisappear { narration.stop() }
    }

    private var tool: PKTool {
        usesMarker ? PKInkingTool(.marker, color: .systemYellow, width: 24) : PKInkingTool(.pen, color: .systemRed, width: 5)
    }

    private func syncColors(_ count: Int) {
        if count < colors.count { colors.removeLast(colors.count - count) }
        while colors.count < count { colors.append(usesMarker ? "yellow" : "red") }
    }

    private func controls(size: CGSize) -> some View {
        VStack(spacing: 10) {
            if let failure { Text(verbatim: failure).font(AppFont.footnote()).foregroundStyle(.red) }
            if !narration.transcript.isEmpty {
                Text(verbatim: narration.transcript).font(AppFont.footnote()).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField(text: $note, axis: .vertical) { Text("Add a note", tableName: "Fork") }
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 18) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("Cancel", tableName: "Fork"))
                Button { usesMarker.toggle() } label: { Image(systemName: usesMarker ? "highlighter" : "pencil.tip") }
                    .accessibilityLabel(usesMarker ? Text("Highlighter", tableName: "Fork") : Text("Pen", tableName: "Fork"))
                Button { if !drawing.strokes.isEmpty { drawing.strokes.removeLast() } } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(drawing.strokes.isEmpty)
                    .accessibilityLabel(Text("Undo", tableName: "Fork"))
                Button { narration.toggle() } label: { Image(systemName: narration.isListening ? "mic.fill" : "mic") }
                    .accessibilityLabel(narration.isListening ? Text("Stop Narrating", tableName: "Fork") : Text("Narrate", tableName: "Fork"))
                Spacer()
                Button { send(size: size) } label: {
                    if isSending { ProgressView() } else { Text("Send", tableName: "Fork").bold() }
                }
                .buttonStyle(.appProminent)
                .disabled(isSending || (drawing.strokes.isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            .font(.system(size: 20, weight: .semibold))
        }
        .padding(16)
        .padding(.bottom, 20)
        .background(.appMaterial(.bar))
    }

    private func send(size: CGSize) {
        narration.stop()
        isSending = true
        failure = nil
        let createdAt = Int((Date().timeIntervalSince1970 * 1000).rounded())
        let screen = AnnotationScreen(id: "chat", route: route, width: size.width, height: size.height)
        let strokes = ForkAnnotationInk.strokes(from: drawing, colors: colors, in: size)
        let segments = narration.segments
        let message = AnnotationCompose.message(strokes: strokes, segments: segments, screen: screen, typed: note)
        let names = AnnotationCompose.attachmentNames(createdAt: createdAt)
        let image = ForkAnnotationInk.composite(snapshot: snapshot, drawing: drawing, canvasSize: size)
        let document = try? AnnotationCompose.document(strokes: strokes, segments: segments, screen: screen, createdAt: createdAt)
        Task {
            defer { isSending = false }
            guard let image, let document,
                  await viewModel.uploadAttachment(data: image, filename: names.image) != nil,
                  await viewModel.uploadAttachment(data: document, filename: names.json) != nil else {
                failure = String(localized: "Couldn't attach the annotation.", table: "Fork")
                return
            }
            if await viewModel.sendMessage(message) { dismiss() } else {
                failure = String(localized: "Couldn't send. The annotation is in your draft.", table: "Fork")
            }
        }
    }
}

@MainActor
@Observable
final class ForkNarration {
    private(set) var segments: [AnnotationSegment] = []
    private(set) var transcript = ""
    @ObservationIgnored private let voice = ComposerVoiceInputController()
    @ObservationIgnored private var draft = ""
    @ObservationIgnored private var startedAt = 0

    var isListening: Bool { voice.isListening }

    func toggle() {
        if voice.isListening { stop() } else { start() }
    }

    func start() {
        draft = ""
        startedAt = Self.now
        voice.scheduleToggle(
            draftState: { [weak self] in
                let text = self?.draft ?? ""
                return ComposerVoiceDraftState(text: text, selection: ComposerSelection(range: NSRange(location: (text as NSString).length, length: 0)))
            },
            updateDraft: { [weak self] update in
                self?.draft = update.text
                self?.refreshTranscript()
            }
        )
    }

    func stop() {
        guard voice.isListening else { return }
        voice.stopKeepingTranscript()
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            segments.append(AnnotationSegment(id: "s\(segments.count + 1)", text: text, start: startedAt, end: Self.now, source: "speech"))
        }
        draft = ""
        refreshTranscript()
    }

    private func refreshTranscript() {
        transcript = (segments.map(\.text) + [draft]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static var now: Int { Int((Date().timeIntervalSince1970 * 1000).rounded()) }
}
