//
//  RoutineSynthesizer.swift
//  leanring-buddy
//
//  Drafts or updates routine memories from a completed session trace.
//

import Foundation

enum RoutineSynthesizer {
    /// Outcome of a synthesis pass: the memory to persist plus whether it patched
    /// an existing routine (so the caller can show the right toast / analytics).
    struct SynthesisResult {
        let memory: Memory
        let updatedExistingMemory: Bool
    }

    private static let synthesisSystemPrompt = """
    you write routine memories for clicky, a screen-native voice tutor.

    given a session transcript of a recurring multi-step workflow, produce a routine memory as plain text with exactly three lines:

    title: short label for the routine (5 words max)
    summary: one sentence describing when this routine runs
    body: ordered numbered steps the user follows each time

    keep it concise, practical, and specific to macos. all lowercase.
    """

    /// Combined judge + writer prompt. The model decides whether the new session
    /// is the same recurring workflow as one of the supplied candidates, then writes
    /// the memory. Same-workflow matches use last-write-wins: the latest steps replace
    /// the old ones, so the user never accumulates parallel copies of one routine.
    private static let reconcileSystemPrompt = """
    you maintain routine memories for clicky, a screen-native voice tutor.

    you are given a new session of a recurring workflow and a list of existing candidate routines. do two things:

    1. decide whether the new session is the SAME recurring workflow as one of the candidates, or a different workflow.
       - "same workflow" means the same goal in the same app(s), even if the exact steps changed since last time.
       - if it is the same workflow as a candidate, update that candidate with the latest steps (last-write-wins): the newest run describes how the routine works now.
       - create new only when the workflow differs from every candidate (different goal or different app).
       - when unsure whether it is the same workflow, create new.

    2. produce the routine memory describing the CURRENT (latest) steps.

    respond as plain text with exactly these lines:

    decision: update <id> | create
    title: short label for the routine (5 words max)
    summary: one sentence describing when this routine runs
    body: ordered numbered steps the user follows each time

    when decision is "update <id>", use the exact id of the candidate you are updating and rewrite the steps to reflect the latest run. when decision is "create", omit the id.
    keep it concise, practical, and specific to macos. all lowercase.
    """

    static func synthesizeRoutine(
        sessionTrace: [SessionTraceEntry],
        gateReasons: [GateReason],
        candidateMemories: [Memory],
        targetBundleId: String?,
        claudeAPI: ClaudeAPI
    ) async throws -> SynthesisResult {
        let topic = SkillTriggerEvaluator.deriveTopic(from: sessionTrace)

        let sessionSummary = renderSessionSummary(
            sessionTrace,
            gateReasons: gateReasons,
            existingMemory: nil,
            targetBundleId: targetBundleId
        )

        let userPrompt: String
        let systemPrompt: String
        if candidateMemories.isEmpty {
            systemPrompt = synthesisSystemPrompt
            userPrompt = "create a new routine memory from this session:\n\n\(sessionSummary)"
        } else {
            systemPrompt = reconcileSystemPrompt
            userPrompt = """
            new routine session:
            \(sessionSummary)

            existing candidate routines:
            \(renderCandidates(candidateMemories))
            """
        }

        let response = try await claudeAPI.sendTextMessage(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 600
        )

        let parsed = parseStructuredResponse(from: response.text)

        let existingMemory = parsed.updateMemoryId.flatMap { updateId in
            candidateMemories.first { $0.id == updateId }
        }

        let bundleIds: [String]
        if let targetBundleId {
            bundleIds = [targetBundleId]
        } else if let existingMemory, !existingMemory.bundleIds.isEmpty {
            bundleIds = existingMemory.bundleIds
        } else {
            bundleIds = orderedUniqueBundleIds(from: sessionTrace)
        }

        let memoryId = existingMemory?.id ?? AuxiliaryMemoryMatcher.stableMemoryId(
            category: .routine,
            topic: topic,
            bundleId: targetBundleId
        )

        let memory = Memory(
            id: memoryId,
            category: .routine,
            title: parsed.title.isEmpty ? (existingMemory?.title ?? "Recurring routine") : parsed.title,
            summary: parsed.summary.isEmpty ? (existingMemory?.summary ?? "") : parsed.summary,
            body: parsed.body.isEmpty ? (existingMemory?.body ?? response.text) : parsed.body,
            bundleIds: bundleIds,
            status: .active,
            isPinned: existingMemory?.isPinned ?? false,
            usageCount: existingMemory?.usageCount ?? 0,
            lastUsed: Date()
        )

        return SynthesisResult(memory: memory, updatedExistingMemory: existingMemory != nil)
    }

    private static func renderCandidates(_ candidates: [Memory]) -> String {
        candidates.map { candidate in
            """
            - id: \(candidate.id)
              title: \(candidate.title)
              summary: \(candidate.summary)
              body: \(candidate.body)
            """
        }.joined(separator: "\n")
    }

    private static func parseStructuredResponse(
        from responseText: String
    ) -> (updateMemoryId: String?, title: String, summary: String, body: String) {
        var updateMemoryId: String?
        var title = ""
        var summary = ""
        var bodyLines: [String] = []
        var currentSection: String?

        for line in responseText.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            if trimmedLine.lowercased().hasPrefix("decision:") {
                updateMemoryId = parseUpdateMemoryId(
                    from: String(trimmedLine.dropFirst("decision:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                )
                currentSection = "decision"
            } else if trimmedLine.lowercased().hasPrefix("title:") {
                title = String(trimmedLine.dropFirst("title:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentSection = "title"
            } else if trimmedLine.lowercased().hasPrefix("summary:") {
                summary = String(trimmedLine.dropFirst("summary:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentSection = "summary"
            } else if trimmedLine.lowercased().hasPrefix("body:") {
                let inlineBody = String(trimmedLine.dropFirst("body:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !inlineBody.isEmpty {
                    bodyLines.append(inlineBody)
                }
                currentSection = "body"
            } else if currentSection == "body" {
                bodyLines.append(trimmedLine)
            }
        }

        return (updateMemoryId: updateMemoryId, title: title, summary: summary, body: bodyLines.joined(separator: "\n"))
    }

    /// Parses the `decision:` value. Returns the candidate id to update, or nil for "create".
    private static func parseUpdateMemoryId(from decisionValue: String) -> String? {
        let normalizedDecision = decisionValue.lowercased()
        guard normalizedDecision.hasPrefix("update") else { return nil }

        let remainder = String(decisionValue.dropFirst("update".count))
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t<>"))
        return remainder.isEmpty ? nil : remainder
    }

    private static func orderedUniqueBundleIds(from sessionTrace: [SessionTraceEntry]) -> [String] {
        var seenBundleIds = Set<String>()
        var orderedBundleIds: [String] = []

        for bundleId in sessionTrace.compactMap(\.bundleId) {
            if seenBundleIds.insert(bundleId).inserted {
                orderedBundleIds.append(bundleId)
            }
        }

        return orderedBundleIds
    }

    private static func renderSessionSummary(
        _ sessionTrace: [SessionTraceEntry],
        gateReasons: [GateReason],
        existingMemory: Memory?,
        targetBundleId: String?
    ) -> String {
        var lines: [String] = []
        lines.append("gate reasons: \(gateReasons.map(\.rawValue).joined(separator: ", "))")
        lines.append("target bundle id: \(targetBundleId ?? "unknown")")
        if let existingMemory {
            lines.append("existing memory id: \(existingMemory.id)")
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
