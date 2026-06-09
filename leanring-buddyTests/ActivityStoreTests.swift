//
//  ActivityStoreTests.swift
//  leanring-buddyTests
//

import Foundation
import Testing
@testable import leanring_buddy

@Suite(.serialized)
struct ActivityStoreTests {
    private func makeTemporaryHome() throws -> URL {
        let temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicky-activity-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
        return temporaryHome
    }

    @Test func recordTransitionIncrementsCount() throws {
        let temporaryHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: temporaryHome) }

        try ClickyTestHomeIsolation.withIsolatedHome(temporaryHome) {
            let activityFileURL = temporaryHome.appendingPathComponent("activity.json")
            let store = ActivityStore(activityFileURL: activityFileURL)
            let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

            store.recordTransition(from: "com.slack.Slack", to: "com.figma.Desktop", at: timestamp)
            store.recordTransition(from: "com.slack.Slack", to: "com.figma.Desktop", at: timestamp)

            let edges = store.allEdges(now: timestamp)
            #expect(edges.count == 1)
            #expect(edges[0].count == 2)
            #expect(edges[0].fromBundleId == "com.slack.Slack")
            #expect(edges[0].toBundleId == "com.figma.Desktop")
        }
    }

    @Test func sameDayTransitionsCountAsOneDistinctDay() throws {
        let temporaryHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: temporaryHome) }

        try ClickyTestHomeIsolation.withIsolatedHome(temporaryHome) {
            let activityFileURL = temporaryHome.appendingPathComponent("activity.json")
            let store = ActivityStore(activityFileURL: activityFileURL)
            let morning = Date(timeIntervalSince1970: 1_700_000_000)
            let afternoon = morning.addingTimeInterval(6 * 60 * 60)

            store.recordTransition(from: "com.slack.Slack", to: "com.figma.Desktop", at: morning)
            store.recordTransition(from: "com.slack.Slack", to: "com.figma.Desktop", at: afternoon)

            let edges = store.allEdges(now: afternoon)
            #expect(edges[0].count == 2)
            #expect(edges[0].distinctDayCount == 1)
        }
    }

    @Test func differentDaysIncreaseDistinctDayCount() throws {
        let temporaryHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: temporaryHome) }

        try ClickyTestHomeIsolation.withIsolatedHome(temporaryHome) {
            let activityFileURL = temporaryHome.appendingPathComponent("activity.json")
            let store = ActivityStore(activityFileURL: activityFileURL)
            let dayOne = Date(timeIntervalSince1970: 1_700_000_000)
            let dayTwo = dayOne.addingTimeInterval(24 * 60 * 60)

            store.recordTransition(from: "com.slack.Slack", to: "com.figma.Desktop", at: dayOne)
            store.recordTransition(from: "com.slack.Slack", to: "com.figma.Desktop", at: dayTwo)

            let edges = store.allEdges(now: dayTwo)
            #expect(edges[0].distinctDayCount == 2)
        }
    }

    @Test func pruneDropsEdgesOlderThanRollingWindow() throws {
        let temporaryHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: temporaryHome) }

        try ClickyTestHomeIsolation.withIsolatedHome(temporaryHome) {
            let activityFileURL = temporaryHome.appendingPathComponent("activity.json")
            let store = ActivityStore(activityFileURL: activityFileURL)
            let oldTimestamp = Date(timeIntervalSince1970: 1_600_000_000)
            let now = oldTimestamp.addingTimeInterval(TimeInterval((ActivityStore.rollingWindowDays + 1) * 24 * 60 * 60))

            store.recordTransition(from: "com.slack.Slack", to: "com.figma.Desktop", at: oldTimestamp)

            let edges = store.allEdges(now: now)
            #expect(edges.isEmpty)
        }
    }

    @Test func suppressionPersistsAcrossReload() throws {
        let temporaryHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: temporaryHome) }

        try ClickyTestHomeIsolation.withIsolatedHome(temporaryHome) {
            let activityFileURL = temporaryHome.appendingPathComponent("activity.json")
            let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
            let edgeId = TransitionEdge.edgeIdentifier(fromBundleId: "com.slack.Slack", toBundleId: "com.figma.Desktop")

            let store = ActivityStore(activityFileURL: activityFileURL)
            store.recordTransition(from: "com.slack.Slack", to: "com.figma.Desktop", at: timestamp)
            store.suppress(edgeId: edgeId)

            let reloadedStore = ActivityStore(activityFileURL: activityFileURL)
            #expect(reloadedStore.isSuppressed(edgeId: edgeId))
            #expect(reloadedStore.suppressedEdgeIdentifiers().contains(edgeId))
        }
    }
}

@Suite(.serialized)
struct RoutineDetectorTests {
    @Test func requiresMinimumDistinctDaysAndStrength() {
        let edges = [
            TransitionEdge(
                fromBundleId: "com.slack.Slack",
                toBundleId: "com.figma.Desktop",
                count: 5,
                occurrenceDays: ["2026-06-01"],
                firstSeen: Date(),
                lastSeen: Date()
            ),
            TransitionEdge(
                fromBundleId: "com.slack.Slack",
                toBundleId: "com.apple.mail",
                count: 6,
                occurrenceDays: ["2026-06-01", "2026-06-02"],
                firstSeen: Date(),
                lastSeen: Date()
            )
        ]

        let suggestions = RoutineDetector.suggestions(from: edges, suppressedEdgeIds: [])
        #expect(suggestions.count == 1)
        #expect(suggestions[0].toBundleId == "com.apple.mail")
    }

    @Test func respectsSuppressionAndSessionDismissal() {
        let edgeId = TransitionEdge.edgeIdentifier(fromBundleId: "com.slack.Slack", toBundleId: "com.figma.Desktop")
        let edges = [
            TransitionEdge(
                fromBundleId: "com.slack.Slack",
                toBundleId: "com.figma.Desktop",
                count: 6,
                occurrenceDays: ["2026-06-01", "2026-06-02"],
                firstSeen: Date(),
                lastSeen: Date()
            )
        ]

        let suppressed = RoutineDetector.suggestions(from: edges, suppressedEdgeIds: [edgeId])
        #expect(suppressed.isEmpty)

        let sessionDismissed = RoutineDetector.suggestions(
            from: edges,
            suppressedEdgeIds: [],
            sessionDismissedEdgeIds: [edgeId]
        )
        #expect(sessionDismissed.isEmpty)
    }

    @Test func collapsesReverseEdgeIntoSinglePairChip() {
        // A back-and-forth workflow: both directions qualify, but only the
        // stronger direction (Slack->Figma) should surface as a chip.
        let edges = [
            TransitionEdge(
                fromBundleId: "com.slack.Slack",
                toBundleId: "com.figma.Desktop",
                count: 9,
                occurrenceDays: ["2026-06-01", "2026-06-02", "2026-06-03"],
                firstSeen: Date(),
                lastSeen: Date()
            ),
            TransitionEdge(
                fromBundleId: "com.figma.Desktop",
                toBundleId: "com.slack.Slack",
                count: 8,
                occurrenceDays: ["2026-06-01", "2026-06-02"],
                firstSeen: Date(),
                lastSeen: Date()
            )
        ]

        let suggestions = RoutineDetector.suggestions(from: edges, suppressedEdgeIds: [])
        #expect(suggestions.count == 1)
        #expect(suggestions[0].fromBundleId == "com.slack.Slack")
        #expect(suggestions[0].toBundleId == "com.figma.Desktop")
    }

    @Test func strengthDenominatorIgnoresImmatureEdges() {
        // A recurring Slack->Figma (3 days) alongside many one-day, one-off
        // destinations should still surface: the immature edges must not dilute
        // the strength denominator below the threshold.
        var edges = [
            TransitionEdge(
                fromBundleId: "com.slack.Slack",
                toBundleId: "com.figma.Desktop",
                count: 3,
                occurrenceDays: ["2026-06-01", "2026-06-02", "2026-06-03"],
                firstSeen: Date(),
                lastSeen: Date()
            )
        ]
        for oneOffIndex in 0..<10 {
            edges.append(
                TransitionEdge(
                    fromBundleId: "com.slack.Slack",
                    toBundleId: "com.example.oneoff\(oneOffIndex)",
                    count: 1,
                    occurrenceDays: ["2026-06-01"],
                    firstSeen: Date(),
                    lastSeen: Date()
                )
            )
        }

        let suggestions = RoutineDetector.suggestions(from: edges, suppressedEdgeIds: [])
        #expect(suggestions.count == 1)
        #expect(suggestions[0].toBundleId == "com.figma.Desktop")
    }

    @Test func capsSuggestionCountAtTwo() {
        // Strength = count / totalOutgoingFromSource. With totals 10+8+2=20,
        // Figma (0.50) and Mail (0.40) pass the 0.4 bar; Cursor (0.10) does not.
        let edges = [
            TransitionEdge(
                fromBundleId: "com.slack.Slack",
                toBundleId: "com.figma.Desktop",
                count: 10,
                occurrenceDays: ["2026-06-01", "2026-06-02"],
                firstSeen: Date(),
                lastSeen: Date()
            ),
            TransitionEdge(
                fromBundleId: "com.slack.Slack",
                toBundleId: "com.apple.mail",
                count: 8,
                occurrenceDays: ["2026-06-01", "2026-06-02"],
                firstSeen: Date(),
                lastSeen: Date()
            ),
            TransitionEdge(
                fromBundleId: "com.slack.Slack",
                toBundleId: "com.todesktop.230313mzl4w4u92",
                count: 2,
                occurrenceDays: ["2026-06-01", "2026-06-02"],
                firstSeen: Date(),
                lastSeen: Date()
            )
        ]

        let suggestions = RoutineDetector.suggestions(from: edges, suppressedEdgeIds: [])
        #expect(suggestions.count == 2)
    }
}
