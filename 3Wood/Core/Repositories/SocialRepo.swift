import Foundation
import Supabase

enum SocialRepo {
    static func searchProfiles(_ query: String) async throws -> [ProfileSummary] {
        try await supa.rpc("search_profiles", params: ["p_query": query])
            .execute()
            .value
    }

    static func follow(userID: UUID) async throws {
        struct Row: Encodable {
            let follower_id: UUID
            let followee_id: UUID
        }
        guard let me = supa.auth.currentSession?.user.id else { return }
        try await supa.from("follows")
            .insert(Row(follower_id: me, followee_id: userID))
            .execute()
    }

    static func unfollow(userID: UUID) async throws {
        guard let me = supa.auth.currentSession?.user.id else { return }
        try await supa.from("follows")
            .delete()
            .eq("follower_id", value: me)
            .eq("followee_id", value: userID)
            .execute()
    }

    static func rankedCourses(of userID: UUID) async throws -> [RankedCourse] {
        try await supa.rpc("user_ranked_courses", params: ["p_user_id": userID])
            .execute()
            .value
    }

    static func friendScores(courseID: Int) async throws -> [FriendScore] {
        try await supa.rpc("friend_scores", params: ["p_course_id": courseID])
            .execute()
            .value
    }

    static func stats(of userID: UUID) async throws -> ProfileStats {
        let rows: [ProfileStats] = try await supa.rpc("profile_stats", params: ["p_user_id": userID])
            .execute()
            .value
        return rows.first ?? ProfileStats(played: 0, followers: 0, following: 0)
    }
}
