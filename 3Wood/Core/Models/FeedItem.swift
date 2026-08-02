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
    /// One chip per emoji, busiest first, each knowing whether you're in it.
    var reactions: [ReactionSummary]
    /// Playing partners named on this round.
    var taggedUsernames: [String]?

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
        case reactions
        case taggedUsernames = "tagged_usernames"
    }

    /// Applies a reaction tap locally so the chip row moves before the network
    /// answers. Mirrors what toggle_reaction does server-side.
    mutating func applyToggle(_ emoji: String) {
        if let i = reactions.firstIndex(where: { $0.emoji == emoji }) {
            let chip = reactions[i]
            if chip.mine {
                reactionCount = max(0, reactionCount - 1)
                if chip.count <= 1 {
                    reactions.remove(at: i)
                } else {
                    reactions[i] = ReactionSummary(emoji: emoji, count: chip.count - 1, mine: false)
                }
            } else {
                reactionCount += 1
                reactions[i] = ReactionSummary(emoji: emoji, count: chip.count + 1, mine: true)
            }
        } else {
            reactions.append(ReactionSummary(emoji: emoji, count: 1, mine: true))
            reactionCount += 1
        }
    }
}

/// One emoji chip: how many people used it, and whether you're one of them.
struct ReactionSummary: Codable, Hashable, Sendable, Identifiable {
    let emoji: String
    let count: Int
    let mine: Bool

    var id: String { emoji }
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
