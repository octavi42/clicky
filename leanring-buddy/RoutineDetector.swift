//
//  RoutineDetector.swift
//  leanring-buddy
//
//  Deterministic recurrence detection over transition edges (no LLM).
//

import AppKit
import Foundation

struct RoutineSuggestion: Identifiable, Equatable, Codable {
    let id: String
    let fromBundleId: String
    let toBundleId: String
    let label: String
}

enum RoutineDetector {
    static let minimumDistinctDays = 2
    static let minimumTransitionStrength = 0.4
    static let maximumSuggestionCount = 2
    static let minimumPreviousAppDwellSeconds: TimeInterval = 8

    static func suggestions(
        from edges: [TransitionEdge],
        suppressedEdgeIds: Set<String>,
        sessionDismissedEdgeIds: Set<String> = [],
        now: Date = Date()
    ) -> [RoutineSuggestion] {
        let outgoingTotalsByBundleId = outgoingTransitionTotals(from: edges)

        let rankedEdges = edges
            .filter { edge in
                guard !suppressedEdgeIds.contains(edge.id) else { return false }
                guard !sessionDismissedEdgeIds.contains(edge.id) else { return false }
                guard edge.distinctDayCount >= minimumDistinctDays else { return false }

                let totalOutgoing = outgoingTotalsByBundleId[edge.fromBundleId] ?? 0
                guard totalOutgoing > 0 else { return false }

                let strength = Double(edge.count) / Double(totalOutgoing)
                return strength >= minimumTransitionStrength
            }
            .sorted { lhs, rhs in
                let lhsStrength = transitionStrength(for: lhs, outgoingTotalsByBundleId: outgoingTotalsByBundleId)
                let rhsStrength = transitionStrength(for: rhs, outgoingTotalsByBundleId: outgoingTotalsByBundleId)

                if lhsStrength != rhsStrength {
                    return lhsStrength > rhsStrength
                }

                if lhs.distinctDayCount != rhs.distinctDayCount {
                    return lhs.distinctDayCount > rhs.distinctDayCount
                }

                return lhs.count > rhs.count
            }

        // Collapse a back-and-forth workflow (A->B and B->A both qualifying) into a
        // single chip. `rankedEdges` is already strongest-first, so the first edge
        // we see for an unordered pair is the one we keep.
        var seenAppPairKeys: Set<String> = []
        let deduplicatedEdges = rankedEdges.filter { edge in
            let appPairKey = unorderedAppPairKey(fromBundleId: edge.fromBundleId, toBundleId: edge.toBundleId)
            return seenAppPairKeys.insert(appPairKey).inserted
        }

        return Array(
            deduplicatedEdges
                .prefix(maximumSuggestionCount)
                .map { edge in
                    RoutineSuggestion(
                        id: edge.id,
                        fromBundleId: edge.fromBundleId,
                        toBundleId: edge.toBundleId,
                        label: suggestionLabel(fromBundleId: edge.fromBundleId, toBundleId: edge.toBundleId)
                    )
                }
        )
    }

    private static func unorderedAppPairKey(fromBundleId: String, toBundleId: String) -> String {
        [fromBundleId, toBundleId].sorted().joined(separator: "<->")
    }

    private static func outgoingTransitionTotals(from edges: [TransitionEdge]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for edge in edges {
            totals[edge.fromBundleId, default: 0] += edge.count
        }
        return totals
    }

    private static func transitionStrength(
        for edge: TransitionEdge,
        outgoingTotalsByBundleId: [String: Int]
    ) -> Double {
        let totalOutgoing = outgoingTotalsByBundleId[edge.fromBundleId] ?? 0
        guard totalOutgoing > 0 else { return 0 }
        return Double(edge.count) / Double(totalOutgoing)
    }

    private static func suggestionLabel(fromBundleId: String, toBundleId: String) -> String {
        let fromDisplayName = displayName(for: fromBundleId)
        let toDisplayName = displayName(for: toBundleId)
        return "You often open \(toDisplayName) after \(fromDisplayName)"
    }

    private static func displayName(for bundleId: String) -> String {
        if let mappedName = NicheAppSuggestionMapping.appDisplayName(bundleId: bundleId) {
            return mappedName
        }

        if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: applicationURL),
           let localizedName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !localizedName.isEmpty {
            return localizedName
        }

        if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: applicationURL),
           let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty {
            return bundleName
        }

        return bundleId
    }
}
