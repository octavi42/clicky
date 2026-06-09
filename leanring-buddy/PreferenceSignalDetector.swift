//
//  PreferenceSignalDetector.swift
//  leanring-buddy
//
//  Cheap deterministic heuristics for detecting stated user preferences
//  in session transcripts. Used by MemoryGate (no LLM).
//

import Foundation

enum PreferenceSignalDetector {
    private static let preferencePhrases = [
        "always",
        "from now on",
        "i prefer",
        "i'd prefer",
        "id prefer",
        "i like when",
        "stop doing",
        "don't do",
        "dont do",
        "instead of",
        "keep it short",
        "keep answers short",
        "be concise",
        "use the keyboard",
        "keyboard shortcut",
        "no menus",
        "avoid the menu",
        "never show",
        "every time"
    ]

    private static let styleCorrectionPhrases = [
        "too long",
        "too verbose",
        "shorter",
        "more concise",
        "less detail",
        "not what i asked",
        "that's not what i meant",
        "thats not what i meant",
        "wrong tone",
        "too much"
    ]

    /// Nouns that indicate the user is talking about assistant behavior, not screen content.
    private static let assistantBehaviorNouns: Set<String> = [
        "answer", "answers", "response", "responses", "reply", "replies",
        "explanation", "explanations", "tone", "format", "summary", "summaries",
        "language", "wording", "style", "help", "instructions", "sentence", "sentences"
    ]

    /// Imperative openers for implicit assistant-behavior preferences.
    private static let implicitPreferenceOpeners = [
        "give ",
        "keep ",
        "make ",
        "use ",
        "respond ",
        "answer ",
        "avoid ",
        "don't ",
        "dont ",
        "never ",
        "always ",
        "be more ",
        "be less ",
        "talk less ",
        "talk more "
    ]

    /// Screen-question patterns that should not be saved as preferences.
    private static let screenQuestionPrefixes = [
        "how do i ",
        "how can i ",
        "how to ",
        "what is ",
        "what's ",
        "whats ",
        "where is ",
        "where's ",
        "wheres ",
        "when is ",
        "why is ",
        "which ",
        "show me ",
        "can you show ",
        "help me find ",
        "help me with ",
        "tell me how ",
        "tell me where ",
        "what does ",
        "what do i "
    ]

    static func hasStatedPreference(in turns: [SessionTraceEntry]) -> Bool {
        turns.contains { turn in
            containsAnyPreferenceSignal(in: turn.userTranscript)
        }
    }

    static func hasStyleCorrectionAcrossTurns(in turns: [SessionTraceEntry]) -> Bool {
        guard turns.count >= 2 else { return false }

        let correctionTurnCount = turns.filter { turn in
            containsStyleCorrectionPhrase(in: turn.userTranscript)
        }.count

        return correctionTurnCount >= 2
    }

    static func isClearlyAppSpecificPreference(in turns: [SessionTraceEntry]) -> Bool {
        turns.contains { turn in
            TeachingSkill.detectBundleId(in: turn.userTranscript) != nil
        }
    }

    /// Returns the user transcript most useful for dedup matching, preferring the full
    /// preference statement over a shortened derived topic.
    static func preferenceMatchText(from turns: [SessionTraceEntry]) -> String {
        if let preferenceTranscript = primaryPreferenceTranscript(in: turns) {
            return preferenceTranscript
        }

        return SkillTriggerEvaluator.deriveTopic(from: turns)
    }

    static func primaryPreferenceTranscript(in turns: [SessionTraceEntry]) -> String? {
        turns.last { turn in
            containsAnyPreferenceSignal(in: turn.userTranscript)
        }?.userTranscript
    }

    static func containsAnyPreferenceSignal(in transcript: String) -> Bool {
        containsPreferencePhrase(in: transcript) ||
        containsImplicitAssistantPreference(in: transcript)
    }

    private static func containsPreferencePhrase(in transcript: String) -> Bool {
        let normalizedTranscript = transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTranscript.isEmpty else { return false }

        let transcriptWords = words(from: normalizedTranscript)
        return preferencePhrases.contains { phrase in
            containsContiguousWords(words(from: phrase), in: transcriptWords)
        }
    }

    private static func containsImplicitAssistantPreference(in transcript: String) -> Bool {
        let normalizedTranscript = transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTranscript.isEmpty else { return false }
        guard !looksLikeScreenQuestion(normalizedTranscript) else { return false }

        let transcriptWords = Set(words(from: normalizedTranscript))
        let mentionsAssistantBehavior = assistantBehaviorNouns.contains { transcriptWords.contains($0) }
        guard mentionsAssistantBehavior else { return false }

        return implicitPreferenceOpeners.contains { opener in
            normalizedTranscript.hasPrefix(opener) ||
            normalizedTranscript.contains(" \(opener.trimmingCharacters(in: .whitespaces))")
        }
    }

    private static func looksLikeScreenQuestion(_ normalizedTranscript: String) -> Bool {
        screenQuestionPrefixes.contains { normalizedTranscript.hasPrefix($0) }
    }

    private static func containsStyleCorrectionPhrase(in transcript: String) -> Bool {
        let normalizedTranscript = transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTranscript.isEmpty else { return false }

        let transcriptWords = words(from: normalizedTranscript)
        return styleCorrectionPhrases.contains { phrase in
            containsContiguousWords(words(from: phrase), in: transcriptWords)
        }
    }

    private static func words(from text: String) -> [String] {
        text
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
