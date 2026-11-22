import Foundation
import Observation

@MainActor
@Observable
final class ForkCouncilController {
    let run: CouncilRun
    let live: Bool
    private(set) var reader: CouncilReader
    private(set) var now: Double = 0
    private(set) var caption = ""

    @ObservationIgnored private let speaker = ForkLiveSpeaker()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let origin = Date()

    private static let tick = Duration.milliseconds(110)

    init(run: CouncilRun, live: Bool, reduceMotion: Bool) {
        self.run = run
        self.live = live
        reader = CouncilReader(run: run, reduceMotion: reduceMotion)
        speaker.onStarted = { [weak self] text in self?.caption = text }
        speaker.onFinished = { [weak self] in self?.handle(.readingFinished) }
    }

    var exchange: CouncilExchange {
        CouncilExchange(run: run, timing: reader.timing, elapsed: reader.elapsed(at: now))
    }

    func handle(_ event: CouncilReaderEvent) {
        now = Date().timeIntervalSince(origin)
        for effect in reader.handle(event, at: now) { perform(effect) }
    }

    private func perform(_ effect: CouncilReaderEffect) {
        switch effect {
        case .startClock:
            ticker?.cancel()
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.tick)
                    guard let self, !Task.isCancelled else { return }
                    self.handle(.tick)
                }
            }
        case .stopClock:
            ticker?.cancel()
            ticker = nil
        case .read(let reading):
            let chunks = LiveSpeechText.chunks(ForkCouncilCopy.speech(reading, run: run))
            caption = chunks.first ?? ""
            if chunks.isEmpty { return handle(.readingFinished) }
            speaker.speak(chunks)
        case .stopSpeaking:
            speaker.stop()
            caption = ""
        }
    }
}
