import Contacts
import EventKit
import Foundation
import HealthKit

final class ForkAppleDeviceProvider: ForkDeviceProvider, @unchecked Sendable {
    static let shared = ForkAppleDeviceProvider()

    private let health = HKHealthStore()
    private let calendar = EKEventStore()
    private let contacts = CNContactStore()
    private let stepType = HKQuantityType(.stepCount)

    func isAvailable(_ source: ForkDeviceSource) async -> Bool {
        switch source {
        case .health: return HKHealthStore.isHealthDataAvailable()
        case .calendar, .contacts, .location: return true
        case .alarm: return ForkDeviceAlarms.isSupported
        }
    }

    func permission(for source: ForkDeviceSource) async -> ForkDevicePermission {
        switch source {
        case .health:
            let status = try? await health.statusForAuthorizationRequest(toShare: [], read: [stepType])
            switch status {
            case .unnecessary: return .granted
            case .shouldRequest: return .notDetermined
            default: return .denied
            }
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized, .limited: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .location:
            return await ForkLocationReader.shared.permission()
        case .alarm:
            return ForkDeviceAlarms.permission()
        }
    }

    func requestPermission(for source: ForkDeviceSource) async {
        switch source {
        case .health: try? await health.requestAuthorization(toShare: [], read: [stepType])
        case .calendar: _ = try? await calendar.requestFullAccessToEvents()
        case .contacts: _ = try? await contacts.requestAccess(for: .contacts)
        case .location: await ForkLocationReader.shared.requestPermission()
        case .alarm: await ForkDeviceAlarms.requestPermission()
        }
    }

    func steps(from start: Date, to end: Date) async throws -> Int64? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum
        )
        do {
            guard let sum = try await descriptor.result(for: health)?.sumQuantity() else { return nil }
            return Int64(sum.doubleValue(for: .count()).rounded())
        } catch let error as HKError where error.code == .errorNoData {
            return nil
        } catch let error as HKError where error.code == .errorAuthorizationDenied || error.code == .errorAuthorizationNotDetermined {
            throw ForkDeviceProviderError.permissionDenied
        }
    }

    func events(from start: Date, to end: Date, limit: Int) async throws -> [ForkCalendarEvent] {
        let predicate = calendar.predicateForEvents(withStart: start, end: end, calendars: nil)
        return calendar.events(matching: predicate)
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .prefix(limit)
            .map { event in
                ForkCalendarEvent(
                    title: event.title ?? "",
                    startMs: ForkDeviceTime.milliseconds(event.startDate ?? start),
                    endMs: ForkDeviceTime.milliseconds(event.endDate ?? end)
                )
            }
    }

    func contactNames(matching query: String, limit: Int) async throws -> [String] {
        let keys = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        do {
            let matches = try contacts.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys)
            return Array(matches.lazy.compactMap { CNContactFormatter.string(from: $0, style: .fullName) }.prefix(limit))
        } catch let error as CNError where error.code == .authorizationDenied {
            throw ForkDeviceProviderError.permissionDenied
        }
    }

    func approximateFix(maximumAge: TimeInterval) async throws -> ForkDeviceFix? {
        await ForkLocationReader.shared.recentFix(maximumAge: maximumAge)
    }

    func setAlarm(at date: Date) async throws {
        try await ForkDeviceAlarms.schedule(at: date)
    }
}
