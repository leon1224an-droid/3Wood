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

    static func addComment(activityID: Int, body: String) async throws {
        struct Params: Encodable {
            let p_activity_id: Int
            let p_body: String
        }
        try await supa.rpc("add_comment", params: Params(p_activity_id: activityID, p_body: body))
            .execute()
    }

    static func deleteComment(id: Int) async throws {
        try await supa.from("activity_comments").delete().eq("id", value: id).execute()
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
