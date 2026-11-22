import XCTest
@testable import HermesMobile

final class ForkDeviceApprovalTests: XCTestCase {
    private let nowMs: Int64 = 1_760_000_060_000
    private var defaults: UserDefaults!
    private var suite: String!
    private var settings: ForkDeviceAccessSettings!
    private var provider: ForkDeviceFakeProvider!
    private var prompts: AsyncStream<ForkDevicePrompt?>!
    private var promptSink: AsyncStream<ForkDevicePrompt?>.Continuation!
    private var deadlineSink: AsyncStream<Void>.Continuation!
    private var gate: ForkDeviceApprovalGate!
    private var host: ForkDeviceToolHost!

    override func setUp() {
        super.setUp()
        suite = "fork.device.approval.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        settings = ForkDeviceAccessSettings(defaults: defaults)
        provider = ForkDeviceFakeProvider()
        (prompts, promptSink) = AsyncStream.makeStream(of: ForkDevicePrompt?.self)
        let (deadlines, deadlineSink) = AsyncStream.makeStream(of: Void.self)
        self.deadlineSink = deadlineSink
        let sink = promptSink!
        gate = ForkDeviceApprovalGate(deadline: { for await _ in deadlines { return } }, present: { sink.yield($0) })
        let now = ForkDeviceTime.date(nowMs)
        host = ForkDeviceToolHost(dispatcher: ForkDeviceDispatcher(settings: settings, provider: provider, clock: { now }), gate: gate)
    }

    override func tearDown() {
        promptSink.finish()
        deadlineSink.finish()
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func nextPrompt() async -> ForkDevicePrompt? {
        for await prompt in prompts { return prompt }
        return nil
    }

    private var contactsParams: Data {
        Data(#"{"session_id":"s","tool":"device.contacts.find","args":{"name":"Alex"}}"#.utf8)
    }

    func testApprovedRequestShowsDestinationOperationAndArgumentsThenRuns() async throws {
        settings.setEnabled(true, for: .contacts)
        provider.contacts = ["Alex"]
        async let response = host.handle(params: contactsParams, destination: "studio", foreground: true)
        let shown = await nextPrompt()
        let prompt = try XCTUnwrap(shown)
        XCTAssertEqual(prompt.destination, "studio")
        XCTAssertEqual(prompt.operation, "device.contacts.find")
        XCTAssertEqual(prompt.request, .contactsFind(ForkContactsFindRequest(name: "Alex")))
        XCTAssertTrue(provider.calls.isEmpty)
        await gate.answer(prompt.id, approved: true)
        let result = await response
        XCTAssertEqual(result, .success(.contactsFind(ForkContactsFindResult(names: ["Alex"]))))
        let cleared = await nextPrompt()
        XCTAssertNil(cleared)
    }

    func testDeclinedOrTimedOutPromptNeverCallsTheDispatcher() async throws {
        settings.setEnabled(true, for: .contacts)
        async let declined = host.handle(params: contactsParams, destination: "studio", foreground: true)
        let first = await nextPrompt()
        await gate.answer(try XCTUnwrap(first).id, approved: false)
        let declinedResult = await declined
        XCTAssertEqual(declinedResult, .failure(.userDenied))
        _ = await nextPrompt()
        async let expired = host.handle(params: contactsParams, destination: "studio", foreground: true)
        _ = await nextPrompt()
        deadlineSink.yield()
        let expiredResult = await expired
        XCTAssertEqual(expiredResult, .failure(.cancelled))
        XCTAssertTrue(provider.calls.isEmpty)
    }

    func testOnlyOnePromptAtATimeAndOnlyInTheForeground() async throws {
        settings.setEnabled(true, for: .contacts)
        let background = await host.handle(params: contactsParams, destination: "studio", foreground: false)
        XCTAssertEqual(background, .failure(.notForeground))
        async let first = host.handle(params: contactsParams, destination: "studio", foreground: true)
        let shown = await nextPrompt()
        let second = await host.handle(params: contactsParams, destination: "studio", foreground: true)
        XCTAssertEqual(second, .failure(.busy))
        await gate.dismissPending()
        let firstResult = await first
        XCTAssertEqual(firstResult, .failure(.cancelled))
        XCTAssertNotNil(shown)
    }

    func testDisabledOrInvalidRequestsFailWithoutPrompting() async {
        let disabled = await host.handle(params: contactsParams, destination: "studio", foreground: true)
        XCTAssertEqual(disabled, .failure(.disabled))
        settings.setEnabled(true, for: .alarm)
        let past = await host.handle(.alarmSet(ForkAlarmSetRequest(atMs: nowMs - 1)), destination: "studio", foreground: true)
        XCTAssertEqual(past, .failure(.invalidArguments))
        let unknown = await host.handle(params: Data(#"{"session_id":"s","tool":"device.sms.send","args":{}}"#.utf8), destination: "studio", foreground: true)
        XCTAssertEqual(unknown, .failure(.invalidArguments))
        promptSink.finish()
        let shown = await nextPrompt()
        XCTAssertNil(shown)
    }
}
