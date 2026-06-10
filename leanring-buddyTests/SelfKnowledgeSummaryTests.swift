//
//  SelfKnowledgeSummaryTests.swift
//  leanring-buddyTests
//
//  Covers the "what did you learn about me?" intent detector (positives and
//  near-miss negatives) and the grounding of the spoken summary prompt:
//  per-category caps, honest truncation counts, omitted empty categories,
//  and the deterministic counts fallback.
//

import Foundation
import Testing
@testable import leanring_buddy

struct SelfKnowledgeSummaryTests {
    private func makeMemory(
        id: String,
        category: MemoryCategory,
        title: String,
        summary: String = "",
        bundleIds: [String] = [],
        usageCount: Int = 0,
        lastUsed: Date? = nil
    ) -> Memory {
        Memory(
            id: id,
            category: category,
            title: title,
            summary: summary,
            body: "",
            bundleIds: bundleIds,
            status: .active,
            isPinned: false,
            usageCount: usageCount,
            lastUsed: lastUsed,
            receipts: []
        )
    }

    // MARK: - Intent detection

    @Test func detectorMatchesDirectSelfKnowledgeQuestions() {
        #expect(SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(transcript: "what did you learn about me"))
        #expect(SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(transcript: "What do you know about me?"))
        #expect(SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(transcript: "what have you learned about me"))
        #expect(SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(transcript: "what do you remember about me"))
        #expect(SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(transcript: "tell me what you know about me"))
    }

    @Test func detectorMatchesQuestionsEmbeddedInLongerTranscripts() {
        #expect(SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(
            transcript: "hey clicky, what have you learned about me so far?"
        ))
        #expect(SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(
            transcript: "i'm curious. what do you know about me, after all these sessions?"
        ))
    }

    @Test func detectorIgnoresQuestionsAboutOtherTopics() {
        #expect(!SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(transcript: "what do you know about swift?"))
        // Word-boundary matching: "merge" must not match the word "me".
        #expect(!SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(transcript: "what do you know about merge conflicts"))
        #expect(!SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(transcript: "tell me about this function"))
        #expect(!SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(transcript: "what did you learn"))
        #expect(!SelfKnowledgeIntentDetector.isSelfKnowledgeQuery(transcript: ""))
    }

    // MARK: - Summary prompt grounding

    @Test func summaryPromptContainsFactsFromEveryProvidedCategory() {
        let activeSkills = [
            makeMemory(
                id: "skill-xcode-commit",
                category: .skill,
                title: "Commit in Xcode",
                summary: "Use the source control menu or command option c.",
                bundleIds: ["com.apple.dt.Xcode"]
            )
        ]
        let activePreferences = [
            makeMemory(
                id: "pref-short-answers",
                category: .preference,
                title: "Prefer concise answers",
                summary: "Short responses by default."
            )
        ]
        let activeRoutines = [
            makeMemory(
                id: "routine-standup",
                category: .routine,
                title: "Morning standup flow",
                summary: "Opens Slack then Notion every morning."
            )
        ]

        let summaryUserPrompt = SelfKnowledgePromptBuilder.buildSummaryUserPrompt(
            activeSkills: activeSkills,
            activePreferences: activePreferences,
            activeRoutines: activeRoutines,
            nicheDisplayName: "Developer",
            vaultNoteCount: 42
        )

        #expect(summaryUserPrompt.contains("\"Commit in Xcode\""))
        #expect(summaryUserPrompt.contains("Use the source control menu or command option c."))
        #expect(summaryUserPrompt.contains("(app: Xcode)"))
        #expect(summaryUserPrompt.contains("\"Prefer concise answers\""))
        #expect(summaryUserPrompt.contains("\"Morning standup flow\""))
        #expect(summaryUserPrompt.contains("the user's working niche: developer"))
        #expect(summaryUserPrompt.contains("42 searchable markdown notes"))
        #expect(summaryUserPrompt.contains("using only the facts above"))
    }

    @Test func summaryPromptOmitsEmptyCategoriesAndOptionalFacts() {
        let activeSkills = [
            makeMemory(id: "skill-only", category: .skill, title: "Save in TextEdit")
        ]

        let summaryUserPrompt = SelfKnowledgePromptBuilder.buildSummaryUserPrompt(
            activeSkills: activeSkills,
            activePreferences: [],
            activeRoutines: [],
            nicheDisplayName: nil,
            vaultNoteCount: nil
        )

        #expect(summaryUserPrompt.contains("teaching skills clicky learned"))
        #expect(!summaryUserPrompt.contains("preferences the user stated"))
        #expect(!summaryUserPrompt.contains("recurring routines clicky noticed"))
        #expect(!summaryUserPrompt.contains("niche"))
        #expect(!summaryUserPrompt.contains("vault"))
    }

    @Test func summaryPromptCapsEachCategoryAtFiveMostUsedMemories() {
        let sevenSkills = (1...7).map { skillIndex in
            makeMemory(
                id: "skill-\(skillIndex)",
                category: .skill,
                title: "Skill number \(skillIndex)",
                usageCount: skillIndex
            )
        }

        let summaryUserPrompt = SelfKnowledgePromptBuilder.buildSummaryUserPrompt(
            activeSkills: sevenSkills,
            activePreferences: [],
            activeRoutines: [],
            nicheDisplayName: nil,
            vaultNoteCount: nil
        )

        #expect(summaryUserPrompt.contains("showing the 5 most used of 7 total"))
        // The five most used skills (usage 3-7) are included…
        #expect(summaryUserPrompt.contains("\"Skill number 7\""))
        #expect(summaryUserPrompt.contains("\"Skill number 3\""))
        // …and the two least used (usage 1-2) are represented only by the total.
        #expect(!summaryUserPrompt.contains("\"Skill number 2\""))
        #expect(!summaryUserPrompt.contains("\"Skill number 1\""))
    }

    @Test func summaryPromptBreaksUsageTiesByMostRecentlyUsed() {
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_700_500_000)
        let tiedSkills = [
            makeMemory(id: "skill-old", category: .skill, title: "Older skill", usageCount: 1, lastUsed: olderDate),
            makeMemory(id: "skill-new", category: .skill, title: "Newer skill", usageCount: 1, lastUsed: newerDate)
        ]

        let summaryUserPrompt = SelfKnowledgePromptBuilder.buildSummaryUserPrompt(
            activeSkills: tiedSkills,
            activePreferences: [],
            activeRoutines: [],
            nicheDisplayName: nil,
            vaultNoteCount: nil
        )

        let newerSkillPosition = summaryUserPrompt.range(of: "\"Newer skill\"")
        let olderSkillPosition = summaryUserPrompt.range(of: "\"Older skill\"")
        #expect(newerSkillPosition != nil)
        #expect(olderSkillPosition != nil)
        if let newerSkillPosition, let olderSkillPosition {
            #expect(newerSkillPosition.lowerBound < olderSkillPosition.lowerBound)
        }
    }

    // MARK: - Deterministic fallback

    @Test func fallbackSummaryListsGroundedCountsAndNiche() {
        let fallbackSummary = SelfKnowledgePromptBuilder.buildDeterministicFallbackSummary(
            activeSkillCount: 3,
            activePreferenceCount: 1,
            activeRoutineCount: 2,
            nicheDisplayName: "Developer"
        )

        #expect(fallbackSummary.contains("3 skills, 1 preference, and 2 routines"))
        #expect(fallbackSummary.contains("working as a developer"))
        #expect(fallbackSummary.contains("memories library"))
    }

    @Test func fallbackSummaryOmitsZeroCountCategoriesAndMissingNiche() {
        let fallbackSummary = SelfKnowledgePromptBuilder.buildDeterministicFallbackSummary(
            activeSkillCount: 2,
            activePreferenceCount: 0,
            activeRoutineCount: 0,
            nicheDisplayName: nil
        )

        #expect(fallbackSummary.contains("2 skills"))
        #expect(!fallbackSummary.contains("preference"))
        #expect(!fallbackSummary.contains("routine"))
        #expect(!fallbackSummary.contains("working as a"))
    }

    @Test func fallbackSummaryWithNoMemoriesUsesEmptyStateAnswer() {
        let fallbackSummary = SelfKnowledgePromptBuilder.buildDeterministicFallbackSummary(
            activeSkillCount: 0,
            activePreferenceCount: 0,
            activeRoutineCount: 0,
            nicheDisplayName: "Developer"
        )

        #expect(fallbackSummary == SelfKnowledgePromptBuilder.emptyMemoryStateAnswer)
    }
}
