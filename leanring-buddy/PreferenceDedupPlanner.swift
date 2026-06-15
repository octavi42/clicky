//
//  PreferenceDedupPlanner.swift
//  leanring-buddy
//
//  Cheap routing before the preference reconcile LLM call: create-only when
//  clearly novel, reconcile only when recall surfaces plausible candidates.
//

import Foundation

enum PreferenceDedupPlanReason: String, Codable, Equatable {
    case clearlyNovel
    case ambiguousCandidates
}

enum PreferenceDedupPlan: Equatable {
    /// Skip reconcile — no plausible existing memory to compare against.
    case createNew(reason: PreferenceDedupPlanReason)
    /// Send these candidates to the LLM same-axis judge + writer.
    case reconcile(candidates: [Memory], reason: PreferenceDedupPlanReason)

    var candidateMemories: [Memory] {
        switch self {
        case .createNew:
            return []
        case .reconcile(let candidates, _):
            return candidates
        }
    }

    var skipsReconcileLLM: Bool {
        if case .createNew = self { return true }
        return false
    }
}

enum PreferenceDedupPlanner {
    @MainActor
    static func planPreferenceDedup(
        existingMemories: [Memory],
        newTopic: String,
        bundleId: String?,
        candidateLimit: Int = 3
    ) -> PreferenceDedupPlan {
        let trimmedTopic = newTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTopic.isEmpty else {
            return .createNew(reason: .clearlyNovel)
        }

        let candidateMemories = AuxiliaryMemoryMatcher.mergeCandidates(
            in: existingMemories,
            category: .preference,
            topic: trimmedTopic,
            bundleId: bundleId,
            limit: candidateLimit
        )

        if candidateMemories.isEmpty {
            return .createNew(reason: .clearlyNovel)
        }

        return .reconcile(candidates: candidateMemories, reason: .ambiguousCandidates)
    }
}
