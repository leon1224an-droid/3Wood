import Foundation

/// One activity-feed entry: a friend (or you) ranked or saved a course.
struct FeedItem: Codable, Identifiable, Hashable, Sendable {
    let kind: String          // "ranked" | "want"
    let actorID: UUID
    let username: String
    let courseID: Int
    let courseName: String
    let city: String?
    let state: String?
    let score: Double?
    let bucket: Bucket?
    let createdAt: Date

    var id: String { "\(kind)-\(actorID)-\(courseID)-\(createdAt.timeIntervalSince1970)" }

    var isRanked: Bool { kind == "ranked" }

    var locationText: String {
        [city, state].compactMap(\.self).joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case kind, username, score, bucket
        case actorID = "actor_id"
        case courseID = "course_id"
        case courseName = "course_name"
        case city, state
        case createdAt = "created_at"
    }
}

/// One leaderboard row, ranked by courses logged.
struct LeaderboardEntry: Codable, Identifiable, Hashable, Sendable {
    let rank: Int
    let id: UUID
    let username: String
    let displayName: String?
    let played: Int
    let isMe: Bool

    enum CodingKeys: String, CodingKey {
        case rank, id, username, played
        case displayName = "display_name"
        case isMe = "is_me"
    }
}
