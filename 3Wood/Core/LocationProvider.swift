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
        // Ten-metre accuracy: beta testers reported the map landing on their
        // general area rather than where they actually are. One-shot requests
        // only, so the battery cost of the tighter fix is bounded.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// How old a cached fix may be before we ask for a fresh one. A fix from
    /// this morning would drop the user somewhere they no longer are.
    private static let maxCacheAge: TimeInterval = 60

    /// requestLocation() makes exactly one attempt and then reports failure. On
    /// a real device that first attempt often comes back kCLErrorLocationUnknown
    /// — indoors, or simply before the GPS has settled — and the caller was
    /// given nil, so the map silently stayed over the continental US with
    /// nothing to retry. A simulator always answers instantly, which is why
    /// this never showed up in testing.
    private static let maxRetries = 2
    private var retriesLeft = 0

    /// Nothing guarantees CoreLocation ever calls back. Without this the
    /// awaiting task hangs forever rather than falling back to the default map.
    private static let timeout: Duration = .seconds(15)
    private var watchdog: Task<Void, Never>?

    /// Requests permission if needed, then resolves one location (or nil on
    /// denial/failure — callers fall back to the country-wide default).
    func currentLocation() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
                startWatchdog()
                manager.requestWhenInUseAuthorization()
            }
        default:
            if let cached = manager.location,
               -cached.timestamp.timeIntervalSinceNow < Self.maxCacheAge {
                return cached
            }
            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
                requestFix()
            }
        }
    }

    /// One location request, with retries armed.
    private func requestFix() {
        retriesLeft = Self.maxRetries
        startWatchdog()
        manager.requestLocation()
    }

    /// Fall back to nil if CoreLocation never answers, so callers are never
    /// left awaiting a continuation that has no one left to resume it.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            self?.resume(with: nil)
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
        watchdog?.cancel()
        watchdog = nil
        retriesLeft = 0
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
                // Covers "Allow Once" as well as a standing grant — both land
                // here, and both need the retries armed.
                self.requestFix()
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
        let isTransient = (error as? CLError)?.code == .locationUnknown
        Task { @MainActor in
            // kCLErrorLocationUnknown means "not yet", not "never" — the usual
            // answer when the first fix is still settling. Anything else
            // (denied, network) is final.
            if isTransient, self.retriesLeft > 0 {
                self.retriesLeft -= 1
                self.manager.requestLocation()
                return
            }
            self.resume(with: nil)
        }
    }
}
