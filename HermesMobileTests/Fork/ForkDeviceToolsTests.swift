import XCTest
@testable import HermesMobile

final class ForkDeviceToolsTests: XCTestCase {
    private let nowMs: Int64 = 1_759_999_000_000

    private func call(_ json: String) -> ForkDeviceToolCall? {
        try? ForkDeviceToolCall.decode(Data(json.utf8)).get()
    }

    private func params(_ tool: String, _ args: String) -> String {
        #"{"session_id":"active-session","tool":"\#(tool)","args":\#(args)}"#
    }

    private func json(_ response: ForkDeviceToolResponse) -> String {
        String(decoding: response.json(), as: UTF8.self)
    }

    func testEveryToolNameMatchesTheContractAndItsSource() {
        XCTAssertEqual(ForkDeviceTool.allCases.map(\.rawValue), [
            "device.health.steps", "device.calendar.events", "device.contacts.find",
            "device.location.approximate", "device.alarm.set",
        ])
        XCTAssertEqual(ForkDeviceTool.allCases.map(\.source), ForkDeviceSource.allCases)
    }

    func testHealthStepsTakesNoArgumentsAndReportsNullWithoutRecords() {
        XCTAssertEqual(call(params("device.health.steps", "{}"))?.request, .healthSteps(ForkHealthStepsRequest()))
        XCTAssertNil(call(params("device.health.steps", #"{"days":7}"#)))
        XCTAssertEqual(json(.success(.healthSteps(ForkHealthStepsResult(steps: 1200)))), #"{"data":{"steps":1200},"ok":true}"#)
        XCTAssertEqual(json(.success(.healthSteps(ForkHealthStepsResult(steps: nil)))), #"{"data":{"steps":null},"ok":true}"#)
    }

    func testCalendarEventsWindowAndResultShape() throws {
        let request = try XCTUnwrap(call(params("device.calendar.events", #"{"startMs":1760000000000,"endMs":1760003600000}"#))?.request)
        XCTAssertEqual(request, .calendarEvents(ForkCalendarEventsRequest(startMs: 1_760_000_000_000, endMs: 1_760_003_600_000)))
        XCTAssertTrue(request.isValid(nowMs: nowMs))
        let week = ForkDeviceLimits.week
        XCTAssertFalse(ForkCalendarEventsRequest(startMs: nowMs - week - 1, endMs: nowMs).isValid(nowMs: nowMs))
        XCTAssertFalse(ForkCalendarEventsRequest(startMs: nowMs + 4 * week + 1, endMs: nowMs + 5 * week).isValid(nowMs: nowMs))
        XCTAssertFalse(ForkCalendarEventsRequest(startMs: nowMs, endMs: nowMs).isValid(nowMs: nowMs))
        XCTAssertFalse(ForkCalendarEventsRequest(startMs: nowMs, endMs: nowMs + week + 1).isValid(nowMs: nowMs))
        XCTAssertNil(call(params("device.calendar.events", #"{"startMs":1760000000000}"#)))
        XCTAssertNil(call(params("device.calendar.events", #"{"startMs":1760000000000.5,"endMs":1760003600000}"#)))
        XCTAssertNil(call(params("device.calendar.events", #"{"startMs":"1760000000000","endMs":1760003600000}"#)))
        let event = ForkCalendarEvent(title: "Meeting", startMs: 1_760_000_000_000, endMs: 1_760_003_600_000)
        XCTAssertEqual(
            json(.success(.calendarEvents(ForkCalendarEventsResult(events: [event])))),
            #"{"data":{"events":[{"endMs":1760003600000,"startMs":1760000000000,"title":"Meeting"}]},"ok":true}"#
        )
        let many = (0..<40).map { ForkCalendarEvent(title: String(repeating: "x", count: 300), startMs: Int64($0), endMs: Int64($0) + 1) }
        let clamped = ForkCalendarEventsResult(clamping: many)
        XCTAssertEqual(clamped.events.count, 25)
        XCTAssertEqual(clamped.events.map(\.title.count).max(), 200)
    }

    func testContactsFindQueryBoundsAndNameOnlyResult() throws {
        let request = try XCTUnwrap(call(params("device.contacts.find", #"{"name":"Alex"}"#))?.request)
        XCTAssertEqual(request, .contactsFind(ForkContactsFindRequest(name: "Alex")))
        XCTAssertTrue(request.isValid(nowMs: nowMs))
        XCTAssertEqual(ForkContactsFindRequest(name: "  Al  ").query, "Al")
        XCTAssertFalse(ForkContactsFindRequest(name: " A ").isValid)
        XCTAssertFalse(ForkContactsFindRequest(name: String(repeating: "a", count: 81)).isValid)
        XCTAssertTrue(ForkContactsFindRequest(name: String(repeating: "a", count: 80)).isValid)
        XCTAssertNil(call(params("device.contacts.find", #"{"name":"Alex","phone":true}"#)))
        XCTAssertEqual(json(.success(.contactsFind(ForkContactsFindResult(names: ["Alex"])))), #"{"data":{"names":["Alex"]},"ok":true}"#)
        let clamped = ForkContactsFindResult(clamping: (0..<15).map { "\($0)" + String(repeating: "n", count: 200) })
        XCTAssertEqual(clamped.names.count, 10)
        XCTAssertEqual(clamped.names.map(\.count).max(), 120)
    }

    func testLocationIsCoarseAndOnlyFromAFreshFix() throws {
        XCTAssertEqual(call(params("device.location.approximate", "{}"))?.request, .locationApproximate(ForkLocationApproximateRequest()))
        XCTAssertNil(call(params("device.location.approximate", #"{"precise":true}"#)))
        let fix = ForkDeviceFix(latitude: 12.3412, longitude: 45.6691, timeMs: 1_760_000_000_000)
        let result = try XCTUnwrap(ForkLocationApproximateResult(coarsening: fix, nowMs: 1_760_000_000_000 + 60_000))
        XCTAssertEqual(json(.success(.locationApproximate(result))), #"{"data":{"latitude":12.34,"longitude":45.67,"timeMs":1760000000000},"ok":true}"#)
        XCTAssertNil(ForkLocationApproximateResult(coarsening: fix, nowMs: 1_760_000_000_000 + 300_001))
        XCTAssertNil(ForkLocationApproximateResult(coarsening: fix, nowMs: 1_760_000_000_000 - 1))
        XCTAssertEqual(ForkLocationApproximateResult.coarse(12.3456), 12.35)
    }

    func testAlarmSetWindowAndEcho() throws {
        let request = try XCTUnwrap(call(params("device.alarm.set", #"{"atMs":1760000000000}"#))?.request)
        XCTAssertEqual(request, .alarmSet(ForkAlarmSetRequest(atMs: 1_760_000_000_000)))
        XCTAssertTrue(request.isValid(nowMs: nowMs))
        XCTAssertFalse(ForkAlarmSetRequest(atMs: nowMs + 9_999).isValid(nowMs: nowMs))
        XCTAssertTrue(ForkAlarmSetRequest(atMs: nowMs + 10_000).isValid(nowMs: nowMs))
        XCTAssertFalse(ForkAlarmSetRequest(atMs: nowMs + ForkDeviceLimits.week + 1).isValid(nowMs: nowMs))
        XCTAssertEqual(json(.success(.alarmSet(ForkAlarmSetResult(atMs: 1_760_000_000_000)))), #"{"data":{"atMs":1760000000000},"ok":true}"#)
    }

    func testEnvelopeRejectsUnknownToolsOversizedParamsAndMissingSession() {
        XCTAssertEqual(ForkDeviceToolCall.decode(Data(params("device.unknown", "{}").utf8)).failure, .invalidArguments)
        XCTAssertEqual(ForkDeviceToolCall.decode(Data(#"{"tool":"device.health.steps","args":{}}"#.utf8)).failure, .invalidArguments)
        let padded = params("device.contacts.find", #"{"name":"\#(String(repeating: "a", count: 5000))"}"#)
        XCTAssertEqual(ForkDeviceToolCall.decode(Data(padded.utf8)).failure, .invalidArguments)
        XCTAssertEqual(call(params("device.health.steps", "{}"))?.sessionID, "active-session")
    }

    func testFailuresCarryOnlyTheContractCode() {
        XCTAssertEqual(json(.failure(.permissionDenied)), #"{"error":{"code":"permission_denied"},"ok":false}"#)
        XCTAssertEqual(Set(ForkDeviceErrorCode.allCases.map(\.rawValue)), [
            "disabled", "permission_denied", "unavailable", "invalid_arguments",
            "user_denied", "cancelled", "busy", "not_foreground",
        ])
    }

    func testCallsAndResponsesRoundTrip() throws {
        let requests: [ForkDeviceToolRequest] = [
            .healthSteps(ForkHealthStepsRequest()),
            .calendarEvents(ForkCalendarEventsRequest(startMs: 1, endMs: 2)),
            .contactsFind(ForkContactsFindRequest(name: "Alex")),
            .locationApproximate(ForkLocationApproximateRequest()),
            .alarmSet(ForkAlarmSetRequest(atMs: 3)),
        ]
        for request in requests {
            let encoded = try JSONEncoder().encode(ForkDeviceToolCall(sessionID: "s", request: request))
            XCTAssertEqual(try ForkDeviceToolCall.decode(encoded).get().request, request)
        }
        let outputs: [ForkDeviceToolOutput] = [
            .healthSteps(ForkHealthStepsResult(steps: nil)),
            .calendarEvents(ForkCalendarEventsResult(events: [ForkCalendarEvent(title: "T", startMs: 1, endMs: 2)])),
            .contactsFind(ForkContactsFindResult(names: ["A"])),
            .locationApproximate(ForkLocationApproximateResult(latitude: 1.5, longitude: -2.25, timeMs: 4)),
            .alarmSet(ForkAlarmSetResult(atMs: 5)),
        ]
        for output in outputs {
            XCTAssertEqual(try ForkDeviceToolResponse.decode(ForkDeviceToolResponse.success(output).json(), for: output.tool), .success(output))
            XCTAssertEqual(try ForkDeviceToolResponse.decode(ForkDeviceToolResponse.failure(.busy).json(), for: output.tool), .failure(.busy))
        }
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
