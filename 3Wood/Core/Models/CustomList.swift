import Foundation

/// A user-curated, ranked sub-list of courses they've already played and
/// ranked. Optional fields differ by which RPC returned the row — `my_lists`
/// omits owner/liked-by-me (it's always the caller's own), `list_detail`/
/// `explore_lists`/`profile_public_lists` include them. Same reasoning as
/// `RankedCourse`'s optionals.
struct CustomList: Codable, Identifiable, Hashable, Sendable {
    enum Visibility: String, Codable, Sendable {
        case `private`, `public`
    }

    let id: Int
    var title: String
    var description: String?
    var visibility: Visibility
    var ownerID: UUID?
    var ownerUsername: String?
    var isMine: Bool?
    var bookmarkedByMe: Bool?
    var courseCount: Int
    var bookmarkCount: Int
    var commentCount: Int
    var createdAt: Date?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, visibility
        case ownerID = "owner_id"
        case ownerUsername = "owner_username"
        case isMine = "is_mine"
        case bookmarkedByMe = "bookmarked_by_me"
        case courseCount = "course_count"
        case bookmarkCount = "bookmark_count"
        case commentCount = "comment_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// One ranked course row in a list, as returned by `list_courses`. Not the
/// full `RankedCourse` — bucket/rank_position are the owner's private
/// bookkeeping, meaningless to someone viewing a public list.
struct ListCourse: Codable, Identifiable, Hashable, Sendable {
    let courseID: Int
    let name: String
    let city: String?
    let state: String?
    let score: Double
    let addedAt: Date

    var id: Int { courseID }

    enum CodingKeys: String, CodingKey {
        case courseID = "course_id"
        case name, city, state, score
        case addedAt = "added_at"
    }

    var locationText: String {
        [city, state].compactMap(\.self).joined(separator: ", ")
    }
}
