import Foundation
import MapKit

@Observable
@MainActor
final class MapViewModel {
    private(set) var courses: [Course] = []
    private var fetchTask: Task<Void, Never>?

    /// Above this many degrees of latitude the pins are too dense to be useful.
    static let maxUsefulSpan: Double = 12

    var showZoomHint = false

    func regionChanged(_ region: MKCoordinateRegion) {
        showZoomHint = region.span.latitudeDelta > Self.maxUsefulSpan
        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            // On failure keep the pins already drawn — replacing them with an
            // empty array would wipe the map over a transient network blip.
            guard let found = try? await CourseRepo.inRegion(
                minLat: region.center.latitude - region.span.latitudeDelta / 2,
                minLng: region.center.longitude - region.span.longitudeDelta / 2,
                maxLat: region.center.latitude + region.span.latitudeDelta / 2,
                maxLng: region.center.longitude + region.span.longitudeDelta / 2
            ), !Task.isCancelled else { return }
            courses = found
        }
    }
}
