//
//  MemoryGate.swift
//  leanring-buddy
//
//  Cheap cold-path rules deciding whether a persisted session is worth
//  distilling and into which memory categories. No LLM.
//

import Foundation

enum MemoryCategory: String, Codable, CaseIterable {
    case skill
    case preference
    case routine
}

enum GateReason: String, Codable, Equatable {
    case userConfirmed
    case multiStepPointing
    case repeatedTopic
    case screenTeaching
    case statedPreference
    case styleCorrection
    case recurringRoutine
}

enum BlockReason: String, Codable, Equatable {
    case privacyOptOut
    case abandonedWithoutConfirmation
    case genericOffScreenQA
    case learningDisabled
    case empty
}

struct MemoryGateDecision: Equatable {
    let sessionId: UUID
    let passedCategories: [MemoryCategory: [GateReason]]
    let blockReasons: [BlockReason]

    func passes(_ category: MemoryCategory) -> Bool {
        passedCategories[category] != nil
    }

    var shouldDistillSkill: Bool {
        passes(.skill)
    }

    var shouldDistillPreference: Bool {
        passes(.preference)
    }

    var shouldDistillRoutine: Bool {
        passes(.routine)
    }
}

enum MemoryGate {
    /// Hermes-style bar for proactive mid-session drafting: screen teaching with
    /// real depth (2+ turns or 2+ pointing), and the user did not reject on the last turn.
    static func meetsImplicitSaveBar(turns: [SessionTraceEntry]) -> Bool {
        guard SkillTriggerEvaluator.isScreenTeachingSession(turns) else { return false }

        if let lastTurn = turns.last,
           SkillTriggerEvaluator.isNegativeFeedbackTranscript(lastTurn.userTranscript) {
            return false
        }

        return turns.count >= 2 || turns.filter(\.pointed).count >= 2
    }

    static func evaluate(
        session: PersistedSession,
        topicHistory: [TeachingTopicHistoryEntry],
        isLearningEnabled: Bool,
        now: Date = Date()
    ) -> MemoryGateDecision {
        guard isLearningEnabled else {
            return blockedDecision(sessionId: session.sessionId, reason: .learningDisabled)
        }

        guard !session.privacyOptOut else {
            return blockedDecision(sessionId: session.sessionId, reason: .privacyOptOut)
        }

        guard !session.turns.isEmpty else {
            return blockedDecision(sessionId: session.sessionId, reason: .empty)
        }

        var passedCategories: [MemoryCategory: [GateReason]] = [:]

        if SkillTriggerEvaluator.isScreenTeachingSession(session.turns) {
            let skillGateReasons = gateReasonsForSkillDistillation(
                turns: session.turns,
                topicHistory: topicHistory,
                now: now
            )
            if !skillGateReasons.isEmpty {
                passedCategories[.skill] = skillGateReasons
            }
        }

        let preferenceGateReasons = gateReasonsForPreference(turns: session.turns)
        if !preferenceGateReasons.isEmpty {
            passedCategories[.preference] = preferenceGateReasons
        }

        let routineGateReasons = gateReasonsForRoutine(
            turns: session.turns,
            topicHistory: topicHistory,
            now: now
        )
        if !routineGateReasons.isEmpty {
            passedCategories[.routine] = routineGateReasons
        }

        guard !passedCategories.isEmpty else {
            let blockReason: BlockReason
            if SkillTriggerEvaluator.isScreenTeachingSession(session.turns) {
                blockReason = .abandonedWithoutConfirmation
            } else {
                blockReason = .genericOffScreenQA
            }
            return blockedDecision(sessionId: session.sessionId, reason: blockReason)
        }

        return MemoryGateDecision(
            sessionId: session.sessionId,
            passedCategories: passedCategories,
            blockReasons: []
        )
    }

    static func gateReasonsForSkillDistillation(
        turns: [SessionTraceEntry],
        topicHistory: [TeachingTopicHistoryEntry],
        now: Date = Date()
    ) -> [GateReason] {
        let hasConfirmationOnAnyTurn = turns.contains {
            SkillTriggerEvaluator.isConfirmationTranscript($0.userTranscript)
        }
        let hasMultiStepPointing = turns.filter(\.pointed).count >= 2
        let meetsImplicitBar = meetsImplicitSaveBar(turns: turns)

        let topic = SkillTriggerEvaluator.deriveTopic(from: turns)
        let resolvedBundleId = SkillTargetAppResolver.resolveTargetBundleId(
            from: turns,
            frontmostBundleId: turns.last?.bundleId
        )
        let hasRepeatedTopic = TeachingTopicHistoryStore.hasRepeatedTopic(
            topic: topic,
            bundleId: resolvedBundleId,
            withinDays: 7,
            in: topicHistory,
            now: now
        )

        let qualifiesForDistillation = meetsImplicitBar
            || hasMultiStepPointing
            || hasRepeatedTopic
            || hasConfirmationOnAnyTurn

        guard qualifiesForDistillation else { return [] }

        // Collect reasons most-specific first so the primary reported reason
        // (`gateReasons.first`, used for analytics and the skill-write trigger)
        // reflects the strongest signal. `.screenTeaching` is the generic
        // baseline and is always recorded last so it never masks a more
        // specific reason like `.repeatedTopic`.
        var skillReasons: [GateReason] = []

        if let lastTurn = turns.last,
           SkillTriggerEvaluator.isConfirmationTranscript(lastTurn.userTranscript) {
            skillReasons.append(.userConfirmed)
        }

        if hasRepeatedTopic {
            skillReasons.append(.repeatedTopic)
        }

        if hasMultiStepPointing {
            skillReasons.append(.multiStepPointing)
        }

        skillReasons.append(.screenTeaching)

        return skillReasons
    }

    static func gateReasonsForPreference(turns: [SessionTraceEntry]) -> [GateReason] {
        var preferenceReasons: [GateReason] = []

        if PreferenceSignalDetector.hasStatedPreference(in: turns) {
            preferenceReasons.append(.statedPreference)
        }

        if PreferenceSignalDetector.hasStyleCorrectionAcrossTurns(in: turns) {
            preferenceReasons.append(.styleCorrection)
        }

        return preferenceReasons
    }

    static func gateReasonsForRoutine(
        turns: [SessionTraceEntry],
        topicHistory: [TeachingTopicHistoryEntry],
        now: Date = Date()
    ) -> [GateReason] {
        let hasMultiStepSequence = turns.filter(\.pointed).count >= 2 || turns.count >= 2
        guard hasMultiStepSequence else { return [] }

        let topic = SkillTriggerEvaluator.deriveTopic(from: turns)
        let resolvedBundleId = SkillTargetAppResolver.resolveTargetBundleId(
            from: turns,
            frontmostBundleId: turns.last?.bundleId
        )

        let hasRecurringTopic = TeachingTopicHistoryStore.hasRecurringTopicAcrossDays(
            topic: topic,
            bundleId: resolvedBundleId,
            minDistinctDays: 2,
            withinDays: 7,
            in: topicHistory,
            now: now
        )

        guard hasRecurringTopic else { return [] }

        return [.recurringRoutine]
    }

    static func makeSkillWriteTrigger(
        for session: PersistedSession,
        gateReasons: [GateReason]
    ) -> SkillWriteTrigger {
        makeSkillWriteTrigger(from: session.turns, gateReasons: gateReasons)
    }

    static func makeSkillWriteTrigger(
        from turns: [SessionTraceEntry],
        gateReasons: [GateReason]
    ) -> SkillWriteTrigger {
        let primaryGateReason = gateReasons.first ?? .screenTeaching
        let skillReason = SkillWriteTrigger.Reason(rawValue: primaryGateReason.rawValue) ?? .screenTeaching
        let topic = SkillTriggerEvaluator.deriveTopic(from: turns)
        return SkillWriteTrigger(reason: skillReason, topic: topic)
    }

    private static func blockedDecision(sessionId: UUID, reason: BlockReason) -> MemoryGateDecision {
        MemoryGateDecision(
            sessionId: sessionId,
            passedCategories: [:],
            blockReasons: [reason]
        )
    }
}
