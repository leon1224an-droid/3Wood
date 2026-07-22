import Foundation

/// A row from search_profiles: another user + whether the caller follows them.
struct ProfileSummary: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let username: String
    let displayName: String?
    var isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case isFollowing = "is_following"
    }
}

struct FriendScore: Codable, Identifiable, Hashable, Sendable {
    let userID: UUID
    let username: String
    let score: Double

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username, score
    }
}

struct ProfileStats: Codable, Sendable {
    let played: Int
    let followers: Int
    let following: Int
}
