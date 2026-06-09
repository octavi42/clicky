//
//  MemoryDedupEvalTests.swift
//  leanring-buddyTests
//
//  Offline eval harness for preference/routine dedup threshold tuning.
//

import Foundation
import Testing
@testable import leanring_buddy

private struct DedupEvalFixture: Decodable {
    let pairs: [DedupEvalPair]
}

private struct DedupEvalPair: Decodable {
    let id: String
    let newTopic: String
    let existingMemory: DedupEvalExistingMemory
    let bundleId: String?
    let expectedDecision: String
}

private struct DedupEvalExistingMemory: Decodable {
    let title: String
    let summary: String
    let body: String
}

private struct DedupThresholdMetrics {
    let threshold: Double
    let precision: Double
    let recall: Double
    let f05Score: Double
    let falseMergeCount: Int
}

@Suite(.serialized)
struct MemoryDedupEvalTests {
    private func loadEvalPairs() throws -> [DedupEvalPair] {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/dedup-eval-pairs.json")

        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixture = try JSONDecoder().decode(DedupEvalFixture.self, from: fixtureData)
        return fixture.pairs
    }

    private func makeExistingMemory(
        from existingMemory: DedupEvalExistingMemory,
        bundleId: String?,
        pairId: String
    ) -> Memory {
        Memory(
            id: "eval-\(pairId)",
            category: .preference,
            title: existingMemory.title,
            summary: existingMemory.summary,
            body: existingMemory.body,
            bundleIds: bundleId.map { [$0] } ?? [],
            status: .active
        )
    }

    @MainActor
    private func predictedDecision(
        for pair: DedupEvalPair,
        scorerKind: MemorySimilarityScorerKind,
        mergeThreshold: Double
    ) -> String {
        let existingMemory = makeExistingMemory(
            from: pair.existingMemory,
            bundleId: pair.bundleId,
            pairId: pair.id
        )

        let match = AuxiliaryMemoryMatcher.decideDedup(
            newTopic: pair.newTopic,
            category: .preference,
            bundleId: pair.bundleId,
            existingMemories: [existingMemory],
            scorerKind: scorerKind,
            mergeThreshold: mergeThreshold
        )

        return match == nil ? "separate" : "merge"
    }

    @MainActor
    private func evaluateProductionConfiguration(pairs: [DedupEvalPair]) -> DedupThresholdMetrics {
        var truePositiveCount = 0
        var falsePositiveCount = 0
        var falseNegativeCount = 0

        for pair in pairs {
            let expectedMerge = pair.expectedDecision == "merge"
            let predictedMerge = predictedDecision(
                for: pair,
                scorerKind: MemoryDedupConfiguration.productionScorerKind,
                mergeThreshold: MemoryDedupConfiguration.mergeThreshold
            ) == "merge"

            switch (predictedMerge, expectedMerge) {
            case (true, true):
                truePositiveCount += 1
            case (true, false):
                falsePositiveCount += 1
            case (false, true):
                falseNegativeCount += 1
            case (false, false):
                break
            }
        }

        let precision = truePositiveCount + falsePositiveCount > 0
            ? Double(truePositiveCount) / Double(truePositiveCount + falsePositiveCount)
            : 0
        let recall = truePositiveCount + falseNegativeCount > 0
            ? Double(truePositiveCount) / Double(truePositiveCount + falseNegativeCount)
            : 0
        let beta = 0.5
        let betaSquared = beta * beta
        let f05Score = precision + recall > 0
            ? (1 + betaSquared) * precision * recall / (betaSquared * precision + recall)
            : 0

        return DedupThresholdMetrics(
            threshold: MemoryDedupConfiguration.mergeThreshold,
            precision: precision,
            recall: recall,
            f05Score: f05Score,
            falseMergeCount: falsePositiveCount
        )
    }

    @MainActor
    private func sweepLexicalThresholds(pairs: [DedupEvalPair]) -> DedupThresholdMetrics? {
        let minimumPrecision = 0.90
        var bestMetrics: DedupThresholdMetrics?

        var threshold = 0.30
        while threshold <= 0.95 + 0.0001 {
            var truePositiveCount = 0
            var falsePositiveCount = 0
            var falseNegativeCount = 0

            for pair in pairs {
                let expectedMerge = pair.expectedDecision == "merge"
                let predictedMerge = predictedDecision(
                    for: pair,
                    scorerKind: .lexicalDice,
                    mergeThreshold: threshold
                ) == "merge"

                switch (predictedMerge, expectedMerge) {
                case (true, true): truePositiveCount += 1
                case (true, false): falsePositiveCount += 1
                case (false, true): falseNegativeCount += 1
                case (false, false): break
                }
            }

            let precision = truePositiveCount + falsePositiveCount > 0
                ? Double(truePositiveCount) / Double(truePositiveCount + falsePositiveCount)
                : 0
            let recall = truePositiveCount + falseNegativeCount > 0
                ? Double(truePositiveCount) / Double(truePositiveCount + falseNegativeCount)
                : 0
            let beta = 0.5
            let betaSquared = beta * beta
            let f05Score = precision + recall > 0
                ? (1 + betaSquared) * precision * recall / (betaSquared * precision + recall)
                : 0

            let metrics = DedupThresholdMetrics(
                threshold: threshold,
                precision: precision,
                recall: recall,
                f05Score: f05Score,
                falseMergeCount: falsePositiveCount
            )

            let meetsPrecisionBar = metrics.precision >= minimumPrecision
            let isBetterCandidate: Bool = {
                guard let bestMetrics else { return meetsPrecisionBar }
                guard meetsPrecisionBar else { return false }
                if metrics.f05Score != bestMetrics.f05Score {
                    return metrics.f05Score > bestMetrics.f05Score
                }
                return metrics.recall > bestMetrics.recall
            }()

            if isBetterCandidate {
                bestMetrics = metrics
            }

            threshold += 0.01
        }

        return bestMetrics
    }

    @Test @MainActor func productionConfigurationPassesEvalBar() throws {
        let pairs = try loadEvalPairs()
        #expect(pairs.count >= 40)

        let lexicalBest = sweepLexicalThresholds(pairs: pairs)
        let productionMetrics = evaluateProductionConfiguration(pairs: pairs)

        if let lexicalBest {
            print("Dedup eval lexical best: threshold=\(lexicalBest.threshold), precision=\(lexicalBest.precision), recall=\(lexicalBest.recall), f0.5=\(lexicalBest.f05Score), falseMerges=\(lexicalBest.falseMergeCount)")
        } else {
            print("Dedup eval lexical best: none met precision bar")
        }

        print("Dedup eval production hybrid: lexicalThreshold=\(MemoryDedupConfiguration.lexicalMergeThreshold), appleThreshold=\(MemoryDedupConfiguration.appleMergeThreshold), sameAxisAppleThreshold=\(MemoryDedupConfiguration.sameAxisParaphraseAppleThreshold), appleLexicalFloor=\(MemoryDedupConfiguration.appleMergeLexicalFloor), precision=\(productionMetrics.precision), recall=\(productionMetrics.recall), f0.5=\(productionMetrics.f05Score), falseMerges=\(productionMetrics.falseMergeCount)")

        #expect(productionMetrics.precision >= 0.90)
        #expect(productionMetrics.falseMergeCount <= 2)
    }

    /// Guards the threshold dedup layer (`decideDedup`, the recall/precision
    /// reference): fuzzy lexical/embedding scores alone must never auto-merge
    /// opposite preferences. Production preferences and routines additionally run an
    /// LLM judge that applies last-write-wins on the same axis, so a contradicting
    /// preference there UPDATES the existing memory rather than creating a duplicate —
    /// a deliberately different (smarter) layer from the one asserted here.
    @Test @MainActor func doesNotMergeOppositePreferences() throws {
        let pairs = try loadEvalPairs()

        let oppositePairIDs = [
            "opposite-answers-length",
            "opposite-answers-shared-word",
            "opposite-keyboard-vs-mouse",
            "opposite-dark-vs-light",
            "opposite-typescript-vs-javascript",
            "opposite-confirm-vs-auto",
            "opposite-jargon-vs-technical",
            "opposite-step-by-step-vs-quick",
            "opposite-explain-before-code",
            "opposite-fast-for-experts",
            "opposite-go-over-rust",
            "opposite-metric-units",
            "opposite-no-pointing"
        ]

        for pair in pairs where oppositePairIDs.contains(pair.id) {
            let decision = predictedDecision(
                for: pair,
                scorerKind: MemoryDedupConfiguration.productionScorerKind,
                mergeThreshold: MemoryDedupConfiguration.mergeThreshold
            )
            #expect(decision == "separate", "Expected \(pair.id) to stay separate, got \(decision)")
        }
    }

    @Test @MainActor func mergesParaphrasePreferences() throws {
        let pairs = try loadEvalPairs()

        let paraphrasePairIDs = [
            "paraphrase-one-sentence-answers"
        ]

        for pair in pairs where paraphrasePairIDs.contains(pair.id) {
            let decision = predictedDecision(
                for: pair,
                scorerKind: MemoryDedupConfiguration.productionScorerKind,
                mergeThreshold: MemoryDedupConfiguration.mergeThreshold
            )
            #expect(decision == "merge", "Expected \(pair.id) to merge, got \(decision)")
        }
    }

    /// Pass 1 (recall) must surface a lexically-distant paraphrase as a merge candidate
    /// even when the precision-first threshold path (`decideDedup`) would reject it.
    /// This is the real-world bug: a short utterance vs an expanded synthesized memory
    /// scores too low for any fixed threshold, so the LLM judge needs it as a candidate.
    @Test @MainActor func mergeCandidatesSurfaceLexicallyDistantParaphrase() {
        let existingShortAnswers = Memory(
            id: "pref-keep-answers-short",
            category: .preference,
            title: "keep answers short",
            summary: "the user prefers brief, concise responses",
            body: "keep all answers short. avoid unnecessary elaboration or filler. get to the point immediately.",
            bundleIds: [],
            status: .active
        )

        let newParaphrase = "from now on keep the answers in one sentence"

        let thresholdMatch = AuxiliaryMemoryMatcher.decideDedup(
            newTopic: newParaphrase,
            category: .preference,
            bundleId: nil,
            existingMemories: [existingShortAnswers],
            scorerKind: MemoryDedupConfiguration.productionScorerKind,
            mergeThreshold: MemoryDedupConfiguration.mergeThreshold
        )

        let candidates = AuxiliaryMemoryMatcher.mergeCandidates(
            in: [existingShortAnswers],
            category: .preference,
            topic: newParaphrase,
            bundleId: nil
        )

        #expect(thresholdMatch == nil, "Threshold path is expected to miss this lexically-distant paraphrase")
        #expect(
            candidates.contains { $0.id == existingShortAnswers.id },
            "Recall must surface the paraphrase as a merge candidate for the LLM judge"
        )
    }

    @Test func preferenceConflictDetectorBlocksReversedPreferOverPairs() {
        #expect(
            PreferenceConflictDetector.hasConflict(
                between: "prefer javascript over typescript",
                and: "prefer typescript examples over javascript"
            )
        )
        #expect(
            PreferenceConflictDetector.hasConflict(
                between: "prefer go over rust for systems code",
                and: "prefer rust over go for systems programming"
            )
        )
        #expect(
            PreferenceConflictDetector.hasConflict(
                between: "just do it without asking for confirmation",
                and: "ask before suggesting destructive changes"
            )
        )
        #expect(
            PreferenceConflictDetector.hasConflict(
                between: "explain concepts before showing any code",
                and: "show code examples before explaining concepts"
            )
        )
        #expect(
            PreferenceSameAxisMatcher.isSameAnswerLengthPreferenceAxis(
                between: "from now on keep the answers in one sentence",
                and: "keep answers short. keep answers brief and concise"
            )
        )
        #expect(
            !PreferenceConflictDetector.hasConflict(
                between: "keep answers short",
                and: "keep answers brief and concise"
            )
        )
    }

    @Test func oldSingleTokenOverlapWouldHaveFalseMerged() throws {
        let pairs = try loadEvalPairs()

        let falseMergeCount = pairs.filter { pair in
            guard pair.expectedDecision == "separate" else { return false }

            let existingText = [
                pair.existingMemory.title,
                pair.existingMemory.summary,
                pair.existingMemory.body
            ].joined(separator: ". ")

            let topicTokens = Set(SkillMatcher.meaningfulTokens(pair.newTopic))
            let memoryTokens = Set(SkillMatcher.meaningfulTokens(existingText))
            return topicTokens.intersection(memoryTokens).count >= 1
        }.count

        #expect(falseMergeCount >= 5, "Fixture should include cases where old overlap behavior was unsafe")
    }
}
