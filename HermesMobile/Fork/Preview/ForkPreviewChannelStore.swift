import Foundation
import Observation

@MainActor @Observable
final class ForkPreviewChannelStore {
    static let shared = ForkPreviewChannelStore()

    private(set) var model: ForkPreviewChannel
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, session: URLSession = .shared,
         running: ForkRunningBuild = .fromInfo(Bundle.main.infoDictionary)) {
        self.defaults = defaults
        self.session = session
        model = ForkPreviewChannel(running: running,
                                   storedChannel: defaults.string(forKey: ForkPreviewChannel.channelKey),
                                   cachedServed: defaults.data(forKey: ForkPreviewChannel.servedKey))
    }

    var isPreview: Bool { model.isPreview }

    func setPreview(_ isOn: Bool) {
        let channel: ForkUpdateChannel = isOn ? .preview : .stable
        defaults.set(channel.rawValue, forKey: ForkPreviewChannel.channelKey)
        if model.setChannel(channel) { refresh(force: true) }
    }

    func hide() {
        model.hide()
    }

    func refresh(force: Bool = false) {
        let now = Date()
        guard inFlight == nil, model.shouldFetch(now: now, force: force) else { return }
        model.beginFetch(now: now)
        var request = URLRequest(url: ForkPreviewSource.runsURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        inFlight = Task { [weak self, session] in
            let result = try? await session.data(for: request)
            guard let self else { return }
            let status = (result?.1 as? HTTPURLResponse)?.statusCode
            if let body = model.finishFetch(status: status, body: result?.0) {
                defaults.set(body, forKey: ForkPreviewChannel.servedKey)
            }
            inFlight = nil
        }
    }
}
