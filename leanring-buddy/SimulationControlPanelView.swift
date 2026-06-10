//
//  SimulationControlPanelView.swift
//  leanring-buddy
//
//  Presenter-only "Clicky Memory Demo" control panel. Hosted in a dedicated
//  resizable NSWindow managed by SimulationControlPanelWindowManager.
//
//  This is a deterministic demo cockpit for presenting the learning-companion
//  features (skills, preferences, routines, niche suggestions, demo profiles)
//  in a meeting without depending on live speech recognition, network timing,
//  or macOS permissions.
//
//  Current state: every section is wired to SimulationDemoEngine — the demo
//  state strip, demo profile chips, reset, all four feature cards (Skills,
//  Preferences, Routines, Niche Suggestions — scripted runs that play in the
//  separate before/after comparison window), the Ask Clicky quick asks
//  (spoken aloud by the real Clicky overlay from read-only store recall),
//  and the proof panel.
//

import SwiftUI

struct SimulationControlPanelView: View {
    @ObservedObject var companionManager: CompanionManager
    @ObservedObject var simulationDemoEngine: SimulationDemoEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                controlPanelHeader
                demoStateStrip
                featureDemoCardsSection
                demoProfilesSection
                askClickyQuickActionsSection
                proofPanelSection
            }
            .padding(DS.Spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.Colors.background)
        .frame(minWidth: 860, minHeight: 600)
        .onAppear {
            // Counts can drift when memories are created outside the demo
            // engine (e.g. a real voice session), so recompute on open.
            simulationDemoEngine.refreshDemoStateCounts()
        }
    }

    // MARK: - Header

    private var controlPanelHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Clicky Memory Demo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Text("Presenter-only cockpit · all data and metrics are simulated")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            Spacer()

            SimulationControlPanelChipButton(
                title: "Reset",
                iconSystemName: "arrow.counterclockwise",
                action: {
                    simulationDemoEngine.resetDemoStateToBaseline()
                }
            )
        }
    }

    // MARK: - Demo State

    /// The six live demo-state readouts, rendered as one continuous strip so
    /// they read as a single instrument row instead of six separate cards.
    /// Values come straight from the engine's published state.
    private var demoStateStrip: some View {
        HStack(spacing: 0) {
            demoStateColumn(
                label: "Profile",
                value: simulationDemoEngine.loadedDemoProfile?.displayName ?? "None"
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            demoStateColumnDivider

            demoStateColumn(label: "Skills", value: String(simulationDemoEngine.demoSkillCount))
                .frame(maxWidth: .infinity, alignment: .leading)

            demoStateColumnDivider

            demoStateColumn(label: "Preferences", value: String(simulationDemoEngine.demoPreferenceCount))
                .frame(maxWidth: .infinity, alignment: .leading)

            demoStateColumnDivider

            demoStateColumn(label: "Routines", value: String(simulationDemoEngine.demoRoutineMemoryCount))
                .frame(maxWidth: .infinity, alignment: .leading)

            demoStateColumnDivider

            demoStateColumn(
                label: "Simulated app",
                value: simulationDemoEngine.simulatedAppContextDisplayName ?? "—"
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            demoStateColumnDivider

            // Hugs its natural width (the other columns share the rest) so
            // longer engine strings like "Loaded Developer · 14:32:08"
            // never truncate.
            demoStateColumn(label: "Last run", value: simulationDemoEngine.lastRunStatusDescription)
                .fixedSize()
        }
        .padding(.vertical, DS.Spacing.md)
        .simulationCardSurface()
    }

    private func demoStateColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private var demoStateColumnDivider: some View {
        Rectangle()
            .fill(DS.Colors.borderSubtle.opacity(0.6))
            .frame(width: 0.5, height: 26)
    }

    // MARK: - Feature Demo Cards

    /// Lays out the cards two per row at equal height. The fixedSize +
    /// maxHeight pattern stretches the shorter card to match the taller one,
    /// so Run buttons in the same row always sit on the same baseline.
    private var featureDemoCardsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("FEATURE DEMOS")

            VStack(spacing: DS.Spacing.md) {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    skillsFeatureDemoCard
                        .frame(maxHeight: .infinity)
                    preferencesFeatureDemoCard
                        .frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    routinesFeatureDemoCard
                        .frame(maxHeight: .infinity)
                    nicheSuggestionsFeatureDemoCard
                        .frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Skills Card (live)

    /// The one fully wired feature card. Run opens the before/after
    /// comparison window and plays the scripted learn-then-reuse Xcode
    /// commit arc there, driving the real skill store, matcher, and prompt
    /// builder; the card itself stays a compact dashboard whose proof
    /// values stream in as the run advances.
    private var skillsFeatureDemoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.accentText)

                Text("SKILLS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(DS.Colors.textTertiary)

                Spacer()

                demoRunStatusIndicator(for: simulationDemoEngine.skillsDemoRunState)
            }

            Text("Xcode Commit Flow")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.top, 10)

            Text("Proves Clicky learns a successful screen workflow and reuses it the next time the user asks.")
                .font(.system(size: 11))
                .lineSpacing(2)
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Rectangle()
                .fill(DS.Colors.borderSubtle.opacity(0.5))
                .frame(height: 0.5)
                .padding(.top, DS.Spacing.md)

            VStack(spacing: 6) {
                liveProofFieldRow(
                    label: "Skill saved",
                    value: simulationDemoEngine.skillsDemoSavedSkillNameProof
                )
                liveProofFieldRow(
                    label: "Skill matched",
                    value: simulationDemoEngine.skillsDemoSkillMatchedProof
                )
                liveProofFieldRow(
                    label: "Prompt included teaching skills",
                    value: simulationDemoEngine.skillsDemoPromptIncludedProof
                )
                liveProofFieldRow(
                    label: "Turns to success",
                    value: simulationDemoEngine.skillsDemoTurnsToSuccessProof
                )
            }
            .padding(.top, DS.Spacing.md)

            Spacer(minLength: DS.Spacing.lg)

            HStack {
                SimulationControlPanelRunButton(
                    isRunning: simulationDemoEngine.skillsDemoRunState.isRunning,
                    action: {
                        // Surface the comparison window first, then start the
                        // run so the audience sees the conversation from its
                        // opening beat.
                        NotificationCenter.default.post(
                            name: .clickyOpenSimulationDemoComparisonWindow,
                            object: nil
                        )
                        simulationDemoEngine.runSkillsDemo()
                    }
                )

                Spacer()
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .simulationCardSurface()
    }

    // MARK: - Preferences Card (live)

    /// Live Preferences card. Run opens the before/after comparison window
    /// and plays the scripted "Short Answers + Shortcuts" arc there, driving
    /// the real PreferenceSignalDetector, memory store, and prompt builder;
    /// the card stays a compact dashboard whose proof values stream in as
    /// the run advances.
    private var preferencesFeatureDemoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.accentText)

                Text("PREFERENCES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(DS.Colors.textTertiary)

                Spacer()

                demoRunStatusIndicator(for: simulationDemoEngine.preferencesDemoRunState)
            }

            Text("Short Answers + Shortcuts")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.top, 10)

            Text("Proves Clicky learns how the user wants to be taught and answers in that style.")
                .font(.system(size: 11))
                .lineSpacing(2)
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Rectangle()
                .fill(DS.Colors.borderSubtle.opacity(0.5))
                .frame(height: 0.5)
                .padding(.top, DS.Spacing.md)

            VStack(spacing: 6) {
                liveProofFieldRow(
                    label: "Preference signal detected",
                    value: simulationDemoEngine.preferencesDemoSignalDetectedProof
                )
                liveProofFieldRow(
                    label: "Preference saved",
                    value: simulationDemoEngine.preferencesDemoSavedPreferenceTitleProof
                )
                liveProofFieldRow(
                    label: "Prompt included preferences",
                    value: simulationDemoEngine.preferencesDemoPromptIncludedProof
                )
                liveProofFieldRow(
                    label: "Answer length",
                    value: simulationDemoEngine.preferencesDemoAnswerLengthProof
                )
            }
            .padding(.top, DS.Spacing.md)

            Spacer(minLength: DS.Spacing.lg)

            HStack {
                SimulationControlPanelRunButton(
                    isRunning: simulationDemoEngine.preferencesDemoRunState.isRunning,
                    action: {
                        // Surface the comparison window first, then start the
                        // run so the audience sees the conversation from its
                        // opening beat.
                        NotificationCenter.default.post(
                            name: .clickyOpenSimulationDemoComparisonWindow,
                            object: nil
                        )
                        simulationDemoEngine.runPreferencesDemo()
                    }
                )

                Spacer()
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .simulationCardSurface()
    }

    // MARK: - Routines Card (live)

    /// Live Routines card. Run opens the before/after comparison window and
    /// plays the scripted "Linear → Xcode" arc there, driving the real
    /// ActivityStore writes and RoutineDetector recurrence rules; the card
    /// stays a compact dashboard whose proof values stream in as the run
    /// advances.
    private var routinesFeatureDemoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.accentText)

                Text("ROUTINES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(DS.Colors.textTertiary)

                Spacer()

                demoRunStatusIndicator(for: simulationDemoEngine.routinesDemoRunState)
            }

            Text("Linear → Xcode")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.top, 10)

            Text("Proves Clicky notices repeated app transitions and surfaces a lightweight routine chip.")
                .font(.system(size: 11))
                .lineSpacing(2)
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Rectangle()
                .fill(DS.Colors.borderSubtle.opacity(0.5))
                .frame(height: 0.5)
                .padding(.top, DS.Spacing.md)

            VStack(spacing: 6) {
                liveProofFieldRow(
                    label: "Activity edges seeded",
                    value: simulationDemoEngine.routinesDemoEdgesSeededProof
                )
                liveProofFieldRow(
                    label: "Routine chip shown",
                    value: simulationDemoEngine.routinesDemoChipShownProof
                )
                liveProofFieldRow(
                    label: "Chip label",
                    value: simulationDemoEngine.routinesDemoChipLabelProof
                )
                liveProofFieldRow(
                    label: "Answer style",
                    value: simulationDemoEngine.routinesDemoAnswerStyleProof
                )
            }
            .padding(.top, DS.Spacing.md)

            Spacer(minLength: DS.Spacing.lg)

            HStack {
                SimulationControlPanelRunButton(
                    isRunning: simulationDemoEngine.routinesDemoRunState.isRunning,
                    action: {
                        // Surface the comparison window first, then start the
                        // run so the audience sees the conversation from its
                        // opening beat.
                        NotificationCenter.default.post(
                            name: .clickyOpenSimulationDemoComparisonWindow,
                            object: nil
                        )
                        simulationDemoEngine.runRoutinesDemo()
                    }
                )

                Spacer()
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .simulationCardSurface()
    }

    // MARK: - Niche Suggestions Card (live)

    /// Live Niche Suggestions card. Run opens the before/after comparison
    /// window and plays the scripted "Developer + Xcode" arc there, driving
    /// the real niche override writes and the real suggestion-snapshot path;
    /// the card stays a compact dashboard whose proof values stream in as
    /// the run advances.
    private var nicheSuggestionsFeatureDemoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.accentText)

                Text("NICHE SUGGESTIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(DS.Colors.textTertiary)

                Spacer()

                demoRunStatusIndicator(for: simulationDemoEngine.nicheSuggestionsDemoRunState)
            }

            Text("Developer + Xcode")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.top, 10)

            Text("Proves Clicky helps users know what to ask before it has learned much about them.")
                .font(.system(size: 11))
                .lineSpacing(2)
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Rectangle()
                .fill(DS.Colors.borderSubtle.opacity(0.5))
                .frame(height: 0.5)
                .padding(.top, DS.Spacing.md)

            VStack(spacing: 6) {
                liveProofFieldRow(
                    label: "Niche picked",
                    value: simulationDemoEngine.nicheSuggestionsDemoNichePickedProof
                )
                liveProofFieldRow(
                    label: "Simulated frontmost app",
                    value: simulationDemoEngine.nicheSuggestionsDemoSimulatedFrontmostAppProof
                )
                liveProofFieldRow(
                    label: "Suggestion mode",
                    value: simulationDemoEngine.nicheSuggestionsDemoSuggestionModeProof
                )
                liveProofFieldRow(
                    label: "App-aware suggestions shown",
                    value: simulationDemoEngine.nicheSuggestionsDemoSuggestionsShownProof
                )
            }
            .padding(.top, DS.Spacing.md)

            Spacer(minLength: DS.Spacing.lg)

            HStack {
                SimulationControlPanelRunButton(
                    isRunning: simulationDemoEngine.nicheSuggestionsDemoRunState.isRunning,
                    action: {
                        // Surface the comparison window first, then start the
                        // run so the audience sees the conversation from its
                        // opening beat.
                        NotificationCenter.default.post(
                            name: .clickyOpenSimulationDemoComparisonWindow,
                            object: nil
                        )
                        simulationDemoEngine.runNicheSuggestionsDemo()
                    }
                )

                Spacer()
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .simulationCardSurface()
    }

    /// Status pill for a live feature card, mapping its engine run state to
    /// the shared indicator styles.
    @ViewBuilder
    private func demoRunStatusIndicator(for featureDemoRunState: FeatureDemoRunState) -> some View {
        switch featureDemoRunState {
        case .notRun:
            statusIndicator(text: "Not run")
        case .running:
            statusIndicator(text: "Running…", dotColor: DS.Colors.warning)
        case .finished(let atTimeDescription):
            statusIndicator(text: "Ran · \(atTimeDescription)", dotColor: DS.Colors.success)
        }
    }

    /// Proof readout row whose value streams in from the engine.
    /// nil renders as a quiet em dash until the run proves the field.
    private func liveProofFieldRow(label: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textTertiary)

            Spacer(minLength: DS.Spacing.md)

            Text(value ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(value == nil ? DS.Colors.textSecondary : DS.Colors.success)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Demo Profiles

    private var demoProfilesSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("PROFILES")

            HStack(spacing: DS.Spacing.sm) {
                ForEach(SimulationDemoProfile.allCases) { demoProfile in
                    let isLoadedProfile = simulationDemoEngine.loadedDemoProfile == demoProfile

                    SimulationControlPanelChipButton(
                        title: demoProfile.displayName,
                        iconSystemName: isLoadedProfile ? "checkmark" : nil,
                        isSelected: isLoadedProfile,
                        action: {
                            simulationDemoEngine.loadDemoProfile(demoProfile)
                        }
                    )
                }

                Spacer()

                // Pinned to the trailing edge so the destructive action stays
                // visually separated from the profile choices.
                SimulationControlPanelChipButton(
                    title: "Clear",
                    isDestructive: true,
                    action: {
                        simulationDemoEngine.clearLoadedDemoProfile()
                    }
                )
            }
        }
    }

    // MARK: - Ask Clicky Quick Actions

    private var askClickyQuickActionsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("ASK CLICKY")

            HStack(spacing: DS.Spacing.sm) {
                ForEach(simulationDemoEngine.askClickyQuickActionsForCurrentProfile()) { askClickyQuickAction in
                    SimulationControlPanelChipButton(
                        title: "\u{201C}\(askClickyQuickAction.promptText)\u{201D}",
                        iconSystemName: "mic.fill",
                        iconColor: DS.Colors.accentText,
                        action: {
                            simulationDemoEngine.runAskClickyQuickAction(askClickyQuickAction)
                        }
                    )
                }

                Spacer()
            }
        }
    }

    // MARK: - Proof Panel

    /// Live evidence readouts shared by every demo card. The engine updates
    /// these as runs complete; reset returns them to em dashes.
    private var proofPanelSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("PROOF PANEL")

            VStack(alignment: .leading, spacing: 0) {
                proofPanelRow(
                    label: "Last memory written",
                    value: simulationDemoEngine.lastMemoryWrittenDescription
                )
                proofPanelRowDivider
                proofPanelRow(
                    label: "Last matched memory",
                    value: simulationDemoEngine.lastMatchedMemoryDescription
                )
                proofPanelRowDivider
                proofPanelRow(
                    label: "Prompt sections included",
                    value: simulationDemoEngine.promptSectionsIncludedDescription
                )
                proofPanelRowDivider
                proofPanelRow(
                    label: "Before / after metrics",
                    value: simulationDemoEngine.beforeAfterMetricDescription
                )
            }
            .simulationCardSurface()
        }
    }

    private var proofPanelRowDivider: some View {
        Rectangle()
            .fill(DS.Colors.borderSubtle.opacity(0.6))
            .frame(height: 0.5)
            .padding(.horizontal, DS.Spacing.lg)
    }

    private func proofPanelRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(value == "—" ? DS.Colors.textTertiary : DS.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, 11)
    }

    // MARK: - Shared Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(DS.Colors.textTertiary)
    }

    /// Dot + label status readout. The dot stays a quiet tertiary gray while
    /// idle and carries run state (amber running, green ran) on live cards.
    private func statusIndicator(text: String, dotColor: Color = DS.Colors.textTertiary.opacity(0.7)) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)

            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }
}

// MARK: - Card Surface

extension View {
    /// The one shared card treatment for the cockpit and the comparison
    /// window: first-elevation fill, continuous corners, and a hairline
    /// border. Keeping every container on this single recipe is what makes
    /// the demo surfaces read as aligned and calm. Internal (not private)
    /// so SimulationDemoComparisonView uses the same recipe.
    func simulationCardSurface() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous)
                    .fill(DS.Colors.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
            )
    }
}

// MARK: - Buttons

/// Small accent capsule used as the single strong call-to-action per card.
/// While its demo is running it goes quiet and ignores clicks so a paced
/// run can't be restarted mid-flight.
private struct SimulationControlPanelRunButton: View {
    var isRunning: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .semibold))
                }

                Text(isRunning ? "Running…" : "Run")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isRunning ? DS.Colors.textTertiary : DS.Colors.textOnAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(runButtonBackgroundColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .pointerCursor(isEnabled: !isRunning)
        .onHover { hovering in
            withAnimation(.easeOut(duration: DS.Animation.fast)) {
                isHovered = hovering
            }
        }
    }

    private var runButtonBackgroundColor: Color {
        if isRunning {
            return DS.Colors.surface3
        }
        return isHovered ? DS.Colors.accentHover : DS.Colors.accent
    }
}

/// Quiet capsule chip used for every secondary action in the cockpit and
/// the comparison window (reset, profile selection, ask prompts, replay).
/// Hover brightens both the fill and the label so clickability is obvious
/// without a border. Selected chips (the loaded demo profile) flip to a
/// solid accent fill. Internal (not private) so SimulationDemoComparisonView
/// shares the exact same chip language.
struct SimulationControlPanelChipButton: View {
    let title: String
    var iconSystemName: String? = nil
    /// Explicit icon tint (e.g. the accent mic on ask prompts). When nil the
    /// icon follows the label color, including its hover brightening.
    var iconColor: Color? = nil
    var isSelected: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let iconSystemName {
                    Image(systemName: iconSystemName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(iconColor ?? titleColor)
                }

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(chipBackgroundColor)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering in
            withAnimation(.easeOut(duration: DS.Animation.fast)) {
                isHovered = hovering
            }
        }
    }

    private var titleColor: Color {
        if isSelected {
            return DS.Colors.textOnAccent
        }
        if isDestructive {
            return DS.Colors.destructiveText
        }
        return isHovered ? DS.Colors.textPrimary : DS.Colors.textSecondary
    }

    private var chipBackgroundColor: Color {
        if isSelected {
            return isHovered ? DS.Colors.accentHover : DS.Colors.accent
        }
        if isDestructive {
            return isHovered ? DS.Colors.destructive.opacity(0.16) : DS.Colors.surface2
        }
        return isHovered ? DS.Colors.surface3 : DS.Colors.surface2
    }
}
