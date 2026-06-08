//
//  AuxiliaryMemoryMatcher.swift
//  leanring-buddy
//
//  Finds existing preference/routine memories to patch instead of duplicating.
//

import Foundation

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

        let topicTokens = Set(SkillMatcher.meaningfulTokens(topic))
        guard !topicTokens.isEmpty else { return nil }

        let categoryMemories = memories.filter { memory in
            memory.category == category &&
            (bundleId == nil || memory.bundleIds.isEmpty || memory.bundleIds.contains(bundleId!))
        }

        return categoryMemories.max { lhs, rhs in
            overlapScore(lhs, topicTokens: topicTokens) < overlapScore(rhs, topicTokens: topicTokens)
        }
        .flatMap { candidate in
            overlapScore(candidate, topicTokens: topicTokens) >= 1 ? candidate : nil
        }
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
            (bundleId == nil || memory.bundleIds.isEmpty || memory.bundleIds.contains(bundleId!))
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

    private static func overlapScore(_ memory: Memory, topicTokens: Set<String>) -> Int {
        let memoryTokens = Set(
            SkillMatcher.meaningfulTokens(memory.title) +
            SkillMatcher.meaningfulTokens(memory.summary) +
            SkillMatcher.meaningfulTokens(memory.body)
        )
        return memoryTokens.filter { topicTokens.contains($0) }.count
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
