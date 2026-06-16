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
//
//  The view is demo-agnostic: it renders whatever lane beats the engine
//  publishes. Each feature demo (Skills, Preferences, Routines, Niche
//  Suggestions) only contributes its script and per-lane header copy.
//

import SwiftUI

struct SimulationDemoComparisonView: View {
    @ObservedObject var simulationDemoEngine: SimulationDemoEngine

    var body: some View {
        Group {
            if simulationDemoEngine.stageDemoTitle != nil {
                comparisonLaneColumns
                    .padding(DS.Spacing.xl)
            } else {
                comparisonIdlePlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DS.Colors.background)
        .frame(minWidth: 1000, minHeight: 620)
    }

    // MARK: - Lane Columns

    /// Column header copy for the demo that owns the window. Each feature
    /// demo frames its before/after contrast differently (skills: a time
    /// jump; preferences: the same moment with vs without the preference;
    /// routines: days of quiet observation vs the day the pattern qualifies).
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
        case .routines:
            return (
                firstEyebrow: "EARLIER THIS WEEK",
                firstSubtitle: "Clicky quietly notices repeated switches",
                secondEyebrow: "TODAY",
                secondSubtitle: "The pattern clears the recurrence bar"
            )
        case .nicheSuggestions:
            return (
                firstEyebrow: "NO NICHE PICKED",
                firstSubtitle: "Clicky doesn't know what to suggest yet",
                secondEyebrow: "DEVELOPER + XCODE",
                secondSubtitle: "App-aware suggestions from the real mapping"
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
                        comparisonBeatRow(
                            stageBeat,
                            shouldAnimateScribbleReveal: shouldAnimateScribbleReveal(
                                for: stageBeat,
                                in: laneBeats
                            ),
                            onScribbleRevealProgress: {
                                laneScrollProxy.scrollTo(
                                    Self.laneBottomAnchorId(for: lane),
                                    anchor: .bottom
                                )
                            }
                        )
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

    /// Only the newest Clicky bubble in a lane scribbles in; user messages and
    /// earlier agent bubbles snap to full text immediately.
    private func shouldAnimateScribbleReveal(
        for stageBeat: DemoStageBeat,
        in laneBeats: [DemoStageBeat]
    ) -> Bool {
        guard stageBeat.id == laneBeats.last?.id else { return false }
        if case .clickyResponds = stageBeat.beat { return true }
        return false
    }

    @ViewBuilder
    private func comparisonBeatRow(
        _ stageBeat: DemoStageBeat,
        shouldAnimateScribbleReveal: Bool,
        onScribbleRevealProgress: @escaping () -> Void
    ) -> some View {
        switch stageBeat.beat {
        case .userSays(let text):
            StageUserSpeechBubbleRow(text: text)
        case .clickyResponds(let text, _):
            StageClickyResponseBubbleRow(
                text: text,
                shouldAnimateScribbleReveal: shouldAnimateScribbleReveal,
                onScribbleRevealProgress: onScribbleRevealProgress
            )
        case .demoInsight(let iconSystemName, let label, let detail, let insightBody):
            StageDemoInsightRow(
                iconSystemName: iconSystemName,
                label: label,
                detail: detail,
                insightBody: insightBody
            )
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

/// Reveals chat copy one character at a time — the same scribble rhythm as
/// the cursor overlay's navigation bubble, tuned for demo column width.
private struct StageScribbleText: View {
    let fullText: String
    let shouldAnimateReveal: Bool
    var onRevealProgress: (() -> Void)? = nil
    var onRevealComplete: (() -> Void)? = nil

    @State private var revealedCharacterCount: Int = 0
    @State private var revealTask: Task<Void, Never>?

    private var isRevealComplete: Bool {
        revealedCharacterCount >= fullText.count
    }

    private var displayedText: String {
        String(fullText.prefix(revealedCharacterCount))
    }

    var body: some View {
        Text(displayedText)
            .onAppear {
                resetRevealStateForCurrentMode()
            }
            .onChange(of: fullText) { _, _ in
                resetRevealStateForCurrentMode()
            }
            .onChange(of: shouldAnimateReveal) { _, shouldAnimateReveal in
                if shouldAnimateReveal {
                    startCharacterRevealIfNeeded()
                } else {
                    snapToFullText()
                }
            }
            .onDisappear {
                revealTask?.cancel()
                revealTask = nil
            }
    }

    private func resetRevealStateForCurrentMode() {
        revealTask?.cancel()
        revealedCharacterCount = 0

        if shouldAnimateReveal {
            startCharacterRevealIfNeeded()
        } else {
            snapToFullText()
        }
    }

    private func snapToFullText() {
        revealTask?.cancel()
        revealTask = nil
        revealedCharacterCount = fullText.count
        onRevealComplete?()
    }

    private func startCharacterRevealIfNeeded() {
        guard shouldAnimateReveal, !isRevealComplete else { return }
        guard revealTask == nil else { return }

        let delayPerCharacterNanoseconds = Self.delayPerCharacterNanoseconds(for: fullText)

        revealTask = Task { @MainActor in
            for characterIndex in 0..<fullText.count {
                guard !Task.isCancelled else { return }

                if characterIndex > 0 {
                    try? await Task.sleep(nanoseconds: delayPerCharacterNanoseconds)
                    guard !Task.isCancelled else { return }
                }

                revealedCharacterCount = characterIndex + 1

                if revealedCharacterCount % 4 == 0 || revealedCharacterCount == fullText.count {
                    onRevealProgress?()
                }
            }

            onRevealComplete?()
            revealTask = nil
        }
    }

    /// Keeps short asks snappy and long Clicky answers readable within ~0.8–2.5s.
    private static func delayPerCharacterNanoseconds(for fullText: String) -> UInt64 {
        let characterCount = max(fullText.count, 1)
        let targetRevealDurationSeconds = min(2.5, max(0.8, Double(characterCount) * 0.018))
        let delaySeconds = targetRevealDurationSeconds / Double(characterCount)
        return UInt64(delaySeconds * 1_000_000_000)
    }
}

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

/// Left-aligned Clicky bubble with the blue cursor avatar.
private struct StageClickyResponseBubbleRow: View {
    let text: String
    let shouldAnimateScribbleReveal: Bool
    let onScribbleRevealProgress: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            StageClickyAvatar()

            StageScribbleText(
                fullText: text,
                shouldAnimateReveal: shouldAnimateScribbleReveal,
                onRevealProgress: onScribbleRevealProgress
            )
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

/// Centered insight pill for a memory-pipeline step. Tap to fade in the
/// short detail line and/or a monospace peek at what actually ran.
private struct StageDemoInsightRow: View {
    let iconSystemName: String
    let label: String
    let detail: String?
    let insightBody: String?

    @State private var isExpanded = false

    private let expandFadeAnimation = Animation.easeOut(duration: DS.Animation.normal)

    private var hasExpandableContent: Bool {
        detail != nil || insightBody != nil
    }

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            Button {
                guard hasExpandableContent else { return }
                withAnimation(expandFadeAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: iconSystemName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Colors.accentText)

                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(
                    Capsule(style: .continuous)
                        .fill(DS.Colors.surface2)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerCursor(isEnabled: hasExpandableContent)

            if isExpanded {
                VStack(spacing: DS.Spacing.md) {
                    if let detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundColor(DS.Colors.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Spacing.sm)
                    }

                    if let insightBody {
                        ScrollView {
                            Text(insightBody)
                                .font(.system(size: 10, design: .monospaced))
                                .lineSpacing(3)
                                .foregroundColor(DS.Colors.textPrimary.opacity(0.92))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 160, alignment: .top)
                        .padding(DS.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                                .fill(DS.Colors.surface2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                        )
                    }
                }
                .padding(.top, DS.Spacing.xs)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        .animation(expandFadeAnimation, value: isExpanded)
    }
}
