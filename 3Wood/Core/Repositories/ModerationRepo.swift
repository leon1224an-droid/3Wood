import Foundation
import Supabase

enum ModerationRepo {
    /// Report a user, a review (author + course identifies it), a comment,
    /// a photo, a list, or a list comment.
    static func report(
        userID: UUID? = nil, reviewCourseID: Int? = nil,
        commentID: Int? = nil, photoID: Int? = nil,
        listID: Int? = nil, listCommentID: Int? = nil, reason: String
    ) async throws {
        struct Row: Encodable {
            let reported_user: UUID?
            let review_course_id: Int?
            let comment_id: Int?
            let photo_id: Int?
            let list_id: Int?
            let list_comment_id: Int?
            let reason: String
        }
        try await supa.from("reports")
            .insert(Row(
                reported_user: userID, review_course_id: reviewCourseID,
                comment_id: commentID, photo_id: photoID,
                list_id: listID, list_comment_id: listCommentID, reason: reason
            ))
            .execute()
    }

    /// Blocking also files a report — Guideline 1.2 requires that blocking an
    /// abusive user notify us of the content, not just hide it from the blocker.
    static func block(userID: UUID) async throws {
        struct Row: Encodable { let blocked: UUID }
        try await supa.from("blocked_users").insert(Row(blocked: userID)).execute()
        try? await report(userID: userID, reason: "blocked-by-user")
    }

    static func unblock(userID: UUID) async throws {
        try await supa.from("blocked_users").delete()
            .eq("blocked", value: userID)
            .execute()
    }

    static func isBlocked(userID: UUID) async throws -> Bool {
        struct Row: Decodable { let blocked: UUID }
        let rows: [Row] = try await supa.from("blocked_users").select("blocked")
            .eq("blocked", value: userID)
            .execute()
            .value
        return !rows.isEmpty
    }
}
