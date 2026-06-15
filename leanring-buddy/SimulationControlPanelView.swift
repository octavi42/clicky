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
//  Current state: every section is wired to SimulationDemoEngine — demo
//  profile chips, reset, all four feature cards (Skills,
//  Preferences, Routines, Niche Suggestions — scripted runs that play in the
//  separate before/after comparison window), the Ask Clicky quick asks
//  (spoken aloud by the real Clicky overlay from read-only store recall),
//  and an FAQ section for presenter talking points.
//

import SwiftUI

struct SimulationControlPanelView: View {
    @ObservedObject var companionManager: CompanionManager
    @ObservedObject var simulationDemoEngine: SimulationDemoEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                controlPanelHeader
                featureDemoCardsSection
                demoProfilesSection
                askClickyQuickActionsSection
                faqSection
            }
            .padding(DS.Spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.Colors.background)
        .frame(minWidth: 860, minHeight: 600)
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

            HStack(spacing: DS.Spacing.sm) {
                SimulationControlPanelChipButton(
                    title: "Ask",
                    iconSystemName: "mic.fill",
                    iconColor: DS.Colors.accentText,
                    action: {
                        Task {
                            await companionManager.speakSimulationDemoAskResponse(
                                spokenText: "What do you want to hear about this feature?"
                            )
                        }
                    }
                )

                SimulationControlPanelChipButton(
                    title: "Reset",
                    iconSystemName: "arrow.counterclockwise",
                    action: {
                        simulationDemoEngine.resetDemoStateToBaseline()
                    }
                )
            }
        }
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

    /// Run opens the before/after comparison window and plays the scripted
    /// learn-then-reuse Xcode commit arc there.
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
            }

            Text("Ship It, Your Way")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.top, 10)

            Text("Proves Clicky learns the team's house rules for a workflow — conventions no stateless assistant could guess — and reuses them from a one-word ask.")
                .font(.system(size: 11))
                .lineSpacing(2)
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Spacer(minLength: DS.Spacing.lg)

            HStack {
                SimulationControlPanelRunButton(
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

    /// Run opens the before/after comparison window and plays the scripted
    /// "Stop Reading Code Aloud" arc there.
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
            }

            Text("Stop Reading Code Aloud")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.top, 10)

            Text("Proves Clicky learns to STOP doing something annoying — a negative-space preference no assistant defaults to — and applies it next time.")
                .font(.system(size: 11))
                .lineSpacing(2)
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Spacer(minLength: DS.Spacing.lg)

            HStack {
                SimulationControlPanelRunButton(
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

    /// Run opens the before/after comparison window and plays the scripted
    /// "Linear → Xcode" arc there.
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

            Spacer(minLength: DS.Spacing.lg)

            HStack {
                SimulationControlPanelRunButton(
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

    /// Run opens the before/after comparison window and plays the scripted
    /// "Developer + Xcode" arc there.
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

            Spacer(minLength: DS.Spacing.lg)

            HStack {
                SimulationControlPanelRunButton(
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

    // MARK: - FAQ

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionTitle("FAQ")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(simulationControlPanelFAQItems.enumerated()), id: \.element.id) { index, faqItem in
                    if index > 0 {
                        faqRowDivider
                    }

                    SimulationControlPanelFAQRow(faqItem: faqItem)
                }
            }
            .simulationCardSurface()
        }
    }

    private var faqRowDivider: some View {
        Rectangle()
            .fill(DS.Colors.borderSubtle.opacity(0.6))
            .frame(height: 0.5)
            .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Shared Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(DS.Colors.textTertiary)
    }
}

// MARK: - FAQ

private struct SimulationControlPanelFAQItem: Identifiable {
    let id: String
    let question: String
    let answer: String
}

private let simulationControlPanelFAQItems: [SimulationControlPanelFAQItem] = [
    SimulationControlPanelFAQItem(
        id: "what-is-this",
        question: "What is this demo?",
        answer: "A presenter-only cockpit for showing how Clicky becomes a local learning companion. Runs are scripted and deterministic — no live speech, network timing, or macOS permissions required."
    ),
    SimulationControlPanelFAQItem(
        id: "skills",
        question: "What do Skills prove?",
        answer: "Clicky can learn a screen workflow you teach once — house rules no stateless assistant would guess — and reuse it the next time you ask."
    ),
    SimulationControlPanelFAQItem(
        id: "preferences",
        question: "What do Preferences prove?",
        answer: "Clicky can learn how you want answers — including things to stop doing — and apply that style on the next turn."
    ),
    SimulationControlPanelFAQItem(
        id: "routines",
        question: "What do Routines prove?",
        answer: "Clicky notices repeated app transitions in the background and surfaces a lightweight chip when a familiar workflow starts again."
    ),
    SimulationControlPanelFAQItem(
        id: "niche-suggestions",
        question: "What do Niche Suggestions prove?",
        answer: "Before Clicky has learned much about you, it helps you know what to ask — with app-aware prompts matched to your niche."
    ),
    SimulationControlPanelFAQItem(
        id: "profiles",
        question: "What do demo profiles do?",
        answer: "Load a work style — Developer, Creator, Designer, or Student — to pre-seed skills, preferences, routines, and niche so Ask Clicky answers from a realistic learned state."
    ),
    SimulationControlPanelFAQItem(
        id: "reset",
        question: "What does Reset do?",
        answer: "Wipes all demo-learned state back to a blank Clicky: skills, preferences, routines, activity edges, and the loaded profile. Safe to run any time."
    ),
]

private struct SimulationControlPanelFAQRow: View {
    let faqItem: SimulationControlPanelFAQItem

    @State private var isExpanded = false

    private let expandCollapseAnimation = Animation.easeOut(duration: DS.Animation.fast)

    var body: some View {
        Button {
            withAnimation(expandCollapseAnimation) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                    Text(faqItem.question)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Colors.textPrimary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: DS.Spacing.md)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }

                Text(faqItem.answer)
                    .font(.system(size: 11))
                    .lineSpacing(3)
                    .foregroundColor(DS.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, isExpanded ? 8 : 0)
                    .frame(maxHeight: isExpanded ? nil : 0, alignment: .top)
                    .opacity(isExpanded ? 1 : 0)
                    .clipped()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
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
