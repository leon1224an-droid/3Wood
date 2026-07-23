import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.results.isEmpty {
                    if viewModel.isSearching {
                        ProgressView()
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
                        NavigationLink(value: course) {
                            CourseRow(course: course)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Course name or city")
            .navigationDestination(for: Course.self) { course in
                CourseDetailView(course: course)
            }
        }
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
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
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
}
