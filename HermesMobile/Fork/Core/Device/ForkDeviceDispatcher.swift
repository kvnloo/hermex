import Foundation

enum ForkDevicePermission: Equatable, Sendable {
    case granted, denied, notDetermined
}

enum ForkDeviceProviderError: Error, Equatable, Sendable {
    case permissionDenied, unavailable
}

protocol ForkDeviceProvider: Sendable {
    func isAvailable(_ source: ForkDeviceSource) async -> Bool
    func permission(for source: ForkDeviceSource) async -> ForkDevicePermission
    func steps(from start: Date, to end: Date) async throws -> Int64?
    func events(from start: Date, to end: Date, limit: Int) async throws -> [ForkCalendarEvent]
    func contactNames(matching query: String, limit: Int) async throws -> [String]
    func approximateFix(maximumAge: TimeInterval) async throws -> ForkDeviceFix?
    func setAlarm(at date: Date) async throws
}

final class ForkDeviceAccessSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static func key(for source: ForkDeviceSource) -> String { "fork.device.\(source.rawValue).enabled" }

    func isEnabled(_ source: ForkDeviceSource) -> Bool { defaults.bool(forKey: Self.key(for: source)) }

    func setEnabled(_ enabled: Bool, for source: ForkDeviceSource) {
        defaults.set(enabled, forKey: Self.key(for: source))
    }
}

struct ForkDeviceDispatcher: Sendable {
    let settings: ForkDeviceAccessSettings
    let provider: any ForkDeviceProvider
    var clock: @Sendable () -> Date = { Date() }

    func execute(_ request: ForkDeviceToolRequest) async -> ForkDeviceToolResponse {
        let source = request.tool.source
        guard settings.isEnabled(source) else { return .failure(.disabled) }
        guard await provider.isAvailable(source) else { return .failure(.unavailable) }
        guard await provider.permission(for: source) == .granted else { return .failure(.permissionDenied) }
        let now = clock()
        let nowMs = ForkDeviceTime.milliseconds(now)
        guard request.isValid(nowMs: nowMs) else { return .failure(.invalidArguments) }
        do {
            return try await run(request, now: now, nowMs: nowMs)
        } catch ForkDeviceProviderError.permissionDenied {
            return .failure(.permissionDenied)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.unavailable)
        }
    }

    private func run(_ request: ForkDeviceToolRequest, now: Date, nowMs: Int64) async throws -> ForkDeviceToolResponse {
        switch request {
        case .healthSteps:
            let start = ForkDeviceTime.date(nowMs - ForkDeviceLimits.day)
            return .success(.healthSteps(ForkHealthStepsResult(steps: try await provider.steps(from: start, to: now))))
        case .calendarEvents(let args):
            let events = try await provider.events(
                from: ForkDeviceTime.date(args.startMs), to: ForkDeviceTime.date(args.endMs), limit: ForkDeviceLimits.calendarEvents
            )
            return .success(.calendarEvents(ForkCalendarEventsResult(clamping: events)))
        case .contactsFind(let args):
            let names = try await provider.contactNames(matching: args.query, limit: ForkDeviceLimits.contactNames)
            return .success(.contactsFind(ForkContactsFindResult(clamping: names)))
        case .locationApproximate:
            let maximumAge = Double(ForkDeviceLimits.fixAge) / 1000
            guard let fix = try await provider.approximateFix(maximumAge: maximumAge),
                  let result = ForkLocationApproximateResult(coarsening: fix, nowMs: ForkDeviceTime.milliseconds(clock())) else {
                return .failure(.unavailable)
            }
            return .success(.locationApproximate(result))
        case .alarmSet(let args):
            try await provider.setAlarm(at: ForkDeviceTime.date(args.atMs))
            return .success(.alarmSet(ForkAlarmSetResult(atMs: args.atMs)))
        }
    }
}
