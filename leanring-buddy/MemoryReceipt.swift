//
//  MemoryReceipt.swift
//  leanring-buddy
//
//  Self-contained evidence for why a memory (skill, preference, routine) was
//  saved. Captured at distill time from the session turns and gate decision.
//  Receipts must copy everything they need out of the session: session JSONs
//  under ~/.clicky/sessions/ are deleted after 7 days, so a receipt cannot
//  reference a session file and look it up later.
//

import Foundation

struct MemoryReceipt: Codable, Equatable {
    /// When the memory write that produced this receipt happened.
    let savedAt: Date
    /// The persisted session this save came from. Nil for proactive mid-session
    /// drafts, which run before the session is finalized and persisted.
    let sessionId: UUID?
    /// Gate reasons that fired for this category, most specific first.
    let gateReasons: [GateReason]
    /// Bundle ID of the app the teaching happened in, when known.
    let appBundleId: String?
    /// The user's original ask, verbatim (e.g. "how do I commit in Xcode?").
    let userAsk: String?
    /// The verbatim user phrase that triggered the save: a confirmation for
    /// skills ("perfect, that worked") or a stated preference ("keep answers
    /// short"). Nil for routines, which are saved on recurrence, not a phrase.
    let triggerPhrase: String?
    /// Condensed final assistant response from the session, for context.
    let assistantAnswerSummary: String?
    /// Whether any turn in the session confirmed the help worked.
    let userConfirmedItWorked: Bool
    /// Whether this save updated an existing memory rather than creating a new one.
    let updatedExistingMemory: Bool
    /// The memory's title exactly as this save persisted it. The stores
    /// overwrite memories in place, so without a snapshot on each receipt the
    /// previous wording is lost and the diff timeline ("How this changed")
    /// could not show a Was → Now comparison. Nil on receipts captured before
    /// the timeline shipped.
    let memoryTitleSnapshot: String?
    /// The memory's one-line summary exactly as this save persisted it.
    /// Fallback diff text for the timeline when the title did not change.
    let memorySummarySnapshot: String?

    var primaryGateReason: GateReason? {
        gateReasons.first
    }

    // Explicit initializer so the snapshot fields can default to nil: receipts
    // built outside `capture` (tests, dummy seeds) predate snapshots and should
    // keep compiling without naming them.
    init(
        savedAt: Date,
        sessionId: UUID?,
        gateReasons: [GateReason],
        appBundleId: String?,
        userAsk: String?,
        triggerPhrase: String?,
        assistantAnswerSummary: String?,
        userConfirmedItWorked: Bool,
        updatedExistingMemory: Bool,
        memoryTitleSnapshot: String? = nil,
        memorySummarySnapshot: String? = nil
    ) {
        self.savedAt = savedAt
        self.sessionId = sessionId
        self.gateReasons = gateReasons
        self.appBundleId = appBundleId
        self.userAsk = userAsk
        self.triggerPhrase = triggerPhrase
        self.assistantAnswerSummary = assistantAnswerSummary
        self.userConfirmedItWorked = userConfirmedItWorked
        self.updatedExistingMemory = updatedExistingMemory
        self.memoryTitleSnapshot = memoryTitleSnapshot
        self.memorySummarySnapshot = memorySummarySnapshot
    }

    /// Upper bound on receipts kept per memory. Receipts append on every save,
    /// so a frequently-updated memory would otherwise grow without bound.
    static let maximumReceiptsPerMemory = 10

    private static let maximumAssistantAnswerSummaryCharacters = 200

    /// Builds a receipt from the session turns and gate decision at distill time.
    /// Pass `memoryTitleSnapshot`/`memorySummarySnapshot` with the memory text
    /// this save is about to persist so the diff timeline can compare
    /// consecutive saves later.
    static func capture(
        category: MemoryCategory,
        turns: [SessionTraceEntry],
        gateReasons: [GateReason],
        sessionId: UUID?,
        targetBundleId: String?,
        updatedExistingMemory: Bool,
        memoryTitleSnapshot: String? = nil,
        memorySummarySnapshot: String? = nil,
        now: Date = Date()
    ) -> MemoryReceipt {
        let userAsk = SkillTriggerEvaluator.primaryTeachingQuestion(from: turns)
            ?? firstNonEmptyUserTranscript(in: turns)

        let triggerPhrase: String?
        switch category {
        case .skill:
            triggerPhrase = lastConfirmationTranscript(in: turns)
        case .preference:
            triggerPhrase = PreferenceSignalDetector.primaryPreferenceTranscript(in: turns)
        case .routine:
            // Routines are saved because a workflow recurred across days, not
            // because of a single phrase the user said.
            triggerPhrase = nil
        }

        let lastAssistantResponse = turns
            .map(\.assistantResponse)
            .last { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let assistantAnswerSummary = lastAssistantResponse.map {
            truncated($0, to: maximumAssistantAnswerSummaryCharacters)
        }

        return MemoryReceipt(
            savedAt: now,
            sessionId: sessionId,
            gateReasons: gateReasons,
            appBundleId: targetBundleId,
            userAsk: userAsk,
            triggerPhrase: triggerPhrase,
            assistantAnswerSummary: assistantAnswerSummary,
            userConfirmedItWorked: lastConfirmationTranscript(in: turns) != nil,
            updatedExistingMemory: updatedExistingMemory,
            memoryTitleSnapshot: memoryTitleSnapshot,
            memorySummarySnapshot: memorySummarySnapshot
        )
    }

    /// Appends a receipt, keeping only the most recent
    /// `maximumReceiptsPerMemory` entries (oldest dropped first).
    static func appendReceipt(
        _ newReceipt: MemoryReceipt,
        to existingReceipts: [MemoryReceipt]
    ) -> [MemoryReceipt] {
        let combinedReceipts = existingReceipts + [newReceipt]
        guard combinedReceipts.count > maximumReceiptsPerMemory else { return combinedReceipts }
        return Array(combinedReceipts.suffix(maximumReceiptsPerMemory))
    }

    private static func firstNonEmptyUserTranscript(in turns: [SessionTraceEntry]) -> String? {
        turns
            .map(\.userTranscript)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Last user turn that confirms the help worked. Skips empty transcripts:
    /// `isConfirmationTranscript` treats an empty string as a confirmation, but
    /// an empty phrase is useless as receipt evidence.
    private static func lastConfirmationTranscript(in turns: [SessionTraceEntry]) -> String? {
        turns
            .map(\.userTranscript)
            .last { transcript in
                !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                SkillTriggerEvaluator.isConfirmationTranscript(transcript)
            }
    }

    private static func truncated(_ text: String, to maxCharacters: Int) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count > maxCharacters else { return trimmedText }
        let endIndex = trimmedText.index(trimmedText.startIndex, offsetBy: maxCharacters)
        return String(trimmedText[..<endIndex]) + "…"
    }
}

extension GateReason {
    /// Human-readable explanation of why the gate fired, shown in the receipt
    /// UI and fed as a fact into the spoken explanation prompt.
    var userFacingExplanation: String {
        switch self {
        case .userConfirmed:
            return "You confirmed it worked"
        case .multiStepPointing:
            return "Clicky pointed you through multiple steps"
        case .repeatedTopic:
            return "You asked about this topic again within a week"
        case .screenTeaching:
            return "Clicky taught this on your screen"
        case .statedPreference:
            return "You stated a preference"
        case .styleCorrection:
            return "You corrected Clicky's style more than once"
        case .recurringRoutine:
            return "This workflow recurred across multiple days"
        }
    }
}

/// Composes the grounded prompt for the "Ask Clicky why" explanation and the
/// deterministic fallbacks used when the receipt or the Claude call is missing.
enum ReceiptExplanationPromptBuilder {
    static let explanationSystemPrompt = """
    you are clicky, a friendly screen-native voice companion. the user pressed "ask clicky why" on a memory you saved and wants to know why you saved it.

    you are given verified receipt facts about how the memory was saved. explain, speaking as clicky in first person, why you saved it.

    hard rules:
    - only use the facts provided below. never invent details, dates, apps, quotes, or reasons that are not in the receipt facts.
    - if a fact is missing, simply don't mention it. do not guess.
    - when a user phrase is provided, quote it back naturally.
    - 2-3 short sentences, written to be spoken aloud. conversational and warm. no markdown, no lists.
    - all lowercase.
    """

    /// Spoken verbatim (no LLM call) for memories saved before receipts existed.
    static let missingReceiptExplanation =
        "i saved this before i started keeping receipts, so i don't have the exact moment on file. " +
        "if it doesn't look right you can edit or delete it from here."

    /// How many of the most recent receipts to include as prompt facts.
    private static let maximumReceiptsInPrompt = 3

    static func buildExplanationUserPrompt(memory: Memory, receipts: [MemoryReceipt]) -> String {
        var promptLines: [String] = []
        promptLines.append("memory category: \(memory.category.displayLabel.lowercased())")
        promptLines.append("memory title: \(memory.title)")
        if !memory.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptLines.append("memory summary: \(memory.summary)")
        }

        let mostRecentReceiptsFirst = Array(receipts.suffix(maximumReceiptsInPrompt).reversed())
        for (receiptIndex, receipt) in mostRecentReceiptsFirst.enumerated() {
            let receiptLabel = receiptIndex == 0 ? "most recent save" : "earlier save \(receiptIndex)"
            promptLines.append("")
            promptLines.append("receipt (\(receiptLabel)):")
            promptLines.append(contentsOf: factLines(for: receipt))
        }

        promptLines.append("")
        promptLines.append("explain why you saved this memory, using only the facts above.")
        return promptLines.joined(separator: "\n")
    }

    /// Template explanation used when the Claude call fails, so the button
    /// still answers with grounded facts instead of erroring out.
    static func buildDeterministicFallbackExplanation(receipt: MemoryReceipt) -> String {
        var sentenceParts: [String] = []

        var savedClause = "i saved this on \(absoluteDateLabel(for: receipt.savedAt))"
        if let appDisplayName = TeachingSkill.displayName(forBundleId: receipt.appBundleId) {
            savedClause += " while you were in \(appDisplayName)"
        }
        if let primaryGateReason = receipt.primaryGateReason {
            savedClause += " because \(primaryGateReason.userFacingExplanation.lowercased())"
        }
        sentenceParts.append(savedClause + ".")

        if let triggerPhrase = receipt.triggerPhrase {
            sentenceParts.append("you said: \"\(triggerPhrase)\".")
        } else if let userAsk = receipt.userAsk {
            sentenceParts.append("you had asked: \"\(userAsk)\".")
        }

        return sentenceParts.joined(separator: " ")
    }

    private static func factLines(for receipt: MemoryReceipt) -> [String] {
        var factLines: [String] = []
        factLines.append("- saved on: \(absoluteDateLabel(for: receipt.savedAt))")

        if let appDisplayName = TeachingSkill.displayName(forBundleId: receipt.appBundleId) {
            factLines.append("- app: \(appDisplayName)")
        }

        if !receipt.gateReasons.isEmpty {
            let reasonExplanations = receipt.gateReasons
                .map { $0.userFacingExplanation.lowercased() }
                .joined(separator: "; ")
            factLines.append("- why the save fired: \(reasonExplanations)")
        }

        if let userAsk = receipt.userAsk {
            factLines.append("- the user's original ask, verbatim: \"\(userAsk)\"")
        }

        if let triggerPhrase = receipt.triggerPhrase {
            factLines.append("- the user phrase that triggered the save, verbatim: \"\(triggerPhrase)\"")
        }

        if let assistantAnswerSummary = receipt.assistantAnswerSummary {
            factLines.append("- what clicky answered (condensed): \"\(assistantAnswerSummary)\"")
        }

        factLines.append("- user confirmed the help worked: \(receipt.userConfirmedItWorked ? "yes" : "no")")

        if receipt.updatedExistingMemory {
            factLines.append("- this save updated an existing memory rather than creating a new one")
        }

        return factLines
    }

    private static func absoluteDateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
}
