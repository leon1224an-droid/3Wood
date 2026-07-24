import Foundation
import MapKit

/// Live suggestions for the map search field: matching courses (from our DB)
/// and place completions (cities/areas via MapKit), updated as the user types.
@Observable
@MainActor
final class MapSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var courses: [Course] = []
    private(set) var places: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private var courseTask: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            courses = []
            places = []
            courseTask?.cancel()
            return
        }
        completer.queryFragment = trimmed
        courseTask?.cancel()
        courseTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = (try? await CourseRepo.search(trimmed)) ?? []
            guard !Task.isCancelled else { return }
            courses = Array(found.prefix(5))
        }
    }

    // MKLocalSearchCompleter calls its delegate on the main queue.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            places = Array(completer.results.prefix(4))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            places = []
        }
    }
}
