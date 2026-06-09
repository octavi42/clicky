//
//  ActivityStore.swift
//  leanring-buddy
//
//  Persists app-to-app transition edges for passive routine detection.
//

import Foundation

struct TransitionEdge: Codable, Equatable, Identifiable {
    let fromBundleId: String
    let toBundleId: String
    /// Transition counts keyed by calendar day (yyyy-MM-dd). Storing per-day
    /// counts (instead of a single lifetime total) lets pruning drop days that
    /// fall outside the rolling window so `count` and `distinctDayCount` always
    /// reflect only in-window activity. Otherwise old transitions keep inflating
    /// the strength ranking long after they stop happening.
    var transitionCountsByDay: [String: Int]
    var firstSeen: Date
    var lastSeen: Date

    var id: String {
        Self.edgeIdentifier(fromBundleId: fromBundleId, toBundleId: toBundleId)
    }

    /// Total in-window transitions across all retained days.
    var count: Int {
        transitionCountsByDay.values.reduce(0, +)
    }

    var occurrenceDays: [String] {
        transitionCountsByDay.keys.sorted()
    }

    var distinctDayCount: Int {
        transitionCountsByDay.count
    }

    init(
        fromBundleId: String,
        toBundleId: String,
        transitionCountsByDay: [String: Int],
        firstSeen: Date,
        lastSeen: Date
    ) {
        self.fromBundleId = fromBundleId
        self.toBundleId = toBundleId
        self.transitionCountsByDay = transitionCountsByDay
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }

    /// Convenience initializer that distributes a total `count` across the given
    /// `occurrenceDays` (used by tests and any callers thinking in totals).
    init(
        fromBundleId: String,
        toBundleId: String,
        count: Int,
        occurrenceDays: [String],
        firstSeen: Date,
        lastSeen: Date
    ) {
        var countsByDay: [String: Int] = [:]
        let sortedDays = occurrenceDays.sorted()
        if !sortedDays.isEmpty {
            let baseCountPerDay = count / sortedDays.count
            let remainderToFrontload = count % sortedDays.count
            for (dayIndex, day) in sortedDays.enumerated() {
                countsByDay[day] = baseCountPerDay + (dayIndex < remainderToFrontload ? 1 : 0)
            }
        }

        self.init(
            fromBundleId: fromBundleId,
            toBundleId: toBundleId,
            transitionCountsByDay: countsByDay,
            firstSeen: firstSeen,
            lastSeen: lastSeen
        )
    }

    static func edgeIdentifier(fromBundleId: String, toBundleId: String) -> String {
        "\(fromBundleId)>>>>\(toBundleId)"
    }
}

struct ActivityStoreFile: Codable {
    var version: Int = 1
    var edges: [TransitionEdge]
    var suppressedEdgeIds: [String]
}

final class ActivityStore {
    static let rollingWindowDays = 30

    static var activityFileURL: URL {
        ClickyPaths.activity
    }

    private let activityFileURL: URL
    private var edges: [TransitionEdge] = []
    private var suppressedEdgeIds: Set<String> = []

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(activityFileURL: URL = ActivityStore.activityFileURL) {
        self.activityFileURL = activityFileURL
        load()
    }

    func allEdges(now: Date = Date()) -> [TransitionEdge] {
        pruneExpiredEdges(now: now)
        return edges
    }

    func suppressedEdgeIdentifiers() -> Set<String> {
        suppressedEdgeIds
    }

    func isSuppressed(edgeId: String) -> Bool {
        suppressedEdgeIds.contains(edgeId)
    }

    func recordTransition(from fromBundleId: String, to toBundleId: String, at timestamp: Date = Date()) {
        pruneExpiredEdges(now: timestamp)

        let dayString = dayFormatter.string(from: timestamp)
        let edgeId = TransitionEdge.edgeIdentifier(fromBundleId: fromBundleId, toBundleId: toBundleId)

        if let index = edges.firstIndex(where: { $0.id == edgeId }) {
            edges[index].transitionCountsByDay[dayString, default: 0] += 1
            edges[index].lastSeen = timestamp
        } else {
            edges.append(
                TransitionEdge(
                    fromBundleId: fromBundleId,
                    toBundleId: toBundleId,
                    transitionCountsByDay: [dayString: 1],
                    firstSeen: timestamp,
                    lastSeen: timestamp
                )
            )
        }

        save()
    }

    func suppress(edgeId: String) {
        suppressedEdgeIds.insert(edgeId)
        save()
    }

    private func pruneExpiredEdges(now: Date) {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -Self.rollingWindowDays,
            to: now
        ) ?? .distantPast
        let cutoffDayString = dayFormatter.string(from: cutoffDate)

        edges = edges.compactMap { edge in
            var prunedEdge = edge
            prunedEdge.transitionCountsByDay = prunedEdge.transitionCountsByDay.filter { day, _ in
                day >= cutoffDayString
            }
            guard !prunedEdge.transitionCountsByDay.isEmpty else { return nil }
            return prunedEdge
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: activityFileURL.path),
              let data = try? Data(contentsOf: activityFileURL),
              let decoded = try? decoder.decode(ActivityStoreFile.self, from: data) else {
            edges = []
            suppressedEdgeIds = []
            return
        }

        edges = decoded.edges
        suppressedEdgeIds = Set(decoded.suppressedEdgeIds)
    }

    private func save() {
        let directory = activityFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let payload = ActivityStoreFile(
            edges: edges,
            suppressedEdgeIds: Array(suppressedEdgeIds).sorted()
        )

        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: activityFileURL, options: .atomic)
    }
}
