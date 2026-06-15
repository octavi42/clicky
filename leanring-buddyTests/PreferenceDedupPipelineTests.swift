//
//  PreferenceDedupPipelineTests.swift
//  leanring-buddyTests
//
//  Offline end-to-end tests for preference dedup: planner → (simulated LLM) → validator.
//  No network. Run via Xcode Cmd+U.
//
//  E2E automation strategy (app launch):
//  1. Seed auxiliary-memories.json under isolated CLICKY_HOME.
//  2. Launch with -CLICKY_E2E=1 and inject a preference transcript.
//  3. Assert e2e-preference-dedup-plan.json (candidate ids, skipsReconcileLLM)
//     and e2e-preference-dedup-outcome.json (savedMemoryID, validatorForcedCreate).
//  Unit tests here guarantee the deterministic layers; E2E artifacts guarantee wiring.
//

import Foundation
import Testing
@testable import leanring_buddy

private struct DedupSynthesizerEvalFixture: Decodable {
    let pairs: [DedupSynthesizerEvalPair]
}

private struct DedupSynthesizerEvalPair: Decodable {
    let id: String
    let newTopic: String
    let existingMemoryId: String
    let existingMemory: DedupEvalExistingMemory
    /// Scope of the stored memory (e.g. VSCode-scoped pref).
    let existingBundleId: String?
    /// App context for the new preference statement (planner + validator target).
    let targetBundleId: String?
    let simulatedLLMDecision: String
    let expectedPipelineDecision: String

    /// Legacy single-field alias — applies to both when the split fields are absent.
    let bundleId: String?

    var resolvedExistingBundleId: String? {
        existingBundleId ?? bundleId
    }

    var resolvedTargetBundleId: String? {
        targetBundleId ?? bundleId
    }
}

private struct DedupEvalExistingMemory: Decodable {
    let title: String
    let summary: String
    let body: String
}

@Suite(.serialized)
struct PreferenceDedupPipelineTests {
    private func loadSynthesizerEvalPairs() throws -> [DedupSynthesizerEvalPair] {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/dedup-synthesizer-eval-pairs.json")

        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixture = try JSONDecoder().decode(DedupSynthesizerEvalFixture.self, from: fixtureData)
        return fixture.pairs
    }

    private func makeExistingMemory(
        id: String,
        from existingMemory: DedupEvalExistingMemory,
        bundleId: String?
    ) -> Memory {
        Memory(
            id: id,
            category: .preference,
            title: existingMemory.title,
            summary: existingMemory.summary,
            body: existingMemory.body,
            bundleIds: bundleId.map { [$0] } ?? [],
            status: .active
        )
    }

    @Test @MainActor func plannerSkipsReconcileForClearlyNovelPreference() {
        let unrelatedExisting = Memory(
            id: "pref-keep-answers-short",
            category: .preference,
            title: "short answers",
            summary: "keep answers brief and concise",
            body: "answer in one or two sentences whenever possible",
            status: .active
        )

        let plan = PreferenceDedupPlanner.planPreferenceDedup(
            existingMemories: [unrelatedExisting],
            newTopic: "export video to youtube weekly",
            bundleId: nil
        )

        #expect(plan.skipsReconcileLLM)
        #expect(plan.candidateMemories.isEmpty)
    }

    @Test @MainActor func plannerSurfacesSameAxisParaphraseCandidate() {
        let existingShortAnswers = Memory(
            id: "pref-keep-answers-short",
            category: .preference,
            title: "keep answers short",
            summary: "the user prefers brief, concise responses",
            body: "keep all answers short. avoid unnecessary elaboration or filler.",
            status: .active
        )

        let plan = PreferenceDedupPlanner.planPreferenceDedup(
            existingMemories: [existingShortAnswers],
            newTopic: "from now on keep the answers in one sentence",
            bundleId: nil
        )

        #expect(!plan.skipsReconcileLLM)
        #expect(plan.candidateMemories.contains { $0.id == existingShortAnswers.id })
    }

    @Test @MainActor func validatorAllowsSameAxisReversalUpdate() {
        let existingShortAnswers = Memory(
            id: "pref-keep-answers-short",
            category: .preference,
            title: "short answers",
            summary: "keep answers brief and concise",
            body: "answer in one or two sentences whenever possible",
            status: .active
        )

        let validation = PreferenceDedupValidator.validateParsedDecision(
            parsedUpdateMemoryId: existingShortAnswers.id,
            candidateMemories: [existingShortAnswers],
            newTopic: "give detailed answers with examples",
            stableMemoryId: "pref-give-detailed-answers-with-examples",
            targetBundleId: nil
        )

        #expect(validation.validatedUpdateMemoryId == existingShortAnswers.id)
        #expect(!validation.forcedCreate)
    }

    @Test @MainActor func validatorRejectsRelatedButDistinctToneUpdate() {
        let existingShortAnswers = Memory(
            id: "pref-keep-answers-short",
            category: .preference,
            title: "short answers",
            summary: "keep answers brief and concise",
            body: "answer in one or two sentences whenever possible",
            status: .active
        )

        let validation = PreferenceDedupValidator.validateParsedDecision(
            parsedUpdateMemoryId: existingShortAnswers.id,
            candidateMemories: [existingShortAnswers],
            newTopic: "be friendly and casual in tone",
            stableMemoryId: "pref-be-friendly-and-casual-in-tone",
            targetBundleId: nil
        )

        #expect(validation.validatedUpdateMemoryId == nil)
        #expect(validation.forcedCreate)
        #expect(validation.overrideReason == .relatedButDistinctAxis)
    }

    @Test @MainActor func validatorRejectsCrossAppScopeUpdate() {
        let vscodeTypescript = Memory(
            id: "pref-typescript-first",
            category: .preference,
            title: "typescript first",
            summary: "prefer typescript examples over javascript",
            body: "default to typescript syntax in code examples",
            bundleIds: ["com.microsoft.VSCode"],
            status: .active
        )

        let validation = PreferenceDedupValidator.validateParsedDecision(
            parsedUpdateMemoryId: vscodeTypescript.id,
            candidateMemories: [vscodeTypescript],
            newTopic: "prefer typescript in xcode",
            stableMemoryId: "pref-xcode-prefer-typescript-in-xcode",
            targetBundleId: "com.apple.dt.Xcode"
        )

        #expect(validation.validatedUpdateMemoryId == nil)
        #expect(validation.overrideReason == .appScopeMismatch)
    }

    @Test @MainActor func plannerExcludesCrossAppScopedCandidate() {
        let vscodeTypescript = Memory(
            id: "pref-typescript-first",
            category: .preference,
            title: "typescript first",
            summary: "prefer typescript examples over javascript",
            body: "default to typescript syntax in code examples",
            bundleIds: ["com.microsoft.VSCode"],
            status: .active
        )

        let plan = PreferenceDedupPlanner.planPreferenceDedup(
            existingMemories: [vscodeTypescript],
            newTopic: "prefer typescript in xcode",
            bundleId: "com.apple.dt.Xcode"
        )

        #expect(plan.skipsReconcileLLM)
        #expect(plan.candidateMemories.isEmpty)
    }

    @Test @MainActor func pipelineEvalFixturePassesEndToEnd() throws {
        let pairs = try loadSynthesizerEvalPairs()
        #expect(pairs.count >= 5)

        var results: [PreferenceDedupPipelineEvaluator.EvaluatedPairResult] = []

        for pair in pairs {
            let existingMemory = makeExistingMemory(
                id: pair.existingMemoryId,
                from: pair.existingMemory,
                bundleId: pair.resolvedExistingBundleId
            )

            let result = PreferenceDedupPipelineEvaluator.evaluateOfflinePair(
                pairId: pair.id,
                newTopic: pair.newTopic,
                existingMemory: existingMemory,
                bundleId: pair.resolvedTargetBundleId,
                simulatedLLMDecision: pair.simulatedLLMDecision,
                expectedPipelineDecision: pair.expectedPipelineDecision
            )

            results.append(result)
            #expect(result.passed, "Pipeline pair \(pair.id) expected \(pair.expectedPipelineDecision), got \(result.validatedDecision)")
        }

        let summary = PreferenceDedupPipelineEvaluator.summarize(results)
        #expect(summary.failedCount == 0, "Failed pairs: \(summary.failedPairIds.joined(separator: ", "))")
    }

    @Test @MainActor func buildMemoryFromParsedResponsePreservesExistingMetadataOnUpdate() {
        let existingMemory = Memory(
            id: "pref-keep-answers-short",
            category: .preference,
            title: "short answers",
            summary: "keep answers brief",
            body: "keep answers short",
            isPinned: true,
            usageCount: 4,
            receipts: []
        )

        let validation = PreferenceDedupValidationResult(
            validatedUpdateMemoryId: existingMemory.id,
            forcedCreate: false,
            overrideReason: nil
        )

        let built = PreferenceSynthesizer.buildMemoryFromParsedResponse(
            title: "one sentence answers",
            summary: "answer in one sentence",
            body: "keep every answer to one sentence.",
            fallbackResponseText: "",
            candidateMemories: [existingMemory],
            topic: "from now on keep the answers in one sentence",
            resolvedBundleId: nil,
            bundleIds: [],
            validationResult: validation
        )

        #expect(built.updatedExistingMemory)
        #expect(built.memory.id == existingMemory.id)
        #expect(built.memory.isPinned)
        #expect(built.memory.usageCount == 4)
        #expect(built.memory.title == "one sentence answers")
    }
}
