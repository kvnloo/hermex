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

    private(set) var router = LiveLaneRouter()
    private(set) var isAddingLane = false

    @ObservationIgnored private var laneModels: [Int: ChatViewModel] = [:]
    @ObservationIgnored private var laneBaselines: [Int: Set<String>] = [:]
    @ObservationIgnored private var laneThread: String?
    @ObservationIgnored private var addTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private weak var viewModel: ChatViewModel?
    @ObservationIgnored private let voice = ComposerVoiceInputController()
    @ObservationIgnored private let speaker = ForkLiveSpeaker()
    @ObservationIgnored private var draft = ""
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var replyBaselineID: String?
    @ObservationIgnored private var sentAt: Date?
    @ObservationIgnored private var watch: LiveReplyWatch?
    @ObservationIgnored private var recovering: Task<Void, Never>?
    @ObservationIgnored private var replyBaselineEnd: TranscriptTurnRunOutcome?
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
        let lane = router.selected
        guard let model = lane == LiveLaneRouter.root ? viewModel : laneModels[lane] else { return [] }
        let baseline = lane == LiveLaneRouter.root ? transcriptBaseline : laneBaselines[lane] ?? []
        return ForkLiveTranscriptSource.turns(in: model, excluding: baseline)
    }

    func belongs(to model: ChatViewModel) -> Bool { viewModel === model }

    var supportsLanes: Bool { viewModel?.supportsLiveLanes == true }

    var canAddLane: Bool {
        canChangeLane && router.canAttach && viewModel?.canBranchLiveLane == true
            && (laneModels.isEmpty || laneThread == viewModel?.liveLaneThread)
    }

    var canChangeLane: Bool { !isAddingLane && router.pending == nil }

    func selectLane(_ lane: Int) {
        guard canChangeLane, router.select(lane) else { return }
        resetListening()
    }

    func detachLane() {
        guard canChangeLane, let lane = router.detachSelected() else { return }
        laneModels.removeValue(forKey: lane)?.suspendStreamForNavigation()
        laneBaselines.removeValue(forKey: lane)
        resetListening()
    }

    func addLane() {
        guard canAddLane, let viewModel, let thread = viewModel.liveLaneThread else { return }
        resetListening()
        isAddingLane = true
        addTask = Task { [weak self] in
            do {
                let model = try await viewModel.makeLiveLane()
                try Task.checkCancellation()
                guard let self else { return }
                guard viewModel.liveLaneThread == thread else {
                    self.isAddingLane = false
                    return
                }
                guard let lane = self.router.attach() else {
                    self.isAddingLane = false
                    return
                }
                self.laneThread = thread
                self.laneModels[lane] = model
                self.laneBaselines[lane] = ForkLiveTranscriptSource.baseline(model)
                self.isAddingLane = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.isAddingLane = false
                self?.errorMessage = String(localized: "Couldn’t add a Live lane.", table: "Fork")
            }
        }
    }

    private func resetListening() {
        listenTask?.cancel()
        voice.stopBeforeSubmittingDraft()
        voice.dismissError()
        speaker.stop()
        machine = LiveModeMachine()
        errorMessage = nil
        draft = ""
        level = 0
    }

    private func clearChangedThread() {
        guard !laneModels.isEmpty, laneThread != viewModel?.liveLaneThread else { return }
        laneModels.values.forEach { $0.suspendStreamForNavigation() }
        laneModels.removeAll()
        laneBaselines.removeAll()
        router = LiveLaneRouter()
        laneThread = nil
    }

    func start() {
        guard ticker == nil else { return }
        clearChangedThread()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
        handle(.start)
    }

    func stop() {
        guard ticker != nil else { return }
        ticker?.cancel()
        ticker = nil
        recovering?.cancel()
        recovering = nil
        watch = nil
        isReconnecting = false
        addTask?.cancel()
        addTask = nil
        isAddingLane = false
        sendTask?.cancel()
        sendTask = nil
        if let pending = router.pending { _ = router.finish(pending) }
        sentAt = nil
        laneModels.values.forEach { $0.suspendStreamForNavigation() }
        resetListening()
        onClose?()
    }

    func tapOrb() {
        guard !isAddingLane else { return }
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
        if router.pending == nil, !laneModels.isEmpty, laneThread != viewModel?.liveLaneThread {
            clearChangedThread()
            resetListening()
        }
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
            voice.dismissError()
            listenTask?.cancel()
            listenTask = Task { [weak self] in
                try? await Task.sleep(for: Self.echoGuard)
                guard !Task.isCancelled else { return }
                self?.beginListening()
            }
        case .stopListening:
            listenTask?.cancel()
            voice.stopBeforeSubmittingDraft()
        case .send(let text):
            send(text)
        case .speak(let chunks):
            speaker.speak(chunks)
        case .stopSpeaking:
            speaker.stop()
        case .close:
            break
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
        guard laneModels.isEmpty || laneThread == viewModel?.liveLaneThread else {
            clearChangedThread()
            return handle(.sendRefused)
        }
        guard let turn = router.beginTurn() else { return handle(.sendRefused) }
        guard let model = model(for: turn) else {
            _ = router.finish(turn)
            return handle(.sendRefused)
        }
        sendTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            if turn.lane != LiveLaneRouter.root { await model.reconnectStreamIfNeeded() }
            guard let self, self.router.pending == turn, !Task.isCancelled else { return }
            guard model.activeStreamID == nil, !model.isStartingChat, model.pendingAttachments.isEmpty,
                  self.laneModels.isEmpty || self.laneThread == self.viewModel?.liveLaneThread else {
                self.finish(turn, event: .sendRefused)
                return
            }
            self.replyBaselineID = Self.latestAssistant(in: model)?.id
            self.replyBaselineEnd = model.latestRunOutcome
            self.sentAt = Date()
            self.watch = LiveReplyWatch(sentAt: self.now)
            let started = await model.sendMessage(text)
            guard self.router.pending == turn, !Task.isCancelled else { return }
            if started {
                self.handle(.sendAccepted)
            } else {
                self.errorMessage = model.sendErrorMessage
                self.finish(turn, event: .sendRefused)
            }
        }
    }

    private func model(for turn: LiveLaneRouter.Turn) -> ChatViewModel? {
        turn.lane == LiveLaneRouter.root ? viewModel : laneModels[turn.lane]
    }

    private func checkReply() {
        guard let turn = router.pending, let model = model(for: turn), let sentAt else { return }
        let age = Date().timeIntervalSince(sentAt)
        if !laneModels.isEmpty && laneThread != viewModel?.liveLaneThread {
            finish(turn, event: .replyFailed)
            return
        }
        if model.activeStreamID == nil {
            let reply = Self.latestAssistant(in: model).flatMap { $0.id != replyBaselineID ? $0.content : nil }
            if model.supportsLiveLanes {
                if let ending = model.latestRunOutcome, ending != replyBaselineEnd {
                    return finish(turn, event: ending.ending == .completed ? .replyFinished(reply ?? "") : .replyFailed)
                }
            } else if age > 0.8, let reply {
                return finish(turn, event: .replyFinished(reply))
            }
        }
        guard age > 0.8 else { return }
        watchConnection(model, turn: turn)
    }

    private func watchConnection(_ model: ChatViewModel, turn: LiveLaneRouter.Turn) {
        guard var watch else { return }
        let observation = LiveReplyWatch.Observation(
            hasStream: model.activeStreamID != nil,
            isConnected: !model.isActiveStreamConnectionSuspended && model.activeStreamRecoveryState == .idle
        )
        let action = watch.observe(observation, at: now)
        self.watch = watch
        if isReconnecting != watch.isReconnecting { isReconnecting = watch.isReconnecting }
        switch action {
        case .wait:
            break
        case .reconnect:
            recover {
                await model.reconnectStreamIfNeeded()
                await model.networkPathDidChange()
                await model.recoverStaleActiveStreamIfNeeded()
            }
        case .refresh:
            recover { await model.loadMessages() }
        case .fail:
            finish(turn, event: .replyFailed)
        }
    }

    private func recover(_ work: @escaping @MainActor () async -> Void) {
        guard recovering == nil else { return }
        recovering = Task { [weak self] in
            await work()
            self?.recovering = nil
        }
    }

    private func finish(_ turn: LiveLaneRouter.Turn, event: LiveEvent) {
        guard router.finish(turn) else { return }
        sentAt = nil
        watch = nil
        isReconnecting = false
        handle(event)
    }

    private static func latestAssistant(in viewModel: ChatViewModel) -> ChatMessage? {
        viewModel.messages.reversed().prefix { $0.role != "user" }
            .first { $0.role == "assistant" && !($0.content ?? "").isEmpty }
    }
}

@MainActor
final class ForkLiveSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var pending: Set<ObjectIdentifier> = []
    var onStarted: ((String) -> Void)?
    var onFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { !pending.isEmpty }

    func speak(_ chunks: [String]) {
        stop()
        for chunk in chunks {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
            pending.insert(ObjectIdentifier(utterance))
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        pending.removeAll()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [utterance] in
            withExtendedLifetime(utterance) {
                guard self.pending.contains(id) else { return }
                self.onStarted?(text)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [utterance] in
            withExtendedLifetime(utterance) {
                guard self.pending.remove(id) != nil, self.pending.isEmpty else { return }
                self.onFinished?()
            }
        }
    }
}
