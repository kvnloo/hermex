import PencilKit
import SwiftUI
import Vision

struct ForkInkCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let tool: PKTool

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = tool
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.tool = tool
        if canvas.drawing != drawing { canvas.drawing = drawing }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if drawing.wrappedValue != canvasView.drawing { drawing.wrappedValue = canvasView.drawing }
        }
    }
}

enum ForkAnnotationInk {
    static func strokes(from drawing: PKDrawing, colors: [String], in size: CGSize) -> [AnnotationStroke] {
        guard size.width > 0, size.height > 0 else { return [] }
        return drawing.strokes.enumerated().map { index, stroke in
            let created = stroke.path.creationDate.timeIntervalSince1970
            let points = stroke.path.map { point in
                AnnotationPoint(x: point.location.x / size.width, y: point.location.y / size.height,
                                pressure: min(max(Double(point.force), 0), 1),
                                time: Int(((created + point.timeOffset) * 1000).rounded()))
            }
            let isStylus = stroke.path.contains { $0.altitude < .pi / 2 - 0.01 }
            let isMarker = stroke.ink.inkType == .marker
            return AnnotationStroke(
                id: index + 1, tool: isMarker ? "highlighter" : "pen",
                color: index < colors.count ? colors[index] : "red", pointer: isStylus ? "stylus" : "touch",
                points: points, startedAt: points.first?.time ?? Int(created * 1000),
                endedAt: points.last?.time ?? Int(created * 1000)
            )
        }
    }

    static func composite(snapshot: UIImage, drawing: PKDrawing, canvasSize: CGSize) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.scale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let image = renderer.image { _ in
            snapshot.draw(in: CGRect(origin: .zero, size: canvasSize))
            drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: snapshot.scale)
                .draw(in: CGRect(origin: .zero, size: canvasSize))
        }
        return image.pngData()
    }

    @MainActor
    static func captureKeyWindow() -> UIImage? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
    }
}

struct ForkLiveInkCanvas: UIViewRepresentable {
    let onSelection: (String) -> Void

    func makeUIView(context: Context) -> LiveInkView { LiveInkView() }

    func updateUIView(_ view: LiveInkView, context: Context) {
        view.onSelection = onSelection
    }

    static func dismantleUIView(_ view: LiveInkView, coordinator: ()) {
        view.cancelRecognition()
    }

    final class LiveInkView: UIView {
        var onSelection: ((String) -> Void)?
        private let ink = CAShapeLayer()
        private var samples: [AnnotationPoint] = []
        private var path = UIBezierPath()
        private var recognition: Task<Void, Never>?

        init() {
            super.init(frame: .zero)
            backgroundColor = .clear
            isOpaque = false
            isAccessibilityElement = false
            ink.fillColor = nil
            ink.strokeColor = UIColor.systemRed.cgColor
            ink.lineWidth = 4
            ink.lineCap = .round
            ink.lineJoin = .round
            layer.addSublayer(ink)
        }

        required init?(coder: NSCoder) { nil }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            cancelRecognition()
            resetStroke()
            append(touches)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            append(event?.coalescedTouches(for: touch) ?? [touch])
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            append(touches)
            let stroke = AnnotationStroke(id: 1, tool: "pen", color: "red",
                                          pointer: touches.first?.type == .pencil ? "stylus" : "touch",
                                          points: samples, startedAt: samples.first?.time ?? 0, endedAt: samples.last?.time ?? 0)
            let screen = AnnotationScreen(id: "chat", route: "chat", width: bounds.width, height: bounds.height)
            resetStroke()
            guard let region = AnnotationCompose.closedLoopRegion(stroke, screen: screen, allowsTouch: true),
                  let image = capture(region) else { return }
            recognition = Task { [weak self] in
                let text = await Self.recognize(image, region: region)
                guard !Task.isCancelled, !text.isEmpty else { return }
                self?.onSelection?(text)
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            resetStroke()
        }

        func cancelRecognition() {
            recognition?.cancel()
            recognition = nil
        }

        private func append(_ touches: some Sequence<UITouch>) {
            guard bounds.width > 0, bounds.height > 0 else { return }
            for touch in touches {
                let point = touch.location(in: self)
                guard bounds.contains(point) else { continue }
                if samples.isEmpty { path.move(to: point) } else { path.addLine(to: point) }
                samples.append(AnnotationPoint(x: point.x / bounds.width, y: point.y / bounds.height,
                                               pressure: 1, time: Int(touch.timestamp * 1000)))
            }
            ink.path = path.cgPath
        }

        private func resetStroke() {
            samples.removeAll()
            path = UIBezierPath()
            ink.path = nil
        }

        private func capture(_ region: AnnotationRegion) -> Data? {
            guard let window else { return nil }
            let rect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
            let crop = convert(rect, to: window)
            let format = UIGraphicsImageRendererFormat()
            format.scale = window.traitCollection.displayScale
            let renderer = UIGraphicsImageRenderer(size: crop.size, format: format)
            var drawn = false
            isHidden = true
            defer { isHidden = false }
            let image = renderer.image { context in
                context.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
                drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            return drawn ? image.pngData() : nil
        }

        nonisolated private static func recognize(_ image: Data, region: AnnotationRegion) async -> String {
            await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(data: image)
                guard (try? handler.perform([request])) != nil else { return "" }
                let boxes = (request.results ?? []).compactMap { observation -> AnnotationTextBox? in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    let rect = observation.boundingBox
                    return AnnotationTextBox(x: Double(region.x) + rect.minX * Double(region.width),
                                             y: Double(region.y) + (1 - rect.maxY) * Double(region.height),
                                             width: rect.width * Double(region.width),
                                             height: rect.height * Double(region.height), text: text)
                }
                return AnnotationCompose.visibleText(in: region, boxes: boxes)
            }.value
        }
    }
}
