//
//  MemoryReceiptTests.swift
//  leanring-buddyTests
//
//  Covers receipt capture from session turns, backward-compatible decoding,
//  store round-trips (auxiliary JSON + skill sidecar), and the grounding of
//  the spoken explanation prompt.
//

import Foundation
import Testing
@testable import leanring_buddy

@Suite(.serialized)
struct MemoryReceiptTests {
    private func makeTurn(
        userTranscript: String,
        assistantResponse: String = "here's how you do it",
        bundleId: String? = "com.apple.TextEdit",
        pointed: Bool = false
    ) -> SessionTraceEntry {
        SessionTraceEntry(
            timestamp: Date(),
            userTranscript: userTranscript,
            assistantResponse: assistantResponse,
            bundleId: bundleId,
            pointed: pointed
        )
    }

    // MARK: - Capture

    @Test func captureForSkillUsesConfirmationAsTriggerPhrase() {
        let turns = [
            makeTurn(userTranscript: "how do I save this document?", pointed: true),
            makeTurn(userTranscript: "perfect, that worked")
        ]

        let receipt = MemoryReceipt.capture(
            category: .skill,
            turns: turns,
            gateReasons: [.userConfirmed, .screenTeaching],
            sessionId: UUID(),
            targetBundleId: "com.apple.TextEdit",
            updatedExistingMemory: false
        )

        #expect(receipt.userAsk == "how do I save this document?")
        #expect(receipt.triggerPhrase == "perfect, that worked")
        #expect(receipt.userConfirmedItWorked)
        #expect(receipt.gateReasons == [.userConfirmed, .screenTeaching])
        #expect(receipt.primaryGateReason == .userConfirmed)
        #expect(receipt.appBundleId == "com.apple.TextEdit")
        #expect(!receipt.updatedExistingMemory)
    }

    @Test func captureForPreferenceUsesStatedPreferenceAsTriggerPhrase() {
        let turns = [
            makeTurn(userTranscript: "can you explain this function?"),
            makeTurn(userTranscript: "keep answers short from now on")
        ]

        let receipt = MemoryReceipt.capture(
            category: .preference,
            turns: turns,
            gateReasons: [.statedPreference],
            sessionId: nil,
            targetBundleId: nil,
            updatedExistingMemory: false
        )

        #expect(receipt.userAsk == "can you explain this function?")
        #expect(receipt.triggerPhrase == "keep answers short from now on")
        #expect(!receipt.userConfirmedItWorked)
        #expect(receipt.sessionId == nil)
    }

    @Test func captureForRoutineHasNoTriggerPhrase() {
        let turns = [
            makeTurn(userTranscript: "walk me through the export workflow", pointed: true),
            makeTurn(userTranscript: "now the upload step", pointed: true)
        ]

        let receipt = MemoryReceipt.capture(
            category: .routine,
            turns: turns,
            gateReasons: [.recurringRoutine],
            sessionId: UUID(),
            targetBundleId: "com.apple.finder",
            updatedExistingMemory: true
        )

        #expect(receipt.triggerPhrase == nil)
        #expect(receipt.userAsk == "walk me through the export workflow")
        #expect(receipt.updatedExistingMemory)
    }

    @Test func captureTruncatesLongAssistantAnswer() throws {
        let longAssistantResponse = String(repeating: "step then ", count: 60)
        let turns = [
            makeTurn(userTranscript: "how do I do this?", assistantResponse: longAssistantResponse)
        ]

        let receipt = MemoryReceipt.capture(
            category: .skill,
            turns: turns,
            gateReasons: [.screenTeaching],
            sessionId: nil,
            targetBundleId: nil,
            updatedExistingMemory: false
        )

        let assistantAnswerSummary = try #require(receipt.assistantAnswerSummary)
        #expect(assistantAnswerSummary.count <= 201)
        #expect(assistantAnswerSummary.hasSuffix("…"))
    }

    @Test func appendReceiptCapsAtMostRecentEntries() {
        var receipts: [MemoryReceipt] = []
        for receiptIndex in 0..<12 {
            let receipt = MemoryReceipt.capture(
                category: .skill,
                turns: [makeTurn(userTranscript: "ask number \(receiptIndex)")],
                gateReasons: [.screenTeaching],
                sessionId: nil,
                targetBundleId: nil,
                updatedExistingMemory: false
            )
            receipts = MemoryReceipt.appendReceipt(receipt, to: receipts)
        }

        #expect(receipts.count == MemoryReceipt.maximumReceiptsPerMemory)
        // The oldest entries are dropped first, so the newest append survives.
        #expect(receipts.last?.userAsk == "ask number 11")
        #expect(receipts.first?.userAsk == "ask number 2")
    }

    // MARK: - Codable backward compatibility

    @Test func legacyMemoryJSONWithoutReceiptsKeyStillDecodes() throws {
        let legacyMemoryJSON = """
        [{
            "id": "pref-legacy",
            "category": "preference",
            "title": "Prefer concise answers",
            "summary": "Short responses by default",
            "body": "Keep it brief.",
            "bundleIds": [],
            "status": "active",
            "isPinned": false,
            "usageCount": 3
        }]
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedMemories = try decoder.decode([Memory].self, from: Data(legacyMemoryJSON.utf8))

        let legacyMemory = try #require(decodedMemories.first)
        #expect(legacyMemory.id == "pref-legacy")
        #expect(legacyMemory.receipts.isEmpty)
        #expect(legacyMemory.latestReceipt == nil)
    }

    @Test func auxiliaryMemoryStoreRoundTripsReceipts() throws {
        let isolatedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicky-receipt-tests-\(UUID().uuidString)", isDirectory: true)

        try ClickyTestHomeIsolation.withIsolatedHome(isolatedHome) {
            let store = AuxiliaryMemoryStore()
            let receipt = MemoryReceipt(
                savedAt: Date(timeIntervalSince1970: 1_700_000_000),
                sessionId: UUID(),
                gateReasons: [.statedPreference],
                appBundleId: "com.apple.dt.Xcode",
                userAsk: "can you explain this function?",
                triggerPhrase: "keep answers short from now on",
                assistantAnswerSummary: "short version: it parses the config.",
                userConfirmedItWorked: false,
                updatedExistingMemory: false
            )
            let memory = Memory(
                id: "pref-receipt-test",
                category: .preference,
                title: "Prefer concise answers",
                summary: "Short responses by default",
                body: "Keep it brief.",
                receipts: [receipt]
            )

            try store.save(memory)
            store.load()

            let loadedMemory = try #require(store.memory(withID: "pref-receipt-test"))
            #expect(loadedMemory.receipts == [receipt])
        }
    }

    @Test func teachingSkillStoreRoundTripsReceiptsSidecar() throws {
        let isolatedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicky-receipt-tests-\(UUID().uuidString)", isDirectory: true)

        try ClickyTestHomeIsolation.withIsolatedHome(isolatedHome) {
            let store = TeachingSkillStore()
            let receipt = MemoryReceipt(
                savedAt: Date(timeIntervalSince1970: 1_700_000_000),
                sessionId: UUID(),
                gateReasons: [.userConfirmed, .screenTeaching],
                appBundleId: "com.apple.TextEdit",
                userAsk: "how do I save this document?",
                triggerPhrase: "perfect, that worked",
                assistantAnswerSummary: "press command s, then click save.",
                userConfirmedItWorked: true,
                updatedExistingMemory: false
            )
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
                receipts: [receipt],
                body: "click file then save"
            )

            try store.saveSkill(skill)
            store.loadSkills()

            let loadedSkill = try #require(store.skill(withID: skill.id))
            #expect(loadedSkill.receipts == [receipt])

            // The unified memories adapter must surface skill receipts too.
            let adaptedMemory = Memory(skill: loadedSkill)
            #expect(adaptedMemory.receipts == [receipt])
        }
    }

    // MARK: - Explanation prompt grounding

    @Test func explanationPromptQuotesReceiptEvidence() {
        let receipt = MemoryReceipt(
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sessionId: UUID(),
            gateReasons: [.userConfirmed],
            appBundleId: "com.apple.TextEdit",
            userAsk: "how do I save this document?",
            triggerPhrase: "perfect, that worked",
            assistantAnswerSummary: "press command s, then click save.",
            userConfirmedItWorked: true,
            updatedExistingMemory: false
        )
        let memory = Memory(
            id: "teach-textedit-save",
            category: .skill,
            title: "Save in TextEdit",
            summary: "Walk the user through saving a document",
            body: "click file then save",
            receipts: [receipt]
        )

        let userPrompt = ReceiptExplanationPromptBuilder.buildExplanationUserPrompt(
            memory: memory,
            receipts: memory.receipts
        )

        #expect(userPrompt.contains("\"how do I save this document?\""))
        #expect(userPrompt.contains("\"perfect, that worked\""))
        #expect(userPrompt.contains("you confirmed it worked"))
        #expect(userPrompt.contains("TextEdit"))
        #expect(userPrompt.contains("Save in TextEdit"))
    }

    @Test func deterministicFallbackExplanationUsesReceiptFacts() {
        let receipt = MemoryReceipt(
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sessionId: nil,
            gateReasons: [.statedPreference],
            appBundleId: "com.apple.dt.Xcode",
            userAsk: "can you explain this function?",
            triggerPhrase: "keep answers short from now on",
            assistantAnswerSummary: nil,
            userConfirmedItWorked: false,
            updatedExistingMemory: false
        )

        let fallbackExplanation = ReceiptExplanationPromptBuilder.buildDeterministicFallbackExplanation(
            receipt: receipt
        )

        #expect(fallbackExplanation.contains("Xcode"))
        #expect(fallbackExplanation.contains("you stated a preference"))
        #expect(fallbackExplanation.contains("\"keep answers short from now on\""))
    }
}
