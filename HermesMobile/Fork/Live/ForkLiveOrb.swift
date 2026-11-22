import SwiftUI

enum ForkLiveOrbStyle: String, CaseIterable, Identifiable {
    case voice
    case thinking

    var id: String { rawValue }

    var label: Text {
        switch self {
        case .voice: Text("Voice Orb", tableName: "Fork")
        case .thinking: Text("Thinking Orb", tableName: "Fork")
        }
    }
}

extension EnvironmentValues {
    @Entry var forkLiveOrbIsStill = false
}

struct ForkLiveOrb: View {
    let phase: LivePhase
    let level: Double
    let style: ForkLiveOrbStyle
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forkLiveOrbIsStill) private var isStill

    private var reduceMotion: Bool { systemReduceMotion || isStill }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let side = min(size.width, size.height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = side * 0.34 * LiveOrbGeometry.voiceScale(level: reduceMotion ? 0 : level, time: time, phase: phase)
                if style == .voice || phase == .listening || phase == .speaking {
                    drawBlob(in: &canvas, center: center, radius: radius, time: time)
                }
                if style == .thinking || phase == .thinking || phase == .sending {
                    drawDots(in: &canvas, center: center, side: side, time: time)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func drawBlob(in canvas: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        let points = LiveOrbGeometry.blob(level: reduceMotion ? 0 : level, time: time)
        var path = Path()
        for (index, point) in points.enumerated() {
            let location = CGPoint(x: center.x + point.x * radius, y: center.y + point.y * radius)
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        path.closeSubpath()
        let gradient = Gradient(colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.35)])
        canvas.fill(path, with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius * 1.2))
        canvas.stroke(path, with: .color(Color.accentColor.opacity(0.5)), lineWidth: 1.5)
    }

    private func drawDots(in canvas: inout GraphicsContext, center: CGPoint, side: CGFloat, time: Double) {
        for dot in LiveOrbGeometry.thinkingDots(time: time) {
            let size = side * 0.09 * dot.scale
            let rect = CGRect(x: center.x + dot.x * side - size / 2, y: center.y + dot.y * side - size / 2, width: size, height: size)
            canvas.fill(Path(ellipseIn: rect), with: .color(Color.accentColor.opacity(dot.opacity)))
        }
    }
}
