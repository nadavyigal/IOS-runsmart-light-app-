import Foundation

/// What the home-screen widget shows, written by the app into the shared App Group.
/// The widget never calls the network; it reads only this.
nonisolated struct RunSmartWidgetSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var updatedAt: Date
    /// Start of the calendar week the totals below belong to.
    var weekStart: Date
    /// Distance actually recorded this week, from saved runs.
    var weekDistanceMeters: Double
    /// Planned distance for this week from the active plan. Nil without a plan.
    var weekGoalMeters: Double?
    var isRunInProgress: Bool
}

/// Reads and writes `RunSmartWidgetSnapshot` in the App Group shared by the app and the
/// widget extension. Every call is a no-op when the App Group container is unavailable
/// (for example a build signed without the entitlement), so nothing crashes.
struct RunSmartWidgetSnapshotStore {
    nonisolated static let appGroupID = "group.com.runsmart.lite"
    nonisolated static let widgetKind = "RunSmartWeeklyWidget"
    private nonisolated static let key = "runsmart.widget.snapshot.v1"

    private let defaults: UserDefaults?

    nonisolated init(defaults: UserDefaults? = UserDefaults(suiteName: RunSmartWidgetSnapshotStore.appGroupID)) {
        self.defaults = defaults
    }

    /// The real store. `UserDefaults(suiteName:)` returns an object even when the build lacks
    /// the App Group entitlement, so availability is decided by the group container itself.
    nonisolated static var shared: RunSmartWidgetSnapshotStore {
        let hasContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
        return RunSmartWidgetSnapshotStore(defaults: hasContainer ? UserDefaults(suiteName: appGroupID) : nil)
    }

    nonisolated var isAvailable: Bool { defaults != nil }

    nonisolated func load() -> RunSmartWidgetSnapshot? {
        guard let data = defaults?.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(RunSmartWidgetSnapshot.self, from: data),
              snapshot.schemaVersion == RunSmartWidgetSnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    nonisolated func save(_ snapshot: RunSmartWidgetSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }

    nonisolated func clear() {
        defaults?.removeObject(forKey: Self.key)
    }
}

/// What the small weekly widget should draw, decided from the snapshot alone.
nonisolated struct RunSmartWeeklyWidgetContent: Equatable {
    /// A "run in progress" flag older than this is ignored (the app likely died mid-run).
    static let runFlagMaximumAge: TimeInterval = 12 * 3_600

    var hasData: Bool
    var weekDistanceKm: Double
    var weekGoalKm: Double?
    var isRunInProgress: Bool

    /// Ring fill 0...1, nil without a goal (no empty ring).
    var progress: Double? {
        guard let weekGoalKm, weekGoalKm > 0 else { return nil }
        return min(1, max(0, weekDistanceKm / weekGoalKm))
    }

    /// "21.4" for the big number.
    var distanceLabel: String { String(format: "%.1f", weekDistanceKm) }

    /// "of 30 km", or "km this week" without a goal.
    var goalLabel: String {
        guard let weekGoalKm, weekGoalKm > 0 else { return "km this week" }
        let rounded = weekGoalKm.rounded()
        return abs(rounded - weekGoalKm) < 0.05 ? String(format: "of %.0f km", rounded) : String(format: "of %.1f km", weekGoalKm)
    }

    static func make(snapshot: RunSmartWidgetSnapshot?, now: Date, calendar: Calendar) -> RunSmartWeeklyWidgetContent {
        guard let snapshot else {
            return RunSmartWeeklyWidgetContent(hasData: false, weekDistanceKm: 0, weekGoalKm: nil, isRunInProgress: false)
        }
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let isCurrentWeek = abs(snapshot.weekStart.timeIntervalSince(currentWeek)) < 1
        let runFlagIsFresh = now.timeIntervalSince(snapshot.updatedAt) < runFlagMaximumAge
        return RunSmartWeeklyWidgetContent(
            hasData: true,
            weekDistanceKm: isCurrentWeek ? max(0, snapshot.weekDistanceMeters) / 1_000 : 0,
            weekGoalKm: isCurrentWeek ? snapshot.weekGoalMeters.map { $0 / 1_000 } : nil,
            isRunInProgress: snapshot.isRunInProgress && runFlagIsFresh
        )
    }

    /// Next timeline refresh: the start of next week, so the totals reset on time.
    static func nextRefresh(after now: Date, calendar: Calendar) -> Date {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return now.addingTimeInterval(6 * 3_600) }
        return week.end
    }
}
