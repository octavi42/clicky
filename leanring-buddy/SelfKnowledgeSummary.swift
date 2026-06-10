//
//  SelfKnowledgeSummary.swift
//  leanring-buddy
//
//  "What did you learn about me?" support. The intent detector recognizes the
//  voice question deterministically (no LLM); the prompt builder composes a
//  hard-grounded summary prompt over the active local memories, plus
//  deterministic fallbacks for when nothing has been learned yet or the
//  Claude call fails. Mirrors the ReceiptExplanationPromptBuilder pattern.
//

import Foundation

/// Cheap deterministic detection of "what did you learn about me?"-style voice
/// queries, checked before the normal screenshot pipeline runs.
enum SelfKnowledgeIntentDetector {
    /// Phrases that ask Clicky to summarize what it knows about the user.
    /// Matched as contiguous word sequences so casing, punctuation, and
    /// surrounding words ("hey clicky, what do you know about me today?")
    /// don't matter. Word-level matching also prevents false positives like
    /// "what do you know about merge conflicts" — "merge" is not "me".
    private static let selfKnowledgeQueryPhrases = [
        "what did you learn about me",
        "what have you learned about me",
        "what did you learn from me",
        "what do you know about me",
        "what do you remember about me",
        "what have you saved about me",
        "what have you noticed about me",
        "tell me what you know about me",
        "tell me what you learned about me",
        "what memories do you have about me",
        "what have you learned about how i work"
    ]

    static func isSelfKnowledgeQuery(transcript: String) -> Bool {
        let transcriptWords = words(from: transcript)
        guard !transcriptWords.isEmpty else { return false }

        return selfKnowledgeQueryPhrases.contains { phrase in
            containsContiguousWords(words(from: phrase), in: transcriptWords)
        }
    }

    private static func words(from text: String) -> [String] {
        text
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func containsContiguousWords(_ phraseWords: [String], in transcriptWords: [String]) -> Bool {
        guard !phraseWords.isEmpty, phraseWords.count <= transcriptWords.count else { return false }
        for startIndex in 0...(transcriptWords.count - phraseWords.count) {
            if Array(transcriptWords[startIndex..<startIndex + phraseWords.count]) == phraseWords {
                return true
            }
        }
        return false
    }
}

/// Composes the grounded prompt for the spoken "what did you learn about me?"
/// summary and the deterministic fallbacks used when no memories exist yet or
/// the Claude call fails.
enum SelfKnowledgePromptBuilder {
    static let summarySystemPrompt = """
    you are clicky, a friendly screen-native voice companion. the user asked what you have learned about them.

    you are given verified facts about the memories you currently hold: teaching skills, stated preferences, recurring routines, the user's niche, and their connected vault. summarize, speaking as clicky in first person, what you know about the user.

    hard rules:
    - only use the facts provided below. never invent skills, preferences, routines, apps, niches, or counts that are not listed.
    - if a category has no facts, simply don't mention it. do not guess.
    - lead with the most useful things you know, not with category names or counts.
    - 4-5 short sentences, written to be spoken aloud. conversational and warm. no markdown, no lists.
    - all lowercase.
    - end by mentioning the user can review or edit all of this in the memories library.
    """

    /// Spoken verbatim (no LLM call) when no active memories exist yet.
    static let emptyMemoryStateAnswer =
        "i haven't learned anything about you yet. " +
        "teach me something on screen or tell me how you like your answers, and i'll start remembering."

    /// How many memories per category to include as prompt facts. The rest are
    /// represented by the total count so Clicky can honestly say "and N more".
    private static let maximumMemoriesPerCategoryInPrompt = 5

    static func buildSummaryUserPrompt(
        activeSkills: [Memory],
        activePreferences: [Memory],
        activeRoutines: [Memory],
        nicheDisplayName: String?,
        vaultNoteCount: Int?
    ) -> String {
        var promptSections: [String] = []

        if let nicheDisplayName {
            promptSections.append("the user's working niche: \(nicheDisplayName.lowercased())")
        }

        if let skillsSection = factSection(
            header: "teaching skills clicky learned",
            memories: activeSkills
        ) {
            promptSections.append(skillsSection)
        }

        if let preferencesSection = factSection(
            header: "preferences the user stated",
            memories: activePreferences
        ) {
            promptSections.append(preferencesSection)
        }

        if let routinesSection = factSection(
            header: "recurring routines clicky noticed",
            memories: activeRoutines
        ) {
            promptSections.append(routinesSection)
        }

        if let vaultNoteCount {
            promptSections.append("connected personal vault: \(vaultNoteCount) searchable markdown notes")
        }

        promptSections.append("summarize what you have learned about the user, using only the facts above.")
        return promptSections.joined(separator: "\n\n")
    }

    /// Template summary used when the Claude call fails, so both the voice
    /// query and the Brain tab button still answer with grounded counts.
    static func buildDeterministicFallbackSummary(
        activeSkillCount: Int,
        activePreferenceCount: Int,
        activeRoutineCount: Int,
        nicheDisplayName: String?
    ) -> String {
        var countLabels: [String] = []
        if activeSkillCount > 0 {
            countLabels.append(pluralizedCountLabel(activeSkillCount, singularNoun: "skill"))
        }
        if activePreferenceCount > 0 {
            countLabels.append(pluralizedCountLabel(activePreferenceCount, singularNoun: "preference"))
        }
        if activeRoutineCount > 0 {
            countLabels.append(pluralizedCountLabel(activeRoutineCount, singularNoun: "routine"))
        }

        guard !countLabels.isEmpty else {
            return emptyMemoryStateAnswer
        }

        var sentenceParts: [String] = []
        sentenceParts.append("so far i've learned \(joinedNaturalList(countLabels)) from working with you.")
        if let nicheDisplayName {
            sentenceParts.append("i mostly see you working as a \(nicheDisplayName.lowercased()).")
        }
        sentenceParts.append("you can review all of it in the memories library.")
        return sentenceParts.joined(separator: " ")
    }

    /// Builds one category's fact block: a header (with honest truncation
    /// counts when the cap kicks in) followed by one fact line per memory.
    /// Returns nil when the category is empty so it is omitted entirely.
    private static func factSection(header: String, memories: [Memory]) -> String? {
        guard !memories.isEmpty else { return nil }

        let mostUsefulFirst = memories.sorted { firstMemory, secondMemory in
            if firstMemory.usageCount != secondMemory.usageCount {
                return firstMemory.usageCount > secondMemory.usageCount
            }
            let firstLastUsed = firstMemory.lastUsed ?? .distantPast
            let secondLastUsed = secondMemory.lastUsed ?? .distantPast
            if firstLastUsed != secondLastUsed {
                return firstLastUsed > secondLastUsed
            }
            return firstMemory.title < secondMemory.title
        }
        let includedMemories = Array(mostUsefulFirst.prefix(maximumMemoriesPerCategoryInPrompt))

        let headerLine: String
        if memories.count > includedMemories.count {
            headerLine = "\(header) (showing the \(includedMemories.count) most used of \(memories.count) total):"
        } else {
            headerLine = "\(header):"
        }

        let factLines = includedMemories.map { memory in
            var factLine = "- \"\(memory.title)\""
            let trimmedSummary = memory.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSummary.isEmpty {
                factLine += ": \(trimmedSummary)"
            }
            if let appDisplayName = TeachingSkill.displayName(forBundleId: memory.bundleIds.first) {
                factLine += " (app: \(appDisplayName))"
            }
            return factLine
        }

        return ([headerLine] + factLines).joined(separator: "\n")
    }

    private static func pluralizedCountLabel(_ count: Int, singularNoun: String) -> String {
        count == 1 ? "1 \(singularNoun)" : "\(count) \(singularNoun)s"
    }

    /// Joins items the way they'd be spoken: "a", "a and b", "a, b, and c".
    private static func joinedNaturalList(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return items[0]
        case 2:
            return "\(items[0]) and \(items[1])"
        default:
            let allButLast = items.dropLast().joined(separator: ", ")
            return "\(allButLast), and \(items[items.count - 1])"
        }
    }
}
