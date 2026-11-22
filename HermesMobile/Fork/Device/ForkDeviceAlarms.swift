import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

enum ForkDeviceAlarms {
    static let identifierKey = "fork.device.alarm.id"

    static var isSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static func permission() -> ForkDevicePermission {
        guard #available(iOS 26.0, *) else { return .denied }
        switch AlarmManager.shared.authorizationState {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    static func requestPermission() async {
        guard #available(iOS 26.0, *) else { return }
        _ = try? await AlarmManager.shared.requestAuthorization()
    }

    static func schedule(at date: Date, defaults: UserDefaults = .standard) async throws {
        guard #available(iOS 26.0, *) else { throw ForkDeviceProviderError.unavailable }
        cancel(defaults: defaults)
        let stop = AlarmButton(text: LocalizedStringResource("Stop", table: "Fork"), textColor: .white, systemImageName: "stop.circle")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource("Hermes alarm", table: "Fork"), stopButton: stop)
        let attributes = AlarmAttributes<ForkDeviceAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert), metadata: ForkDeviceAlarmMetadata(), tintColor: .accentColor
        )
        let configuration = AlarmManager.AlarmConfiguration<ForkDeviceAlarmMetadata>(
            countdownDuration: nil, schedule: .fixed(date), attributes: attributes,
            stopIntent: nil, secondaryIntent: nil, sound: .default
        )
        let id = UUID()
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        defaults.set(id.uuidString, forKey: identifierKey)
    }

    static func cancel(defaults: UserDefaults = .standard) {
        guard #available(iOS 26.0, *) else { return }
        guard let raw = defaults.string(forKey: identifierKey), let id = UUID(uuidString: raw) else { return }
        try? AlarmManager.shared.cancel(id: id)
        defaults.removeObject(forKey: identifierKey)
    }
}

@available(iOS 26.0, *)
struct ForkDeviceAlarmMetadata: AlarmMetadata {}
