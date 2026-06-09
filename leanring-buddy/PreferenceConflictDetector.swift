//
//  PreferenceConflictDetector.swift
//  leanring-buddy
//
//  Blocks merge when two preference texts express opposite choices on the same axis.
//

import Foundation

enum PreferenceSameAxisMatcher {
    private static let answerFocusTokens: Set<String> = ["answer", "answers", "response", "responses"]
    private static let brevityTokens: Set<String> = ["short", "brief", "concise", "sentence", "sentences", "one"]
    private static let verbosityTokens: Set<String> = ["detailed", "verbose", "expand", "thorough", "examples"]

    /// True when both texts express answer-length brevity on the same side of the axis.
    static func isSameAnswerLengthPreferenceAxis(between textA: String, and textB: String) -> Bool {
        let tokensA = Set(SkillMatcher.meaningfulTokens(textA))
        let tokensB = Set(SkillMatcher.meaningfulTokens(textB))

        guard !tokensA.intersection(answerFocusTokens).isEmpty,
              !tokensB.intersection(answerFocusTokens).isEmpty else {
            return false
        }

        guard !tokensA.intersection(brevityTokens).isEmpty,
              !tokensB.intersection(brevityTokens).isEmpty else {
            return false
        }

        let textAVerbosity = !tokensA.intersection(verbosityTokens).isEmpty
        let textBVerbosity = !tokensB.intersection(verbosityTokens).isEmpty
        return textAVerbosity == textBVerbosity
    }
}

enum PreferenceConflictDetector {
    /// Each inner array is a pair of opposing subgroups on the same preference axis.
    /// Two texts conflict only when they hit different subgroups, not when one is a
    /// subset of the other on the same side (e.g. "short" vs "short and concise").
    private static let opposingPreferenceSubgroups: [[[String]]] = [
        [["short", "brief", "concise"], ["detailed", "verbose", "expand", "thorough"]],
        [["dark"], ["light"]],
        [["javascript"], ["typescript"]],
        [["rust"], ["go"]],
        [["metric"], ["imperial"]],
        [["beginner", "slowly", "slow"], ["expert", "fast"]],
        [["keyboard"], ["menu", "clicking", "visually"]],
        [["pointing"], ["describe"]],
        [["jargon", "plain", "simple"], ["technical", "terminology"]],
        [["step", "numbered", "walk"], ["quick", "one-line", "line"]],
        [["confirm", "asking"], ["without"]]
    ]

    static func hasConflict(between newTopic: String, and existingText: String) -> Bool {
        if hasReversedPreferOverPair(between: newTopic, and: existingText) {
            return true
        }

        if hasInstructionOrderConflict(between: newTopic, and: existingText) {
            return true
        }

        if hasConfirmationStyleConflict(between: newTopic, and: existingText) {
            return true
        }

        return hasConflictingPreferenceGroup(between: newTopic, and: existingText)
    }

    private static func hasReversedPreferOverPair(between textA: String, and textB: String) -> Bool {
        guard let pairA = extractPreferOverPair(from: textA),
              let pairB = extractPreferOverPair(from: textB) else {
            return false
        }

        return pairA.preferred == pairB.dispreferred && pairA.dispreferred == pairB.preferred
    }

    private static func hasInstructionOrderConflict(between textA: String, and textB: String) -> Bool {
        let normalizedTextA = textA.lowercased()
        let normalizedTextB = textB.lowercased()

        let textAUsesCodeFirstPattern = normalizedTextA.contains("code first") ||
            normalizedTextA.contains("show code") ||
            normalizedTextA.contains("lead with a code")
        let textBUsesCodeFirstPattern = normalizedTextB.contains("code first") ||
            normalizedTextB.contains("show code") ||
            normalizedTextB.contains("lead with a code")

        let textAUsesConceptsFirstPattern = normalizedTextA.contains("before") &&
            normalizedTextA.contains("code") &&
            (normalizedTextA.contains("explain") || normalizedTextA.contains("concept"))
        let textBUsesConceptsFirstPattern = normalizedTextB.contains("before") &&
            normalizedTextB.contains("code") &&
            (normalizedTextB.contains("explain") || normalizedTextB.contains("concept"))

        return (textAUsesCodeFirstPattern && textBUsesConceptsFirstPattern) ||
            (textAUsesConceptsFirstPattern && textBUsesCodeFirstPattern)
    }

    private static func hasConfirmationStyleConflict(between textA: String, and textB: String) -> Bool {
        let normalizedTextA = textA.lowercased()
        let normalizedTextB = textB.lowercased()

        let textASkipsConfirmation = normalizedTextA.contains("without asking") ||
            normalizedTextA.contains("without confirmation") ||
            normalizedTextA.contains("just do it")
        let textBSkipsConfirmation = normalizedTextB.contains("without asking") ||
            normalizedTextB.contains("without confirmation") ||
            normalizedTextB.contains("just do it")

        let textARequiresConfirmation = normalizedTextA.contains("confirm") ||
            normalizedTextA.contains("ask before")
        let textBRequiresConfirmation = normalizedTextB.contains("confirm") ||
            normalizedTextB.contains("ask before")

        return (textASkipsConfirmation && textBRequiresConfirmation) ||
            (textBSkipsConfirmation && textARequiresConfirmation)
    }

    private static func extractPreferOverPair(from text: String) -> (preferred: String, dispreferred: String)? {
        let normalizedText = text.lowercased()
        guard let preferRange = normalizedText.range(of: "prefer ") else { return nil }
        guard let overRange = normalizedText.range(of: " over ", range: preferRange.upperBound..<normalizedText.endIndex) else {
            return nil
        }

        let preferredPhrase = String(normalizedText[preferRange.upperBound..<overRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dispreferredPhrase = String(normalizedText[overRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let preferredToken = firstPreferenceToken(in: preferredPhrase),
              let dispreferredToken = firstPreferenceToken(in: dispreferredPhrase) else {
            return nil
        }

        return (preferred: preferredToken, dispreferred: dispreferredToken)
    }

    /// Prefer/over parsing must keep short language tokens like "go" and "js".
    /// SkillMatcher.meaningfulTokens drops tokens shorter than three characters.
    private static func firstPreferenceToken(in phrase: String) -> String? {
        phrase
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first { token in
                !token.isEmpty && !SkillMatcher.topicStopwords.contains(token)
            }
    }

    private static func hasConflictingPreferenceGroup(between textA: String, and textB: String) -> Bool {
        let tokensA = Set(SkillMatcher.meaningfulTokens(textA))
        let tokensB = Set(SkillMatcher.meaningfulTokens(textB))

        for opposingSubgroups in opposingPreferenceSubgroups {
            guard let subgroupIndexA = matchedSubgroupIndex(in: tokensA, subgroups: opposingSubgroups),
                  let subgroupIndexB = matchedSubgroupIndex(in: tokensB, subgroups: opposingSubgroups) else {
                continue
            }

            if subgroupIndexA != subgroupIndexB {
                return true
            }
        }

        return false
    }

    private static func matchedSubgroupIndex(in tokens: Set<String>, subgroups: [[String]]) -> Int? {
        for (subgroupIndex, subgroupTokens) in subgroups.enumerated() {
            if !tokens.intersection(subgroupTokens).isEmpty {
                return subgroupIndex
            }
        }
        return nil
    }
}
