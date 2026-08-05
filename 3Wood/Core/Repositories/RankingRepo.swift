import Foundation
import Supabase

enum RankingRepo {
    static func myRankedCourses() async throws -> [RankedCourse] {
        try await supa.rpc("my_ranked_courses").execute().value
    }

    static func insert(courseID: Int, bucket: Bucket, position: Int) async throws {
        struct Params: Encodable {
            let p_course_id: Int
            let p_bucket: String
            let p_position: Int
        }
        try await supa.rpc(
            "insert_ranking",
            params: Params(p_course_id: courseID, p_bucket: bucket.rawValue, p_position: position)
        ).execute()
    }

    static func remove(courseID: Int) async throws {
        try await supa.rpc("remove_ranking", params: ["p_course_id": courseID]).execute()
    }
}

extension RankingRepo {
    /// The caller's rounds at a course, most recent first.
    static func visits(courseID: Int) async throws -> [CourseVisit] {
        try await supa.rpc("course_visits", params: ["p_course_id": courseID])
            .execute()
            .value
    }

    /// Records another round. Nil date means today.
    static func logVisit(courseID: Int, playedOn: Date? = nil) async throws {
        struct Params: Encodable {
            let p_course_id: Int
            let p_played_on: String?
        }
        try await supa.rpc("log_visit", params: Params(
            p_course_id: courseID,
            p_played_on: playedOn.map(PlayDate.string(from:))
        )).execute()
    }

    static func deleteVisit(id: Int) async throws {
        try await supa.rpc("delete_visit", params: ["p_id": id]).execute()
    }
}
