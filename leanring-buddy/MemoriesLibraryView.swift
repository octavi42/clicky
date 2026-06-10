//
//  MemoriesLibraryView.swift
//  leanring-buddy
//
//  Unified memories library with detail view, inline editing, and delete.
//

import SwiftUI

enum MemoriesCategoryFilter: String, CaseIterable, Identifiable {
    case skill
    case preference
    case routine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .skill: return "Skills"
        case .preference: return "Preferences"
        case .routine: return "Routines"
        }
    }

    var memoryCategory: MemoryCategory {
        switch self {
        case .skill: return .skill
        case .preference: return .preference
        case .routine: return .routine
        }
    }

    init(memoryCategory: MemoryCategory) {
        switch memoryCategory {
        case .skill: self = .skill
        case .preference: self = .preference
        case .routine: self = .routine
        }
    }
}

struct MemoriesLibraryView: View {
    @ObservedObject var companionManager: CompanionManager
    let initialSelectedMemoryID: String?
    let onBack: () -> Void

    @State private var selectedCategoryFilter: MemoriesCategoryFilter = .skill
    @State private var selectedMemory: Memory?
    @State private var isEditingSelectedMemory = false
    @State private var memoryEdit = MemoryEdit(
        title: "",
        summary: "",
        body: "",
        bundleIds: [],
        status: .active
    )
    @State private var memoryPendingDelete: Memory?
    @State private var isHoveringAskClickyWhyButton = false
    @State private var isTimelineExpanded = false
    @State private var isHoveringTimelineHeader = false

    private var filteredMemories: [Memory] {
        companionManager.memories(
            category: selectedCategoryFilter.memoryCategory,
            status: nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            libraryHeader

            Divider()
                .background(DS.Colors.borderSubtle)
                .padding(.horizontal, 16)

            if let selectedMemory {
                memoryDetailView(selectedMemory)
            } else {
                categoryFilterPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                memoriesList
            }
        }
        .onAppear {
            openInitialMemoryIfNeeded()
        }
        .onChange(of: initialSelectedMemoryID) { _, _ in
            openInitialMemoryIfNeeded()
        }
        .onChange(of: companionManager.memories) { _, _ in
            refreshSelectedMemoryIfNeeded()
        }
        .confirmationDialog(
            "Delete this memory?",
            isPresented: Binding(
                get: { memoryPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        memoryPendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                confirmDeletePendingMemory()
            }
            Button("Cancel", role: .cancel) {
                memoryPendingDelete = nil
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var libraryHeader: some View {
        HStack(spacing: 8) {
            Button(action: {
                if selectedMemory != nil {
                    cancelEditingIfNeeded()
                    companionManager.clearMemoryReceiptExplanation()
                    selectedMemory = nil
                } else {
                    onBack()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Text(selectedMemory?.title ?? "Memories")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textSecondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var categoryFilterPicker: some View {
        HStack(spacing: 4) {
            ForEach(MemoriesCategoryFilter.allCases) { filter in
                Button(action: {
                    selectedCategoryFilter = filter
                }) {
                    Text(filter.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(
                            selectedCategoryFilter == filter ? DS.Colors.textOnAccent : DS.Colors.textTertiary
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                                .fill(selectedCategoryFilter == filter ? DS.Colors.accent : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityIdentifier("clicky.panel.memories-library.category.\(filter.rawValue)")
            }
        }
    }

    private var memoriesList: some View {
        ScrollView {
            if filteredMemories.isEmpty {
                Text(selectedCategoryFilter.memoryCategory.emptyStateMessage)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredMemories) { memory in
                        memoryRow(memory)
                        Divider()
                            .background(DS.Colors.borderSubtle.opacity(0.5))
                            .padding(.leading, 16)
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxHeight: 300)
    }

    private func memoryRow(_ memory: Memory) -> some View {
        Button(action: {
            companionManager.clearMemoryReceiptExplanation()
            selectedMemory = memory
            isEditingSelectedMemory = false
            // The timeline starts collapsed for every freshly opened memory.
            isTimelineExpanded = false
        }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(memory.category.displayLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )

                    Text(memory.relativeSavedLabel())
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityIdentifier("clicky.panel.memories-library.row.\(memory.id)")
    }

    @ViewBuilder
    private func memoryDetailView(_ memory: Memory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isEditingSelectedMemory {
                    memoryEditForm(memory)
                } else {
                    memoryReadOnlyDetail(memory)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 320)
    }

    private func memoryReadOnlyDetail(_ memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(memory.summary)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textSecondary)

                HStack(spacing: 6) {
                    Text(memory.category.displayLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )

                    Text(memory.relativeSavedLabel())
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }

            HStack(spacing: 12) {
                Button(action: {
                    beginEditing(memory)
                }) {
                    Text("Edit")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.accent)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityIdentifier("clicky.panel.memories-library.edit")

                Button(action: {
                    memoryPendingDelete = memory
                }) {
                    Text("Delete")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.destructive)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityIdentifier("clicky.panel.memories-library.delete")

                Spacer()
            }

            memoryTimelineSection(memory)

            memoryReceiptSection(memory)

            Divider()
                .background(DS.Colors.borderSubtle)

            memoryMarkdownBody(memory.body)
        }
    }

    // MARK: - Memory Diff Timeline ("How this changed")

    /// Collapsible change history for the memory, one entry per saved receipt.
    /// Hidden entirely until the memory has been saved at least twice — a
    /// single save has no history worth a section.
    @ViewBuilder
    private func memoryTimelineSection(_ memory: Memory) -> some View {
        if MemoryDiffTimelineBuilder.shouldShowTimeline(for: memory) {
            let timelineEntries = MemoryDiffTimelineBuilder.buildTimelineEntries(for: memory)

            VStack(alignment: .leading, spacing: 0) {
                timelineHeaderButton(timelineEntryCount: timelineEntries.count)

                if isTimelineExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(timelineEntries.enumerated()), id: \.element.id) { entryIndex, timelineEntry in
                            timelineEntryRow(
                                timelineEntry,
                                isNewestEntry: entryIndex == 0,
                                isOldestEntry: entryIndex == timelineEntries.count - 1,
                                isSkillCategory: memory.category == .skill
                            )
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                            .stroke(DS.Colors.borderSubtle.opacity(0.5), lineWidth: 0.8)
                    )
            )
        }
    }

    private func timelineHeaderButton(timelineEntryCount: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                isTimelineExpanded.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.accent)

                Text("How this changed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isHoveringTimelineHeader ? DS.Colors.textSecondary : DS.Colors.textTertiary)

                Text("\(timelineEntryCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DS.Colors.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                Spacer()

                Image(systemName: isTimelineExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isHoveringTimelineHeader ? DS.Colors.textSecondary : DS.Colors.textTertiary)
            }
            // Make the whole header row clickable, including the empty space
            // between the title and the chevron.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { isHovering in
            isHoveringTimelineHeader = isHovering
        }
        .accessibilityIdentifier("clicky.panel.memories-library.timeline-toggle")
    }

    private func timelineEntryRow(
        _ timelineEntry: MemoryTimelineEntry,
        isNewestEntry: Bool,
        isOldestEntry: Bool,
        isSkillCategory: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Gutter: dot for this entry plus the connecting line down to the
            // next (older) entry. The newest entry gets the filled accent dot.
            VStack(spacing: 2) {
                if isNewestEntry {
                    Circle()
                        .fill(DS.Colors.accent)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .strokeBorder(DS.Colors.textTertiary, lineWidth: 1)
                        .frame(width: 6, height: 6)
                }

                if !isOldestEntry {
                    Rectangle()
                        .fill(DS.Colors.borderSubtle)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(timelineEntryContextLine(timelineEntry, isSkillCategory: isSkillCategory))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Colors.textSecondary)

                if let previousText = timelineEntry.previousText,
                   let currentText = timelineEntry.currentText {
                    timelineWasNowLine(label: "Was", text: previousText, isCurrentValue: false)
                    timelineWasNowLine(label: "Now", text: currentText, isCurrentValue: true)
                } else if let currentText = timelineEntry.currentText {
                    Text("\u{201C}\(currentText)\u{201D}")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textSecondary)
                        .lineLimit(2)
                }

                if let gateReasonExplanation = timelineEntry.gateReasonExplanation {
                    Text(gateReasonExplanation)
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }

                // Skills keep the lighter activity style: date, Saved/Updated,
                // and the gate reason — no quoted phrase per entry.
                if !isSkillCategory, let userPhrase = timelineEntry.userPhrase {
                    Text("\u{201C}\(userPhrase)\u{201D}")
                        .font(.system(size: 10))
                        .italic()
                        .foregroundColor(DS.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, isOldestEntry ? 0 : 10)
        }
        // Lets the gutter line stretch to the full height of the row content.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Header line for a timeline entry: relative date, the Saved/Updated
    /// activity label for skills, and the app name when known.
    private func timelineEntryContextLine(
        _ timelineEntry: MemoryTimelineEntry,
        isSkillCategory: Bool
    ) -> String {
        var contextParts = [timelineEntry.relativeSavedAtLabel()]
        if isSkillCategory {
            contextParts.append(timelineEntry.activityLabel)
        }
        if let appDisplayName = timelineEntry.appDisplayName {
            contextParts.append(appDisplayName)
        }
        return contextParts.joined(separator: " · ")
    }

    private func timelineWasNowLine(
        label: String,
        text: String,
        isCurrentValue: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(DS.Colors.textTertiary)
                // Fixed label column so the Was/Now quotes align vertically.
                .frame(width: 26, alignment: .leading)
                .padding(.top, 1)

            Text("\u{201C}\(text)\u{201D}")
                .font(.system(size: 10))
                .foregroundColor(isCurrentValue ? DS.Colors.textSecondary : DS.Colors.textTertiary)
                .lineLimit(2)
        }
    }

    // MARK: - Memory Receipt ("Why Clicky saved this")

    private func memoryReceiptSection(_ memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why Clicky saved this")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)

            if let latestReceipt = memory.latestReceipt {
                VStack(alignment: .leading, spacing: 4) {
                    if let primaryGateReason = latestReceipt.primaryGateReason {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 10))
                                .foregroundColor(DS.Colors.accent)
                            Text(primaryGateReason.userFacingExplanation)
                                .font(.system(size: 11))
                                .foregroundColor(DS.Colors.textSecondary)
                        }
                    }

                    Text(receiptContextLine(latestReceipt))
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)

                    if let triggerPhrase = latestReceipt.triggerPhrase {
                        Text("\u{201C}\(triggerPhrase)\u{201D}")
                            .font(.system(size: 11))
                            .italic()
                            .foregroundColor(DS.Colors.textSecondary)
                            .lineLimit(3)
                    }
                }
            } else {
                Text("Saved before Clicky started keeping receipts.")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            askClickyWhyButton(memory)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                        .stroke(DS.Colors.borderSubtle.opacity(0.5), lineWidth: 0.8)
                )
        )
    }

    private func askClickyWhyButton(_ memory: Memory) -> some View {
        let isGeneratingForThisMemory = companionManager.memoryReceiptExplanationState
            == .generating(memoryID: memory.id)

        return Button(action: {
            companionManager.explainWhyMemoryWasSaved(memory)
        }) {
            HStack(spacing: 5) {
                if isGeneratingForThisMemory {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "questionmark.bubble")
                        .font(.system(size: 10, weight: .medium))
                }
                Text(isGeneratingForThisMemory ? "Clicky is thinking…" : "Ask Clicky why")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(DS.Colors.textOnAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(DS.Colors.accent.opacity(isHoveringAskClickyWhyButton && !isGeneratingForThisMemory ? 0.85 : 1.0))
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .disabled(isGeneratingForThisMemory)
        .onHover { isHovering in
            isHoveringAskClickyWhyButton = isHovering
        }
        .accessibilityIdentifier("clicky.panel.memories-library.ask-why")
    }

    private func receiptContextLine(_ receipt: MemoryReceipt) -> String {
        var contextParts = [Self.receiptSavedDateFormatter.string(from: receipt.savedAt)]
        if let appDisplayName = TeachingSkill.displayName(forBundleId: receipt.appBundleId) {
            contextParts.append(appDisplayName)
        }
        if receipt.updatedExistingMemory {
            contextParts.append("updated an earlier save")
        }
        return contextParts.joined(separator: " · ")
    }

    private static let receiptSavedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func memoryEditForm(_ memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            editFieldLabel("Title")
            TextField("Title", text: $memoryEdit.title)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textSecondary)
                .padding(8)
                .background(editFieldBackground)

            editFieldLabel("Description")
            TextField("Description", text: $memoryEdit.summary)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textSecondary)
                .padding(8)
                .background(editFieldBackground)

            editFieldLabel("Steps")
            TextEditor(text: $memoryEdit.body)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Colors.textSecondary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
                .padding(8)
                .background(editFieldBackground)

            HStack(spacing: 12) {
                Button(action: {
                    saveEditedMemory(memory)
                }) {
                    Text("Save")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Colors.textOnAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                                .fill(DS.Colors.accent)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityIdentifier("clicky.panel.memories-library.save")

                Button(action: {
                    cancelEditingIfNeeded()
                }) {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
    }

    private var editFieldBackground: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(DS.Colors.borderSubtle.opacity(0.5), lineWidth: 0.8)
            )
    }

    private func editFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(DS.Colors.textTertiary)
    }

    private func beginEditing(_ memory: Memory) {
        memoryEdit = MemoryEdit(from: memory)
        isEditingSelectedMemory = true
    }

    private func cancelEditingIfNeeded() {
        isEditingSelectedMemory = false
    }

    private func saveEditedMemory(_ memory: Memory) {
        var edit = memoryEdit
        edit.bundleIds = memory.bundleIds
        edit.status = memory.status

        companionManager.updateMemory(id: memory.id, category: memory.category, edit: edit)
        isEditingSelectedMemory = false

        if let updatedMemory = companionManager.memories.first(where: { $0.id == memory.id }) {
            selectedMemory = updatedMemory
        }
    }

    private func confirmDeletePendingMemory() {
        guard let memory = memoryPendingDelete else { return }

        if selectedMemory?.id == memory.id {
            companionManager.clearMemoryReceiptExplanation()
            selectedMemory = nil
            isEditingSelectedMemory = false
        }

        companionManager.deleteMemory(id: memory.id, category: memory.category)
        memoryPendingDelete = nil
    }

    private func openInitialMemoryIfNeeded() {
        guard let initialSelectedMemoryID,
              let memory = companionManager.memories.first(where: { $0.id == initialSelectedMemoryID }) else {
            return
        }

        selectedCategoryFilter = MemoriesCategoryFilter(memoryCategory: memory.category)
        selectedMemory = memory
        isEditingSelectedMemory = false
        isTimelineExpanded = false
    }

    private func refreshSelectedMemoryIfNeeded() {
        guard let selectedMemory,
              let refreshedMemory = companionManager.memories.first(where: { $0.id == selectedMemory.id }) else {
            return
        }

        self.selectedMemory = refreshedMemory
    }

    @ViewBuilder
    private func memoryMarkdownBody(_ body: String) -> some View {
        if let attributedBody = try? AttributedString(
            markdown: body,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributedBody)
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else {
            Text(body)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private extension MemoryEdit {
    init(title: String, summary: String, body: String, bundleIds: [String], status: TeachingSkillStatus) {
        self.title = title
        self.summary = summary
        self.body = body
        self.bundleIds = bundleIds
        self.status = status
    }
}
