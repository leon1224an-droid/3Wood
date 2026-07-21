import Foundation
import Supabase

enum ProfileRepo {
    static func fetch(userID: UUID) async throws -> Profile? {
        let profiles: [Profile] = try await supa.from("profiles")
            .select()
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value
        return profiles.first
    }

    static func create(userID: UUID, username: String) async throws -> Profile {
        struct NewProfile: Encodable {
            let id: UUID
            let username: String
        }
        return try await supa.from("profiles")
            .insert(NewProfile(id: userID, username: username))
            .select()
            .single()
            .execute()
            .value
    }
}
