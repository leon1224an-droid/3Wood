import Foundation
import Supabase

enum FeedRepo {
    static func feed() async throws -> [FeedItem] {
        try await supa.rpc("activity_feed").execute().value
    }

    /// Contributor rankings, all-time or for the current week.
    static func leaderboard(period: LeaderboardPeriod = .allTime) async throws -> [LeaderboardEntry] {
        try await supa.rpc("leaderboard", params: ["p_period": period.rpcValue])
            .execute()
            .value
    }

    /// Consecutive weeks in which the signed-in user added a new course.
    static func weekStreak() async throws -> Int {
        try await supa.rpc("streak_weeks").execute().value
    }
}

/// Which slice of the leaderboard to show.
enum LeaderboardPeriod: String, CaseIterable, Identifiable, Sendable {
    case week = "This Week"
    case allTime = "All Time"

    var id: String { rawValue }

    var rpcValue: String {
        switch self {
        case .week: "week"
        case .allTime: "all"
        }
    }
}
