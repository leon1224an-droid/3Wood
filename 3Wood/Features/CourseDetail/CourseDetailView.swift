import SwiftUI
import MapKit

struct CourseDetailView: View {
    let course: Course

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
    }
}
