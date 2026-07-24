import Foundation

@Observable
@MainActor
final class SearchViewModel {
    var query = "" {
        didSet { scheduleSearch() }
    }
    private(set) var results: [Course] = []
    private(set) var isSearching = false
    private(set) var searchFailed = false

    private var searchTask: Task<Void, Never>?

    func retry() {
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            searchFailed = false
            return
        }
        isSearching = true
        searchTask = Task {
            // Debounce so we search once per pause, not per keystroke.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let found = try await CourseRepo.search(trimmed)
                guard !Task.isCancelled else { return }
                results = found
                searchFailed = false
            } catch {
                guard !Task.isCancelled else { return }
                searchFailed = true
            }
            isSearching = false
        }
    }
}
