//
//  MemoryDiffTimeline.swift
//  leanring-buddy
//
//  Builds the "How this changed" timeline shown in the memory detail view.
//  Each saved receipt becomes one timeline entry, newest first. Preferences
//  and routines lead with a Was → Now text diff derived from the title/summary
//  snapshots captured on consecutive receipts; skills get a lighter
//  saved/updated activity style because they grow rather than flip values.
//  The timeline is read-only transparency: it never changes which memory is
//  active (latest preference/routine still wins for Clicky's responses).
//

import Foundation

/// One event in a memory's change history, derived from a single receipt.
struct MemoryTimelineEntry: Identifiable, Equatable {
    let id: String
    /// When the save that produced this entry happened.
    let savedAt: Date
    /// "Saved" when the save created the memory, "Updated" when it patched an
    /// existing one. Shown prominently for skills (activity style).
    let activityLabel: String
    /// The memory text before this save. Only set when both this receipt and
    /// the previous one carry snapshots and the text actually changed — never
    /// guessed. Nil for the original save and for legacy receipts.
    let previousText: String?
    /// The memory text as of this save. For the original save (or when the
    /// previous receipt has no snapshot) this is shown alone, without a "Was".
    let currentText: String?
    /// Human-readable explanation of why the save fired (`GateReason`).
    let gateReasonExplanation: String?
    /// Verbatim user phrase tied to this save: the trigger phrase when one
    /// exists, otherwise the user's original ask.
    let userPhrase: String?
    /// Display name of the app the save happened in, when known.
    let appDisplayName: String?

    /// Relative label like "Today", "Yesterday", or "2 weeks ago" for the row
    /// header. `now` is injectable for tests.
    func relativeSavedAtLabel(now: Date = Date()) -> String {
        if Calendar.current.isDateInToday(savedAt) {
            return "Today"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        let relativeLabel = formatter.localizedString(for: savedAt, relativeTo: now)
        return relativeLabel.prefix(1).capitalized + String(relativeLabel.dropFirst())
    }
}

enum MemoryDiffTimelineBuilder {
    /// The timeline only earns its space once there are at least two saves —
    /// a single save has nothing to compare, and its evidence is already
    /// covered by the "Why Clicky saved this" receipt card.
    static let minimumSaveEventsToShowTimeline = 2

    static func shouldShowTimeline(for memory: Memory) -> Bool {
        memory.receipts.count >= minimumSaveEventsToShowTimeline
    }

    /// Maps a memory's receipts (stored oldest first) to timeline entries,
    /// newest first so the most recent change sits at the top of the section.
    static func buildTimelineEntries(for memory: Memory) -> [MemoryTimelineEntry] {
        var entriesOldestFirst: [MemoryTimelineEntry] = []

        for (receiptIndex, receipt) in memory.receipts.enumerated() {
            let previousReceipt = receiptIndex > 0 ? memory.receipts[receiptIndex - 1] : nil
            let textChange = deriveTextChange(
                for: receipt,
                previousReceipt: previousReceipt,
                category: memory.category
            )

            let entry = MemoryTimelineEntry(
                // savedAt alone could collide if two saves land in the same
                // second, so the receipt index keeps the ID unique and stable.
                id: "\(receiptIndex)-\(receipt.savedAt.timeIntervalSince1970)",
                savedAt: receipt.savedAt,
                activityLabel: receipt.updatedExistingMemory ? "Updated" : "Saved",
                previousText: textChange.previousText,
                currentText: textChange.currentText,
                gateReasonExplanation: receipt.primaryGateReason?.userFacingExplanation,
                userPhrase: receipt.triggerPhrase ?? receipt.userAsk,
                appDisplayName: TeachingSkill.displayName(forBundleId: receipt.appBundleId)
            )
            entriesOldestFirst.append(entry)
        }

        return Array(entriesOldestFirst.reversed())
    }

    /// Decides what text (if any) a timeline entry shows for this save.
    ///
    /// - Skills: no text at all — they accumulate steps rather than flip
    ///   values, so a Was → Now diff would mostly show noisy rewrites.
    /// - Original save: the value as saved then, with no "Was" side.
    /// - Update with snapshots on both sides: Was → Now on the title when it
    ///   changed, falling back to the summary when only the summary changed.
    /// - Update where the previous receipt predates snapshots: the value at
    ///   this save alone — never claim a "before" we don't actually have.
    /// - Update where nothing textual changed: no text (date + reason +
    ///   phrase still tell the story, e.g. a routine recurring unchanged).
    private static func deriveTextChange(
        for receipt: MemoryReceipt,
        previousReceipt: MemoryReceipt?,
        category: MemoryCategory
    ) -> (previousText: String?, currentText: String?) {
        guard category != .skill else { return (nil, nil) }

        guard let previousReceipt else {
            return (nil, receipt.memoryTitleSnapshot ?? receipt.memorySummarySnapshot)
        }

        if let currentTitle = receipt.memoryTitleSnapshot,
           let previousTitle = previousReceipt.memoryTitleSnapshot,
           currentTitle != previousTitle {
            return (previousTitle, currentTitle)
        }

        if let currentSummary = receipt.memorySummarySnapshot,
           let previousSummary = previousReceipt.memorySummarySnapshot,
           currentSummary != previousSummary {
            return (previousSummary, currentSummary)
        }

        let previousReceiptHasNoSnapshots = previousReceipt.memoryTitleSnapshot == nil
            && previousReceipt.memorySummarySnapshot == nil
        if previousReceiptHasNoSnapshots {
            return (nil, receipt.memoryTitleSnapshot ?? receipt.memorySummarySnapshot)
        }

        return (nil, nil)
    }
}
