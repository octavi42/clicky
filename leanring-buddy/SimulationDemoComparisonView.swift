//
//  SimulationDemoComparisonView.swift
//  leanring-buddy
//
//  Before/after comparison screen for feature demo runs, hosted in its own
//  window by SimulationDemoComparisonWindowManager. Pressing Run on a
//  feature card in the cockpit opens this window and plays the demo's
//  scripted conversation into two side-by-side columns:
//
//  - Left column: the "before" session — the user asks before Clicky has
//    learned anything, playing beat by beat.
//  - Right column: stays in a dimmed waiting state until the first session
//    ends, then the informed "after" session plays in it.
//  - A recap strip spanning both columns lands last.
//
//  The view is demo-agnostic: it renders whatever lane beats the engine
//  publishes. Each feature demo (Skills, Preferences, …) only contributes
//  its script and per-lane header copy; future cards (Routines, Niche)
//  reuse it the same way.
//

import SwiftUI

struct SimulationDemoComparisonView: View {
    @ObservedObject var simulationDemoEngine: SimulationDemoEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if simulationDemoEngine.stageDemoTitle != nil {
                comparisonHeaderRow

                Rectangle()
                    .fill(DS.Colors.borderSubtle.opacity(0.5))
                    .frame(height: 0.5)

                comparisonLaneColumns
                    .padding(DS.Spacing.xl)

                if let comparisonRecapText = simulationDemoEngine.comparisonRecapText {
                    StageRecapRow(text: comparisonRecapText)
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.bottom, DS.Spacing.xl)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            } else {
                comparisonIdlePlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DS.Colors.background)
        .frame(minWidth: 1000, minHeight: 620)
        .animation(
            .easeOut(duration: DS.Animation.normal),
            value: simulationDemoEngine.comparisonRecapText
        )
    }

    // MARK: - Header

    private var comparisonHeaderRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(simulationDemoEngine.stageDemoTitle ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Text("Same ask, before and after Clicky has learned · conversation text simulated, memory operations real")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            Spacer()

            // Replay restarts whichever demo currently owns the window —
            // the engine knows which script that is.
            if case .finished = simulationDemoEngine.activeFeatureDemoRunState {
                SimulationControlPanelChipButton(
                    title: "Replay",
                    iconSystemName: "arrow.counterclockwise",
                    action: {
                        simulationDemoEngine.replayActiveFeatureDemo()
                    }
                )
            }
        }
        // Reserve the chip's height even while it's hidden during playback,
        // so the header doesn't jump when the run finishes.
        .frame(minHeight: 31)
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.lg)
    }

    // MARK: - Lane Columns

    /// Column header copy for the demo that owns the window. Each feature
    /// demo frames its before/after contrast differently (skills: a time
    /// jump; preferences: the same moment with vs without the preference).
    private var laneHeaderCopy: (
        firstEyebrow: String, firstSubtitle: String,
        secondEyebrow: String, secondSubtitle: String
    ) {
        switch simulationDemoEngine.activeFeatureDemoKind {
        case .preferences:
            return (
                firstEyebrow: "BEFORE",
                firstSubtitle: "No style preference saved yet",
                secondEyebrow: "AFTER",
                secondSubtitle: "With the saved preference applied"
            )
        case .skills, nil:
            return (
                firstEyebrow: "FIRST TIME",
                firstSubtitle: "Clicky hasn't learned this yet",
                secondEyebrow: "NEXT DAY",
                secondSubtitle: "With the saved skill in memory"
            )
        }
    }

    private var comparisonLaneColumns: some View {
        HStack(alignment: .top, spacing: DS.Spacing.lg) {
            comparisonLaneColumn(
                lane: .firstSession,
                eyebrowLabel: laneHeaderCopy.firstEyebrow,
                subtitle: laneHeaderCopy.firstSubtitle,
                laneBeats: simulationDemoEngine.firstSessionLaneBeats
            )

            comparisonLaneColumn(
                lane: .secondSession,
                eyebrowLabel: laneHeaderCopy.secondEyebrow,
                subtitle: laneHeaderCopy.secondSubtitle,
                laneBeats: simulationDemoEngine.secondSessionLaneBeats
            )
        }
        .frame(maxHeight: .infinity)
    }

    private func comparisonLaneColumn(
        lane: DemoComparisonLane,
        eyebrowLabel: String,
        subtitle: String,
        laneBeats: [DemoStageBeat]
    ) -> some View {
        VStack(spacing: 0) {
            comparisonLaneColumnHeader(
                eyebrowLabel: eyebrowLabel,
                subtitle: subtitle,
                laneBeats: laneBeats
            )

            Rectangle()
                .fill(DS.Colors.borderSubtle.opacity(0.5))
                .frame(height: 0.5)

            if laneBeats.isEmpty && simulationDemoEngine.clickyTypingLane != lane {
                comparisonLaneWaitingPlaceholder(lane: lane)
            } else {
                comparisonLaneConversationScrollView(lane: lane, laneBeats: laneBeats)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simulationCardSurface()
    }

    private func comparisonLaneColumnHeader(
        eyebrowLabel: String,
        subtitle: String,
        laneBeats: [DemoStageBeat]
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrowLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(DS.Colors.textTertiary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textSecondary)
            }

            Spacer()

            if let userTurnCountLabel = userTurnCountLabel(for: laneBeats) {
                Text(userTurnCountLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Colors.accentText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DS.Colors.accent.opacity(0.14))
                    )
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }

    /// Live "asks" counter for a column header, derived from the beats that
    /// have actually played so far. This is what makes the before/after
    /// contrast legible at a glance: "4 asks" on the left vs "1 ask" right.
    private func userTurnCountLabel(for laneBeats: [DemoStageBeat]) -> String? {
        let userTurnCount = laneBeats.filter { stageBeat in
            if case .userSays = stageBeat.beat { return true }
            return false
        }.count

        guard userTurnCount > 0 else { return nil }
        return userTurnCount == 1 ? "1 ask" : "\(userTurnCount) asks"
    }

    private func comparisonLaneConversationScrollView(
        lane: DemoComparisonLane,
        laneBeats: [DemoStageBeat]
    ) -> some View {
        ScrollViewReader { laneScrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    ForEach(laneBeats) { stageBeat in
                        comparisonBeatRow(stageBeat)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if simulationDemoEngine.clickyTypingLane == lane {
                        StageClickyTypingIndicatorRow()
                            .transition(.opacity)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.laneBottomAnchorId(for: lane))
                }
                .padding(DS.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: DS.Animation.normal), value: laneBeats)
                .animation(
                    .easeOut(duration: DS.Animation.fast),
                    value: simulationDemoEngine.clickyTypingLane
                )
            }
            .onChange(of: laneBeats.count) { _, _ in
                withAnimation(.easeOut(duration: DS.Animation.normal)) {
                    laneScrollProxy.scrollTo(Self.laneBottomAnchorId(for: lane), anchor: .bottom)
                }
            }
            .onChange(of: simulationDemoEngine.clickyTypingLane) { _, clickyTypingLane in
                guard clickyTypingLane == lane else { return }
                withAnimation(.easeOut(duration: DS.Animation.normal)) {
                    laneScrollProxy.scrollTo(Self.laneBottomAnchorId(for: lane), anchor: .bottom)
                }
            }
        }
    }

    /// Per-lane anchor id for the invisible row at the end of a column's
    /// conversation, so each column auto-scrolls independently.
    private static func laneBottomAnchorId(for lane: DemoComparisonLane) -> String {
        switch lane {
        case .firstSession:
            return "first-session-lane-bottom-anchor"
        case .secondSession:
            return "second-session-lane-bottom-anchor"
        }
    }

    @ViewBuilder
    private func comparisonBeatRow(_ stageBeat: DemoStageBeat) -> some View {
        switch stageBeat.beat {
        case .userSays(let text):
            StageUserSpeechBubbleRow(text: text)
        case .clickyResponds(let text, let matchedSkillBadge):
            StageClickyResponseBubbleRow(text: text, matchedSkillBadge: matchedSkillBadge)
        case .systemEvent(let iconSystemName, let label, let detail):
            StageSystemEventRow(iconSystemName: iconSystemName, label: label, detail: detail)
        }
    }

    // MARK: - Placeholders

    /// Dimmed column body shown before any beat has played in the lane. The
    /// right column sits here for the whole first session — that visible
    /// waiting is what sells the time jump when it wakes up.
    private func comparisonLaneWaitingPlaceholder(lane: DemoComparisonLane) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: lane == .secondSession ? "moon.zzz" : "ellipsis")
                .font(.system(size: 20))
                .foregroundColor(DS.Colors.textTertiary.opacity(0.5))

            Text(lane == .secondSession ? "Plays after the first session" : "Starting…")
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textTertiary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Full-window state when no run owns the comparison yet (e.g. the
    /// window stayed open across a cockpit Reset, which clears playback).
    private var comparisonIdlePlaceholder: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 24))
                .foregroundColor(DS.Colors.textTertiary.opacity(0.6))

            Text("Run a feature demo from the cockpit to play it here")
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Conversation Rows

/// Right-aligned bubble for what the user "says" in a demo script, styled
/// like a sent chat message.
private struct StageUserSpeechBubbleRow: View {
    let text: String

    var body: some View {
        HStack {
            // Keeps user bubbles from spanning the full column width so the
            // left/right conversation shape stays readable from a distance.
            Spacer(minLength: 60)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineSpacing(3)
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                        .fill(DS.Colors.helpChatUserBubble)
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Left-aligned Clicky bubble with the blue cursor avatar. When the engine
/// proves a saved skill informed the answer, a "Matched: …" badge renders
/// under the bubble.
private struct StageClickyResponseBubbleRow: View {
    let text: String
    let matchedSkillBadge: String?

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            StageClickyAvatar()

            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                            .fill(DS.Colors.surface3)
                    )
                    .fixedSize(horizontal: false, vertical: true)

                if let matchedSkillBadge {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9, weight: .semibold))

                        Text(matchedSkillBadge)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(DS.Colors.accentText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DS.Colors.accent.opacity(0.14))
                    )
                }
            }

            Spacer(minLength: 60)
        }
    }
}

/// Small stand-in for the blue Clicky cursor, shown next to its bubbles.
private struct StageClickyAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(DS.Colors.overlayCursorBlue.opacity(0.18))

            Image(systemName: "location.north.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(DS.Colors.overlayCursorBlue)
                .rotationEffect(.degrees(-35))
        }
        .frame(width: 24, height: 24)
    }
}

/// Clicky-side bubble with three pulsing dots, shown while the engine
/// "thinks" before each Clicky response lands.
private struct StageClickyTypingIndicatorRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            StageClickyAvatar()

            StageTypingIndicatorDots()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                        .fill(DS.Colors.surface3)
                )

            Spacer()
        }
    }
}

private struct StageTypingIndicatorDots: View {
    /// Flipped once on appear; each dot animates toward the raised phase on
    /// a staggered delay with auto-reverse, producing the wave effect.
    @State private var dotsAreInRaisedPhase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { dotIndex in
                Circle()
                    .fill(DS.Colors.textSecondary)
                    .frame(width: 5, height: 5)
                    .opacity(dotsAreInRaisedPhase ? 0.9 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(dotIndex) * 0.15),
                        value: dotsAreInRaisedPhase
                    )
            }
        }
        .onAppear {
            dotsAreInRaisedPhase = true
        }
    }
}

/// Centered pill marking a real engine event (skill saved, matcher result),
/// with an optional quieter detail line underneath.
private struct StageSystemEventRow: View {
    let iconSystemName: String
    let label: String
    let detail: String?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: iconSystemName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Colors.accentText)

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(DS.Colors.surface2)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
            )

            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

/// Emphasized full-width strip closing a demo run with its headline metric.
/// Spans both comparison columns.
private struct StageRecapRow: View {
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Colors.accentText)

            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .fill(DS.Colors.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .stroke(DS.Colors.accent.opacity(0.35), lineWidth: 0.5)
        )
    }
}
