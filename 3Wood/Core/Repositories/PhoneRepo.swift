import Foundation
import Supabase

/// A contact-book match: someone on 3Wood whose linked number is in the
/// caller's contacts. `phone` echoes the matched number so the UI can show
/// which contact this is.
struct ContactMatch: Decodable, Sendable {
    let id: UUID
    let username: String
    let displayName: String?
    let isFollowing: Bool
    let phone: String

    var person: ProfileSummary {
        ProfileSummary(id: id, username: username, displayName: displayName, isFollowing: isFollowing)
    }

    enum CodingKeys: String, CodingKey {
        case id, username, phone
        case displayName = "display_name"
        case isFollowing = "is_following"
    }
}

enum PhoneRepo {
    /// The caller's linked number, if any (RLS scopes the table to own row).
    static func myPhone() async throws -> String? {
        struct Row: Decodable { let phone: String }
        let rows: [Row] = try await supa.from("profile_phones")
            .select("phone")
            .execute()
            .value
        return rows.first?.phone
    }

    /// Link (E.164) or unlink (nil) the caller's number.
    static func setPhone(_ phone: String?) async throws {
        struct Params: Encodable { let p_phone: String? }
        try await supa.rpc("set_my_phone", params: Params(p_phone: phone)).execute()
    }

    /// Which of these numbers belong to 3Wood users. Chunked so huge contact
    /// books don't exceed request limits.
    static func matchContacts(_ phones: [String]) async throws -> [ContactMatch] {
        var matches: [ContactMatch] = []
        for chunk in stride(from: 0, to: phones.count, by: 300) {
            let slice = Array(phones[chunk..<min(chunk + 300, phones.count)])
            let found: [ContactMatch] = try await supa
                .rpc("match_contacts", params: ["p_phones": slice])
                .execute()
                .value
            matches.append(contentsOf: found)
        }
        return matches
    }
}
