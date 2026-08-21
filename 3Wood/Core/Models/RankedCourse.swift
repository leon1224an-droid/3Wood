import Foundation

/// A row of the user's ranked list, as returned by the my_ranked_courses RPC.
struct RankedCourse: Codable, Identifiable, Hashable, Sendable {
    let courseID: Int
    let name: String
    let city: String?
    let state: String?
    /// public / private / resort / municipal… — used by the custom-list
    /// picker's type filter. Optional for the same reason as the fields
    /// below: only my_ranked_courses returns it.
    var courseType: String?
    let bucket: Bucket
    let rankPosition: Int
    let score: Double
    /// When the course was logged. Optional: only my_ranked_courses returns
    /// it (user_ranked_courses and older backends omit it).
    var createdAt: Date?
    /// When this course was last played, and how many rounds in total.
    /// Optional for the same reason as createdAt — only my_ranked_courses
    /// returns them.
    var lastPlayedOn: String?
    var visitCount: Int?

    var id: Int { courseID }

    enum CodingKeys: String, CodingKey {
        case courseID = "course_id"
        case name, city, state, bucket, score
        case courseType = "course_type"
        case rankPosition = "rank_position"
        case createdAt = "created_at"
        case lastPlayedOn = "last_played_on"
        case visitCount = "visit_count"
    }

    var locationText: String {
        [city, state].compactMap(\.self).joined(separator: ", ")
    }

    /// A short access-type label, e.g. "public/municipal" → "Public" — same
    /// recipe as `Course.shortType`.
    var shortType: String? {
        guard let type = courseType, !type.isEmpty else { return nil }
        let primary = type.split(separator: "/").first.map(String.init) ?? type
        return primary.capitalized
    }
}
