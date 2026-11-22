import Foundation

enum ForkDeviceSource: String, CaseIterable, Sendable {
    case health, calendar, contacts, location, alarm
}

enum ForkDeviceTool: String, CaseIterable, Sendable {
    case healthSteps = "device.health.steps"
    case calendarEvents = "device.calendar.events"
    case contactsFind = "device.contacts.find"
    case locationApproximate = "device.location.approximate"
    case alarmSet = "device.alarm.set"

    var source: ForkDeviceSource {
        switch self {
        case .healthSteps: .health
        case .calendarEvents: .calendar
        case .contactsFind: .contacts
        case .locationApproximate: .location
        case .alarmSet: .alarm
        }
    }
}

enum ForkDeviceErrorCode: String, Codable, CaseIterable, Error, Sendable {
    case disabled
    case permissionDenied = "permission_denied"
    case unavailable
    case invalidArguments = "invalid_arguments"
    case userDenied = "user_denied"
    case cancelled
    case busy
    case notForeground = "not_foreground"
}

enum ForkDeviceLimits {
    static let day: Int64 = 86_400_000
    static let week: Int64 = 604_800_000
    static let maximumParamsBytes = 4096
    static let calendarEvents = 25
    static let calendarTitle = 200
    static let contactNames = 10
    static let contactName = 120
    static let contactQuery = 2...80
    static let fixAge: Int64 = 300_000
    static let alarmLead: Int64 = 10_000
}

enum ForkDeviceTime {
    static func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded(.down)) }
    static func date(_ milliseconds: Int64) -> Date { Date(timeIntervalSince1970: Double(milliseconds) / 1000) }
}

struct ForkDeviceArgumentKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Decoder {
    func deviceArguments(exactly keys: Set<String>) throws -> KeyedDecodingContainer<ForkDeviceArgumentKey> {
        let container = try container(keyedBy: ForkDeviceArgumentKey.self)
        guard Set(container.allKeys.map(\.stringValue)) == keys else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Unexpected device tool arguments"))
        }
        return container
    }
}

struct ForkHealthStepsRequest: Codable, Equatable, Sendable {
    init() {}
    init(from decoder: Decoder) throws { _ = try decoder.deviceArguments(exactly: []) }
    func encode(to encoder: Encoder) throws { _ = encoder.container(keyedBy: ForkDeviceArgumentKey.self) }
}

struct ForkHealthStepsResult: Codable, Equatable, Sendable {
    let steps: Int64?

    private enum CodingKeys: String, CodingKey { case steps }

    init(steps: Int64?) { self.steps = steps }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
    }
}

struct ForkCalendarEventsRequest: Codable, Equatable, Sendable {
    let startMs: Int64
    let endMs: Int64

    init(startMs: Int64, endMs: Int64) {
        self.startMs = startMs
        self.endMs = endMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.deviceArguments(exactly: ["startMs", "endMs"])
        startMs = try container.decode(Int64.self, forKey: .init("startMs"))
        endMs = try container.decode(Int64.self, forKey: .init("endMs"))
    }

    func isValid(nowMs: Int64) -> Bool {
        (nowMs - ForkDeviceLimits.week...nowMs + 4 * ForkDeviceLimits.week).contains(startMs)
            && endMs > startMs && endMs - startMs <= ForkDeviceLimits.week
    }
}

struct ForkCalendarEvent: Codable, Equatable, Sendable {
    let title: String
    let startMs: Int64
    let endMs: Int64
}

struct ForkCalendarEventsResult: Codable, Equatable, Sendable {
    let events: [ForkCalendarEvent]

    init(events: [ForkCalendarEvent]) { self.events = events }

    init(clamping events: [ForkCalendarEvent]) {
        self.events = events.prefix(ForkDeviceLimits.calendarEvents).map {
            ForkCalendarEvent(title: String($0.title.prefix(ForkDeviceLimits.calendarTitle)), startMs: $0.startMs, endMs: $0.endMs)
        }
    }
}

struct ForkContactsFindRequest: Codable, Equatable, Sendable {
    let name: String

    init(name: String) { self.name = name }

    init(from decoder: Decoder) throws {
        let container = try decoder.deviceArguments(exactly: ["name"])
        name = try container.decode(String.self, forKey: .init("name"))
    }

    var query: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isValid: Bool { ForkDeviceLimits.contactQuery.contains(query.count) }
}

struct ForkContactsFindResult: Codable, Equatable, Sendable {
    let names: [String]

    init(names: [String]) { self.names = names }

    init(clamping names: [String]) {
        self.names = names.prefix(ForkDeviceLimits.contactNames).map { String($0.prefix(ForkDeviceLimits.contactName)) }
    }
}

struct ForkLocationApproximateRequest: Codable, Equatable, Sendable {
    init() {}
    init(from decoder: Decoder) throws { _ = try decoder.deviceArguments(exactly: []) }
    func encode(to encoder: Encoder) throws { _ = encoder.container(keyedBy: ForkDeviceArgumentKey.self) }
}

struct ForkDeviceFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let timeMs: Int64
}

struct ForkLocationApproximateResult: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let timeMs: Int64

    init(latitude: Double, longitude: Double, timeMs: Int64) {
        self.latitude = latitude
        self.longitude = longitude
        self.timeMs = timeMs
    }

    init?(coarsening fix: ForkDeviceFix, nowMs: Int64) {
        guard (0...ForkDeviceLimits.fixAge).contains(nowMs - fix.timeMs),
              fix.latitude.isFinite, fix.longitude.isFinite else { return nil }
        self.init(latitude: Self.coarse(fix.latitude), longitude: Self.coarse(fix.longitude), timeMs: fix.timeMs)
    }

    static func coarse(_ coordinate: Double) -> Double { (coordinate * 100).rounded() / 100 }
}

struct ForkAlarmSetRequest: Codable, Equatable, Sendable {
    let atMs: Int64

    init(atMs: Int64) { self.atMs = atMs }

    init(from decoder: Decoder) throws {
        let container = try decoder.deviceArguments(exactly: ["atMs"])
        atMs = try container.decode(Int64.self, forKey: .init("atMs"))
    }

    func isValid(nowMs: Int64) -> Bool {
        (nowMs + ForkDeviceLimits.alarmLead...nowMs + ForkDeviceLimits.week).contains(atMs)
    }
}

struct ForkAlarmSetResult: Codable, Equatable, Sendable {
    let atMs: Int64
}

enum ForkDeviceToolRequest: Equatable, Sendable {
    case healthSteps(ForkHealthStepsRequest)
    case calendarEvents(ForkCalendarEventsRequest)
    case contactsFind(ForkContactsFindRequest)
    case locationApproximate(ForkLocationApproximateRequest)
    case alarmSet(ForkAlarmSetRequest)

    var tool: ForkDeviceTool {
        switch self {
        case .healthSteps: .healthSteps
        case .calendarEvents: .calendarEvents
        case .contactsFind: .contactsFind
        case .locationApproximate: .locationApproximate
        case .alarmSet: .alarmSet
        }
    }

    func isValid(nowMs: Int64) -> Bool {
        switch self {
        case .healthSteps, .locationApproximate: true
        case .calendarEvents(let request): request.isValid(nowMs: nowMs)
        case .contactsFind(let request): request.isValid
        case .alarmSet(let request): request.isValid(nowMs: nowMs)
        }
    }
}

struct ForkDeviceToolCall: Codable, Equatable, Sendable {
    let sessionID: String
    let request: ForkDeviceToolRequest

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case tool, args
    }

    init(sessionID: String, request: ForkDeviceToolRequest) {
        self.sessionID = sessionID
        self.request = request
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        let name = try container.decode(String.self, forKey: .tool)
        guard let tool = ForkDeviceTool(rawValue: name) else {
            throw DecodingError.dataCorruptedError(forKey: .tool, in: container, debugDescription: "Unknown device tool")
        }
        switch tool {
        case .healthSteps: request = .healthSteps(try container.decode(ForkHealthStepsRequest.self, forKey: .args))
        case .calendarEvents: request = .calendarEvents(try container.decode(ForkCalendarEventsRequest.self, forKey: .args))
        case .contactsFind: request = .contactsFind(try container.decode(ForkContactsFindRequest.self, forKey: .args))
        case .locationApproximate: request = .locationApproximate(try container.decode(ForkLocationApproximateRequest.self, forKey: .args))
        case .alarmSet: request = .alarmSet(try container.decode(ForkAlarmSetRequest.self, forKey: .args))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(request.tool.rawValue, forKey: .tool)
        switch request {
        case .healthSteps(let args): try container.encode(args, forKey: .args)
        case .calendarEvents(let args): try container.encode(args, forKey: .args)
        case .contactsFind(let args): try container.encode(args, forKey: .args)
        case .locationApproximate(let args): try container.encode(args, forKey: .args)
        case .alarmSet(let args): try container.encode(args, forKey: .args)
        }
    }

    static func decode(_ params: Data) -> Result<ForkDeviceToolCall, ForkDeviceErrorCode> {
        guard params.count <= ForkDeviceLimits.maximumParamsBytes,
              let call = try? JSONDecoder().decode(ForkDeviceToolCall.self, from: params) else {
            return .failure(.invalidArguments)
        }
        return .success(call)
    }
}

enum ForkDeviceToolOutput: Equatable, Sendable {
    case healthSteps(ForkHealthStepsResult)
    case calendarEvents(ForkCalendarEventsResult)
    case contactsFind(ForkContactsFindResult)
    case locationApproximate(ForkLocationApproximateResult)
    case alarmSet(ForkAlarmSetResult)

    var tool: ForkDeviceTool {
        switch self {
        case .healthSteps: .healthSteps
        case .calendarEvents: .calendarEvents
        case .contactsFind: .contactsFind
        case .locationApproximate: .locationApproximate
        case .alarmSet: .alarmSet
        }
    }
}

enum ForkDeviceToolResponse: Equatable, Sendable, Encodable {
    case success(ForkDeviceToolOutput)
    case failure(ForkDeviceErrorCode)

    private enum CodingKeys: String, CodingKey { case ok, data, error }
    private enum ErrorKeys: String, CodingKey { case code }

    private struct Envelope<Payload: Decodable>: Decodable {
        struct Failure: Decodable { let code: ForkDeviceErrorCode }
        let ok: Bool
        let data: Payload?
        let error: Failure?
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let output):
            try container.encode(true, forKey: .ok)
            switch output {
            case .healthSteps(let data): try container.encode(data, forKey: .data)
            case .calendarEvents(let data): try container.encode(data, forKey: .data)
            case .contactsFind(let data): try container.encode(data, forKey: .data)
            case .locationApproximate(let data): try container.encode(data, forKey: .data)
            case .alarmSet(let data): try container.encode(data, forKey: .data)
            }
        case .failure(let code):
            try container.encode(false, forKey: .ok)
            var error = container.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error)
            try error.encode(code, forKey: .code)
        }
    }

    func json() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data(#"{"error":{"code":"unavailable"},"ok":false}"#.utf8)
    }

    static func decode(_ data: Data, for tool: ForkDeviceTool) throws -> ForkDeviceToolResponse {
        switch tool {
        case .healthSteps: try envelope(data, ForkHealthStepsResult.self, ForkDeviceToolOutput.healthSteps)
        case .calendarEvents: try envelope(data, ForkCalendarEventsResult.self, ForkDeviceToolOutput.calendarEvents)
        case .contactsFind: try envelope(data, ForkContactsFindResult.self, ForkDeviceToolOutput.contactsFind)
        case .locationApproximate: try envelope(data, ForkLocationApproximateResult.self, ForkDeviceToolOutput.locationApproximate)
        case .alarmSet: try envelope(data, ForkAlarmSetResult.self, ForkDeviceToolOutput.alarmSet)
        }
    }

    private static func envelope<Payload: Decodable>(
        _ data: Data, _ type: Payload.Type, _ wrap: (Payload) -> ForkDeviceToolOutput
    ) throws -> ForkDeviceToolResponse {
        let envelope = try JSONDecoder().decode(Envelope<Payload>.self, from: data)
        if envelope.ok, let payload = envelope.data { return .success(wrap(payload)) }
        if !envelope.ok, let failure = envelope.error { return .failure(failure.code) }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Malformed device tool response"))
    }
}
