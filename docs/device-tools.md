# Device tools v1 on iOS (proposed host contract)

This is the iOS side of `device_tools_v1`, the proposed host contract in
[kvnloo/hermes-android `docs/device-tools.md`](https://github.com/kvnloo/hermes-android/blob/boat/android/device-access/docs/device-tools.md).
That file is the source of truth for the wire shapes; this one records how Hermex maps them.

The Hermes gateway does not negotiate `device_tools_v1` or send `device.tool.call` yet, so Hermex
does not advertise these tools to any host. Settings → Device Access can run a sample request
locally through the same approval prompt and dispatcher a host request would use. Turning a
source on or granting an iOS permission never sends data off the phone.

## Shapes

Each tool has one `Codable` request type and one result type in
`HermesMobile/Fork/Core/Device/ForkDeviceTools.swift` (Foundation only, so
`scripts/fork-linux-test` runs their tests on Linux):

| Tool | Request | Result `data` |
| --- | --- | --- |
| `device.health.steps` | `ForkHealthStepsRequest` `{}` | `ForkHealthStepsResult` `{"steps":1200}` or `{"steps":null}` |
| `device.calendar.events` | `ForkCalendarEventsRequest` `{"startMs","endMs"}` | `ForkCalendarEventsResult` `{"events":[{"title","startMs","endMs"}]}` |
| `device.contacts.find` | `ForkContactsFindRequest` `{"name"}` | `ForkContactsFindResult` `{"names":[…]}` |
| `device.location.approximate` | `ForkLocationApproximateRequest` `{}` | `ForkLocationApproximateResult` `{"latitude","longitude","timeMs"}` |
| `device.alarm.set` | `ForkAlarmSetRequest` `{"atMs"}` | `ForkAlarmSetResult` `{"atMs"}` |

`ForkDeviceToolCall` decodes the `device.tool.call` params (`session_id`, `tool`, `args`) and
rejects unknown tools, unknown or missing argument keys, non-integer timestamps and params over
4 KB. `ForkDeviceToolResponse` encodes `{"ok":true,"data":{…}}` or
`{"ok":false,"error":{"code":"…"}}` with the contract's eight codes. Limits match Android:
calendar start within now−7 to now+28 days, span up to 7 days, at most 25 events, titles cut
to 200 characters; contact queries 2–80 characters, at most 10 names of up to 120 characters;
location rounded to two decimals from a fix no older than five minutes; alarms 10 seconds to
7 days ahead.

## Order of checks

`ForkDeviceToolHost` (one per client) handles a request in this order: decode (`invalid_arguments`),
source on (`disabled`), arguments in range (`invalid_arguments`), then the per-request prompt.
The prompt shows the destination, the operation and its arguments, needs the app in the
foreground (`not_foreground`), allows one prompt at a time (`busy`), times out after 60 seconds
(`cancelled`), and returns `user_denied` when declined. Only after approval does
`ForkDeviceDispatcher` re-check the source, provider availability (`unavailable`) and the iOS
permission (`permission_denied`) before reading anything.

## iOS mapping

| Source | Framework | Permission | Notes |
| --- | --- | --- | --- |
| Health steps | HealthKit `HKStatisticsQueryDescriptor`, cumulative sum over the last 24 hours | Read `stepCount` | HealthKit never reveals whether reading was allowed; a denied read returns `{"steps":null}`. Needs the HealthKit entitlement. |
| Calendar | EventKit `events(matching:)` | Full calendar access (iOS 17+) | Title and times only. |
| Contacts | Contacts `predicateForContacts(matchingName:)` | Contacts (full or limited) | Full-name strings only. |
| Approximate location | CoreLocation, `kCLLocationAccuracyReduced`, one `requestLocation()` with a 15 s limit when the cached fix is stale | When in use; `NSLocationDefaultAccuracyReduced` | No background location. |
| Alarms | AlarmKit fixed-date alarm (iOS 26+) | AlarmKit authorization | Replaces the previous Hermex alarm; turning the source off cancels it. Unavailable before iOS 26. AlarmKit is weak-linked. |

All five sources are off by default (`fork.device.<source>.enabled` in `UserDefaults`).
