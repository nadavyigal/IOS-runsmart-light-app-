import Foundation

enum FlexWeekAdjustmentHistory {
    private static let key = "runsmart.flexWeek.adjustmentHistory"
    private static let maxRecords = 10

    // MARK: - Write

    /// Record a confirmed adjustment. Caps the history at `maxRecords`.
    static func record(_ record: FlexWeekRecord) {
        var history = load()
        history.append(record)
        if history.count > maxRecords {
            history = Array(history.suffix(maxRecords))
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Read

    /// Returns records whose `confirmedAt` falls within `window` seconds before now.
    static func historyWithin(_ window: TimeInterval, now: Date = Date()) -> [FlexWeekRecord] {
        let cutoff = now.addingTimeInterval(-window)
        return load().filter { $0.confirmedAt > cutoff }
    }

    static func all() -> [FlexWeekRecord] {
        load()
    }

    // MARK: - Test support

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Private

    private static func load() -> [FlexWeekRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([FlexWeekRecord].self, from: data)
        else { return [] }
        return records
    }
}
