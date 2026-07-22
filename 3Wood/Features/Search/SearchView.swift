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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .lineLimit(1)
                Text(course.locationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ScoreBadge(score: course.avgScore)
        }
    }
}

#Preview {
    SearchView()
}
