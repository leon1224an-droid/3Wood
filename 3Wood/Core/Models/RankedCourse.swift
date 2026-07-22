import Foundation

/// A row of the user's ranked list, as returned by the my_ranked_courses RPC.
struct RankedCourse: Codable, Identifiable, Hashable, Sendable {
    let courseID: Int
    let name: String
    let city: String?
    let state: String?
    let bucket: Bucket
    let rankPosition: Int
    let score: Double

    var id: Int { courseID }

    enum CodingKeys: String, CodingKey {
        case courseID = "course_id"
        case name, city, state, bucket, score
        case rankPosition = "rank_position"
    }

    var locationText: String {
        [city, state].compactMap(\.self).joined(separator: ", ")
    }
}
