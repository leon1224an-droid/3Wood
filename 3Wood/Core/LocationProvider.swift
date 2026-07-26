import CoreLocation

/// One-shot when-in-use location for map centering and nearby course
/// suggestions. The fix is used on-device only — it is never sent to the
/// backend (see the privacy policy).
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var continuations: [CheckedContinuation<CLLocation?, Never>] = []

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Requests permission if needed, then resolves one location (or nil on
    /// denial/failure — callers fall back to the country-wide default).
    func currentLocation() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        default:
            if let cached = manager.location { return cached }
            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
                manager.requestLocation()
            }
        }
    }

    /// Like currentLocation(), but never triggers the permission prompt —
    /// used by secondary surfaces (course picker) so the ask stays on the map.
    func currentLocationIfAuthorized() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return await currentLocation()
        default:
            return nil
        }
    }

    private func resume(with location: CLLocation?) {
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting {
            continuation.resume(returning: location)
        }
    }

    // MARK: CLLocationManagerDelegate (delegate is set to main-queue manager;
    // hop explicitly so resumes stay on the main actor).

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.resume(with: nil)
            default:
                break // .notDetermined — keep waiting for the user's answer
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.first
        Task { @MainActor in self.resume(with: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resume(with: nil) }
    }
}
