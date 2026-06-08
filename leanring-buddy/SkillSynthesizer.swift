//
//  SkillSynthesizer.swift
//  leanring-buddy
//
//  Drafts or updates teaching skills from a completed tutoring session trace.
//

import Foundation

enum SkillSynthesizer {
    private static let synthesisSystemPrompt = """
    you write teaching skills for clicky, a screen-native voice tutor that points at ui elements.

    given a tutoring session transcript, produce a markdown teaching skill body only. do not include yaml frontmatter.

    start your output with exactly one line in this format:
    triggers: phrase one | phrase two | phrase three

    include 3-5 natural trigger phrases a user might say when they need this skill again.

    after the triggers line, include:
    - the app/workflow being taught
    - ordered steps
    - exact ui labels, menu paths, and shortcuts when known
    - pointing heuristics (what to point at first, what to avoid)
    - common mistakes the user made or might make
    - user preferences and constraints from the session (e.g. keyboard only, no menu)
    - completion signals ("user said got it", visible ui state)

    keep it concise, practical, and specific to macos ui teaching. all lowercase.
    """

    private static let patchSystemPrompt = """
    you update an existing teaching skill for clicky, a screen-native voice tutor that points at ui elements.

    given the existing skill body and a new tutoring session, produce an updated markdown body only. do not include yaml frontmatter.

    start your output with exactly one line in this format:
    triggers: phrase one | phrase two | phrase three

    include 3-5 natural trigger phrases a user might say when they need this skill again.

    patch-first rules:
    - preserve guidance that still works
    - merge new constraints and refinements from the latest session
    - do not duplicate steps or create a parallel workflow
    - honor user preferences such as "keyboard only" or "avoid the menu"
    - keep ordered steps, ui labels, shortcuts, pointing heuristics, and completion signals

    keep it concise, practical, and specific to macos ui teaching. all lowercase.
    """

    static func synthesizeSkillContent(
        sessionTrace: [SessionTraceEntry],
        trigger: SkillWriteTrigger,
        existingSkill: TeachingSkill?,
        targetBundleId: String?,
        claudeAPI: ClaudeAPI
    ) async throws -> (name: String, description: String, body: String, triggers: [String]) {
        let sessionSummary = renderSessionSummary(
            sessionTrace,
            trigger: trigger,
            existingSkill: existingSkill,
            targetBundleId: targetBundleId
        )
        let primaryQuestion = SkillTriggerEvaluator.primaryTeachingQuestion(from: sessionTrace) ?? trigger.topic
        let metadata = TeachingSkill.buildMetadata(primaryQuestion: primaryQuestion, bundleId: targetBundleId)

        let userPrompt: String
        let systemPrompt: String
        if let existingSkill {
            systemPrompt = patchSystemPrompt
            userPrompt = """
            patch this existing teaching skill using the new session. preserve useful existing guidance and merge refinements:

            existing skill id: \(existingSkill.id)
            existing skill body:
            \(existingSkill.body)

            new session:
            \(sessionSummary)
            """
        } else {
            systemPrompt = synthesisSystemPrompt
            userPrompt = "create a new teaching skill from this session:\n\n\(sessionSummary)"
        }

        let response = try await claudeAPI.sendTextMessage(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 1200
        )

        let parsedResponse = parseTriggersLine(from: response.text)
        let name = existingSkill?.name ?? metadata.name
        let description = existingSkill?.description ?? metadata.description
        let resolvedTriggers = parsedResponse.triggers.isEmpty
            ? (existingSkill?.triggers ?? [])
            : parsedResponse.triggers
        return (
            name: name,
            description: description,
            body: parsedResponse.body,
            triggers: resolvedTriggers
        )
    }

    static func buildSkillMetadata(
        sessionTrace: [SessionTraceEntry],
        trigger: SkillWriteTrigger,
        targetBundleId: String?
    ) -> TeachingSkill.Metadata {
        let primaryQuestion = SkillTriggerEvaluator.primaryTeachingQuestion(from: sessionTrace) ?? trigger.topic
        return TeachingSkill.buildMetadata(primaryQuestion: primaryQuestion, bundleId: targetBundleId)
    }

    static func buildSkill(
        id: String?,
        name: String,
        description: String,
        body: String,
        triggers: [String],
        targetBundleId: String?,
        taskSlug: String?,
        primaryQuestion: String,
        existingSkill: TeachingSkill?
    ) -> TeachingSkill {
        let resolvedID = id
            ?? existingSkill?.id
            ?? TeachingSkill.stableSkillId(bundleId: targetBundleId, primaryQuestion: primaryQuestion)
        let resolvedTaskSlug = taskSlug ?? existingSkill?.taskSlug ?? TeachingSkill.taskSlug(from: primaryQuestion)

        let bundleIds: [String]
        if let targetBundleId {
            bundleIds = [targetBundleId]
        } else if let existingSkill, !existingSkill.bundleIds.isEmpty {
            bundleIds = existingSkill.bundleIds
        } else {
            bundleIds = []
        }

        let resolvedSkill: TeachingSkill
        if let existingSkill {
            resolvedSkill = existingSkill.withSupersededBody(body)
        } else {
            resolvedSkill = TeachingSkill(
                id: resolvedID,
                name: name,
                description: description,
                bundleIds: bundleIds,
                status: .active,
                lastUsed: Date(),
                usageCount: 0,
                isPinned: false,
                taskSlug: resolvedTaskSlug,
                triggers: triggers,
                confirmedSuccessCount: 0,
                supersededAt: nil,
                previousBody: nil,
                body: body
            )
        }

        var updatedSkill = resolvedSkill
        updatedSkill.name = name
        updatedSkill.description = description
        updatedSkill.bundleIds = bundleIds
        updatedSkill.status = .active
        updatedSkill.lastUsed = Date()
        updatedSkill.usageCount = existingSkill?.usageCount ?? 0
        updatedSkill.isPinned = existingSkill?.isPinned ?? false
        updatedSkill.taskSlug = resolvedTaskSlug
        updatedSkill.triggers = triggers.isEmpty ? (existingSkill?.triggers ?? []) : triggers
        updatedSkill.confirmedSuccessCount = existingSkill?.confirmedSuccessCount ?? 0
        return updatedSkill
    }

    static func parseTriggersLine(from responseText: String) -> (triggers: [String], body: String) {
        let trimmedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstLineEnd = trimmedResponse.firstIndex(of: "\n") else {
            return parseTriggersFromSingleLine(trimmedResponse)
        }

        let firstLine = String(trimmedResponse[..<firstLineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remainingBody = String(trimmedResponse[trimmedResponse.index(after: firstLineEnd)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard firstLine.lowercased().hasPrefix("triggers:") else {
            return (triggers: [], body: trimmedResponse)
        }

        let triggerText = String(firstLine.dropFirst("triggers:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let triggers = triggerText
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (triggers: triggers, body: remainingBody)
    }

    private static func parseTriggersFromSingleLine(_ line: String) -> (triggers: [String], body: String) {
        guard line.lowercased().hasPrefix("triggers:") else {
            return (triggers: [], body: line)
        }

        let triggerText = String(line.dropFirst("triggers:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let triggers = triggerText
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (triggers: triggers, body: "")
    }

    private static func renderSessionSummary(
        _ sessionTrace: [SessionTraceEntry],
        trigger: SkillWriteTrigger,
        existingSkill: TeachingSkill?,
        targetBundleId: String?
    ) -> String {
        var lines: [String] = []
        lines.append("trigger: \(trigger.reason.rawValue)")
        lines.append("topic: \(trigger.topic)")
        lines.append("target bundle id: \(targetBundleId ?? "unknown")")
        if let primaryQuestion = SkillTriggerEvaluator.primaryTeachingQuestion(from: sessionTrace) {
            lines.append("primary question: \(primaryQuestion)")
        }
        if let existingSkill {
            lines.append("existing skill id: \(existingSkill.id)")
        }

        for (index, entry) in sessionTrace.enumerated() {
            lines.append("exchange \(index + 1):")
            lines.append("user: \(entry.userTranscript)")
            lines.append("assistant: \(entry.assistantResponse)")
            lines.append("frontmost bundle id: \(entry.bundleId ?? "unknown")")
            lines.append("pointed: \(entry.pointed ? "yes" : "no")")
        }

        return lines.joined(separator: "\n")
    }
}
