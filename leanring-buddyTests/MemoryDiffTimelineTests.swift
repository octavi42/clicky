//
//  MemoryDiffTimelineTests.swift
//  leanring-buddyTests
//
//  Covers the "How this changed" timeline: snapshot capture on receipts,
//  backward-compatible decoding of receipts without snapshot keys, the
//  2+ saves collapse rule, entry ordering, and Was → Now diff derivation
//  for preferences/routines versus the lighter skill activity style.
//

import Foundation
import Testing
@testable import leanring_buddy

struct MemoryDiffTimelineTests {
    private func makeReceipt(
        savedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        gateReasons: [GateReason] = [.statedPreference],
        appBundleId: String? = "com.apple.dt.Xcode",
        userAsk: String? = "can you explain this function?",
        triggerPhrase: String? = nil,
        updatedExistingMemory: Bool = false,
        memoryTitleSnapshot: String? = nil,
        memorySummarySnapshot: String? = nil
    ) -> MemoryReceipt {
        MemoryReceipt(
            savedAt: savedAt,
            sessionId: UUID(),
            gateReasons: gateReasons,
            appBundleId: appBundleId,
            userAsk: userAsk,
            triggerPhrase: triggerPhrase,
            assistantAnswerSummary: nil,
            userConfirmedItWorked: false,
            updatedExistingMemory: updatedExistingMemory,
            memoryTitleSnapshot: memoryTitleSnapshot,
            memorySummarySnapshot: memorySummarySnapshot
        )
    }

    private func makeMemory(
        category: MemoryCategory = .preference,
        receipts: [MemoryReceipt]
    ) -> Memory {
        Memory(
            id: "memory-under-test",
            category: category,
            title: "Current title",
            summary: "Current summary",
            body: "Current body.",
            receipts: receipts
        )
    }

    // MARK: - Snapshot capture

    @Test func captureIncludesMemoryTextSnapshots() {
        let turns = [
            SessionTraceEntry(
                timestamp: Date(),
                userTranscript: "keep answers short from now on",
                assistantResponse: "got it, short answers it is",
                bundleId: "com.apple.dt.Xcode",
                pointed: false
            )
        ]

        let receipt = MemoryReceipt.capture(
            category: .preference,
            turns: turns,
            gateReasons: [.statedPreference],
            sessionId: nil,
            targetBundleId: "com.apple.dt.Xcode",
            updatedExistingMemory: false,
            memoryTitleSnapshot: "Keep answers short",
            memorySummarySnapshot: "Short responses by default"
        )

        #expect(receipt.memoryTitleSnapshot == "Keep answers short")
        #expect(receipt.memorySummarySnapshot == "Short responses by default")
    }

    @Test func captureWithoutSnapshotsLeavesThemNil() {
        let receipt = MemoryReceipt.capture(
            category: .preference,
            turns: [],
            gateReasons: [.statedPreference],
            sessionId: nil,
            targetBundleId: nil,
            updatedExistingMemory: false
        )

        #expect(receipt.memoryTitleSnapshot == nil)
        #expect(receipt.memorySummarySnapshot == nil)
    }

    // MARK: - Codable backward compatibility

    @Test func receiptJSONWithoutSnapshotKeysStillDecodes() throws {
        // A receipt persisted by the receipts feature before the timeline
        // shipped — no snapshot keys on disk.
        let legacyMemoryJSON = """
        [{
            "id": "pref-legacy-receipt",
            "category": "preference",
            "title": "Prefer concise answers",
            "summary": "Short responses by default",
            "body": "Keep it brief.",
            "bundleIds": [],
            "status": "active",
            "isPinned": false,
            "usageCount": 1,
            "receipts": [{
                "savedAt": "2026-06-01T10:00:00Z",
                "gateReasons": ["statedPreference"],
                "userAsk": "can you explain this function?",
                "triggerPhrase": "keep answers short from now on",
                "userConfirmedItWorked": false,
                "updatedExistingMemory": false
            }]
        }]
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedMemories = try decoder.decode([Memory].self, from: Data(legacyMemoryJSON.utf8))

        let decodedReceipt = try #require(decodedMemories.first?.latestReceipt)
        #expect(decodedReceipt.memoryTitleSnapshot == nil)
        #expect(decodedReceipt.memorySummarySnapshot == nil)
        #expect(decodedReceipt.triggerPhrase == "keep answers short from now on")
    }

    // MARK: - Collapse rule

    @Test func timelineHiddenUntilTwoSaves() {
        let memoryWithNoReceipts = makeMemory(receipts: [])
        let memoryWithOneReceipt = makeMemory(receipts: [makeReceipt()])
        let memoryWithTwoReceipts = makeMemory(receipts: [
            makeReceipt(savedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            makeReceipt(savedAt: Date(timeIntervalSince1970: 1_700_100_000), updatedExistingMemory: true)
        ])

        #expect(!MemoryDiffTimelineBuilder.shouldShowTimeline(for: memoryWithNoReceipts))
        #expect(!MemoryDiffTimelineBuilder.shouldShowTimeline(for: memoryWithOneReceipt))
        #expect(MemoryDiffTimelineBuilder.shouldShowTimeline(for: memoryWithTwoReceipts))
    }

    // MARK: - Entry ordering

    @Test func entriesAreNewestFirst() {
        let olderSaveDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerSaveDate = Date(timeIntervalSince1970: 1_700_200_000)
        let memory = makeMemory(receipts: [
            makeReceipt(savedAt: olderSaveDate),
            makeReceipt(savedAt: newerSaveDate, updatedExistingMemory: true)
        ])

        let timelineEntries = MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory)

        #expect(timelineEntries.count == 2)
        #expect(timelineEntries.first?.savedAt == newerSaveDate)
        #expect(timelineEntries.last?.savedAt == olderSaveDate)
    }

    // MARK: - Diff derivation (preferences / routines)

    @Test func diffUsesTitleSnapshotsWhenTitleChanged() throws {
        let memory = makeMemory(receipts: [
            makeReceipt(
                memoryTitleSnapshot: "Keep answers short",
                memorySummarySnapshot: "Short responses by default"
            ),
            makeReceipt(
                savedAt: Date(timeIntervalSince1970: 1_700_200_000),
                updatedExistingMemory: true,
                memoryTitleSnapshot: "Go deeper on code explanations",
                memorySummarySnapshot: "Detailed answers for code questions"
            )
        ])

        let newestEntry = try #require(MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory).first)

        #expect(newestEntry.previousText == "Keep answers short")
        #expect(newestEntry.currentText == "Go deeper on code explanations")
    }

    @Test func diffFallsBackToSummaryWhenTitleUnchanged() throws {
        let memory = makeMemory(category: .routine, receipts: [
            makeReceipt(
                gateReasons: [.recurringRoutine],
                memoryTitleSnapshot: "Review a pull request",
                memorySummarySnapshot: "Open GitHub and skim the diff"
            ),
            makeReceipt(
                savedAt: Date(timeIntervalSince1970: 1_700_200_000),
                gateReasons: [.recurringRoutine],
                updatedExistingMemory: true,
                memoryTitleSnapshot: "Review a pull request",
                memorySummarySnapshot: "Open GitHub, read the diff, leave comments"
            )
        ])

        let newestEntry = try #require(MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory).first)

        #expect(newestEntry.previousText == "Open GitHub and skim the diff")
        #expect(newestEntry.currentText == "Open GitHub, read the diff, leave comments")
    }

    @Test func originalSaveShowsValueWithoutWas() throws {
        let memory = makeMemory(receipts: [
            makeReceipt(
                memoryTitleSnapshot: "Keep answers short",
                memorySummarySnapshot: "Short responses by default"
            ),
            makeReceipt(
                savedAt: Date(timeIntervalSince1970: 1_700_200_000),
                updatedExistingMemory: true,
                memoryTitleSnapshot: "Go deeper on code explanations",
                memorySummarySnapshot: "Detailed answers for code questions"
            )
        ])

        let oldestEntry = try #require(MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory).last)

        #expect(oldestEntry.previousText == nil)
        #expect(oldestEntry.currentText == "Keep answers short")
    }

    @Test func legacyReceiptsWithoutSnapshotsProduceNoDiff() {
        let memory = makeMemory(receipts: [
            makeReceipt(),
            makeReceipt(savedAt: Date(timeIntervalSince1970: 1_700_200_000), updatedExistingMemory: true)
        ])

        let timelineEntries = MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory)

        #expect(timelineEntries.count == 2)
        for timelineEntry in timelineEntries {
            #expect(timelineEntry.previousText == nil)
            #expect(timelineEntry.currentText == nil)
        }
    }

    @Test func updateAfterLegacyReceiptShowsValueWithoutWas() throws {
        // Previous save predates snapshots: never claim a "before" we don't
        // actually have — just show the value as of this save.
        let memory = makeMemory(receipts: [
            makeReceipt(),
            makeReceipt(
                savedAt: Date(timeIntervalSince1970: 1_700_200_000),
                updatedExistingMemory: true,
                memoryTitleSnapshot: "Go deeper on code explanations",
                memorySummarySnapshot: "Detailed answers for code questions"
            )
        ])

        let newestEntry = try #require(MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory).first)

        #expect(newestEntry.previousText == nil)
        #expect(newestEntry.currentText == "Go deeper on code explanations")
    }

    @Test func unchangedUpdateShowsNoText() throws {
        // A routine recurring with identical text: the entry's date and gate
        // reason tell the story, no redundant value line.
        let memory = makeMemory(category: .routine, receipts: [
            makeReceipt(
                gateReasons: [.recurringRoutine],
                memoryTitleSnapshot: "Review a pull request",
                memorySummarySnapshot: "Open GitHub and skim the diff"
            ),
            makeReceipt(
                savedAt: Date(timeIntervalSince1970: 1_700_200_000),
                gateReasons: [.recurringRoutine],
                updatedExistingMemory: true,
                memoryTitleSnapshot: "Review a pull request",
                memorySummarySnapshot: "Open GitHub and skim the diff"
            )
        ])

        let newestEntry = try #require(MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory).first)

        #expect(newestEntry.previousText == nil)
        #expect(newestEntry.currentText == nil)
        #expect(newestEntry.gateReasonExplanation == GateReason.recurringRoutine.userFacingExplanation)
    }

    // MARK: - Skill activity style

    @Test func skillEntriesAreActivityStyleWithoutDiff() {
        let memory = makeMemory(category: .skill, receipts: [
            makeReceipt(
                gateReasons: [.screenTeaching],
                memoryTitleSnapshot: "Commit changes in Xcode",
                memorySummarySnapshot: "Stage and commit via Source Control"
            ),
            makeReceipt(
                savedAt: Date(timeIntervalSince1970: 1_700_200_000),
                gateReasons: [.userConfirmed],
                updatedExistingMemory: true,
                memoryTitleSnapshot: "Commit changes in Xcode and push",
                memorySummarySnapshot: "Stage, commit, and push via Source Control"
            )
        ])

        let timelineEntries = MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory)

        #expect(timelineEntries.count == 2)
        #expect(timelineEntries.first?.activityLabel == "Updated")
        #expect(timelineEntries.last?.activityLabel == "Saved")
        for timelineEntry in timelineEntries {
            #expect(timelineEntry.previousText == nil)
            #expect(timelineEntry.currentText == nil)
        }
    }

    // MARK: - Receipt evidence on entries

    @Test func entryCarriesReceiptEvidence() throws {
        let memory = makeMemory(receipts: [
            makeReceipt(),
            makeReceipt(
                savedAt: Date(timeIntervalSince1970: 1_700_200_000),
                gateReasons: [.styleCorrection, .statedPreference],
                appBundleId: "com.apple.dt.Xcode",
                userAsk: "explain this error in the console",
                triggerPhrase: "that's too short, go deeper when explaining code",
                updatedExistingMemory: true
            )
        ])

        let newestEntry = try #require(MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory).first)

        #expect(newestEntry.gateReasonExplanation == GateReason.styleCorrection.userFacingExplanation)
        #expect(newestEntry.userPhrase == "that's too short, go deeper when explaining code")
        #expect(newestEntry.appDisplayName == "Xcode")
    }

    @Test func entryFallsBackToUserAskWhenNoTriggerPhrase() throws {
        let memory = makeMemory(category: .routine, receipts: [
            makeReceipt(gateReasons: [.recurringRoutine], userAsk: "walk me through my standup prep", triggerPhrase: nil),
            makeReceipt(
                savedAt: Date(timeIntervalSince1970: 1_700_200_000),
                gateReasons: [.recurringRoutine],
                userAsk: "standup prep again please",
                triggerPhrase: nil,
                updatedExistingMemory: true
            )
        ])

        let newestEntry = try #require(MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory).first)

        #expect(newestEntry.userPhrase == "standup prep again please")
    }

    // MARK: - Relative date label

    @Test func relativeLabelIsTodayForSameDaySave() {
        let entry = MemoryTimelineEntry(
            id: "0-0",
            savedAt: Date(),
            activityLabel: "Saved",
            previousText: nil,
            currentText: nil,
            gateReasonExplanation: nil,
            userPhrase: nil,
            appDisplayName: nil
        )

        #expect(entry.relativeSavedAtLabel() == "Today")
    }
}
