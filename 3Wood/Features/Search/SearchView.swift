import SwiftUI

struct SearchView: View {
    @Environment(AppNavigation.self) private var nav
    @State private var viewModel = SearchViewModel()

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
                            CourseRow(course: course)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.sand)
                    }
                    .listStyle(.plain)
                }
            }
            .creamScreen()
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Course name or city")
            .appDestinations()
        }
        .environment(router)
    }
}

struct CourseRow: View {
    let course: Course

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
