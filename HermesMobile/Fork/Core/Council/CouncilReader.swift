import Foundation

enum CouncilReading: Equatable, Sendable {
    case brief
    case report
}

enum CouncilReaderEvent: Equatable, Sendable {
    case convene
    case toggleReadAloud
    case toggleMute
    case tick
    case returnToCard
    case readingFinished
    case close
}

enum CouncilReaderEffect: Equatable, Sendable {
    case startClock
    case stopClock
    case read(CouncilReading)
    case stopSpeaking
}

struct CouncilReader: Equatable, Sendable {
    private struct Hold: Equatable, Sendable {
        let elapsed: Double
        let since: Double
    }

    let timing: CouncilTiming
    let reduceMotion: Bool
    private(set) var startedAt: Double?
    private(set) var clockRunning = false
    private(set) var readAloud = false
    private(set) var muted = false
    private(set) var reading: CouncilReading?
    private var held: Hold?
    private var briefRead = false
    private var reportRead = false

    init(run: CouncilRun, reduceMotion: Bool) {
        timing = CouncilTiming(run: run, reduceMotion: reduceMotion)
        self.reduceMotion = reduceMotion
    }

    func elapsed(at now: Double) -> Double? {
        guard let startedAt else { return nil }
        return held?.elapsed ?? min(timing.total, max(0, now - startedAt))
    }

    var canConvene: Bool { !clockRunning }

    mutating func handle(_ event: CouncilReaderEvent, at now: Double) -> [CouncilReaderEffect] {
        var effects: [CouncilReaderEffect] = []
        switch event {
        case .convene:
            guard !clockRunning else { return [] }
            returnToCard(at: now, into: &effects)
            briefRead = false
            reportRead = false
            startedAt = now
            clockRunning = true
            effects.append(.startClock)
            if reduceMotion, readAloud, !muted {
                briefRead = true
                read(.brief, at: now, into: &effects)
            }
        case .toggleReadAloud:
            readAloud.toggle()
            if !readAloud {
                returnToCard(at: now, into: &effects)
            } else if startedAt != nil {
                reportRead = false
                if !clockRunning {
                    clockRunning = true
                    effects.append(.startClock)
                }
                tick(at: now, into: &effects)
            }
        case .toggleMute:
            muted.toggle()
            if muted { returnToCard(at: now, into: &effects) }
        case .tick:
            tick(at: now, into: &effects)
        case .returnToCard:
            returnToCard(at: now, into: &effects)
        case .readingFinished:
            guard reading != nil else { return [] }
            reading = nil
            release(at: now)
        case .close:
            returnToCard(at: now, into: &effects)
            if clockRunning {
                clockRunning = false
                effects.append(.stopClock)
            }
        }
        return effects
    }

    private mutating func tick(at now: Double, into effects: inout [CouncilReaderEffect]) {
        guard let t = elapsed(at: now) else { return }
        if readAloud, !muted, reading == nil {
            if !briefRead, t >= timing.typing, t < timing.working {
                briefRead = true
                read(.brief, at: now, into: &effects)
            } else if !reportRead, t >= timing.total {
                reportRead = true
                read(.report, at: now, into: &effects)
            }
        }
        if clockRunning, reading == nil, t >= timing.total {
            clockRunning = false
            effects.append(.stopClock)
        }
    }

    private mutating func read(_ kind: CouncilReading, at now: Double, into effects: inout [CouncilReaderEffect]) {
        returnToCard(at: now, into: &effects)
        reading = kind
        held = Hold(elapsed: elapsed(at: now) ?? 0, since: now)
        effects.append(.read(kind))
    }

    private mutating func returnToCard(at now: Double, into effects: inout [CouncilReaderEffect]) {
        if reading != nil {
            reading = nil
            effects.append(.stopSpeaking)
        }
        release(at: now)
    }

    private mutating func release(at now: Double) {
        if let held, let startedAt { self.startedAt = startedAt + (now - held.since) }
        held = nil
    }
}
