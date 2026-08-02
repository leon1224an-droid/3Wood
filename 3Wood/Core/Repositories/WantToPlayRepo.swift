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
        // Idempotent: swipe-to-save rows in search/map results don't know
        // whether a course is already bookmarked, and the (user_id, course_id)
        // primary key would reject the second insert as an error — which it
        // isn't, from the user's side. `ignoreDuplicates` keeps this an
        // INSERT ... ON CONFLICT DO NOTHING, so it needs no UPDATE grant.
        try await supa.from("want_to_play")
            .upsert(
                Row(user_id: userID, course_id: courseID),
                onConflict: "user_id,course_id",
                ignoreDuplicates: true
            )
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
