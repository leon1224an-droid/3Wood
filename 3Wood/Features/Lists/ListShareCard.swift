import SwiftUI

/// The branded, off-screen card rendered to an image for sharing outside the
/// app. Fixed size, text-and-shapes only (no course photos) — kept simple
/// for a first iteration, and it sidesteps ImageRenderer's trouble with
/// async-loaded content.
struct ListShareCard: View {
    let list: CustomList
    let courses: [ListCourse]

    /// Points; rendered at scale 3 for a 1080×1350 export.
    static let size = CGSize(width: 360, height: 450)

    private let maxRows = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(size: 20)
                .padding(.bottom, 14)

            Text(list.title)
                .font(.title3.bold())
                .foregroundStyle(Color.darkPine)
                .lineLimit(2)

            if let username = list.ownerUsername {
                Text("@\(username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            Rectangle()
                .fill(Color.sand)
                .frame(height: 1)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(courses.prefix(maxRows).enumerated()), id: \.element.id) { index, course in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(course.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        ScoreBadge(score: course.score, compact: true)
                    }
                }
            }

            if courses.count > maxRows {
                Text("+\(courses.count - maxRows) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }

            Spacer(minLength: 0)

            Text("Ranked on 3Wood")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.fairwayGreen)
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.cream)
    }
}
