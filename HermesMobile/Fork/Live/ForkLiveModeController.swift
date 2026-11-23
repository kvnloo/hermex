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
    private(set) var pendingAsk: LiveAsk?
    private(set) var answeringAskID: String?

    @ObservationIgnored private var laneModels: [Int: ChatViewModel] = [:]
    @ObservationIgnored private var laneBaselines: [Int: Set<String>] = [:]
    @ObservationIgnored private var laneThread: String?
    @ObservationIgnored private var addTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private weak var viewModel: ChatViewModel?
    @ObservationIgnored private let voice = ComposerVoiceInputController(mayRecord: { ForkLiveAudio.shared.mayRecord })
    @ObservationIgnored private var shownAskID: String?
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
    var onEnd: (() -> Void)?
    var onOpenAsk: ((URL?) -> Void)?
    var onChange: (() -> Void)?

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

    var isMinimized: Bool { machine.isMinimized }
    var isMuted: Bool { machine.isMuted }
    var hasUnseenCard: Bool { machine.hasUnseenCard }

    func minimize() { handle(.minimize) }
    func restore() { handle(.restore) }
    var isHearing: Bool { !machine.isMuted && ![.idle, .paused, .failed].contains(machine.phase) }

    func toggleMute() {
        if machine.isMuted {
            handle(.unmute)
        } else if isHearing {
            handle(.mute)
        } else {
            handle(.start)
        }
    }
    func pauseForInterruption() { handle(.pause) }
    func resumeAfterInterruption() { handle(.start) }

    func answer(_ command: LiveApprovalCommand) {
        guard let ask = pendingAsk, ask.offers.contains(command), answeringAskID == nil else { return }
        handle(.askHandled(ask.id))
        deliver(command, to: ask.id)
    }

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
        machine = machine.restartingConversation()
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
        shownAskID = nil
        pendingAsk = nil
        answeringAskID = nil
        resetListening()
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

    private func syncAsk() {
        let candidates = askingModels().compactMap { lane, model in
            Self.ask(in: model).map { LiveAskCandidate(ask: $0, lane: lane) }
        }
        let ask = LiveAskRoute.pick(candidates, callLanes: router.lanes, selectedLane: router.selected)
        if shownAskID != ask?.id {
            if let shownAskID { handle(.askClosed(shownAskID)) }
            shownAskID = ask?.id
        }
        if pendingAsk != ask { pendingAsk = ask }
        if let ask { handle(.askOpened(ask)) }
    }

    private func askingModels() -> [(Int, ChatViewModel)] {
        var models: [(Int, ChatViewModel)] = []
        if let viewModel { models.append((LiveLaneRouter.root, viewModel)) }
        for lane in router.lanes where lane != LiveLaneRouter.root {
            if let model = laneModels[lane] { models.append((lane, model)) }
        }
        return models
    }

    private func model(asking id: String) -> ChatViewModel? {
        askingModels().first { Self.ask(in: $0.1)?.id == id }?.1
    }

    private func deliver(_ command: LiveApprovalCommand, to id: String) {
        guard let model = model(asking: id) else { return }
        guard command != .open else {
            onOpenAsk?(model.liveCallLink)
            return
        }
        answeringAskID = id
        Task { [weak self] in
            let answered = await Self.respond(command, in: model, to: id)
            guard let self, self.answeringAskID == id else { return }
            self.answeringAskID = nil
            guard !answered else { return }
            self.errorMessage = String(localized: "Couldn’t send your answer. Try again.", table: "Fork")
            self.handle(.askClosed(id))
        }
    }

    private static func respond(_ command: LiveApprovalCommand, in model: ChatViewModel, to id: String) async -> Bool {
        if let requests = model.hermesRequests {
            guard case .approval(let approval)? = requests.onScreen, approval.requestID == id,
                  let action = requests.prepareAnswer() else { return false }
            return await requests.respond(action, choice: command == .allow ? .once : .deny)
        }
        guard model.approvalPrompt?.id == id else { return false }
        return await model.respondToApproval(command == .allow ? .once : .deny)
    }

    static func ask(in model: ChatViewModel) -> LiveAsk? {
        if let requests = model.hermesRequests {
            switch requests.onScreen {
            case .approval(let approval)?:
                return .approval(id: approval.requestID,
                                 summary: approval.consequence ?? approval.command ?? approval.toolName ?? "",
                                 allowsOnce: approval.choices.contains(.once), allowsDeny: approval.choices.contains(.deny))
            case .question(let question)?:
                return .question(id: question.requestID, summary: question.questions.first?.prompt ?? "")
            case .credential(let credential)?:
                return .question(id: credential.requestID, summary: credential.title)
            case .connection(let operation)?:
                return .question(id: operation.opID, summary: "")
            case .desktopTask?, nil:
                return nil
            }
        }
        if let prompt = model.approvalPrompt {
            return .approval(id: prompt.id, summary: prompt.pending.description ?? prompt.pending.command ?? "",
                             allowsOnce: true, allowsDeny: true)
        }
        if let prompt = model.clarificationPrompt { return .question(id: prompt.id, summary: prompt.question) }
        return nil
    }

    static func spokenPrompt(_ ask: LiveAsk, again: Bool) -> String {
        switch (ask.kind, ask.offers.contains(.allow), again) {
        case (.approval, true, false):
            String(localized: "Hermes needs your OK. Say allow, deny, or open it.", table: "Fork")
        case (.approval, true, true):
            String(localized: "Sorry, I didn’t catch that. Say allow, deny, or open it.", table: "Fork")
        case (.approval, false, false):
            String(localized: "Hermes needs your OK. Say deny, or open it to choose.", table: "Fork")
        case (.approval, false, true):
            String(localized: "Sorry, I didn’t catch that. Say deny, or open it.", table: "Fork")
        case (.question, _, false):
            String(localized: "Hermes has a question. Say open it to answer.", table: "Fork")
        case (.question, _, true):
            String(localized: "Sorry, I didn’t catch that. Say open it to answer.", table: "Fork")
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
        syncAsk()
        if machine.phase == .thinking { checkReply() }
        if router.pending == nil, !laneModels.isEmpty, laneThread != viewModel?.liveLaneThread {
            clearChangedThread()
            resetListening()
        }
        handle(.tick)
        onChange?()
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
            onEnd?()
        case .announceAsk(let ask):
            speaker.speak([Self.spokenPrompt(ask, again: false)])
        case .askAgain(let ask):
            speaker.speak([Self.spokenPrompt(ask, again: true)])
        case .answerAsk(let id, let command):
            deliver(command, to: id)
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
