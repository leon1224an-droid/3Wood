import Foundation
import Testing
@testable import ThreeWood

private func makeList(_ count: Int, bucket: Bucket = .liked) -> [RankedCourse] {
    (1...max(count, 0)).map { i in
        RankedCourse(
            courseID: i, name: "Course \(i)", city: nil, state: nil,
            bucket: bucket, rankPosition: i,
            score: ScoreMath.score(position: i, bucketCount: count, bucket: bucket)
        )
    }
}

struct RankingEngineTests {
    @Test func emptyBucketFinishesImmediately() {
        let engine = RankingEngine(bucketList: [])
        #expect(engine.isFinished)
        #expect(engine.insertionPosition == 1)
        #expect(engine.candidate == nil)
    }

    @Test func singleCourseBucket() {
        var engine = RankingEngine(bucketList: makeList(1))
        #expect(engine.candidate?.courseID == 1)
        engine.answer(.preferNew)
        #expect(engine.isFinished)
        #expect(engine.insertionPosition == 1)

        engine = RankingEngine(bucketList: makeList(1))
        engine.answer(.preferExisting)
        #expect(engine.isFinished)
        #expect(engine.insertionPosition == 2)
    }

    @Test func insertAtTopOfSeven() {
        var engine = RankingEngine(bucketList: makeList(7))
        var comparisons = 0
        while !engine.isFinished {
            engine.answer(.preferNew)
            comparisons += 1
        }
        #expect(engine.insertionPosition == 1)
        #expect(comparisons == 3) // ceil(log2(8))
    }

    @Test func insertAtBottomOfSeven() {
        var engine = RankingEngine(bucketList: makeList(7))
        var comparisons = 0
        while !engine.isFinished {
            engine.answer(.preferExisting)
            comparisons += 1
        }
        #expect(engine.insertionPosition == 8)
        #expect(comparisons == 3)
    }

    @Test func tooCloseLandsJustBelowCandidate() {
        var engine = RankingEngine(bucketList: makeList(7))
        let candidate = engine.candidate
        #expect(candidate?.rankPosition == 4) // midpoint of 7
        engine.answer(.tooClose)
        #expect(engine.isFinished)
        #expect(engine.insertionPosition == 5) // directly below the candidate
    }

    /// Simulate a rater with a fixed target slot: the engine must land exactly
    /// there, within the log2 comparison bound, for every slot of every size.
    @Test(arguments: [1, 2, 3, 7, 10, 50, 100])
    func binaryInsertionFindsEverySlot(count: Int) {
        let list = makeList(count)
        let bound = Int(ceil(log2(Double(count + 1))))
        for target in 1...(count + 1) {
            var engine = RankingEngine(bucketList: list)
            var comparisons = 0
            while let candidate = engine.candidate {
                // New course belongs above `candidate` iff target <= its position.
                engine.answer(target <= candidate.rankPosition ? .preferNew : .preferExisting)
                comparisons += 1
            }
            #expect(engine.insertionPosition == target)
            #expect(comparisons <= bound)
        }
    }

    /// Fixtures verified against the SQL view in Postgres (psql, 2026-07-21):
    /// the Swift and SQL formulas must agree to the displayed decimal.
    @Test func scoreFormulaMatchesSQLFixtures() {
        #expect(ScoreMath.score(position: 1, bucketCount: 1, bucket: .liked) == 8.4)
        #expect(ScoreMath.score(position: 1, bucketCount: 2, bucket: .liked) == 9.2)
        #expect(ScoreMath.score(position: 2, bucketCount: 2, bucket: .liked) == 7.5)
        #expect(ScoreMath.score(position: 1, bucketCount: 3, bucket: .liked) == 9.5)
        #expect(ScoreMath.score(position: 2, bucketCount: 3, bucket: .liked) == 8.4)
        #expect(ScoreMath.score(position: 3, bucketCount: 3, bucket: .liked) == 7.3)
        #expect(ScoreMath.score(position: 1, bucketCount: 1, bucket: .fine) == 5.0)
        #expect(ScoreMath.score(position: 1, bucketCount: 1, bucket: .disliked) == 1.7)
    }

    /// Scores stay inside their bucket's range so buckets never overlap.
    @Test(arguments: Bucket.allCases)
    func scoresStayWithinBucketRange(bucket: Bucket) {
        let (hi, width) = ScoreMath.range(of: bucket)
        for count in [1, 2, 5, 20, 200] {
            for position in 1...count {
                let score = ScoreMath.score(position: position, bucketCount: count, bucket: bucket)
                #expect(score <= hi)
                // Rounding can land exactly on the boundary (e.g. 6.70825 -> 6.7),
                // which is still above the next bucket's 1-decimal ceiling.
                #expect(score >= ((hi - width) * 10).rounded() / 10)
            }
        }
    }
}
