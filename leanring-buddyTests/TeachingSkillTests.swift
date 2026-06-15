//
//  TeachingSkillTests.swift
//  leanring-buddyTests
//

import Foundation
import Testing
@testable import leanring_buddy

struct TeachingSkillTests {
    @Test func parsesSkillFrontmatterAndBody() throws {
        let markdown = """
        ---
        name: teach-xcode-source-control
        description: Walk through committing in Xcode
        bundleIds:
          - com.apple.dt.Xcode
        status: active
        lastUsed: 2026-05-24
        usageCount: 3
        pinned: true
        taskSlug: commit
        ---

        step one: open source control.
        step two: click commit.
        """

        let skill = try #require(TeachingSkill.parse(id: "teach-xcode-source-control", markdown: markdown))
        #expect(skill.name == "teach-xcode-source-control")
        #expect(skill.description == "Walk through committing in Xcode")
        #expect(skill.bundleIds == ["com.apple.dt.Xcode"])
        #expect(skill.usageCount == 3)
        #expect(skill.isPinned)
        #expect(skill.taskSlug == "commit")
        #expect(skill.body.contains("step one"))
    }

    @Test func matchesSkillsByBundleAndKeywords() {
        let skill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving a document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 2,
            isPinned: false,
            taskSlug: "save",
            body: "click file then save or use command s"
        )

        let matches = SkillMatcher.matchSkills(
            from: [skill],
            bundleId: "com.apple.TextEdit",
            transcript: "how do I save this document?"
        )

        #expect(matches.count == 1)
        #expect(matches.first?.skill.id == "teach-textedit-save")
    }

    @Test func memoryGatePassesOnUserConfirmation() {
        let trace = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do I save this?",
                assistantResponse: "click file then save",
                bundleId: "com.apple.TextEdit",
                pointed: true
            ),
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "got it thanks that worked",
                assistantResponse: "great",
                bundleId: "com.apple.TextEdit",
                pointed: false
            )
        ]

        let session = PersistedSession(
            sessionId: UUID(),
            startedAt: trace[0].timestamp,
            endedAt: trace[1].timestamp,
            outcome: .success,
            privacyOptOut: false,
            appsUsed: ["com.apple.TextEdit"],
            turns: trace
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(decision.shouldDistillSkill)
        #expect(decision.passedCategories[.skill]?.contains(.userConfirmed) == true)
    }

    @Test func memoryGatePassesOnMultiStepPointingBeforeConfirmation() {
        let trace = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do I save this document?",
                assistantResponse: "click file then save",
                bundleId: "com.apple.TextEdit",
                pointed: true
            ),
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "where is the save button?",
                assistantResponse: "pointing at file menu",
                bundleId: "com.apple.TextEdit",
                pointed: true
            )
        ]

        let session = PersistedSession(
            sessionId: UUID(),
            startedAt: trace[0].timestamp,
            endedAt: trace[1].timestamp,
            outcome: .unknown,
            privacyOptOut: false,
            appsUsed: ["com.apple.TextEdit"],
            turns: trace
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(decision.shouldDistillSkill)
        #expect(decision.passedCategories[.skill]?.contains(.multiStepPointing) == true)
    }

    @Test func topicIgnoresConfirmationPhrase() {
        let trace = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do I save this document?",
                assistantResponse: "click file then save",
                bundleId: "com.apple.TextEdit",
                pointed: true
            ),
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "got it thanks that worked",
                assistantResponse: "great",
                bundleId: "com.apple.TextEdit",
                pointed: false
            )
        ]

        let topic = SkillTriggerEvaluator.deriveTopic(from: trace)
        #expect(topic == "save document")
        #expect(SkillTriggerEvaluator.primaryTeachingQuestion(from: trace) == "how do I save this document?")
    }

    @Test func slugAndNameAreCleanForSaveQuestionWithConfirmation() throws {
        let trace = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do I save this document?",
                assistantResponse: "click file then save",
                bundleId: "com.apple.TextEdit",
                pointed: true
            ),
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "got it thanks that worked",
                assistantResponse: "great",
                bundleId: "com.apple.TextEdit",
                pointed: false
            )
        ]

        let session = PersistedSession(
            sessionId: UUID(),
            startedAt: trace[0].timestamp,
            endedAt: trace[1].timestamp,
            outcome: .success,
            privacyOptOut: false,
            appsUsed: ["com.apple.TextEdit"],
            turns: trace
        )
        let trigger = MemoryGate.makeSkillWriteTrigger(
            for: session,
            gateReasons: [.userConfirmed, .screenTeaching]
        )
        let metadata = SkillSynthesizer.buildSkillMetadata(
            sessionTrace: trace,
            trigger: trigger,
            targetBundleId: "com.apple.TextEdit"
        )

        #expect(metadata.id == "teach-textedit-save")
        #expect(metadata.name == "Save in TextEdit")
        #expect(metadata.description == "Walk the user through save document")
        #expect(metadata.taskSlug == "save")
        #expect(!metadata.id.contains("got"))
        #expect(!metadata.id.contains("thanks"))
        #expect(!metadata.id.contains("worked"))
    }

    @Test func crossSessionRepeatPassesMemoryGateWithoutConfirmation() throws {
        let tempHistoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicky-topic-history-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempHistoryURL) }

        let topicHistoryStore = TeachingTopicHistoryStore(historyFileURL: tempHistoryURL)
        topicHistoryStore.load()

        let bundleId = "com.apple.TextEdit"
        let topic = "save document"

        topicHistoryStore.recordTopic(topic: topic, bundleId: bundleId)

        let trace = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do I save this document?",
                assistantResponse: "click file then save",
                bundleId: bundleId,
                pointed: true
            )
        ]

        topicHistoryStore.recordTopic(topic: topic, bundleId: bundleId)

        let session = PersistedSession(
            sessionId: UUID(),
            startedAt: trace[0].timestamp,
            endedAt: trace[0].timestamp,
            outcome: .unknown,
            privacyOptOut: false,
            appsUsed: [bundleId],
            turns: trace
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: topicHistoryStore.entries,
            isLearningEnabled: true
        )

        #expect(decision.shouldDistillSkill)
        #expect(decision.passedCategories[.skill]?.contains(.repeatedTopic) == true)
    }

    @Test func resolvesTargetAppFromMentionedAppNotFrontmostBundle() {
        let trace = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do I save this document in TextEdit?",
                assistantResponse: "use command s",
                bundleId: "com.mitchellh.ghostty",
                pointed: true
            )
        ]

        let targetBundleId = SkillTargetAppResolver.resolveTargetBundleId(
            from: trace,
            frontmostBundleId: "com.mitchellh.ghostty"
        )

        #expect(targetBundleId == "com.apple.TextEdit")
    }

    @Test func findSkillForUpdateUsesStableIdentity() {
        let existingSkill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving a document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 2,
            isPinned: false,
            taskSlug: "save",
            body: "click file then save or use command s"
        )

        let matchedSkill = SkillMatcher.findSkillForUpdate(
            in: [existingSkill],
            targetBundleId: "com.apple.TextEdit",
            primaryQuestion: "how do I save this document?"
        )

        #expect(matchedSkill?.id == "teach-textedit-save")
    }

    @Test func findSkillForUpdateMatchesRefinementToExistingSkill() {
        let existingSkill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving a document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 2,
            isPinned: false,
            taskSlug: "save",
            body: "click file then save or use command s"
        )

        let matchedSkill = SkillMatcher.findSkillForUpdate(
            in: [existingSkill],
            targetBundleId: "com.mitchellh.ghostty",
            primaryQuestion: "how do I save this document in TextEdit?"
        )

        #expect(matchedSkill?.id == "teach-textedit-save")
    }

    @Test func promptBuilderInjectsMatchedSkills() {
        let skill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving a document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: nil,
            usageCount: 0,
            isPinned: false,
            taskSlug: "save",
            body: "use file > save"
        )

        let prompt = TeachingPromptBuilder.buildVoiceResponsePrompt(
            basePrompt: "base prompt",
            matchedSkills: [skill]
        )

        #expect(prompt.contains("base prompt"))
        #expect(prompt.contains("teaching skills:"))
        #expect(prompt.contains("Save in TextEdit"))
        #expect(prompt.contains("use file > save"))
    }

    @Test func memoryInjectionExcerptReturnsOnlyAppendedMemorySections() {
        let skill = TeachingSkill(
            id: "demo-skill-xcode-ship",
            name: "Ship changes the team's way",
            description: "Commit via Source Control using the team's house rules",
            bundleIds: ["com.apple.dt.Xcode"],
            status: .active,
            lastUsed: nil,
            usageCount: 1,
            isPinned: false,
            taskSlug: "ship",
            triggers: ["ship it"],
            body: "review diff then commit with imperative message"
        )

        let basePrompt = "you are clicky, a voice screen tutor. answer briefly."
        let builtPrompt = TeachingPromptBuilder.buildVoiceResponsePrompt(
            basePrompt: basePrompt,
            matchedSkills: [skill]
        )

        let injectionExcerpt = TeachingPromptBuilder.memoryInjectionExcerpt(
            basePrompt: basePrompt,
            builtPrompt: builtPrompt
        )

        #expect(injectionExcerpt?.contains("teaching skills:") == true)
        #expect(injectionExcerpt?.contains("Ship changes the team's way") == true)
        #expect(injectionExcerpt?.contains(basePrompt) == false)
    }

    @Test func matchedSkillAppearsInComposedPrompt() {
        let skill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving a document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: nil,
            usageCount: 0,
            isPinned: false,
            taskSlug: "save",
            body: "click file then save or use command s"
        )

        let matches = SkillMatcher.matchSkills(
            from: [skill],
            bundleId: "com.apple.TextEdit",
            transcript: "how do I save this document?"
        )
        let matchedSkills = matches.map(\.skill)
        let prompt = TeachingPromptBuilder.buildVoiceResponsePrompt(
            basePrompt: "companion voice prompt",
            matchedSkills: matchedSkills
        )

        #expect(matchedSkills.map(\.name) == ["Save in TextEdit"])
        #expect(prompt.contains("Save in TextEdit"))
        #expect(prompt.contains("click file then save or use command s"))
    }

    @Test func detectsDuplicateSkillsWithOverlappingContent() {
        let saveSkill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving a document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 3,
            isPinned: false,
            taskSlug: "save",
            body: "click file then save or use command s shortcut"
        )
        let duplicateSaveSkill = TeachingSkill(
            id: "teach-textedit-save-document",
            name: "Save document in TextEdit",
            description: "Help save the current document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date().addingTimeInterval(-86400),
            usageCount: 1,
            isPinned: false,
            taskSlug: "save",
            body: "open file menu then choose save for the document"
        )

        let duplicatePairs = SkillMatcher.findDuplicateSkillPairs(
            in: [saveSkill, duplicateSaveSkill],
            minimumOverlapScore: 3
        )

        #expect(duplicatePairs.count == 1)
        #expect(duplicatePairs.first?.primarySkill.id == "teach-textedit-save")
        #expect(duplicatePairs.first?.duplicateSkill.id == "teach-textedit-save-document")
    }

    @Test func ignoresPinnedSkillsForDuplicateDetection() {
        let pinnedSkill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving a document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 3,
            isPinned: true,
            taskSlug: "save",
            body: "click file then save or use command s shortcut"
        )
        let overlappingSkill = TeachingSkill(
            id: "teach-textedit-save-copy",
            name: "Save document in TextEdit",
            description: "Help save the current document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 1,
            isPinned: false,
            taskSlug: "save",
            body: "click file then save or use command s shortcut"
        )

        let duplicatePairs = SkillMatcher.findDuplicateSkillPairs(
            in: [pinnedSkill, overlappingSkill],
            minimumOverlapScore: 3
        )

        #expect(duplicatePairs.isEmpty)
    }

    @Test func ignoresSkillsWithDifferentBundleIdsForDuplicateDetection() {
        let textEditSkill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving a document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 3,
            isPinned: false,
            taskSlug: "save",
            body: "click file then save or use command s shortcut"
        )
        let xcodeSkill = TeachingSkill(
            id: "teach-xcode-save",
            name: "Save in Xcode",
            description: "Walk the user through saving a file",
            bundleIds: ["com.apple.dt.Xcode"],
            status: .active,
            lastUsed: Date(),
            usageCount: 1,
            isPinned: false,
            taskSlug: "save",
            body: "click file then save or use command s shortcut"
        )

        let duplicatePairs = SkillMatcher.findDuplicateSkillPairs(
            in: [textEditSkill, xcodeSkill],
            minimumOverlapScore: 3
        )

        #expect(duplicatePairs.isEmpty)
    }

    @Test func parsesTriggersConfirmedSuccessAndSupersededBody() throws {
        let markdown = """
        ---
        name: Save in TextEdit
        description: Walk the user through saving
        bundleIds:
          - com.apple.TextEdit
        triggers:
          - how do i save
          - save this document
        status: active
        lastUsed: 2026-06-01
        usageCount: 2
        confirmedSuccessCount: 1
        pinned: false
        taskSlug: save
        supersededAt: 2026-06-08
        ---

        updated body with keyboard shortcut.

        <!-- superseded:2026-06-08 -->

        old body used the menu.
        """

        let skill = try #require(TeachingSkill.parse(id: "teach-textedit-save", markdown: markdown))
        #expect(skill.triggers == ["how do i save", "save this document"])
        #expect(skill.confirmedSuccessCount == 1)
        #expect(skill.supersededAt != nil)
        #expect(skill.body.contains("updated body"))
        #expect(skill.previousBody?.contains("old body") == true)
    }

    @Test func serializesTriggersAndSupersededBodyRoundTrip() throws {
        let originalSkill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 2,
            isPinned: false,
            taskSlug: "save",
            triggers: ["how do i save", "save this document"],
            confirmedSuccessCount: 2,
            supersededAt: Date(),
            previousBody: "old guidance",
            body: "new guidance"
        )

        let reparsedSkill = try #require(
            TeachingSkill.parse(id: originalSkill.id, markdown: originalSkill.serialize())
        )
        #expect(reparsedSkill.triggers == originalSkill.triggers)
        #expect(reparsedSkill.confirmedSuccessCount == 2)
        #expect(reparsedSkill.body == "new guidance")
        #expect(reparsedSkill.previousBody == "old guidance")
    }

    @Test func triggerPhraseMatchBoostsSkillAboveTokenOverlap() {
        let triggeredSkill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 0,
            isPinned: false,
            taskSlug: "save",
            triggers: ["how do i save this document"],
            body: "unrelated workflow"
        )
        let keywordSkill = TeachingSkill(
            id: "teach-textedit-export",
            name: "Export in TextEdit",
            description: "Walk the user through exporting",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 5,
            isPinned: false,
            taskSlug: "export",
            body: "how do i save this document using export panel"
        )

        let matches = SkillMatcher.matchSkills(
            from: [triggeredSkill, keywordSkill],
            bundleId: "com.apple.TextEdit",
            transcript: "how do i save this document?"
        )

        #expect(matches.first?.skill.id == "teach-textedit-save")
    }

    @Test func triggerPhraseMatchesOnWordBoundariesNotSubstrings() {
        let skill = TeachingSkill(
            id: "teach-help",
            name: "Open help",
            description: "Open the help menu",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 0,
            isPinned: false,
            taskSlug: "help",
            triggers: ["help"],
            body: "open help"
        )

        // Whole-word match fires.
        #expect(SkillMatcher.triggerPhraseMatchScore(for: skill, in: "can you help me") > 0)
        // Substring inside an unrelated word ("helpful") must not fire.
        #expect(SkillMatcher.triggerPhraseMatchScore(for: skill, in: "that was helpful") == 0)
    }

    @Test func recencyAndTrustScoringPreferRecentlyConfirmedSkill() {
        let recentConfirmedSkill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 1,
            isPinned: false,
            taskSlug: "save",
            confirmedSuccessCount: 4,
            body: "save document steps"
        )
        let staleSkill = TeachingSkill(
            id: "teach-textedit-save-copy",
            name: "Save document in TextEdit",
            description: "Help save the current document",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date().addingTimeInterval(-40 * 24 * 60 * 60),
            usageCount: 6,
            isPinned: false,
            taskSlug: "save",
            confirmedSuccessCount: 0,
            body: "save document using menu"
        )

        let matches = SkillMatcher.matchSkills(
            from: [recentConfirmedSkill, staleSkill],
            bundleId: "com.apple.TextEdit",
            transcript: "how do I save this document?"
        )

        #expect(matches.first?.skill.id == "teach-textedit-save")
    }

    @Test func findSkillForUpdateMatchesTriggerPhrase() {
        let existingSkill = TeachingSkill(
            id: "teach-textedit-save",
            name: "Save in TextEdit",
            description: "Walk the user through saving",
            bundleIds: ["com.apple.TextEdit"],
            status: .active,
            lastUsed: Date(),
            usageCount: 1,
            isPinned: false,
            taskSlug: "save",
            triggers: ["save this document in textedit"],
            body: "use command s"
        )

        let matchedSkill = SkillMatcher.findSkillForUpdate(
            in: [existingSkill],
            targetBundleId: "com.mitchellh.ghostty",
            primaryQuestion: "save this document in textedit"
        )

        #expect(matchedSkill?.id == "teach-textedit-save")
    }

    @Test func parsesTriggersLineFromSynthesizerResponse() {
        let parsed = SkillSynthesizer.parseTriggersLine(from: """
        triggers: how do i save | save this document

        step one: press command s.
        step two: choose save.
        """)

        #expect(parsed.triggers == ["how do i save", "save this document"])
        #expect(parsed.body.contains("step one"))
    }

    @Test func higherUsageXcodeCommitSkillOutranksFreshShipItDemoSkill() {
        // Regression guard for the Skills demo: both skills match "Ship it" via
        // the same trigger, but SkillMatcher ranks by usageCount among ties.
        // The demo must wipe all skills before its run or proof reads "Unexpected".
        let establishedXcodeCommitSkill = TeachingSkill(
            id: "teach-xcode-commit",
            name: "Commit changes in Xcode",
            description: "Stage and commit your current changes via Source Control",
            bundleIds: ["com.apple.dt.Xcode"],
            status: .active,
            lastUsed: Date(),
            usageCount: 11,
            isPinned: false,
            taskSlug: "commit",
            triggers: ["ship it", "ship my changes"],
            body: "commit from source control"
        )
        let freshlyLearnedDemoShipSkill = TeachingSkill(
            id: "demo-skill-xcode-ship",
            name: "Ship changes the team's way",
            description: "Commit via Source Control using the team's house rules",
            bundleIds: ["com.apple.dt.Xcode"],
            status: .active,
            lastUsed: Date(),
            usageCount: 1,
            isPinned: false,
            taskSlug: "ship",
            triggers: ["ship it", "ship my changes"],
            body: "review diff then commit with imperative message"
        )

        let matches = SkillMatcher.matchSkills(
            from: [establishedXcodeCommitSkill, freshlyLearnedDemoShipSkill],
            bundleId: "com.apple.dt.Xcode",
            transcript: "Ship it"
        )

        #expect(matches.first?.skill.id == "teach-xcode-commit")
        #expect(matches.contains { $0.skill.id == "demo-skill-xcode-ship" })
    }
}
