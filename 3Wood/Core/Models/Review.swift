import Foundation

struct Review: Codable, Identifiable, Hashable, Sendable {
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
