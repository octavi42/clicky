//
//  RoutineSynthesizer.swift
//  leanring-buddy
//
//  Drafts or updates routine memories from a completed session trace.
//

import Foundation

enum RoutineSynthesizer {
    private static let synthesisSystemPrompt = """
    you write routine memories for clicky, a screen-native voice tutor.

    given a session transcript of a recurring multi-step workflow, produce a routine memory as plain text with exactly three lines:

    title: short label for the routine (5 words max)
    summary: one sentence describing when this routine runs
    body: ordered numbered steps the user follows each time

    keep it concise, practical, and specific to macos. all lowercase.
    """

    private static let patchSystemPrompt = """
    you update an existing routine memory for clicky, a screen-native voice tutor.

    given the existing routine and a new session, produce an updated memory as plain text with exactly three lines:

    title: short label for the routine (5 words max)
    summary: one sentence describing when this routine runs
    body: ordered numbered steps the user follows each time

    patch-first rules:
    - preserve steps that still work
    - merge refinements from the latest session
    - do not duplicate steps or create a parallel workflow

    keep it concise, practical, and specific to macos. all lowercase.
    """

    static func synthesizeRoutine(
        sessionTrace: [SessionTraceEntry],
        gateReasons: [GateReason],
        existingMemory: Memory?,
        targetBundleId: String?,
        claudeAPI: ClaudeAPI
    ) async throws -> Memory {
        let topic = SkillTriggerEvaluator.deriveTopic(from: sessionTrace)
        let bundleIds: [String]
        if let targetBundleId {
            bundleIds = [targetBundleId]
        } else if let existingMemory, !existingMemory.bundleIds.isEmpty {
            bundleIds = existingMemory.bundleIds
        } else {
            bundleIds = orderedUniqueBundleIds(from: sessionTrace)
        }

        let sessionSummary = renderSessionSummary(
            sessionTrace,
            gateReasons: gateReasons,
            existingMemory: existingMemory,
            targetBundleId: targetBundleId
        )

        let userPrompt: String
        let systemPrompt: String
        if let existingMemory {
            systemPrompt = patchSystemPrompt
            userPrompt = """
            patch this existing routine using the new session:

            existing routine id: \(existingMemory.id)
            existing title: \(existingMemory.title)
            existing summary: \(existingMemory.summary)
            existing body:
            \(existingMemory.body)

            new session:
            \(sessionSummary)
            """
        } else {
            systemPrompt = synthesisSystemPrompt
            userPrompt = "create a new routine memory from this session:\n\n\(sessionSummary)"
        }

        let response = try await claudeAPI.sendTextMessage(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 600
        )

        let parsed = parseStructuredResponse(from: response.text)
        let memoryId = existingMemory?.id ?? AuxiliaryMemoryMatcher.stableMemoryId(
            category: .routine,
            topic: topic,
            bundleId: targetBundleId
        )

        return Memory(
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
