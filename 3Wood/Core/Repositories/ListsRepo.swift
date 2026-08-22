import Foundation
import Supabase

enum ListsRepo {
    static func myLists() async throws -> [CustomList] {
        try await supa.rpc("my_lists").execute().value
    }

    static func listCourses(listID: Int) async throws -> [ListCourse] {
        try await supa.rpc("list_courses", params: ["p_list_id": listID]).execute().value
    }

    /// Returns nil if the list doesn't exist or isn't visible to the caller
    /// (private and not the owner) — the RPC returns zero rows rather than
    /// erroring, matching `activity(p_activity_id)`'s style.
    static func detail(listID: Int) async throws -> CustomList? {
        let rows: [CustomList] = try await supa.rpc("list_detail", params: ["p_list_id": listID])
            .execute()
            .value
        return rows.first
    }

    static func exploreLists(limit: Int = 30, offset: Int = 0) async throws -> [CustomList] {
        struct Params: Encodable {
            let p_limit: Int
            let p_offset: Int
        }
        return try await supa.rpc("explore_lists", params: Params(p_limit: limit, p_offset: offset))
            .execute()
            .value
    }

    static func publicLists(of userID: UUID) async throws -> [CustomList] {
        try await supa.rpc("profile_public_lists", params: ["p_user_id": userID])
            .execute()
            .value
    }

    /// Lists the caller has bookmarked — the "find it again" surface
    /// bookmarking exists to serve.
    static func myBookmarkedLists() async throws -> [CustomList] {
        try await supa.rpc("my_bookmarked_lists").execute().value
    }

    static func create(title: String, description: String?, visibility: CustomList.Visibility) async throws -> Int {
        struct Params: Encodable {
            let p_title: String
            let p_description: String?
            let p_visibility: String
        }
        return try await supa.rpc("create_list", params: Params(
            p_title: title, p_description: description, p_visibility: visibility.rawValue
        )).execute().value
    }

    static func update(listID: Int, title: String, description: String?, visibility: CustomList.Visibility) async throws {
        struct Params: Encodable {
            let p_list_id: Int
            let p_title: String
            // Empty string clears the description server-side; nil (never
            // sent here) would mean "leave unchanged" — the editor always
            // has a value to send, even if it's "".
            let p_description: String
            let p_visibility: String
        }
        try await supa.rpc("update_list", params: Params(
            p_list_id: listID, p_title: title, p_description: description ?? "",
            p_visibility: visibility.rawValue
        )).execute()
    }

    static func delete(listID: Int) async throws {
        try await supa.rpc("delete_list", params: ["p_list_id": listID]).execute()
    }

    /// Returns how many of the requested courses were actually added — the
    /// server silently skips any the caller hasn't ranked.
    static func addCourses(listID: Int, courseIDs: [Int]) async throws -> Int {
        struct Params: Encodable {
            let p_list_id: Int
            let p_course_ids: [Int]
        }
        return try await supa.rpc("add_courses_to_list", params: Params(
            p_list_id: listID, p_course_ids: courseIDs
        )).execute().value
    }

    static func removeCourse(listID: Int, courseID: Int) async throws {
        struct Params: Encodable {
            let p_list_id: Int
            let p_course_id: Int
        }
        try await supa.rpc("remove_course_from_list", params: Params(
            p_list_id: listID, p_course_id: courseID
        )).execute()
    }

    static func toggleBookmark(listID: Int) async throws {
        try await supa.rpc("toggle_list_bookmark", params: ["p_list_id": listID]).execute()
    }

    static func comments(listID: Int) async throws -> [ActivityComment] {
        try await supa.rpc("list_comments", params: ["p_list_id": listID]).execute().value
    }

    static func addComment(listID: Int, body: String, parentCommentID: Int? = nil) async throws {
        struct Params: Encodable {
            let p_list_id: Int
            let p_body: String
            let p_parent_comment_id: Int?
        }
        try await supa.rpc("add_list_comment", params: Params(
            p_list_id: listID, p_body: body, p_parent_comment_id: parentCommentID
        )).execute()
    }

    static func deleteComment(id: Int) async throws {
        try await supa.from("list_comments").delete().eq("id", value: id).execute()
    }

    /// One tap toggles the caller's own presence in that emoji's chip —
    /// mirrors ActivityRepo.toggleCommentReaction, scoped to a list comment.
    static func toggleCommentReaction(commentID: Int, emoji: String) async throws {
        struct Params: Encodable {
            let p_comment_id: Int
            let p_emoji: String
        }
        try await supa.rpc("toggle_list_comment_reaction",
                           params: Params(p_comment_id: commentID, p_emoji: emoji))
            .execute()
    }
}
