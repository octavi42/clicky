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
//  Current state: the demo state strip, demo profile chips, and reset are
//  wired to SimulationDemoEngine. The feature demo cards, Ask Clicky quick
//  actions, and proof panel still render placeholder content until the rest
//  of the demo engine lands.
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

    /// Static descriptors for the four feature demo cards. Run actions and
    /// live status/proof values get wired in when the demo engine lands.
    private static let featureDemoCardPlaceholders: [FeatureDemoCardPlaceholder] = [
        FeatureDemoCardPlaceholder(
            categoryLabel: "Skills",
            scenarioTitle: "Xcode Commit Flow",
            iconSystemName: "graduationcap.fill",
            explanation: "Proves Clicky learns a successful screen workflow and reuses it the next time the user asks.",
            proofFieldLabels: [
                "Skill saved",
                "Skill matched",
                "Prompt included teaching skills",
                "Turns to success",
            ]
        ),
        FeatureDemoCardPlaceholder(
            categoryLabel: "Preferences",
            scenarioTitle: "Short Answers + Shortcuts",
            iconSystemName: "slider.horizontal.3",
            explanation: "Proves Clicky learns how the user wants to be taught and answers in that style.",
            proofFieldLabels: [
                "Preference saved",
                "Answer style applied",
            ]
        ),
        FeatureDemoCardPlaceholder(
            categoryLabel: "Routines",
            scenarioTitle: "Linear → Xcode",
            iconSystemName: "arrow.triangle.2.circlepath",
            explanation: "Proves Clicky notices repeated app transitions and surfaces a lightweight routine chip.",
            proofFieldLabels: [
                "Activity edges seeded",
                "Routine chip shown",
            ]
        ),
        FeatureDemoCardPlaceholder(
            categoryLabel: "Niche Suggestions",
            scenarioTitle: "Developer + Xcode",
            iconSystemName: "lightbulb.fill",
            explanation: "Proves Clicky helps users know what to ask before it has learned much about them.",
            proofFieldLabels: [
                "App-aware suggestions shown",
            ]
        ),
    ]

    private var featureDemoCardsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("FEATURE DEMOS")

            VStack(spacing: DS.Spacing.md) {
                featureDemoCardRow(
                    Self.featureDemoCardPlaceholders[0],
                    Self.featureDemoCardPlaceholders[1]
                )
                featureDemoCardRow(
                    Self.featureDemoCardPlaceholders[2],
                    Self.featureDemoCardPlaceholders[3]
                )
            }
        }
    }

    /// Lays out two cards side by side at equal height. The fixedSize +
    /// maxHeight pattern stretches the shorter card to match the taller one,
    /// so Run buttons in the same row always sit on the same baseline.
    private func featureDemoCardRow(
        _ leadingFeatureDemoCardPlaceholder: FeatureDemoCardPlaceholder,
        _ trailingFeatureDemoCardPlaceholder: FeatureDemoCardPlaceholder
    ) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            featureDemoCard(leadingFeatureDemoCardPlaceholder)
                .frame(maxHeight: .infinity)
            featureDemoCard(trailingFeatureDemoCardPlaceholder)
                .frame(maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func featureDemoCard(_ featureDemoCardPlaceholder: FeatureDemoCardPlaceholder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: featureDemoCardPlaceholder.iconSystemName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.accentText)

                Text(featureDemoCardPlaceholder.categoryLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(DS.Colors.textTertiary)

                Spacer()

                statusIndicator(text: "Not run")
            }

            Text(featureDemoCardPlaceholder.scenarioTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.top, 10)

            Text(featureDemoCardPlaceholder.explanation)
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
                ForEach(featureDemoCardPlaceholder.proofFieldLabels, id: \.self) { proofFieldLabel in
                    HStack(alignment: .firstTextBaseline) {
                        Text(proofFieldLabel)
                            .font(.system(size: 11))
                            .foregroundColor(DS.Colors.textTertiary)

                        Spacer(minLength: DS.Spacing.md)

                        Text("—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(DS.Colors.textSecondary)
                    }
                }
            }
            .padding(.top, DS.Spacing.md)

            Spacer(minLength: DS.Spacing.lg)

            HStack {
                SimulationControlPanelRunButton(action: {
                    // Demo run action is not wired yet — skeleton placeholder.
                })

                Spacer()
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .simulationCardSurface()
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

    private static let askClickyQuickActionPrompts = [
        "What did you learn about me?",
        "Help me commit in Xcode again",
        "What should I do next in this app?",
    ]

    private var askClickyQuickActionsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("ASK CLICKY")

            HStack(spacing: DS.Spacing.sm) {
                ForEach(Self.askClickyQuickActionPrompts, id: \.self) { askClickyQuickActionPrompt in
                    SimulationControlPanelChipButton(
                        title: "\u{201C}\(askClickyQuickActionPrompt)\u{201D}",
                        iconSystemName: "mic.fill",
                        iconColor: DS.Colors.accentText,
                        action: {
                            // Simulated ask is not wired yet — skeleton placeholder.
                        }
                    )
                }

                Spacer()
            }
        }
    }

    // MARK: - Proof Panel

    private static let proofPanelRowLabels = [
        "Last memory written",
        "Last matched memory",
        "Prompt sections included",
        "Before / after metrics",
    ]

    private var proofPanelSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("PROOF PANEL")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.proofPanelRowLabels.indices, id: \.self) { proofPanelRowIndex in
                    let proofPanelRowLabel = Self.proofPanelRowLabels[proofPanelRowIndex]

                    if proofPanelRowIndex > 0 {
                        Rectangle()
                            .fill(DS.Colors.borderSubtle.opacity(0.6))
                            .frame(height: 0.5)
                            .padding(.horizontal, DS.Spacing.lg)
                    }

                    proofPanelRow(label: proofPanelRowLabel, value: "—")
                }
            }
            .simulationCardSurface()
        }
    }

    private func proofPanelRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(DS.Colors.textTertiary)
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

    /// Dot + label status readout. Stays a quiet tertiary gray while idle;
    /// the dot color is the slot that will carry run/pass state later.
    private func statusIndicator(text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(DS.Colors.textTertiary.opacity(0.7))
                .frame(width: 5, height: 5)

            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }
}

// MARK: - Card Surface

private extension View {
    /// The one shared card treatment for the cockpit: first-elevation fill,
    /// continuous corners, and a hairline border. Keeping every container on
    /// this single recipe is what makes the panel read as aligned and calm.
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
private struct SimulationControlPanelRunButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .semibold))

                Text("Run")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(DS.Colors.textOnAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isHovered ? DS.Colors.accentHover : DS.Colors.accent)
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
}

/// Quiet capsule chip used for every secondary action in the cockpit
/// (reset, profile selection, ask prompts). Hover brightens both the fill
/// and the label so clickability is obvious without a border. Selected
/// chips (the loaded demo profile) flip to a solid accent fill.
private struct SimulationControlPanelChipButton: View {
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

// MARK: - Feature Demo Card Model

/// Static descriptor for one feature demo card in the skeleton UI.
private struct FeatureDemoCardPlaceholder: Identifiable {
    /// Eyebrow label naming the memory feature this card demos (e.g. "Skills").
    let categoryLabel: String
    /// The concrete demo scenario shown as the card title (e.g. "Xcode Commit Flow").
    let scenarioTitle: String
    let iconSystemName: String
    /// One-sentence summary of what the scenario proves, rendered inline
    /// under the title. Purely informational — never mutates demo state.
    let explanation: String
    /// Proof readouts that will display live values once the demo engine lands.
    let proofFieldLabels: [String]

    var id: String { categoryLabel + scenarioTitle }
}
