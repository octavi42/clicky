//
//  PreferenceDedupValidator.swift
//  leanring-buddy
//
//  Post-LLM steel gate: reject implausible update decisions before persisting.
//

import Foundation

enum PreferenceDedupValidatorOverrideReason: String, Codable, Equatable {
    case invalidUpdateMemoryId
    case unrelatedCandidate
    case relatedButDistinctAxis
    case appScopeMismatch
}

struct PreferenceDedupValidationResult: Equatable {
    let validatedUpdateMemoryId: String?
    let forcedCreate: Bool
    let overrideReason: PreferenceDedupValidatorOverrideReason?

    var updatedExistingMemory: Bool {
        validatedUpdateMemoryId != nil
    }
}

enum PreferenceDedupValidator {
    static func validateParsedDecision(
        parsedUpdateMemoryId: String?,
        candidateMemories: [Memory],
        newTopic: String,
        stableMemoryId: String,
        targetBundleId: String?
    ) -> PreferenceDedupValidationResult {
        guard let parsedUpdateMemoryId else {
            return PreferenceDedupValidationResult(
                validatedUpdateMemoryId: nil,
                forcedCreate: false,
                overrideReason: nil
            )
        }

        guard let chosenCandidate = candidateMemories.first(where: { $0.id == parsedUpdateMemoryId }) else {
            return PreferenceDedupValidationResult(
                validatedUpdateMemoryId: nil,
                forcedCreate: true,
                overrideReason: .invalidUpdateMemoryId
            )
        }

        if hasAppScopeMismatch(
            newTargetBundleId: targetBundleId,
            existingMemory: chosenCandidate
        ) {
            return PreferenceDedupValidationResult(
                validatedUpdateMemoryId: nil,
                forcedCreate: true,
                overrideReason: .appScopeMismatch
            )
        }

        let existingText = AuxiliaryMemoryMatcher.memoryComparisonText(for: chosenCandidate)

        // Same-axis revisions (including reversals) use last-write-wins.
        if PreferenceSameAxisMatcher.isSameBehavioralAxis(between: newTopic, and: existingText) {
            return PreferenceDedupValidationResult(
                validatedUpdateMemoryId: parsedUpdateMemoryId,
                forcedCreate: false,
                overrideReason: nil
            )
        }

        if parsedUpdateMemoryId == stableMemoryId {
            return PreferenceDedupValidationResult(
                validatedUpdateMemoryId: parsedUpdateMemoryId,
                forcedCreate: false,
                overrideReason: nil
            )
        }

        if PreferenceSameAxisMatcher.isRelatedButDistinctAxis(between: newTopic, and: existingText) {
            return PreferenceDedupValidationResult(
                validatedUpdateMemoryId: nil,
                forcedCreate: true,
                overrideReason: .relatedButDistinctAxis
            )
        }

        return PreferenceDedupValidationResult(
            validatedUpdateMemoryId: nil,
            forcedCreate: true,
            overrideReason: .unrelatedCandidate
        )
    }

    /// App-scoped memories must not be updated across different bundle ids.
    private static func hasAppScopeMismatch(
        newTargetBundleId: String?,
        existingMemory: Memory
    ) -> Bool {
        guard let newTargetBundleId,
              !existingMemory.bundleIds.isEmpty else {
            return false
        }

        return !existingMemory.bundleIds.contains(newTargetBundleId)
    }
}

/// Offline pipeline evaluator for labeled fixtures — no network, no LLM.
enum PreferenceDedupPipelineEvaluator {
    struct EvaluatedPairResult: Equatable {
        let pairId: String
        let planReason: PreferenceDedupPlanReason
        let candidateCount: Int
        let validatedDecision: String
        let overrideReason: PreferenceDedupValidatorOverrideReason?
        let passed: Bool
    }

    struct PipelineEvalSummary: Equatable {
        let passedCount: Int
        let failedCount: Int
        let failedPairIds: [String]
    }

    @MainActor
    static func evaluateOfflinePair(
        pairId: String,
        newTopic: String,
        existingMemory: Memory,
        bundleId: String?,
        simulatedLLMDecision: String,
        expectedPipelineDecision: String
    ) -> EvaluatedPairResult {
        let plan = PreferenceDedupPlanner.planPreferenceDedup(
            existingMemories: [existingMemory],
            newTopic: newTopic,
            bundleId: bundleId
        )

        let stableMemoryId = AuxiliaryMemoryMatcher.stableMemoryId(
            category: .preference,
            topic: newTopic,
            bundleId: bundleId
        )

        let parsedUpdateId = PreferenceSynthesizer.parseUpdateMemoryId(from: simulatedLLMDecision)
        let validation = PreferenceDedupValidator.validateParsedDecision(
            parsedUpdateMemoryId: parsedUpdateId,
            candidateMemories: plan.candidateMemories,
            newTopic: newTopic,
            stableMemoryId: stableMemoryId,
            targetBundleId: bundleId
        )

        let validatedDecision = validation.validatedUpdateMemoryId == nil ? "create" : "update"
        let passed = validatedDecision == expectedPipelineDecision

        let planReason: PreferenceDedupPlanReason = {
            switch plan {
            case .createNew(let reason):
                return reason
            case .reconcile(_, let reason):
                return reason
            }
        }()

        return EvaluatedPairResult(
            pairId: pairId,
            planReason: planReason,
            candidateCount: plan.candidateMemories.count,
            validatedDecision: validatedDecision,
            overrideReason: validation.overrideReason,
            passed: passed
        )
    }

    static func summarize(_ results: [EvaluatedPairResult]) -> PipelineEvalSummary {
        let failed = results.filter { !$0.passed }
        return PipelineEvalSummary(
            passedCount: results.count - failed.count,
            failedCount: failed.count,
            failedPairIds: failed.map(\.pairId)
        )
    }
}
