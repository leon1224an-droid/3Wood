import Foundation
import Supabase

/// Reactions, comments and the notification inbox.
enum ActivityRepo {
    /// Sets, swaps, or clears the caller's reaction — sending the emoji you
    /// already have removes it, so one call covers every case.
    static func toggleReaction(activityID: Int, emoji: String) async throws {
        struct Params: Encodable {
            let p_activity_id: Int
            let p_emoji: String
        }
        try await supa.rpc("toggle_reaction", params: Params(p_activity_id: activityID, p_emoji: emoji))
            .execute()
    }

    static func comments(activityID: Int) async throws -> [ActivityComment] {
        try await supa.rpc("activity_comments", params: ["p_activity_id": activityID])
            .execute()
            .value
    }

    static func addComment(activityID: Int, body: String, parentCommentID: Int? = nil) async throws {
        struct Params: Encodable {
            let p_activity_id: Int
            let p_body: String
            let p_parent_comment_id: Int?
        }
        try await supa.rpc("add_comment", params: Params(
            p_activity_id: activityID, p_body: body, p_parent_comment_id: parentCommentID
        )).execute()
    }

    static func deleteComment(id: Int) async throws {
        try await supa.from("activity_comments").delete().eq("id", value: id).execute()
    }

    /// One tap toggles the caller's own presence in that emoji's chip —
    /// mirrors toggleReaction, scoped to a comment instead of an activity.
    static func toggleCommentReaction(commentID: Int, emoji: String) async throws {
        struct Params: Encodable {
            let p_comment_id: Int
            let p_emoji: String
        }
        try await supa.rpc("toggle_activity_comment_reaction",
                           params: Params(p_comment_id: commentID, p_emoji: emoji))
            .execute()
    }

    static func notifications() async throws -> [AppNotification] {
        try await supa.rpc("notifications").execute().value
    }

    static func unreadCount() async throws -> Int {
        try await supa.rpc("unread_notification_count").execute().value
    }

    static func markAllRead() async throws {
        try await supa.rpc("mark_notifications_read").execute()
    }
}

extension ActivityRepo {
    /// One activity by id — the alert feed deep-links here.
    static func activity(id: Int) async throws -> FeedItem? {
        let rows: [FeedItem] = try await supa.rpc("activity", params: ["p_activity_id": id])
            .execute()
            .value
        return rows.first
    }
}

extension ActivityRepo {
    /// Replaces the playing partners named on your own activity. The server
    /// ignores anyone you don't follow.
    static func setTags(activityID: Int, userIDs: [UUID]) async throws {
        struct Params: Encodable {
            let p_activity_id: Int
            let p_user_ids: [UUID]
        }
        try await supa.rpc("set_activity_tags",
                           params: Params(p_activity_id: activityID, p_user_ids: userIDs))
            .execute()
    }

    /// The activity just created for a course — used by the ranking flow to
    /// attach playing partners once the ranking is saved.
    static func myActivity(courseID: Int) async throws -> FeedItem? {
        let rows: [FeedItem] = try await supa.rpc("activity_feed").execute().value
        guard let me = supa.auth.currentSession?.user.id else { return nil }
        return rows.first { $0.courseID == courseID && $0.actorID == me && $0.isRanked }
    }
}
