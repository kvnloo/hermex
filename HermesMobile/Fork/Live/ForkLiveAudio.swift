import AVFoundation
import UIKit

@MainActor
final class ForkLiveAudio {
    static let shared = ForkLiveAudio()

    private(set) var isHeld = false
    private var engine: AVAudioEngine?
    private var observers: [NSObjectProtocol] = []
    private var engineObserver: NSObjectProtocol?
    var onInterrupted: (() -> Void)?
    var onResumed: (() -> Void)?

    var mayRecord: Bool {
        guard !AppLock.shared.isLocked else { return false }
        return isHeld || UIApplication.shared.applicationState == .active
    }

    func hold() {
        guard !isHeld else { return }
        isHeld = true
        activate()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:))
                MainActor.assumeIsolated { self?.interrupted(type, resumes: options?.contains(.shouldResume) == true) }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                MainActor.assumeIsolated { self?.routeChanged(reason) }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartEngine() }
            },
        ]
    }

    func release() {
        guard isHeld else { return }
        isHeld = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        stopEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            ComposerVoiceAudioSessionConfiguration.category,
            mode: ComposerVoiceAudioSessionConfiguration.mode,
            options: ComposerVoiceAudioSessionConfiguration.options
        )
        try? session.setActive(true)
        restartEngine()
    }

    private func restartEngine() {
        guard isHeld else { return }
        stopEngine()
        let engine = AVAudioEngine()
        _ = engine.mainMixerNode
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        self.engine = engine
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartEngine() }
        }
    }

    private func stopEngine() {
        if let engineObserver { NotificationCenter.default.removeObserver(engineObserver) }
        engineObserver = nil
        engine?.stop()
        engine = nil
    }

    private func interrupted(_ type: AVAudioSession.InterruptionType?, resumes: Bool) {
        guard isHeld else { return }
        switch type {
        case .began?:
            stopEngine()
            onInterrupted?()
        case .ended?:
            activate()
            if resumes { onResumed?() }
        default:
            break
        }
    }

    private func routeChanged(_ reason: AVAudioSession.RouteChangeReason?) {
        guard isHeld, reason == .oldDeviceUnavailable else { return }
        onInterrupted?()
    }
}
