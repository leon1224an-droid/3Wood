import Foundation

/// One activity-feed entry: a friend (or you) ranked or saved a course.
///
/// Backed by a real `activities` row since migration 00180, so it carries a
/// server id that reactions and comments can hang off. It used to synthesise
/// one client-side, which is precisely why nothing could attach to it.
struct FeedItem: Codable, Identifiable, Hashable, Sendable {
    let activityID: Int
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
    // var so a tapped reaction can move immediately instead of waiting on a
    // round trip; the server is still the authority on the next reload.
    var reactionCount: Int
    var commentCount: Int
    var myReaction: String?
    var topEmojis: [String]?

    var id: Int { activityID }

    var isRanked: Bool { kind == "ranked" }

    var locationText: String {
        [city, state].compactMap(\.self).joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case kind, username, score, bucket, city, state
        case activityID = "activity_id"
        case actorID = "actor_id"
        case courseID = "course_id"
        case courseName = "course_name"
        case createdAt = "created_at"
        case reactionCount = "reaction_count"
        case commentCount = "comment_count"
        case myReaction = "my_reaction"
        case topEmojis = "top_emojis"
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
