import SwiftUI

struct SearchView: View {
    @Environment(AppNavigation.self) private var nav
    @State private var viewModel = SearchViewModel()
    @State private var quickSave = QuickSaveState()

    var body: some View {
        @Bindable var router = nav.searchRouter
        NavigationStack(path: $router.path) {
            Group {
                if viewModel.results.isEmpty {
                    if viewModel.isSearching {
                        ProgressView()
                    } else if viewModel.searchFailed {
                        LoadFailedView { viewModel.retry() }
                    } else if viewModel.query.count >= 2 {
                        ContentUnavailableView.search(text: viewModel.query)
                    } else {
                        ContentUnavailableView(
                            "Find a course",
                            systemImage: "magnifyingglass",
                            description: Text("Search any of 16,000+ US golf courses by name or city.")
                        )
                    }
                } else {
                    List(viewModel.results) { course in
                        NavigationLink(value: Destination.course(course)) {
                            CourseRow(course: course, isSaved: quickSave.saved.contains(course.id))
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.sand)
                        .wantToPlaySwipe(course, state: quickSave)
                    }
                    .listStyle(.plain)
                }
            }
            .quickSaveAlert(quickSave)
            .creamScreen()
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Course name or city")
            .appDestinations()
        }
        .environment(router)
    }
}

/// Swipe-to-save state for a screen of course rows. `CourseRow` is built from
/// the search/map RPCs, which don't report whether the caller has bookmarked a
/// course, so saves are tracked optimistically for the life of the screen —
/// the authoritative state is still fetched by CourseDetailView.
@MainActor
@Observable
final class QuickSaveState {
    private(set) var saved: Set<Int> = []
    var errorMessage: String?

    func toggle(_ course: Course) async {
        let wasSaved = saved.contains(course.id)
        // Move the row first: a swipe that visibly does nothing until the
        // network answers is what made saving feel like a chore.
        if wasSaved { saved.remove(course.id) } else { saved.insert(course.id) }
        do {
            if wasSaved {
                try await WantToPlayRepo.remove(courseID: course.id)
            } else {
                try await WantToPlayRepo.add(courseID: course.id)
            }
        } catch {
            if wasSaved { saved.insert(course.id) } else { saved.remove(course.id) }
            errorMessage = "Couldn't update Want to Play for \(course.name). \(error.localizedDescription)"
        }
    }
}

extension View {
    /// Leading swipe on a course row to add/remove it from Want to Play,
    /// so saving doesn't require opening the course first.
    func wantToPlaySwipe(_ course: Course, state: QuickSaveState) -> some View {
        let isSaved = state.saved.contains(course.id)
        return swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await state.toggle(course) }
            } label: {
                Label(isSaved ? "Remove" : "Want to Play",
                      systemImage: isSaved ? "bookmark.slash.fill" : "bookmark.fill")
            }
            .tint(isSaved ? Color.clayRed : Color.fairwayGreen)
        }
    }

    /// Surfaces a failed quick-save without stealing the screen.
    func quickSaveAlert(_ state: QuickSaveState) -> some View {
        alert("Something went wrong", isPresented: .init(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

struct CourseRow: View {
    let course: Course
    /// Set by screens with swipe-to-save so the row reflects the bookmark.
    var isSaved = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(course.locationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let tag = course.shortType {
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.darkPine)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.sand, in: Capsule())
                    }
                }
            }
            Spacer()
            if isSaved {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(Color.fairwayGreen)
                    .accessibilityLabel("Saved to Want to Play")
            }
            // Community average — labelled so it isn't mistaken for a personal score.
            if course.ratingCount > 0 {
                VStack(spacing: 1) {
                    ScoreBadge(score: course.avgScore, compact: true)
                    Text("avg")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Not rated")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    SearchView()
        .environment(AppNavigation())
}
