import XCTest
@testable import HermesMobile

final class ForkDeviceFakeProvider: ForkDeviceProvider, @unchecked Sendable {
    var available: Set<ForkDeviceSource> = Set(ForkDeviceSource.allCases)
    var permissions: [ForkDeviceSource: ForkDevicePermission] = [:]
    var stepCount: Int64? = 1200
    var calendar: [ForkCalendarEvent] = []
    var contacts: [String] = []
    var fix: ForkDeviceFix?
    var failure: Error?
    private(set) var calls: [String] = []
    private(set) var alarms: [Date] = []

    func isAvailable(_ source: ForkDeviceSource) async -> Bool { available.contains(source) }
    func permission(for source: ForkDeviceSource) async -> ForkDevicePermission { permissions[source] ?? .granted }

    func steps(from start: Date, to end: Date) async throws -> Int64? {
        calls.append("steps \(ForkDeviceTime.milliseconds(start))-\(ForkDeviceTime.milliseconds(end))")
        if let failure { throw failure }
        return stepCount
    }

    func events(from start: Date, to end: Date, limit: Int) async throws -> [ForkCalendarEvent] {
        calls.append("events \(limit)")
        if let failure { throw failure }
        return calendar
    }

    func contactNames(matching query: String, limit: Int) async throws -> [String] {
        calls.append("contacts \(query) \(limit)")
        if let failure { throw failure }
        return contacts
    }

    func approximateFix(maximumAge: TimeInterval) async throws -> ForkDeviceFix? {
        calls.append("fix \(maximumAge)")
        if let failure { throw failure }
        return fix
    }

    func setAlarm(at date: Date) async throws {
        if let failure { throw failure }
        alarms.append(date)
    }
}

final class ForkDeviceDispatcherTests: XCTestCase {
    private let nowMs: Int64 = 1_760_000_060_000
    private var defaults: UserDefaults!
    private var suite: String!
    private var settings: ForkDeviceAccessSettings!
    private var provider: ForkDeviceFakeProvider!
    private var dispatcher: ForkDeviceDispatcher!

    override func setUp() {
        super.setUp()
        suite = "fork.device.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        settings = ForkDeviceAccessSettings(defaults: defaults)
        provider = ForkDeviceFakeProvider()
        let now = ForkDeviceTime.date(nowMs)
        dispatcher = ForkDeviceDispatcher(settings: settings, provider: provider, clock: { now })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testEverySourceIsOffByDefaultAndTogglesIndependently() async {
        XCTAssertEqual(ForkDeviceSource.allCases.filter(settings.isEnabled), [])
        for tool in ForkDeviceTool.allCases {
            let result = await dispatcher.execute(Self.sample(tool, nowMs: nowMs))
            XCTAssertEqual(result, .failure(.disabled), tool.rawValue)
        }
        XCTAssertEqual(provider.calls, [])
        settings.setEnabled(true, for: .contacts)
        XCTAssertEqual(ForkDeviceSource.allCases.filter(settings.isEnabled), [.contacts])
    }

    func testEnabledSourceStillNeedsAvailabilityAndAnOSGrant() async {
        settings.setEnabled(true, for: .contacts)
        provider.permissions[.contacts] = .notDetermined
        let notAsked = await dispatcher.execute(.contactsFind(ForkContactsFindRequest(name: "Alex")))
        XCTAssertEqual(notAsked, .failure(.permissionDenied))
        provider.permissions[.contacts] = .denied
        let denied = await dispatcher.execute(.contactsFind(ForkContactsFindRequest(name: "Alex")))
        XCTAssertEqual(denied, .failure(.permissionDenied))
        settings.setEnabled(true, for: .alarm)
        provider.available.remove(.alarm)
        let alarm = await dispatcher.execute(.alarmSet(ForkAlarmSetRequest(atMs: nowMs + 60_000)))
        XCTAssertEqual(alarm, .failure(.unavailable))
        XCTAssertEqual(provider.calls, [])
    }

    func testGrantedToolsReturnContractData() async {
        ForkDeviceSource.allCases.forEach { settings.setEnabled(true, for: $0) }
        provider.calendar = [ForkCalendarEvent(title: "Meeting", startMs: nowMs, endMs: nowMs + 1)]
        provider.contacts = ["Alex Doe"]
        provider.fix = ForkDeviceFix(latitude: 12.3456, longitude: 45.6712, timeMs: nowMs - 1_000)
        let steps = await dispatcher.execute(.healthSteps(ForkHealthStepsRequest()))
        XCTAssertEqual(steps, .success(.healthSteps(ForkHealthStepsResult(steps: 1200))))
        let events = await dispatcher.execute(.calendarEvents(ForkCalendarEventsRequest(startMs: nowMs, endMs: nowMs + 3_600_000)))
        XCTAssertEqual(events, .success(.calendarEvents(ForkCalendarEventsResult(events: provider.calendar))))
        let names = await dispatcher.execute(.contactsFind(ForkContactsFindRequest(name: "  Alex ")))
        XCTAssertEqual(names, .success(.contactsFind(ForkContactsFindResult(names: ["Alex Doe"]))))
        let location = await dispatcher.execute(.locationApproximate(ForkLocationApproximateRequest()))
        XCTAssertEqual(location, .success(.locationApproximate(ForkLocationApproximateResult(latitude: 12.35, longitude: 45.67, timeMs: nowMs - 1_000))))
        let alarm = await dispatcher.execute(.alarmSet(ForkAlarmSetRequest(atMs: nowMs + 60_000)))
        XCTAssertEqual(alarm, .success(.alarmSet(ForkAlarmSetResult(atMs: nowMs + 60_000))))
        XCTAssertEqual(provider.alarms, [ForkDeviceTime.date(nowMs + 60_000)])
        XCTAssertEqual(provider.calls, [
            "steps \(nowMs - ForkDeviceLimits.day)-\(nowMs)", "events 25", "contacts Alex 10", "fix 300.0",
        ])
    }

    func testInvalidArgumentsNeverReachTheProvider() async {
        ForkDeviceSource.allCases.forEach { settings.setEnabled(true, for: $0) }
        let past = await dispatcher.execute(.alarmSet(ForkAlarmSetRequest(atMs: nowMs)))
        XCTAssertEqual(past, .failure(.invalidArguments))
        let short = await dispatcher.execute(.contactsFind(ForkContactsFindRequest(name: "A")))
        XCTAssertEqual(short, .failure(.invalidArguments))
        let wide = await dispatcher.execute(.calendarEvents(ForkCalendarEventsRequest(startMs: nowMs, endMs: nowMs + 8 * ForkDeviceLimits.day)))
        XCTAssertEqual(wide, .failure(.invalidArguments))
        XCTAssertEqual(provider.calls, [])
        XCTAssertEqual(provider.alarms, [])
    }

    func testProviderFailuresMapToContractCodes() async {
        ForkDeviceSource.allCases.forEach { settings.setEnabled(true, for: $0) }
        let stale = await dispatcher.execute(.locationApproximate(ForkLocationApproximateRequest()))
        XCTAssertEqual(stale, .failure(.unavailable))
        provider.failure = ForkDeviceProviderError.permissionDenied
        let revoked = await dispatcher.execute(.healthSteps(ForkHealthStepsRequest()))
        XCTAssertEqual(revoked, .failure(.permissionDenied))
        provider.failure = CancellationError()
        let cancelled = await dispatcher.execute(.contactsFind(ForkContactsFindRequest(name: "Alex")))
        XCTAssertEqual(cancelled, .failure(.cancelled))
        provider.failure = NSError(domain: "EventKit", code: 1)
        let broken = await dispatcher.execute(.calendarEvents(ForkCalendarEventsRequest(startMs: nowMs, endMs: nowMs + 1)))
        XCTAssertEqual(broken, .failure(.unavailable))
    }

    static func sample(_ tool: ForkDeviceTool, nowMs: Int64) -> ForkDeviceToolRequest {
        switch tool {
        case .healthSteps: .healthSteps(ForkHealthStepsRequest())
        case .calendarEvents: .calendarEvents(ForkCalendarEventsRequest(startMs: nowMs, endMs: nowMs + 3_600_000))
        case .contactsFind: .contactsFind(ForkContactsFindRequest(name: "Alex"))
        case .locationApproximate: .locationApproximate(ForkLocationApproximateRequest())
        case .alarmSet: .alarmSet(ForkAlarmSetRequest(atMs: nowMs + 60_000))
        }
    }
}
