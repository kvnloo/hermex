import CoreLocation
import Foundation

@MainActor
final class ForkLocationReader: NSObject, CLLocationManagerDelegate {
    static let shared = ForkLocationReader()

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var fixWaiters: [CheckedContinuation<ForkDeviceFix?, Never>] = []

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        manager.delegate = self
    }

    func permission() -> ForkDevicePermission {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestPermission() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func recentFix(maximumAge: TimeInterval) async -> ForkDeviceFix? {
        if let cached = manager.location, -cached.timestamp.timeIntervalSinceNow <= maximumAge {
            return Self.fix(cached)
        }
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            finishFix(nil)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation in
            fixWaiters.append(continuation)
            if fixWaiters.count == 1 { manager.requestLocation() }
        }
    }

    nonisolated private static func fix(_ location: CLLocation) -> ForkDeviceFix {
        ForkDeviceFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeMs: ForkDeviceTime.milliseconds(location.timestamp)
        )
    }

    private func finishFix(_ fix: ForkDeviceFix?) {
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0.resume(returning: fix) }
    }

    private func authorizationChanged() {
        guard manager.authorizationStatus != .notDetermined else { return }
        let waiters = authorizationWaiters
        authorizationWaiters = []
        waiters.forEach { $0.resume() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fix = locations.last.map(Self.fix)
        MainActor.assumeIsolated { finishFix(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finishFix(nil) }
    }
}
