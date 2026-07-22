import Foundation
import Supabase

enum WantToPlayRepo {
    static func list() async throws -> [Course] {
        try await supa.rpc("my_want_to_play").execute().value
    }

    static func contains(courseID: Int) async throws -> Bool {
        guard let userID = supa.auth.currentSession?.user.id else { return false }
        let rows: [[String: Int]] = try await supa.from("want_to_play")
            .select("course_id")
            .eq("user_id", value: userID)
            .eq("course_id", value: courseID)
            .execute()
            .value
        return !rows.isEmpty
    }

    static func add(courseID: Int) async throws {
        struct Row: Encodable {
            let user_id: UUID
            let course_id: Int
        }
        guard let userID = supa.auth.currentSession?.user.id else { return }
        try await supa.from("want_to_play")
            .insert(Row(user_id: userID, course_id: courseID))
            .execute()
    }

    static func remove(courseID: Int) async throws {
        guard let userID = supa.auth.currentSession?.user.id else { return }
        try await supa.from("want_to_play")
            .delete()
            .eq("user_id", value: userID)
            .eq("course_id", value: courseID)
            .execute()
    }
}
