import Foundation

/// A comment on someone's feed activity.
struct ActivityComment: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let userID: UUID
    let username: String
    let body: String
    let createdAt: Date
    let isMine: Bool
    /// Nil for a top-level comment. One level deep only — a reply can't
    /// itself be replied to.
    var parentCommentID: Int?
    var reactions: [ReactionSummary] = []

    enum CodingKeys: String, CodingKey {
        case id, username, body, reactions
        case userID = "user_id"
        case createdAt = "created_at"
        case isMine = "is_mine"
        case parentCommentID = "parent_comment_id"
    }

    /// Applies a reaction tap locally so the chip row moves before the
    /// network answers. Mirrors FeedItem.applyToggle, scoped to a comment.
    mutating func applyReactionToggle(_ emoji: String) {
        if let i = reactions.firstIndex(where: { $0.emoji == emoji }) {
            let chip = reactions[i]
            if chip.mine {
                if chip.count <= 1 {
                    reactions.remove(at: i)
                } else {
                    reactions[i] = ReactionSummary(emoji: emoji, count: chip.count - 1, mine: false)
                }
            } else {
                reactions[i] = ReactionSummary(emoji: emoji, count: chip.count + 1, mine: true)
            }
        } else {
            reactions.append(ReactionSummary(emoji: emoji, count: 1, mine: true))
        }
    }
}

/// One entry in the alert feed: a new follower, or engagement on your
/// activity or a list of yours.
struct AppNotification: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    // "follow" | "comment" | "reaction" | "tag" | "mention" | "list_bookmark" |
    // "list_comment" | "comment_reply" | "comment_reaction"
    let kind: String
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
