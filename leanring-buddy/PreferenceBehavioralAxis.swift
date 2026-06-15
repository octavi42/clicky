//
//  PreferenceBehavioralAxis.swift
//  leanring-buddy
//
//  Deterministic behavioral-axis detection for preference dedup recall,
//  pre-judge routing, and post-LLM validation.
//

import Foundation

enum PreferenceBehavioralAxis: String, CaseIterable, Codable {
    case answerLength
    case inputModality
    case visualTheme
    case codeLanguage
    case confirmationStyle
    case plainLanguage
    case explanationStructure
    case expertisePace
    case measurementUnits
    case tone
    case instructionOrder
}

enum PreferenceSameAxisMatcher {
    private static let answerFocusTokens: Set<String> = ["answer", "answers", "response", "responses"]
    private static let brevityTokens: Set<String> = ["short", "brief", "concise", "sentence", "sentences", "one"]
    private static let verbosityTokens: Set<String> = ["detailed", "verbose", "expand", "thorough", "examples", "deeper"]

    private static let toneTokens: Set<String> = ["friendly", "casual", "formal", "warm", "professional"]
    private static let bulletStructureTokens: Set<String> = ["bullet", "bullets", "list"]

    /// Axes mentioned by the text — used for recall boost and same-axis checks.
    static func behavioralAxes(in text: String) -> Set<PreferenceBehavioralAxis> {
        let normalizedText = text.lowercased()
        let tokens = Set(SkillMatcher.meaningfulTokens(text))
        var axes = Set<PreferenceBehavioralAxis>()

        if !tokens.intersection(answerFocusTokens).isEmpty,
           !tokens.intersection(brevityTokens.union(verbosityTokens)).isEmpty {
            axes.insert(.answerLength)
        }

        if !tokens.intersection(["keyboard", "shortcut", "shortcuts"]).isEmpty
            || normalizedText.contains("keyboard")
            || !tokens.intersection(["menu", "clicking", "visually", "pointing"]).isEmpty {
            axes.insert(.inputModality)
        }

        if tokens.contains("dark") || tokens.contains("light") {
            axes.insert(.visualTheme)
        }

        if tokens.contains("typescript") || tokens.contains("javascript") {
            axes.insert(.codeLanguage)
        }

        if tokens.contains("confirm") || normalizedText.contains("without asking")
            || normalizedText.contains("without confirmation") || normalizedText.contains("just do it")
            || normalizedText.contains("ask before") {
            axes.insert(.confirmationStyle)
        }

        if !tokens.intersection(["jargon", "plain", "simple", "technical", "terminology"]).isEmpty {
            axes.insert(.plainLanguage)
        }

        if !tokens.intersection(["step", "numbered", "walk", "quick", "line"]).isEmpty
            || !tokens.intersection(bulletStructureTokens).isEmpty {
            axes.insert(.explanationStructure)
        }

        if tokens.intersection(["beginner", "slowly", "slow", "expert", "fast"]).contains(where: { _ in true }) {
            axes.insert(.expertisePace)
        }

        if tokens.contains("metric") || tokens.contains("imperial") {
            axes.insert(.measurementUnits)
        }

        if !tokens.intersection(toneTokens).isEmpty {
            axes.insert(.tone)
        }

        if normalizedText.contains("code first") || normalizedText.contains("show code")
            || (normalizedText.contains("before") && normalizedText.contains("code")
                && (normalizedText.contains("explain") || normalizedText.contains("concept"))) {
            axes.insert(.instructionOrder)
        }

        return axes
    }

    /// True when both texts express the same dimension of assistant behavior.
    static func isSameBehavioralAxis(between textA: String, and textB: String) -> Bool {
        !behavioralAxes(in: textA).intersection(behavioralAxes(in: textB)).isEmpty
    }

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

    /// True when texts touch different behavioral dimensions (e.g. tone vs answer length).
    static func isRelatedButDistinctAxis(between newTopic: String, and existingText: String) -> Bool {
        let newAxes = behavioralAxes(in: newTopic)
        let existingAxes = behavioralAxes(in: existingText)
        guard !newAxes.isEmpty, !existingAxes.isEmpty else { return false }
        return newAxes.intersection(existingAxes).isEmpty
    }
}
