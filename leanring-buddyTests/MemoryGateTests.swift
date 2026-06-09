//
//  MemoryGateTests.swift
//  leanring-buddyTests
//

import Foundation
import Testing
@testable import leanring_buddy

@Suite(.serialized)
struct MemoryGateTests {
    private func makeSession(
        sessionId: UUID = UUID(),
        outcome: SessionOutcome = .success,
        privacyOptOut: Bool = false,
        turns: [SessionTraceEntry]
    ) -> PersistedSession {
        let startedAt = turns.first?.timestamp ?? Date()
        let endedAt = turns.last?.timestamp ?? startedAt
        let appsUsed = turns.compactMap(\.bundleId).reduce(into: [String]()) { result, bundleId in
            if !result.contains(bundleId) {
                result.append(bundleId)
            }
        }

        return PersistedSession(
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: endedAt,
            outcome: outcome,
            privacyOptOut: privacyOptOut,
            appsUsed: appsUsed,
            turns: turns
        )
    }

    @Test func passesSkillOnUserConfirmation() {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do i save this?",
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
        ])

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(decision.shouldDistillSkill)
        #expect(decision.passes(.skill))
        #expect(decision.passedCategories[.skill]?.contains(.userConfirmed) == true)
        #expect(decision.blockReasons.isEmpty)
    }

    @Test func passesSkillOnMultiStepPointingWithoutConfirmation() {
        let session = makeSession(
            outcome: .unknown,
            turns: [
                SessionTraceEntry(
                    timestamp: Date(),
                    userTranscript: "how do i save this document?",
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
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(decision.shouldDistillSkill)
        #expect(decision.passedCategories[.skill]?.contains(.multiStepPointing) == true)
        #expect(decision.passedCategories[.skill]?.contains(.userConfirmed) == false)
    }

    @Test func blocksWhenPrivacyOptOut() {
        let session = makeSession(
            privacyOptOut: true,
            turns: [
                SessionTraceEntry(
                    timestamp: Date(),
                    userTranscript: "got it thanks",
                    assistantResponse: "great",
                    bundleId: "com.apple.TextEdit",
                    pointed: true
                )
            ]
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(!decision.shouldDistillSkill)
        #expect(decision.blockReasons == [.privacyOptOut])
    }

    @Test func blocksWhenLearningDisabled() {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "got it thanks",
                assistantResponse: "great",
                bundleId: "com.apple.TextEdit",
                pointed: true
            )
        ])

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: false
        )

        #expect(!decision.shouldDistillSkill)
        #expect(decision.blockReasons == [.learningDisabled])
    }

    @Test func blocksAbandonedSessionWithoutConfirmation() {
        let session = makeSession(
            outcome: .abandoned,
            turns: [
                SessionTraceEntry(
                    timestamp: Date(),
                    userTranscript: "how do i save this?",
                    assistantResponse: "click file then save",
                    bundleId: "com.apple.TextEdit",
                    pointed: true
                )
            ]
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(!decision.shouldDistillSkill)
        #expect(decision.blockReasons == [.abandonedWithoutConfirmation])
    }

    @Test func blocksGenericOffScreenQA() {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "what is the capital of france?",
                assistantResponse: "paris",
                bundleId: nil,
                pointed: false
            )
        ])

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(!decision.shouldDistillSkill)
        #expect(decision.blockReasons == [.genericOffScreenQA])
    }

    @Test func blocksGenericOffScreenQAEvenWhileAppFocused() {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "what is the capital of france?",
                assistantResponse: "paris",
                bundleId: "com.apple.TextEdit",
                pointed: false
            )
        ])

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(!decision.shouldDistillSkill)
        #expect(decision.blockReasons == [.genericOffScreenQA])
    }

    @Test func passesSkillOnRepeatedSingleWordTopic() throws {
        let tempHistoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicky-memory-gate-singleword-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempHistoryURL) }

        let topicHistoryStore = TeachingTopicHistoryStore(historyFileURL: tempHistoryURL)
        topicHistoryStore.load()

        let bundleId = "com.apple.FinalCut"

        topicHistoryStore.recordTopic(topic: "export", bundleId: bundleId)
        topicHistoryStore.recordTopic(topic: "export", bundleId: bundleId)

        let session = makeSession(
            outcome: .unknown,
            turns: [
                SessionTraceEntry(
                    timestamp: Date(),
                    userTranscript: "how do i export",
                    assistantResponse: "use the share menu",
                    bundleId: bundleId,
                    pointed: true
                )
            ]
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: topicHistoryStore.entries,
            isLearningEnabled: true
        )

        #expect(decision.passedCategories[.skill]?.contains(.repeatedTopic) == true)
    }

    @Test func passesSkillOnRepeatedTopic() throws {
        let tempHistoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicky-memory-gate-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempHistoryURL) }

        let topicHistoryStore = TeachingTopicHistoryStore(historyFileURL: tempHistoryURL)
        topicHistoryStore.load()

        let bundleId = "com.apple.TextEdit"
        let topic = "save document"

        topicHistoryStore.recordTopic(topic: topic, bundleId: bundleId)
        topicHistoryStore.recordTopic(topic: topic, bundleId: bundleId)

        let session = makeSession(
            outcome: .unknown,
            turns: [
                SessionTraceEntry(
                    timestamp: Date(),
                    userTranscript: "how do i save this document?",
                    assistantResponse: "click file then save",
                    bundleId: bundleId,
                    pointed: true
                )
            ]
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: topicHistoryStore.entries,
            isLearningEnabled: true
        )

        #expect(decision.shouldDistillSkill)
        #expect(decision.passedCategories[.skill]?.contains(.repeatedTopic) == true)
        // A repeat-driven flow must report repeatedTopic as its primary reason,
        // not the generic screenTeaching baseline.
        #expect(decision.passedCategories[.skill]?.first == .repeatedTopic)
    }

    @Test func aggregatesMultipleGateReasons() throws {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do i save this document?",
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
            ),
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "got it thanks that worked",
                assistantResponse: "great",
                bundleId: "com.apple.TextEdit",
                pointed: false
            )
        ])

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        let reasons = try #require(decision.passedCategories[.skill])
        #expect(reasons.contains(.userConfirmed))
        #expect(reasons.contains(.multiStepPointing))
        #expect(reasons.contains(.screenTeaching))
    }

    @Test func negativeFeedbackDoesNotCountAsConfirmation() {
        #expect(SkillTriggerEvaluator.isNegativeFeedbackTranscript("that was not helpful") == true)
        #expect(SkillTriggerEvaluator.isNegativeFeedbackTranscript("that didn't work") == true)
        #expect(SkillTriggerEvaluator.isNegativeFeedbackTranscript("this is wrong") == true)
        // A bare negation in an engaged follow-up is NOT a thumbs-down.
        #expect(SkillTriggerEvaluator.isNegativeFeedbackTranscript("I'm not sure where that is") == false)
        #expect(SkillTriggerEvaluator.isNegativeFeedbackTranscript("can you show me again") == false)
        #expect(SkillTriggerEvaluator.isConfirmationTranscript("that was not helpful") == false)
        #expect(SkillTriggerEvaluator.isConfirmationTranscript("that didn't work") == false)
        #expect(SkillTriggerEvaluator.isConfirmationTranscript("imperfect") == false)
        #expect(SkillTriggerEvaluator.isConfirmationTranscript("got it thanks") == true)
        #expect(SkillTriggerEvaluator.isConfirmationTranscript("perfect") == true)
    }

    @Test func meetsImplicitSaveBarOnTwoTurnScreenTeachingWithoutConfirmation() {
        let turns = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do i save this document?",
                assistantResponse: "click file then save",
                bundleId: "com.apple.TextEdit",
                pointed: true
            ),
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "where is the save button?",
                assistantResponse: "pointing at file menu",
                bundleId: "com.apple.TextEdit",
                pointed: false
            )
        ]

        #expect(MemoryGate.meetsImplicitSaveBar(turns: turns))
    }

    @Test func meetsImplicitSaveBarOnTwoPointingEventsWithoutPhrase() {
        let turns = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do i save this document?",
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

        #expect(MemoryGate.meetsImplicitSaveBar(turns: turns))
    }

    @Test func meetsImplicitSaveBarBlocksOneShotTrivialSession() {
        let turns = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do i save this?",
                assistantResponse: "click file then save",
                bundleId: "com.apple.TextEdit",
                pointed: true
            )
        ]

        #expect(!MemoryGate.meetsImplicitSaveBar(turns: turns))
    }

    @Test func meetsImplicitSaveBarBlocksWhenLastTurnIsNegativeFeedback() {
        let turns = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do i export this clip?",
                assistantResponse: "use the share menu",
                bundleId: "com.apple.FinalCut",
                pointed: true
            ),
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "that was not helpful",
                assistantResponse: "let me try again",
                bundleId: "com.apple.FinalCut",
                pointed: true
            )
        ]

        #expect(!MemoryGate.meetsImplicitSaveBar(turns: turns))
    }

    @Test func lastTurnNegationDoesNotRecordUserConfirmed() {
        let session = makeSession(
            outcome: .unknown,
            turns: [
                SessionTraceEntry(
                    timestamp: Date(),
                    userTranscript: "how do i export this clip?",
                    assistantResponse: "use the share menu",
                    bundleId: "com.apple.FinalCut",
                    pointed: true
                ),
                SessionTraceEntry(
                    timestamp: Date(),
                    userTranscript: "that was not helpful",
                    assistantResponse: "let me try again",
                    bundleId: "com.apple.FinalCut",
                    pointed: true
                )
            ]
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(decision.passedCategories[.skill]?.contains(.userConfirmed) == false)
        // Still distills on the two-pointing path, just not as a false confirmation.
        #expect(decision.passedCategories[.skill]?.contains(.multiStepPointing) == true)
    }

    @Test func passesPreferenceOnStatedPreferencePhrase() {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "from now on keep answers short",
                assistantResponse: "got it, i'll keep things concise",
                bundleId: nil,
                pointed: false
            )
        ])

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(decision.shouldDistillPreference)
        #expect(decision.passedCategories[.preference]?.contains(.statedPreference) == true)
        #expect(!decision.shouldDistillSkill)
        #expect(decision.blockReasons.isEmpty)
    }

    @Test func passesPreferenceEvenOnOffScreenQA() {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "i prefer keyboard shortcuts over menus",
                assistantResponse: "noted",
                bundleId: "com.apple.TextEdit",
                pointed: false
            )
        ])

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(decision.shouldDistillPreference)
        #expect(!decision.shouldDistillSkill)
        #expect(decision.blockReasons.isEmpty)
    }

    @Test func passesRoutineOnRecurringMultiDayTopic() throws {
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!

        let bundleId = "com.apple.dt.Xcode"
        let topic = "standup prep"

        let topicHistory: [TeachingTopicHistoryEntry] = [
            TeachingTopicHistoryEntry(
                topicTokens: SkillMatcher.meaningfulTokens(topic),
                bundleId: bundleId,
                timestamp: twoDaysAgo,
                skillId: nil
            ),
            TeachingTopicHistoryEntry(
                topicTokens: SkillMatcher.meaningfulTokens(topic),
                bundleId: bundleId,
                timestamp: yesterday,
                skillId: nil
            )
        ]

        let session = makeSession(
            outcome: .unknown,
            turns: [
                SessionTraceEntry(
                    timestamp: now,
                    userTranscript: "help me with standup prep again",
                    assistantResponse: "open source control and review commits",
                    bundleId: bundleId,
                    pointed: true
                ),
                SessionTraceEntry(
                    timestamp: now,
                    userTranscript: "show me yesterday's commits",
                    assistantResponse: "pointing at the log",
                    bundleId: bundleId,
                    pointed: true
                )
            ]
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: topicHistory,
            isLearningEnabled: true,
            now: now
        )

        #expect(decision.shouldDistillRoutine)
        #expect(decision.passedCategories[.routine]?.contains(.recurringRoutine) == true)
    }

    @Test func doesNotPassRoutineOnSingleDayRepeat() {
        let now = Date()
        let bundleId = "com.apple.dt.Xcode"
        let topic = "standup prep"

        let topicHistory: [TeachingTopicHistoryEntry] = [
            TeachingTopicHistoryEntry(
                topicTokens: SkillMatcher.meaningfulTokens(topic),
                bundleId: bundleId,
                timestamp: now.addingTimeInterval(-3600),
                skillId: nil
            ),
            TeachingTopicHistoryEntry(
                topicTokens: SkillMatcher.meaningfulTokens(topic),
                bundleId: bundleId,
                timestamp: now.addingTimeInterval(-1800),
                skillId: nil
            )
        ]

        let session = makeSession(
            outcome: .unknown,
            turns: [
                SessionTraceEntry(
                    timestamp: now,
                    userTranscript: "help me with standup prep",
                    assistantResponse: "open source control",
                    bundleId: bundleId,
                    pointed: true
                ),
                SessionTraceEntry(
                    timestamp: now,
                    userTranscript: "show commits",
                    assistantResponse: "pointing at log",
                    bundleId: bundleId,
                    pointed: true
                )
            ]
        )

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: topicHistory,
            isLearningEnabled: true,
            now: now
        )

        #expect(!decision.shouldDistillRoutine)
    }

    @Test func learningDisabledBlocksAllCategories() {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "from now on keep answers short",
                assistantResponse: "got it",
                bundleId: "com.apple.TextEdit",
                pointed: true
            )
        ])

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: false
        )

        #expect(!decision.shouldDistillPreference)
        #expect(!decision.shouldDistillRoutine)
        #expect(!decision.shouldDistillSkill)
        #expect(decision.blockReasons == [.learningDisabled])
    }

    @Test func passesPreferenceOnImplicitInstruction() {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "give detailed answers with examples",
                assistantResponse: "got it, i'll include examples",
                bundleId: nil,
                pointed: false
            )
        ])

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(decision.shouldDistillPreference)
        #expect(decision.passedCategories[.preference]?.contains(.statedPreference) == true)
        #expect(!decision.shouldDistillSkill)
        #expect(decision.blockReasons.isEmpty)
    }

    @Test func doesNotPassPreferenceOnScreenQuestion() {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do i save this document?",
                assistantResponse: "click file then save",
                bundleId: "com.apple.TextEdit",
                pointed: true
            )
        ])

        let decision = MemoryGate.evaluate(
            session: session,
            topicHistory: [],
            isLearningEnabled: true
        )

        #expect(!decision.shouldDistillPreference)
    }

    @Test func preferenceSignalDetectorFindsImplicitPreference() {
        #expect(PreferenceSignalDetector.hasStatedPreference(in: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "give detailed answers with examples",
                assistantResponse: "ok",
                bundleId: nil,
                pointed: false
            )
        ]))
        #expect(PreferenceSignalDetector.primaryPreferenceTranscript(in: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "from now on keep the answers in one sentence",
                assistantResponse: "ok",
                bundleId: nil,
                pointed: false
            )
        ]) == "from now on keep the answers in one sentence")
        #expect(!PreferenceSignalDetector.hasStatedPreference(in: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do i save this?",
                assistantResponse: "click file",
                bundleId: nil,
                pointed: true
            )
        ]))
        #expect(!PreferenceSignalDetector.hasStatedPreference(in: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "show me the save button",
                assistantResponse: "it's in the toolbar",
                bundleId: "com.apple.TextEdit",
                pointed: true
            )
        ]))
    }

    @Test func preferenceSignalDetectorFindsStatedPreference() {
        #expect(PreferenceSignalDetector.hasStatedPreference(in: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "from now on keep answers short",
                assistantResponse: "ok",
                bundleId: nil,
                pointed: false
            )
        ]))
        #expect(!PreferenceSignalDetector.hasStatedPreference(in: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do i save this?",
                assistantResponse: "click file",
                bundleId: nil,
                pointed: true
            )
        ]))
    }

    @Test func hasRecurringTopicAcrossDaysRequiresDistinctCalendarDays() {
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let earlierToday = now.addingTimeInterval(-3600)

        let entries = [
            TeachingTopicHistoryEntry(
                topicTokens: ["standup", "prep"],
                bundleId: "com.apple.dt.Xcode",
                timestamp: earlierToday,
                skillId: nil
            ),
            TeachingTopicHistoryEntry(
                topicTokens: ["standup", "prep"],
                bundleId: "com.apple.dt.Xcode",
                timestamp: yesterday,
                skillId: nil
            )
        ]

        #expect(
            TeachingTopicHistoryStore.hasRecurringTopicAcrossDays(
                topic: "standup prep",
                bundleId: "com.apple.dt.Xcode",
                minDistinctDays: 2,
                withinDays: 7,
                in: entries,
                now: now
            )
        )

        let sameDayEntries = [
            TeachingTopicHistoryEntry(
                topicTokens: ["standup", "prep"],
                bundleId: "com.apple.dt.Xcode",
                timestamp: earlierToday,
                skillId: nil
            ),
            TeachingTopicHistoryEntry(
                topicTokens: ["standup", "prep"],
                bundleId: "com.apple.dt.Xcode",
                timestamp: now.addingTimeInterval(-1800),
                skillId: nil
            )
        ]

        #expect(
            !TeachingTopicHistoryStore.hasRecurringTopicAcrossDays(
                topic: "standup prep",
                bundleId: "com.apple.dt.Xcode",
                minDistinctDays: 2,
                withinDays: 7,
                in: sameDayEntries,
                now: now
            )
        )
    }

    @Test func makeSkillWriteTriggerUsesPrimaryGateReason() {
        let session = makeSession(turns: [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "how do i save this document?",
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
        ])

        let trigger = MemoryGate.makeSkillWriteTrigger(
            for: session,
            gateReasons: [.userConfirmed, .screenTeaching]
        )

        #expect(trigger.reason == .userConfirmed)
        #expect(trigger.topic == "save document")
    }
}
