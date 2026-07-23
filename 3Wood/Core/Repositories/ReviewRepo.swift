import Foundation
import Supabase

enum ReviewRepo {
    static func reviews(courseID: Int) async throws -> [Review] {
        try await supa.rpc("course_reviews", params: ["p_course_id": courseID])
            .execute()
            .value
    }

    static func upsert(courseID: Int, body: String) async throws {
        struct Params: Encodable {
            let p_course_id: Int
            let p_body: String
        }
        try await supa.rpc("upsert_review", params: Params(p_course_id: courseID, p_body: body))
            .execute()
    }

    static func delete(courseID: Int) async throws {
        try await supa.rpc("delete_review", params: ["p_course_id": courseID]).execute()
    }
}
