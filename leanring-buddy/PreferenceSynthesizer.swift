//
//  PreferenceSynthesizer.swift
//  leanring-buddy
//
//  Drafts or updates preference memories from a completed session trace.
//

import Foundation

enum PreferenceSynthesizer {
    /// Outcome of a synthesis pass: the memory to persist plus whether it patched
    /// an existing preference (so the caller can show the right toast / analytics).
    struct SynthesisResult {
        let memory: Memory
        let updatedExistingMemory: Bool
    }

    private static let synthesisSystemPrompt = """
    you write user preference memories for clicky, a screen-native voice tutor.

    given a session transcript where the user stated or corrected a preference, produce a preference memory as plain text with exactly three lines:

    title: short label (5 words max)
    summary: one sentence describing the preference
    body: 1-3 imperative sentences telling clicky how to behave

    keep it concise, practical, and durable. all lowercase.
    """

    /// Combined judge + writer prompt. The model first decides whether the new
    /// preference belongs to the same behavioral axis as one of the supplied
    /// candidates, then writes the memory. Same-axis matches use last-write-wins:
    /// the newest stated value replaces the old one (even when it reverses it), so
    /// the user never ends up with two contradictory active preferences. This
    /// replaces a brittle similarity-threshold merge that failed on short paraphrases.
    private static let reconcileSystemPrompt = """
    you maintain user preference memories for clicky, a screen-native voice tutor.

    you are given a new preference the user just stated and a list of existing candidate preferences. do two things:

    1. decide whether the new preference is on the SAME behavioral axis as one of the candidates, or covers a different aspect of behavior.
       - "axis" means the same dimension of behavior: answer length (short / one sentence / detailed), tone (formal / casual), code style, confirmation behavior, units, etc.
       - if the new preference is on the same axis as a candidate, update that candidate — even if the new value reverses the old one. the user is revising their preference, and the latest statement wins (last-write-wins). example: an existing "keep answers short" candidate should be updated by "give detailed answers" to now describe detailed answers, so the user never has two contradictory preferences.
       - create new only when the preference covers a different aspect of behavior than every candidate (e.g. "use keyboard shortcuts" vs an answer-length candidate).
       - when unsure whether two preferences share an axis, create new.

    2. produce the memory text describing the user's CURRENT (latest) intent.

    respond as plain text with exactly these lines:

    decision: update <id> | create
    title: short label (5 words max)
    summary: one sentence describing the preference
    body: 1-3 imperative sentences telling clicky how to behave

    when decision is "update <id>", use the exact id of the candidate you are updating and rewrite the memory to reflect the latest value. when decision is "create", omit the id.
    keep it concise, practical, and durable. all lowercase.
    """

    static func synthesizePreference(
        sessionTrace: [SessionTraceEntry],
        gateReasons: [GateReason],
        candidateMemories: [Memory],
        targetBundleId: String?,
        dedupTopic: String,
        claudeAPI: ClaudeAPI
    ) async throws -> SynthesisResult {
        // Mint the stable ID from the exact same text the caller used for recall
        // (`PreferenceSignalDetector.preferenceMatchText`). If this used a different
        // topic source, a future restatement's recall key would not match this
        // memory's ID and dedup would miss, accumulating duplicates.
        let topic = dedupTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? SkillTriggerEvaluator.deriveTopic(from: sessionTrace)
            : dedupTopic
        let isAppSpecific = PreferenceSignalDetector.isClearlyAppSpecificPreference(in: sessionTrace)
        let resolvedBundleId = isAppSpecific ? targetBundleId : nil
        let bundleIds = resolvedBundleId.map { [$0] } ?? []

        let sessionSummary = renderSessionSummary(
            sessionTrace,
            gateReasons: gateReasons,
            existingMemory: nil,
            targetBundleId: resolvedBundleId
        )

        let userPrompt: String
        let systemPrompt: String
        if candidateMemories.isEmpty {
            systemPrompt = synthesisSystemPrompt
            userPrompt = "create a new preference memory from this session:\n\n\(sessionSummary)"
        } else {
            systemPrompt = reconcileSystemPrompt
            userPrompt = """
            new preference session:
            \(sessionSummary)

            existing candidate preferences:
            \(renderCandidates(candidateMemories))
            """
        }

        let response = try await claudeAPI.sendTextMessage(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 400
        )

        let parsed = parseStructuredResponse(from: response.text)

        let stableMemoryId = AuxiliaryMemoryMatcher.stableMemoryId(
            category: .preference,
            topic: topic,
            bundleId: resolvedBundleId
        )

        // Prefer the candidate the LLM chose to update; otherwise fall back to a
        // candidate whose id equals the computed stable id. The fallback guards the
        // "create" path against an id collision: `save` upserts by id, so writing a
        // fresh Memory over an existing id would wipe its usageCount / isPinned /
        // bundleIds. `mergeCandidates` always surfaces an exact stable-id match, so
        // a colliding memory in scope is present here to copy metadata from.
        let existingMemory = parsed.updateMemoryId.flatMap { updateId in
            candidateMemories.first { $0.id == updateId }
        } ?? candidateMemories.first { $0.id == stableMemoryId }

        let memoryId = existingMemory?.id ?? stableMemoryId

        let memory = Memory(
            id: memoryId,
            category: .preference,
            title: parsed.title.isEmpty ? (existingMemory?.title ?? "User preference") : parsed.title,
            summary: parsed.summary.isEmpty ? (existingMemory?.summary ?? "") : parsed.summary,
            body: parsed.body.isEmpty ? (existingMemory?.body ?? response.text) : parsed.body,
            // Scope changes only on an explicit app signal. If this restatement
            // names an app, use that scope; otherwise keep the existing memory's
            // scope rather than silently broadening an app-scoped preference to
            // global. An app-agnostic phrasing is not an "apply everywhere" command,
            // and leaking a scoped preference (e.g. "in Xcode use tabs") into every
            // app is the worse failure than under-applying it.
            bundleIds: bundleIds.isEmpty ? (existingMemory?.bundleIds ?? []) : bundleIds,
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

    private static func renderSessionSummary(
        _ sessionTrace: [SessionTraceEntry],
        gateReasons: [GateReason],
        existingMemory: Memory?,
        targetBundleId: String?
    ) -> String {
        var lines: [String] = []
        lines.append("gate reasons: \(gateReasons.map(\.rawValue).joined(separator: ", "))")
        lines.append("target bundle id: \(targetBundleId ?? "app-agnostic")")
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
