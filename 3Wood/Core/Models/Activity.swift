import Foundation

/// A comment on someone's feed activity.
struct ActivityComment: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let userID: UUID
    let username: String
    let body: String
    let createdAt: Date
    let isMine: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, body
        case userID = "user_id"
        case createdAt = "created_at"
        case isMine = "is_mine"
    }
}

/// One entry in the alert feed: a new follower, or engagement on your
/// activity or a list of yours.
struct AppNotification: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let kind: String            // "follow" | "comment" | "reaction" | "tag" | "mention" | "list_like" | "list_comment"
    let actorID: UUID
    let actorUsername: String
    let activityID: Int?
    let courseID: Int?
    let courseName: String?
    let emoji: String?
    let commentBody: String?
    let listID: Int?
    let listTitle: String?
    let readAt: Date?
    let createdAt: Date

    var isUnread: Bool { readAt == nil }

    enum CodingKeys: String, CodingKey {
        case id, kind, emoji
        case actorID = "actor_id"
        case actorUsername = "actor_username"
        case activityID = "activity_id"
        case courseID = "course_id"
        case courseName = "course_name"
        case commentBody = "comment_body"
        case listID = "list_id"
        case listTitle = "list_title"
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

/// The reaction palette. Golf-native rather than generic likes — a blow-up
/// round deserves 💀, not a thumbs up.
enum Reaction {
    /// Kept free of variation selectors so what the app writes is byte-identical
    /// to what it groups on when reading back.
    static let all = ["⛳", "🔥", "🦅", "👏", "😂", "💀"]

    static func label(for emoji: String) -> String {
        switch emoji {
        case "⛳": "Nice track"
        case "🔥": "On fire"
        case "🦅": "Eagle"
        case "👏": "Well played"
        case "😂": "Funny"
        case "💀": "Blow-up round"
        default: "Reaction"
        }
    }
}
