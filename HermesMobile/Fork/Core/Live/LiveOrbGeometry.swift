import Foundation

struct LiveOrbDot: Equatable, Sendable {
    let x: Double
    let y: Double
    let scale: Double
    let opacity: Double
}

enum LiveOrbGeometry {
    static func smoothed(previous: Double, level: Double, rising: Double = 0.55, falling: Double = 0.12) -> Double {
        let clamped = min(max(level, 0), 1)
        let factor = clamped > previous ? rising : falling
        return previous + (clamped - previous) * factor
    }

    static func voiceScale(level: Double, time: Double, phase: LivePhase) -> Double {
        let breath = 0.03 * sin(time * 2 * .pi / 3.2)
        switch phase {
        case .listening: return 1 + 0.35 * min(max(level, 0), 1) + breath
        case .speaking: return 1.06 + 0.08 * sin(time * 2 * .pi / 0.45) + breath
        case .thinking, .sending: return 0.92 + breath
        case .idle, .paused, .failed: return 0.88 + breath / 2
        }
    }

    static func thinkingDots(time: Double, count: Int = 5, radius: Double = 0.32) -> [LiveOrbDot] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let share = Double(index) / Double(count)
            let angle = 2 * .pi * (share + time / 2.4)
            let wobble = 1 + 0.12 * sin(time * 3 + Double(index))
            let pulse = 0.5 + 0.5 * sin(time * 4 - Double(index) * 0.9)
            return LiveOrbDot(x: cos(angle) * radius * wobble, y: sin(angle) * radius * wobble,
                              scale: 0.6 + 0.4 * pulse, opacity: 0.45 + 0.55 * pulse)
        }
    }

    static func blob(level: Double, time: Double, points: Int = 48) -> [(x: Double, y: Double)] {
        let energy = 0.04 + 0.12 * min(max(level, 0), 1)
        return (0..<max(points, 3)).map { index in
            let angle = 2 * .pi * Double(index) / Double(max(points, 3))
            let ripple = sin(angle * 3 + time * 2.1) * 0.6 + sin(angle * 5 - time * 1.3) * 0.4
            let radius = 1 + energy * ripple
            return (cos(angle) * radius, sin(angle) * radius)
        }
    }
}
