import Foundation

enum ForkUpdateChannel: String, Equatable {
    case stable
    case preview
}

struct ForkRunningBuild: Equatable {
    var sha: String?
    var builtAt: Date?

    static let shaInfoKey = "HermexBuildSHA"
    static let timeInfoKey = "HermexBuildTime"

    static func parse(sha: String?, time: String?) -> ForkRunningBuild {
        ForkRunningBuild(sha: parseSHA(sha), builtAt: parseBuildTime(time))
    }

    static func fromInfo(_ info: [String: Any]?) -> ForkRunningBuild {
        parse(sha: info?[shaInfoKey] as? String, time: info?[timeInfoKey] as? String)
    }

    static func parseSHA(_ value: String?) -> String? {
        let candidate = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (7...64).contains(candidate.count), candidate.allSatisfy(\.isHexDigit) else { return nil }
        return candidate
    }

    static func parseBuildTime(_ value: String?) -> Date? {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed: Date?
        if raw.count == 10, raw.allSatisfy(\.isASCIIDigit), let seconds = Double(raw) {
            parsed = Date(timeIntervalSince1970: seconds)
        } else if raw.count == 13, raw.allSatisfy(\.isASCIIDigit), let millis = Double(raw) {
            parsed = Date(timeIntervalSince1970: millis / 1000)
        } else {
            parsed = ForkPreviewDates.instant(raw)
        }
        guard let parsed, parsed.timeIntervalSince1970 > 0 else { return nil }
        return parsed
    }
}

enum ForkPreviewDates {
    static func instant(_ raw: String) -> Date? {
        let zoned = raw.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#,
                              options: [.regularExpression, .caseInsensitive]) != nil
        guard zoned else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw.uppercased()) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw.uppercased())
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

struct ForkServedBuild: Equatable {
    let sha: String
    let runNumber: Int
    let builtAt: Date?
    let runURL: URL
}

enum ForkPreviewSource {
    static let owner = "kvnloo"
    static let repo = "hermex"
    static let workflow = "staging-ci.yml"
    static let branch = "staging"

    static var runsURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(owner)/\(repo)/actions/workflows/\(workflow)/runs"
        components.queryItems = [
            URLQueryItem(name: "branch", value: branch),
            URLQueryItem(name: "status", value: "success"),
            URLQueryItem(name: "per_page", value: "1"),
        ]
        return components.url!
    }

    static func servedBuild(from data: Data) -> ForkServedBuild? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any],
              let runs = payload["workflow_runs"] as? [Any] else { return nil }
        for case let run as [String: Any] in runs {
            if let build = servedBuild(run: run) { return build }
        }
        return nil
    }

    private static func servedBuild(run: [String: Any]) -> ForkServedBuild? {
        guard run["head_branch"] as? String == branch,
              run["status"] as? String == "completed",
              run["conclusion"] as? String == "success",
              let rawSHA = run["head_sha"] as? String, rawSHA.count == 40,
              let sha = ForkRunningBuild.parseSHA(rawSHA),
              let number = run["run_number"] as? Int, number > 0,
              let rawURL = run["html_url"] as? String,
              let url = actionsRunURL(rawURL) else { return nil }
        let builtAt = (run["updated_at"] as? String).flatMap(ForkPreviewDates.instant)
        return ForkServedBuild(sha: sha, runNumber: number, builtAt: builtAt, runURL: url)
    }

    static func actionsRunURL(_ raw: String) -> URL? {
        guard let components = URLComponents(string: raw),
              components.scheme == "https",
              components.host == "github.com",
              components.port == nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let segments = Array(components.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst())
        guard segments.count == 5,
              Array(segments.prefix(4)) == [Substring(owner), Substring(repo), "actions", "runs"],
              let id = segments.last, !id.isEmpty, id.allSatisfy(\.isASCIIDigit) else { return nil }
        return components.url
    }
}

enum ForkPreviewBuildState: Equatable {
    case checking
    case unreachable
    case unknown
    case current
    case newer
}

enum ForkPreviewLabel {
    static func shortSHA(_ sha: String?) -> String {
        guard let sha else { return "?" }
        return String(sha.prefix(7))
    }

    static func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "age unknown" }
        let age = now.timeIntervalSince(date)
        if age < -60 { return "clock skew" }
        if age < 60 { return "just served" }
        if age < 3_600 { return "\(Int(age / 60))m old" }
        if age < 86_400 { return "\(Int(age / 3_600))h old" }
        return "\(Int(age / 86_400))d old"
    }
}

struct ForkPreviewChannel: Equatable {
    static let channelKey = "fork.updateChannel.v1"
    static let servedKey = "fork.previewServedBuild.v1"
    static let minFetchInterval: TimeInterval = 60
    static let pollInterval: TimeInterval = 300

    let running: ForkRunningBuild
    private(set) var channel: ForkUpdateChannel = .stable
    private(set) var served: ForkServedBuild?
    private(set) var fetchFailed = false
    private(set) var lastFetch: Date?
    private var hiddenFor: String?

    init(running: ForkRunningBuild, storedChannel: String? = nil, cachedServed: Data? = nil) {
        self.running = running
        channel = storedChannel == ForkUpdateChannel.preview.rawValue ? .preview : .stable
        served = cachedServed.flatMap(ForkPreviewSource.servedBuild(from:))
    }

    var isPreview: Bool { channel == .preview }

    var state: ForkPreviewBuildState {
        guard let served else { return fetchFailed ? .unreachable : .checking }
        guard let sha = running.sha else { return .unknown }
        return served.sha.hasPrefix(sha) || sha.hasPrefix(served.sha) ? .current : .newer
    }

    func label(now: Date) -> String {
        let short = ForkPreviewLabel.shortSHA(running.sha)
        switch state {
        case .checking:
            return "\(short) · checking"
        case .unreachable:
            return "\(short) · served ?"
        case .unknown:
            return "served \(ForkPreviewLabel.shortSHA(served?.sha)) · \(ForkPreviewLabel.age(served?.builtAt, now: now))"
        case .current:
            return "\(short) · \(ForkPreviewLabel.age(running.builtAt ?? served?.builtAt, now: now))"
        case .newer:
            return "\(short) → \(ForkPreviewLabel.shortSHA(served?.sha))"
        }
    }

    private var hideKey: String { "\(running.sha ?? "-"):\(served?.sha ?? "-")" }

    var isChipVisible: Bool {
        isPreview && (state == .newer || hiddenFor != hideKey)
    }

    var openOnTap: URL? {
        state == .newer ? served?.runURL : nil
    }

    mutating func hide() {
        hiddenFor = hideKey
    }

    mutating func setChannel(_ newChannel: ForkUpdateChannel) -> Bool {
        guard channel != newChannel else { return false }
        channel = newChannel
        hiddenFor = nil
        return newChannel == .preview
    }

    func shouldFetch(now: Date, force: Bool) -> Bool {
        guard isPreview else { return false }
        guard !force, let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= Self.minFetchInterval
    }

    mutating func beginFetch(now: Date) {
        lastFetch = now
    }

    @discardableResult
    mutating func finishFetch(status: Int?, body: Data?) -> Data? {
        guard status == 200, let body, let build = ForkPreviewSource.servedBuild(from: body) else {
            fetchFailed = true
            return nil
        }
        fetchFailed = false
        served = build
        return body
    }
}
