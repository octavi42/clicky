//
//  PreferenceSynthesizer.swift
//  leanring-buddy
//
//  Drafts or updates preference memories from a completed session trace.
//

import Foundation

enum PreferenceSynthesizer {
    private static let synthesisSystemPrompt = """
    you write user preference memories for clicky, a screen-native voice tutor.

    given a session transcript where the user stated or corrected a preference, produce a preference memory as plain text with exactly three lines:

    title: short label (5 words max)
    summary: one sentence describing the preference
    body: 1-3 imperative sentences telling clicky how to behave

    keep it concise, practical, and durable. all lowercase.
    """

    private static let patchSystemPrompt = """
    you update an existing user preference memory for clicky, a screen-native voice tutor.

    given the existing preference and a new session, produce an updated memory as plain text with exactly three lines:

    title: short label (5 words max)
    summary: one sentence describing the preference
    body: 1-3 imperative sentences telling clicky how to behave

    patch-first rules:
    - preserve preferences that still apply
    - merge refinements from the latest session
    - do not duplicate or contradict without resolving

    keep it concise, practical, and durable. all lowercase.
    """

    static func synthesizePreference(
        sessionTrace: [SessionTraceEntry],
        gateReasons: [GateReason],
        existingMemory: Memory?,
        targetBundleId: String?,
        claudeAPI: ClaudeAPI
    ) async throws -> Memory {
        let topic = SkillTriggerEvaluator.deriveTopic(from: sessionTrace)
        let isAppSpecific = PreferenceSignalDetector.isClearlyAppSpecificPreference(in: sessionTrace)
        let resolvedBundleId = isAppSpecific ? targetBundleId : nil
        let bundleIds = resolvedBundleId.map { [$0] } ?? []

        let sessionSummary = renderSessionSummary(
            sessionTrace,
            gateReasons: gateReasons,
            existingMemory: existingMemory,
            targetBundleId: resolvedBundleId
        )

        let userPrompt: String
        let systemPrompt: String
        if let existingMemory {
            systemPrompt = patchSystemPrompt
            userPrompt = """
            patch this existing preference using the new session:

            existing preference id: \(existingMemory.id)
            existing title: \(existingMemory.title)
            existing summary: \(existingMemory.summary)
            existing body:
            \(existingMemory.body)

            new session:
            \(sessionSummary)
            """
        } else {
            systemPrompt = synthesisSystemPrompt
            userPrompt = "create a new preference memory from this session:\n\n\(sessionSummary)"
        }

        let response = try await claudeAPI.sendTextMessage(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 400
        )

        let parsed = parseStructuredResponse(from: response.text)
        let memoryId = existingMemory?.id ?? AuxiliaryMemoryMatcher.stableMemoryId(
            category: .preference,
            topic: topic,
            bundleId: resolvedBundleId
        )

        return Memory(
            id: memoryId,
            category: .preference,
            title: parsed.title.isEmpty ? (existingMemory?.title ?? "User preference") : parsed.title,
            summary: parsed.summary.isEmpty ? (existingMemory?.summary ?? "") : parsed.summary,
            body: parsed.body.isEmpty ? (existingMemory?.body ?? response.text) : parsed.body,
            bundleIds: bundleIds.isEmpty ? (existingMemory?.bundleIds ?? []) : bundleIds,
            status: .active,
            isPinned: existingMemory?.isPinned ?? false,
            usageCount: existingMemory?.usageCount ?? 0,
            lastUsed: Date()
        )
    }

    private static func parseStructuredResponse(from responseText: String) -> (title: String, summary: String, body: String) {
        var title = ""
        var summary = ""
        var bodyLines: [String] = []
        var currentSection: String?

        for line in responseText.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            if trimmedLine.lowercased().hasPrefix("title:") {
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

        return (title: title, summary: summary, body: bodyLines.joined(separator: "\n"))
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
