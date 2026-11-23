import ActivityKit
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ForkLiveSession {
    static let shared = ForkLiveSession()

    private(set) var room = LiveCallRoom()
    private(set) var controller: ForkLiveModeController?
    private(set) var title = ""
    @ObservationIgnored private var model: ChatViewModel?
    @ObservationIgnored private var requester: (model: ChatViewModel, title: String)?
    @ObservationIgnored private var leftChat = false
    @ObservationIgnored private let activity = ForkLiveCallActivityController()
    @ObservationIgnored var openLink: ((URL) -> Void)?

    init() {
        ForkLiveCallCommands.handler = { [weak self] command, callID in
            self?.activityCommand(command, callID: callID)
        }
        ForkLiveAudio.shared.onInterrupted = { [weak self] in self?.controller?.pauseForInterruption() }
        ForkLiveAudio.shared.onResumed = { [weak self] in self?.controller?.resumeAfterInterruption() }
        activity.endAll(except: nil)
    }

    var isRunning: Bool { controller != nil }
    var isFullScreen: Bool { controller.map { !$0.isMinimized } ?? false }
    var showsBar: Bool { controller?.isMinimized == true }

    func holds(_ model: ChatViewModel) -> Bool { self.model === model }

    func adoptsLeavingChat(_ model: ChatViewModel) -> Bool {
        guard holds(model) else { return false }
        leftChat = true
        return true
    }

    func chatAppeared(_ model: ChatViewModel) {
        if holds(model) { leftChat = false }
    }

    func isAskingToSwitch(from model: ChatViewModel) -> Bool {
        room.switchPrompt != nil && requester?.model === model
    }

    func requestStart(_ model: ChatViewModel, title: String) {
        guard !model.isViewingCachedData else { return }
        requester = (model, title)
        apply(room.requestStart(key(for: model)))
        if room.switchPrompt == nil { requester = nil }
    }

    func resolveSwitch(_ switching: Bool) {
        apply(room.resolveSwitch(switching: switching))
        requester = nil
    }

    func minimize() { apply(room.dismiss()) }
    func restore() { apply(room.present()) }
    func end(_ reason: LiveCallEnd) { apply(room.end(reason)) }
    func toggleMute() {
        controller?.toggleMute()
        syncActivity()
    }

    func answer(_ command: LiveApprovalCommand) {
        controller?.answer(command)
    }

    private func key(for model: ChatViewModel) -> String {
        if let current = self.model, let chat = room.chat {
            if current === model { return chat }
            if let key = model.liveCallKey, key == current.liveCallKey { return chat }
        }
        return model.liveCallKey ?? "model-\(UInt(bitPattern: ObjectIdentifier(model).hashValue))"
    }

    private func activityCommand(_ command: ForkLiveCallCommand, callID: String) {
        let mapped: LiveActivityCommand = command == .end ? .end : .returnToCall
        let actions = room.activity(mapped, callID: callID)
        if actions.isEmpty { activity.endAll(except: room.callID) }
        apply(actions)
    }

    private func apply(_ actions: [LiveCallAction]) {
        for action in actions {
            switch action {
            case .begin:
                begin()
            case .restore:
                controller?.restore()
            case .minimize:
                controller?.minimize()
            case .end:
                tearDown()
            }
        }
        syncActivity()
    }

    private func begin() {
        guard let requester else { return }
        self.requester = nil
        let controller = ForkLiveModeController(viewModel: requester.model)
        controller.onEnd = { [weak self] in self?.end(.limit) }
        controller.onOpenAsk = { [weak self] link in self?.openAsk(link) }
        controller.onChange = { [weak self] in self?.syncActivity() }
        model = requester.model
        title = requester.title
        leftChat = false
        self.controller = controller
        ForkLiveAudio.shared.hold()
        controller.start()
        if let callID = room.callID { activity.start(callID: callID, title: requester.title) }
    }

    private func openAsk(_ link: URL?) {
        controller?.minimize()
        if let link { openLink?(link) }
        syncActivity()
    }

    private func tearDown() {
        guard let controller, let model else { return }
        controller.onEnd = nil
        controller.onOpenAsk = nil
        controller.onChange = nil
        controller.stop()
        self.controller = nil
        self.model = nil
        ForkLiveAudio.shared.release()
        activity.end()
        if leftChat {
            model.suspendStreamForNavigation()
            model.cleanupPollingTasks()
        }
        leftChat = false
        if UIApplication.shared.applicationState == .background {
            if model.supportsLiveLanes { model.suspendStreamForBackground() }
            HermesConnections.shared.closeForBackground()
        }
    }

    private func syncActivity() {
        guard let controller else { return }
        activity.update(ForkLiveCallAttributes.ContentState(
            status: Self.status(controller.phase),
            isMuted: controller.isMuted,
            needsAnswer: controller.pendingAsk != nil,
            hasUnseenCard: controller.hasUnseenCard
        ))
    }

    private static func status(_ phase: LivePhase) -> ForkLiveCallAttributes.Status {
        switch phase {
        case .listening: .listening
        case .sending, .thinking: .thinking
        case .speaking: .speaking
        case .idle, .paused: .paused
        case .failed: .failed
        }
    }
}

@MainActor
final class ForkLiveCallActivityController {
    private var current: Activity<ForkLiveCallAttributes>?
    private var lastState: ForkLiveCallAttributes.ContentState?

    func start(callID: String, title: String) {
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = ForkLiveCallAttributes.ContentState(status: .listening, isMuted: false, needsAnswer: false, hasUnseenCard: false)
        current = try? Activity.request(
            attributes: ForkLiveCallAttributes(callID: callID, title: title),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        lastState = state
    }

    func update(_ state: ForkLiveCallAttributes.ContentState) {
        guard let current, state != lastState else { return }
        lastState = state
        Task { await current.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let current else { return }
        self.current = nil
        lastState = nil
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }

    func endAll(except callID: String?) {
        for activity in Activity<ForkLiveCallAttributes>.activities where activity.attributes.callID != callID {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
