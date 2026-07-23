import Foundation
import Supabase

enum FeedRepo {
    static func feed() async throws -> [FeedItem] {
        try await supa.rpc("activity_feed").execute().value
    }

    static func leaderboard() async throws -> [LeaderboardEntry] {
        try await supa.rpc("leaderboard").execute().value
    }
}
