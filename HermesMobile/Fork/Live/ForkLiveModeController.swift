import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class ForkLiveModeController {
    private(set) var machine = LiveModeMachine()
    private(set) var level: Double = 0
    private(set) var errorMessage: String?
    private(set) var isReconnecting = false

    @ObservationIgnored private weak var viewModel: ChatViewModel?
    @ObservationIgnored private let voice = ComposerVoiceInputController()
    @ObservationIgnored private let speaker = ForkLiveSpeaker()
    @ObservationIgnored private var draft = ""
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var replyBaselineID: String?
    @ObservationIgnored private var sentAt: Date?
    @ObservationIgnored private var watch: LiveReplyWatch?
    @ObservationIgnored private var recovering: Task<Void, Never>?
    @ObservationIgnored private let clock = Date()
    @ObservationIgnored private let transcriptBaseline: Set<String>
    var onClose: (() -> Void)?

    private static let echoGuard = Duration.milliseconds(300)

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        transcriptBaseline = ForkLiveTranscriptSource.baseline(viewModel)
        speaker.onFinished = { [weak self] in self?.handle(.speechFinished) }
    }

    var phase: LivePhase { machine.phase }
    var heard: String { machine.heard }
    var transcript: [LiveTurn<ToolCall>] {
        guard let viewModel else { return [] }
        return ForkLiveTranscriptSource.turns(in: viewModel, excluding: transcriptBaseline)
    }

    func start() {
        guard ticker == nil else { return handle(.start) }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.tick()
            }
        }
        handle(.start)
    }

    func stop() {
        handle(.stop)
        ticker?.cancel()
        ticker = nil
        recovering?.cancel()
        recovering = nil
        watch = nil
        isReconnecting = false
    }

    func tapOrb() {
        switch machine.phase {
        case .speaking: handle(.bargeIn)
        case .listening: handle(.pause)
        case .idle, .paused, .failed: handle(.start)
        case .sending, .thinking: break
        }
    }

    private var now: Double { Date().timeIntervalSince(clock) }

    private func tick() {
        let raw = Double(voice.levelMeter.levels.last ?? 0)
        level = LiveOrbGeometry.smoothed(previous: level, level: voice.isListening ? raw : 0)
        if let message = voice.errorMessage, errorMessage != message {
            errorMessage = message
            handle(.pause)
        }
        if machine.phase == .thinking { checkReply() }
        handle(.tick)
    }

    private func handle(_ event: LiveEvent) {
        for effect in machine.handle(event, at: now) { perform(effect) }
    }

    private func perform(_ effect: LiveEffect) {
        switch effect {
        case .startListening:
            draft = ""
            errorMessage = nil
            Task { [weak self] in
                try? await Task.sleep(for: Self.echoGuard)
                self?.beginListening()
            }
        case .stopListening:
            if voice.isListening { voice.stopBeforeSubmittingDraft() }
        case .send(let text):
            send(text)
        case .speak(let chunks):
            speaker.speak(chunks)
        case .stopSpeaking:
            speaker.stop()
        case .close:
            if voice.isListening { voice.stopBeforeSubmittingDraft() }
            speaker.stop()
            onClose?()
        }
    }

    private func beginListening() {
        guard machine.phase == .listening, !voice.isListening else { return }
        voice.scheduleToggle(
            draftState: { [weak self] in
                let text = self?.draft ?? ""
                return ComposerVoiceDraftState(text: text, selection: ComposerSelection(range: NSRange(location: (text as NSString).length, length: 0)))
            },
            updateDraft: { [weak self] update in
                guard let self else { return }
                self.draft = update.text
                self.handle(.heard(update.text))
            }
        )
    }

    private func send(_ text: String) {
        guard let viewModel else { return handle(.sendRefused) }
        replyBaselineID = Self.latestAssistant(in: viewModel)?.id
        sentAt = Date()
        watch = LiveReplyWatch(sentAt: now)
        Task { [weak self] in
            let started = await viewModel.sendMessage(text)
            self?.handle(started ? .sendAccepted : .sendRefused)
        }
    }

    private func checkReply() {
        guard let viewModel, let sentAt else { return }
        if viewModel.activeStreamID == nil, Date().timeIntervalSince(sentAt) > 0.8,
           let reply = Self.latestAssistant(in: viewModel), reply.id != replyBaselineID {
            self.sentAt = nil
            watch = nil
            isReconnecting = false
            return handle(.replyFinished(reply.content ?? ""))
        }
        guard Date().timeIntervalSince(sentAt) > 0.8 else { return }
        watchConnection(viewModel)
    }

    private func watchConnection(_ viewModel: ChatViewModel) {
        guard var watch else { return }
        let observation = LiveReplyWatch.Observation(
            hasStream: viewModel.activeStreamID != nil,
            isConnected: !viewModel.isActiveStreamConnectionSuspended && viewModel.activeStreamRecoveryState == .idle
        )
        let action = watch.observe(observation, at: now)
        self.watch = watch
        if isReconnecting != watch.isReconnecting { isReconnecting = watch.isReconnecting }
        switch action {
        case .wait:
            break
        case .reconnect:
            recover {
                await viewModel.reconnectStreamIfNeeded()
                await viewModel.networkPathDidChange()
                await viewModel.recoverStaleActiveStreamIfNeeded()
            }
        case .refresh:
            recover { await viewModel.loadMessages() }
        case .fail:
            self.watch = nil
            sentAt = nil
            isReconnecting = false
            handle(.replyFailed)
        }
    }

    private func recover(_ work: @escaping @MainActor () async -> Void) {
        guard recovering == nil else { return }
        recovering = Task { [weak self] in
            await work()
            self?.recovering = nil
        }
    }

    private static func latestAssistant(in viewModel: ChatViewModel) -> ChatMessage? {
        viewModel.messages.last { $0.role == "assistant" && !($0.content ?? "").isEmpty }
    }
}

@MainActor
final class ForkLiveSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var pending = 0
    var onFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { pending > 0 }

    func speak(_ chunks: [String]) {
        stop()
        pending = chunks.count
        for chunk in chunks {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        pending = 0
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.pending > 0 else { return }
            self.pending -= 1
            if self.pending == 0 { self.onFinished?() }
        }
    }
}
