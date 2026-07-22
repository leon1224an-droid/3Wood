import Foundation

enum Bucket: String, Codable, CaseIterable, Identifiable, Sendable {
    case liked, fine, disliked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .liked: "Liked it"
        case .fine: "It was fine"
        case .disliked: "Didn't like it"
        }
    }

    var systemImage: String {
        switch self {
        case .liked: "hand.thumbsup.fill"
        case .fine: "minus.circle.fill"
        case .disliked: "hand.thumbsdown.fill"
        }
    }
}

/// Drives the head-to-head comparison flow: binary insertion of a new course
/// into the user's ordered bucket list (best first). Pure logic, no I/O.
struct RankingEngine {
    enum Answer {
        case preferNew        // new course beats the candidate
        case preferExisting   // candidate stays ahead
        case tooClose         // give up splitting: place just below candidate
    }

    /// The user's ranked courses in the chosen bucket, best (position 1) first.
    let bucketList: [RankedCourse]
    /// Insertion window [lo, hi) over bucketList indices.
    private(set) var lo: Int
    private(set) var hi: Int

    init(bucketList: [RankedCourse]) {
        self.bucketList = bucketList
        lo = 0
        hi = bucketList.count
    }

    var isFinished: Bool { lo >= hi }

    /// The course to show as the head-to-head opponent (window midpoint).
    var candidate: RankedCourse? {
        isFinished ? nil : bucketList[(lo + hi) / 2]
    }

    /// Where the new course lands (1-based rank_position) once finished.
    var insertionPosition: Int { lo + 1 }

    /// Upper bound on comparisons still to answer — for a progress hint.
    var maxComparisonsRemaining: Int {
        let window = hi - lo
        return window <= 0 ? 0 : Int(ceil(log2(Double(window + 1))))
    }

    mutating func answer(_ answer: Answer) {
        guard !isFinished else { return }
        let mid = (lo + hi) / 2
        switch answer {
        case .preferNew:
            hi = mid
        case .preferExisting:
            lo = mid + 1
        case .tooClose:
            lo = mid + 1
            hi = lo
        }
    }
}

/// The 0-10 score formula — must stay identical to the SQL view
/// `user_course_scores` (see supabase/migrations/00040000000000_rankings.sql).
enum ScoreMath {
    static func range(of bucket: Bucket) -> (hi: Double, width: Double) {
        switch bucket {
        case .liked: (10.0, 3.3)
        case .fine: (6.6, 3.2)
        case .disliked: (3.3, 3.3)
        }
    }

    /// Score for the course at `position` (1-based) in a bucket of `bucketCount`.
    static func score(position: Int, bucketCount: Int, bucket: Bucket) -> Double {
        let (hi, width) = range(of: bucket)
        let raw = hi - width * (Double(position) - 0.5) / Double(bucketCount)
        return (raw * 10).rounded() / 10
    }
}
