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

    static func hasStatedPreference(in turns: [SessionTraceEntry]) -> Bool {
        turns.contains { turn in
            containsPreferencePhrase(in: turn.userTranscript)
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
