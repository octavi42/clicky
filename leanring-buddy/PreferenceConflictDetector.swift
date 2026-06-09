//
//  PreferenceConflictDetector.swift
//  leanring-buddy
//
//  Blocks merge when two preference texts express opposite choices on the same axis.
//

import Foundation

enum PreferenceConflictDetector {
    private static let conflictingPreferenceGroups: [[String]] = [
        ["short", "brief", "concise", "detailed", "verbose", "expand", "thorough"],
        ["dark", "light"],
        ["javascript", "typescript"],
        ["rust", "go"],
        ["metric", "imperial"],
        ["beginner", "expert"],
        ["keyboard", "menu", "clicking", "visually"],
        ["pointing", "describe"]
    ]

    static func hasConflict(between newTopic: String, and existingText: String) -> Bool {
        if hasReversedPreferOverPair(between: newTopic, and: existingText) {
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

        for preferenceGroup in conflictingPreferenceGroups {
            let hitsA = preferenceGroup.filter { tokensA.contains($0) }
            let hitsB = preferenceGroup.filter { tokensB.contains($0) }
            guard !hitsA.isEmpty, !hitsB.isEmpty else { continue }

            if Set(hitsA) != Set(hitsB) {
                return true
            }
        }

        return false
    }
}
