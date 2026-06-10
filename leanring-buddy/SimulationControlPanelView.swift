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
//  Current state: skeleton only. Every section renders static placeholder
//  content clearly labeled as simulated. Demo run/reset/profile actions are
//  intentionally no-ops until the demo engine is wired in.
//

import SwiftUI

struct SimulationControlPanelView: View {
    @ObservedObject var companionManager: CompanionManager
    @ObservedObject var simulationDemoEngine: SimulationDemoEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                controlPanelHeader
                demoStateSection
                featureDemoCardsSection
                demoProfilesSection
                askClickyQuickActionsSection
                proofPanelSection
            }
            .padding(DS.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.Colors.background)
        .frame(minWidth: 860, minHeight: 600)
        .onAppear {
            simulationDemoEngine.refreshDemoStateCounts()
        }
    }

    // MARK: - Header

    private var controlPanelHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clicky Memory Demo")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(DS.Colors.textPrimary)

                Text("Presenter-only cockpit. All data and metrics shown are simulated demo state.")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            Spacer()

            Button(action: {
                simulationDemoEngine.resetDemoStateToBaseline()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Reset Demo")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(DS.Colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                        .fill(DS.Colors.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    // MARK: - Demo State

    private var demoStateSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("DEMO STATE")

            HStack(spacing: DS.Spacing.md) {
                demoStateTile(
                    title: "Profile",
                    value: simulationDemoEngine.loadedDemoProfile?.displayName ?? "None loaded"
                )
                demoStateTile(title: "Skills", value: String(simulationDemoEngine.demoSkillCount))
                demoStateTile(title: "Preferences", value: String(simulationDemoEngine.demoPreferenceCount))
                demoStateTile(title: "Routines", value: String(simulationDemoEngine.demoRoutineMemoryCount))
                demoStateTile(
                    title: "Simulated App",
                    value: simulationDemoEngine.simulatedAppContextDisplayName ?? "—"
                )
                demoStateTile(title: "Last Run", value: simulationDemoEngine.lastRunStatusDescription)
            }
        }
    }

    private func demoStateTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(DS.Colors.textTertiary)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(DS.Colors.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Feature Demo Cards

    /// Static descriptors for the four feature demo cards. Run actions and
    /// live status/proof values get wired in when the demo engine lands.
    private static let featureDemoCardPlaceholders: [FeatureDemoCardPlaceholder] = [
        FeatureDemoCardPlaceholder(
            title: "Skills: Xcode Commit Flow",
            iconSystemName: "graduationcap.fill",
            explanation: "Proves Clicky learns a successful screen workflow and reuses it the next time the user asks.",
            proofFieldLabels: [
                "Skill saved: —",
                "Skill matched: —",
                "Prompt included teaching skills: —",
                "Turns to success: —",
            ]
        ),
        FeatureDemoCardPlaceholder(
            title: "Preferences: Short Answers + Shortcuts",
            iconSystemName: "slider.horizontal.3",
            explanation: "Proves Clicky learns how the user wants to be taught and answers in that style.",
            proofFieldLabels: [
                "Preference saved: —",
                "Answer style applied: —",
            ]
        ),
        FeatureDemoCardPlaceholder(
            title: "Routines: Linear → Xcode",
            iconSystemName: "arrow.triangle.2.circlepath",
            explanation: "Proves Clicky notices repeated app transitions and surfaces a lightweight routine chip.",
            proofFieldLabels: [
                "Activity edges seeded: —",
                "Routine chip shown: —",
            ]
        ),
        FeatureDemoCardPlaceholder(
            title: "Niche Suggestions: Developer + Xcode",
            iconSystemName: "lightbulb.fill",
            explanation: "Proves Clicky helps users know what to ask before it has learned much about them.",
            proofFieldLabels: [
                "App-aware suggestions shown: —",
            ]
        ),
    ]

    private var featureDemoCardsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("FEATURE DEMOS")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: DS.Spacing.md),
                    GridItem(.flexible(), spacing: DS.Spacing.md),
                ],
                alignment: .leading,
                spacing: DS.Spacing.md
            ) {
                ForEach(Self.featureDemoCardPlaceholders) { featureDemoCardPlaceholder in
                    featureDemoCard(featureDemoCardPlaceholder)
                }
            }
        }
    }

    private func featureDemoCard(_ featureDemoCardPlaceholder: FeatureDemoCardPlaceholder) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: featureDemoCardPlaceholder.iconSystemName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Colors.accentText)

                Text(featureDemoCardPlaceholder.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                statusBadge(text: "Not run")
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(featureDemoCardPlaceholder.proofFieldLabels, id: \.self) { proofFieldLabel in
                    Text(proofFieldLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button(action: {
                    // Demo run action is not wired yet — skeleton placeholder.
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Run")
                            .font(.system(size: 11, weight: .semibold))
                    }
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

                // The "?" action only explains what the scenario proves.
                // It must never mutate demo state.
                Button(action: {
                    // Explanation popover is not wired yet — skeleton placeholder.
                }) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Colors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                                .fill(DS.Colors.surface3)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help(featureDemoCardPlaceholder.explanation)

                Spacer()
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .fill(DS.Colors.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Demo Profiles

    private var demoProfilesSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("DEMO PROFILES / WORK STYLES")

            HStack(spacing: DS.Spacing.sm) {
                ForEach(SimulationDemoProfile.allCases) { demoProfile in
                    demoProfileChip(demoProfile)
                }

                clearProfileChip

                Spacer()
            }
        }
    }

    private func demoProfileChip(_ demoProfile: SimulationDemoProfile) -> some View {
        let isLoadedProfile = simulationDemoEngine.loadedDemoProfile == demoProfile

        return Button(action: {
            simulationDemoEngine.loadDemoProfile(demoProfile)
        }) {
            HStack(spacing: 5) {
                if isLoadedProfile {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }

                Text(demoProfile.displayName)
                    .font(.system(size: 12, weight: isLoadedProfile ? .semibold : .medium))
            }
            .foregroundColor(isLoadedProfile ? DS.Colors.textOnAccent : DS.Colors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isLoadedProfile ? DS.Colors.accent : DS.Colors.surface2)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isLoadedProfile ? Color.clear : DS.Colors.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var clearProfileChip: some View {
        Button(action: {
            simulationDemoEngine.clearLoadedDemoProfile()
        }) {
            Text("Clear Profile")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.destructiveText)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(DS.Colors.surface2)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
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
                    Button(action: {
                        // Simulated ask is not wired yet — skeleton placeholder.
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DS.Colors.accentText)

                            Text("\u{201C}\(askClickyQuickActionPrompt)\u{201D}")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                                .fill(DS.Colors.surface1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }

                Spacer()
            }
        }
    }

    // MARK: - Proof Panel

    private var proofPanelSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("PROOF PANEL")

            VStack(alignment: .leading, spacing: 0) {
                proofPanelRow(label: "Last memory written", value: "—")
                proofPanelDivider
                proofPanelRow(label: "Last matched memory", value: "—")
                proofPanelDivider
                proofPanelRow(label: "Prompt sections included", value: "—")
                proofPanelDivider
                proofPanelRow(label: "Before / after (simulated demo metrics)", value: "—")
            }
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                    .fill(DS.Colors.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
            )
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
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, 10)
    }

    private var proofPanelDivider: some View {
        Divider()
            .background(DS.Colors.borderSubtle)
            .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - Shared Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(DS.Colors.textTertiary)
    }

    private func statusBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(DS.Colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(DS.Colors.surface3)
            )
    }
}

/// Static descriptor for one feature demo card in the skeleton UI.
private struct FeatureDemoCardPlaceholder: Identifiable {
    let title: String
    let iconSystemName: String
    /// Shown by the "?" action. Explains what the scenario proves and never
    /// mutates demo state.
    let explanation: String
    let proofFieldLabels: [String]

    var id: String { title }
}
