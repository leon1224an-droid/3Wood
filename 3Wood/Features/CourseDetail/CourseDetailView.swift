import SwiftUI
import MapKit

struct CourseDetailView: View {
    let course: Course

    @State private var myRanking: RankedCourse?
    @State private var isLoggingCourse = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.name)
                        .font(.title2.bold())
                    Text(course.locationText)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if let holes = course.holes {
                            Label("\(holes) holes", systemImage: "flag")
                        }
                        if let type = course.courseType {
                            Label(type.capitalized, systemImage: "building.columns")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                // Your score (once ranked)
                if let myRanking {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Your score")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("#\(myRanking.rankPosition) of your \"\(myRanking.bucket.label)\" courses")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        ScoreBadge(score: myRanking.score)
                    }
                    .padding()
                    .background(Color.fairwayGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                // Community rating card
                HStack {
                    VStack(alignment: .leading) {
                        Text("Community rating")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if course.ratingCount > 0 {
                            Text("^[\(course.ratingCount) rating](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("No ratings yet — be the first!")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    ScoreBadge(score: course.avgScore)
                }
                .padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    isLoggingCourse = true
                } label: {
                    Label(myRanking == nil ? "Log this course" : "Re-rank this course",
                          systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.fairwayGreen)

                // Map snippet
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: course.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))) {
                    Marker(course.name, coordinate: course.coordinate)
                        .tint(Color.fairwayGreen)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
            }
            .padding()
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isLoggingCourse, onDismiss: {
            Task { await reloadMyRanking() }
        }) {
            LogCourseFlow(course: course)
        }
        .task { await reloadMyRanking() }
    }

    private func reloadMyRanking() async {
        let mine = try? await RankingRepo.myRankedCourses()
        myRanking = mine?.first { $0.courseID == course.id }
    }
}
