import Foundation

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var username: String
    var displayName: String?
    var avatarURL: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }
}
