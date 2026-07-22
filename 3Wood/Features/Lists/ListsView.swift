import SwiftUI

struct ListsView: View {
    @State private var ranked: [RankedCourse] = []
    @State private var isLoggingCourse = false

    var body: some View {
        NavigationStack {
            Group {
                if ranked.isEmpty {
                    ContentUnavailableView {
                        Label("No courses yet", systemImage: "figure.golf")
                    } description: {
                        Text("Courses you log will appear here, ranked.")
                    } actions: {
                        Button("Log your first course") { isLoggingCourse = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, course in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.name).lineLimit(1)
                                    Text(course.locationText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                ScoreBadge(score: course.score)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("My Courses")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isLoggingCourse = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fullScreenCover(isPresented: $isLoggingCourse, onDismiss: {
                Task { await reload() }
            }) {
                LogCourseFlow()
            }
            .task { await reload() }
            .onAppear {
                Task { await reload() }
            }
        }
    }

    private func reload() async {
        ranked = (try? await RankingRepo.myRankedCourses()) ?? ranked
    }
}

#Preview {
    ListsView()
}
