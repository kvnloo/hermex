import PencilKit
import SwiftUI

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
