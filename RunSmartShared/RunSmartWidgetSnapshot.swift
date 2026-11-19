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
