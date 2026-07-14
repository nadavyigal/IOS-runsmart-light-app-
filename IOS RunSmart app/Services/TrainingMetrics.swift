import Foundation

/// WP-44 S3 — the single source for numbers and vocabulary that render on more
/// than one surface (audit §4 Risk 4: Week 3 vs Week 4, "11-week" vs "11 day",
/// plan 86.20 km vs summed ~36 km, zone words on one surface and effort words
/// on another).
///
/// Design note (founder-approved 2026-07-14): a stateless pure helper in
/// Services/, following the StructuredWorkoutFactory / DeterministicFlexWeekBuilder
/// pattern — not a service-protocol retrofit and not an ObservableObject store.
/// Rule: any number or taxonomy rendered twice must come from one accessor here.
enum TrainingMetrics {

    // MARK: - Week number

    /// The plan week a given date falls in, 1-based, clamped to the plan bounds.
    /// Every "Week N of M" render must use this — Beginner5KHabitCard previously
    /// derived its own from `weekOfYear` while other surfaces disagreed.
    static func currentWeekNumber(
        planStartDate: Date,
        totalWeeks: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let components = calendar.dateComponents(
            [.weekOfYear],
            from: calendar.startOfDay(for: planStartDate),
            to: calendar.startOfDay(for: now)
        )
        return max(1, min((components.weekOfYear ?? 0) + 1, max(1, totalWeeks)))
    }

    // MARK: - Streak

    /// Parses a day count out of the streak labels the backends actually produce
    /// ("12", "12 days", "12 day streak"). Returns nil for labels that are not
    /// day streaks (e.g. the production path's "3x/week" cadence), so a foreign
    /// unit can never be re-rendered with "day streak" bolted on — that is
    /// exactly how Profile "11-week" became Today "11 day streak".
    static func streakDays(fromLabel label: String) -> Int? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.range(of: "^[0-9]+", options: .regularExpression) else { return nil }
        let remainder = trimmed[match.upperBound...]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard remainder.isEmpty || remainder.hasPrefix("day") else { return nil }
        return Int(trimmed[match])
    }

    /// The one canonical streak rendering.
    static func streakLabel(days: Int) -> String {
        days == 1 ? "1 day streak" : "\(days) day streak"
    }

    /// Canonical label from any backend label, or nil when the input is not a
    /// day streak.
    static func canonicalStreakLabel(fromLabel label: String) -> String? {
        streakDays(fromLabel: label).map(streakLabel(days:))
    }

    // MARK: - Weekly distance

    /// Distance covered in the same calendar week as `now`. Every "weekly
    /// distance" figure must sum through here.
    static func weeklyDistanceKm(
        runs: [RecordedRun],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        runs.filter { calendar.isDate($0.startedAt, equalTo: now, toGranularity: .weekOfYear) }
            .reduce(0.0) { $0 + $1.distanceMeters / 1_000 }
    }

    // MARK: - Intensity vocabulary

    /// One effort vocabulary per workout kind. Cards said "Easy" while two
    /// separate kind→zone mappers said "Zone 2"/"Zone 3-4" for the same workout;
    /// both mappers now read from here.
    static func effortLabel(for kind: WorkoutKind) -> String {
        switch kind {
        case .recovery: "Very easy"
        case .easy, .long, .parkrun: "Easy"
        case .tempo, .hills: "Comfortably hard"
        case .intervals, .race: "Hard"
        case .strength: "Strength"
        }
    }

    // MARK: - Wellness trend goodness

    enum TrendGoodness {
        case positive
        case caution
        case neutral
    }

    /// Colors a wellness trend by direction + goodness instead of a fixed
    /// palette — an HRV holding stable or improving must never render in the
    /// alarm color (audit: "HRV up in red").
    static func hrvTrendGoodness(forLabel label: String) -> TrendGoodness {
        switch label.trimmingCharacters(in: .whitespaces).lowercased() {
        case "stable", "higher", "up", "improving": .positive
        case "lower", "down", "declining": .caution
        default: .neutral
        }
    }
}
