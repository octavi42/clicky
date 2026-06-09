//
//  AuxiliaryMemoryMatcher.swift
//  leanring-buddy
//
//  Finds existing preference/routine memories to patch instead of duplicating.
//

import Foundation

enum MemoryDedupConfiguration {
    /// Selected by MemoryDedupEvalTests threshold sweep (precision-first).
    static let productionScorerKind: MemorySimilarityScorerKind = .hybrid
    static let lexicalMergeThreshold: Double = 0.55
    static let appleMergeThreshold: Double = 0.93
    /// Apple embeddings have a high unrelated baseline, so require some lexical overlap too.
    static let appleMergeLexicalFloor: Double = 0.18
    /// Same-axis paraphrase merge for answer-length prefs (e.g. short vs one sentence).
    static let sameAxisParaphraseLexicalFloor: Double = 0.30
    static let sameAxisParaphraseAppleThreshold: Double = 0.80

    static var mergeThreshold: Double {
        lexicalMergeThreshold
    }
}

enum AuxiliaryMemoryMatcher {
    static func stableMemoryId(
        category: MemoryCategory,
        topic: String,
        bundleId: String?
    ) -> String {
        let topicSlug = slug(from: SkillMatcher.meaningfulTokens(topic).prefix(4).joined(separator: " "))
        switch category {
        case .preference:
            if let bundleId, let appName = TeachingSkill.displayName(forBundleId: bundleId) {
                return "pref-\(slug(from: appName))-\(topicSlug)"
            }
            return "pref-\(topicSlug)"
        case .routine:
            if let bundleId, let appName = TeachingSkill.displayName(forBundleId: bundleId) {
                return "routine-\(slug(from: appName))-\(topicSlug)"
            }
            return "routine-\(topicSlug)"
        case .skill:
            return TeachingSkill.stableSkillId(bundleId: bundleId, primaryQuestion: topic)
        }
    }

    @MainActor
    static func findMemoryForUpdate(
        in memories: [Memory],
        category: MemoryCategory,
        topic: String,
        bundleId: String?
    ) -> Memory? {
        let expectedMemoryId = stableMemoryId(category: category, topic: topic, bundleId: bundleId)

        if let exactMatch = memories.first(where: { $0.id == expectedMemoryId && $0.category == category }) {
            return exactMatch
        }

        return decideDedup(
            newTopic: topic,
            category: category,
            bundleId: bundleId,
            existingMemories: memories,
            scorerKind: MemoryDedupConfiguration.productionScorerKind,
            mergeThreshold: MemoryDedupConfiguration.mergeThreshold
        )
    }

    @MainActor
    static func decideDedup(
        newTopic: String,
        category: MemoryCategory,
        bundleId: String?,
        existingMemories: [Memory],
        scorer: any MemorySimilarityScorer,
        mergeThreshold: Double
    ) -> Memory? {
        let trimmedTopic = newTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTopic.isEmpty else { return nil }

        let scopedMemories = existingMemories.filter { memory in
            memory.category == category &&
            bundleScopeMatches(existingMemory: memory, bundleId: bundleId)
        }
        guard !scopedMemories.isEmpty else { return nil }

        let bestMatch = scopedMemories.max { lhs, rhs in
            similarityScore(
                between: trimmedTopic,
                and: rhs,
                using: scorer
            ) < similarityScore(
                between: trimmedTopic,
                and: lhs,
                using: scorer
            )
        }

        guard let bestMatch else { return nil }

        let bestScore = similarityScore(between: trimmedTopic, and: bestMatch, using: scorer)
        return shouldMerge(
            newTopic: trimmedTopic,
            existingMemory: bestMatch,
            bestScore: bestScore,
            scorer: scorer,
            mergeThreshold: mergeThreshold
        ) ? bestMatch : nil
    }

    @MainActor
    static func decideDedup(
        newTopic: String,
        category: MemoryCategory,
        bundleId: String?,
        existingMemories: [Memory],
        scorerKind: MemorySimilarityScorerKind,
        mergeThreshold: Double
    ) -> Memory? {
        let scorer = MemorySimilarityScorerFactory.makeScorer(for: scorerKind)
        return decideDedup(
            newTopic: newTopic,
            category: category,
            bundleId: bundleId,
            existingMemories: existingMemories,
            scorer: scorer,
            mergeThreshold: mergeThreshold
        )
    }

    static func matchRoutines(
        from memories: [Memory],
        bundleId: String?,
        transcript: String,
        limit: Int = 2
    ) -> [Memory] {
        let queryTokens = Set(SkillMatcher.meaningfulTokens(transcript))
        let eligibleRoutines = memories.filter { memory in
            memory.category == .routine &&
            memory.status == .active &&
            bundleScopeMatches(existingMemory: memory, bundleId: bundleId)
        }

        let scored = eligibleRoutines.compactMap { routine -> (Memory, Int)? in
            var score = 0
            let haystackTokens = Set(
                SkillMatcher.meaningfulTokens(routine.title) +
                SkillMatcher.meaningfulTokens(routine.summary) +
                SkillMatcher.meaningfulTokens(routine.body)
            )
            score += queryTokens.filter { haystackTokens.contains($0) }.count

            if let bundleId, routine.bundleIds.contains(bundleId) {
                score += 5
            }

            return score > 0 ? (routine, score) : nil
        }

        return Array(
            scored
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return (lhs.0.lastUsed ?? .distantPast) > (rhs.0.lastUsed ?? .distantPast)
                }
                .prefix(limit)
                .map(\.0)
        )
    }

    static func memoryComparisonText(for memory: Memory) -> String {
        [memory.title, memory.summary, memory.body]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    static func bundleScopeMatches(existingMemory: Memory, bundleId: String?) -> Bool {
        bundleId == nil ||
        existingMemory.bundleIds.isEmpty ||
        existingMemory.bundleIds.contains(bundleId!)
    }

    @MainActor
    static func shouldMerge(
        newTopic: String,
        existingMemory: Memory,
        bestScore: Double,
        scorer: any MemorySimilarityScorer,
        mergeThreshold: Double
    ) -> Bool {
        let existingText = memoryComparisonText(for: existingMemory)

        if PreferenceConflictDetector.hasConflict(between: newTopic, and: existingText) {
            return false
        }

        if let hybridScorer = scorer as? HybridMemorySimilarityScorer {
            let lexicalScore = hybridScorer.lexicalSimilarity(between: newTopic, and: existingText)
            let appleScore = hybridScorer.appleSimilarity(between: newTopic, and: existingText)
            let passesLexicalGate = lexicalScore >= MemoryDedupConfiguration.lexicalMergeThreshold
            let passesAppleGate = appleScore >= MemoryDedupConfiguration.appleMergeThreshold &&
                lexicalScore >= MemoryDedupConfiguration.appleMergeLexicalFloor
            let passesSameAxisParaphraseGate =
                PreferenceSameAxisMatcher.isSameAnswerLengthPreferenceAxis(
                    between: newTopic,
                    and: existingText
                ) &&
                (
                    lexicalScore >= MemoryDedupConfiguration.sameAxisParaphraseLexicalFloor ||
                    appleScore >= MemoryDedupConfiguration.sameAxisParaphraseAppleThreshold
                )
            return passesLexicalGate || passesAppleGate || passesSameAxisParaphraseGate
        }

        return bestScore >= mergeThreshold
    }

    private static func similarityScore(
        between newTopic: String,
        and existingMemory: Memory,
        using scorer: any MemorySimilarityScorer
    ) -> Double {
        scorer.similarity(
            between: newTopic,
            and: memoryComparisonText(for: existingMemory)
        )
    }

    private static func slug(from text: String) -> String {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let filtered = normalized.unicodeScalars.filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(filtered))
        return result.isEmpty ? "memory" : result
    }
}
