import Foundation

enum NoticeContextKind: Equatable {
    case streak(days: Int)
    case categoryFirst(distanceKm: Double, label: String)
    case comeback(daysSince: Int)
    case highEffort(percentAbove: Int)
    case earlyMorning(startedAt: Date)
    case lateNight(startedAt: Date)
    case thirdRunWeek

    var contextKey: String {
        switch self {
        case .streak(let days):
            return "streak_\(days)"
        case .categoryFirst(let distanceKm, _):
            if distanceKm >= 21.0 { return "category_first_21.1" }
            if distanceKm >= 10.0 { return "category_first_10" }
            return "category_first_5"
        case .comeback(let daysSince):
            return "comeback_\(daysSince)"
        case .highEffort:
            return "high_effort"
        case .earlyMorning:
            return "early_morning"
        case .lateNight:
            return "late_night"
        case .thirdRunWeek:
            return "third_run_week"
        }
    }
}

enum ContextDetector {

    private static let streakMilestones = [3, 7, 14, 30, 60, 100]
    private static let categoryThresholds: [(km: Double, label: String)] = [
        (21.1, "First half marathon"),
        (10.0, "First 10K"),
        (5.0, "First 5K")
    ]

    static func detect(
        currentRun: RecordedRun,
        allRuns: [RecordedRun],
        noticedOnCooldown: Bool,
        firedContextKeys: Set<String> = []
    ) -> NoticeContextKind? {
        guard !noticedOnCooldown else { return nil }

        let prior = allRuns.filter { $0.id != currentRun.id }
        let calendar = Calendar.current
        let currentKm = currentRun.distanceMeters / 1_000

        let streak = computeStreak(runDates: allRuns.map(\.startedAt), calendar: calendar)
        for milestone in streakMilestones.reversed() where streak == milestone {
            let key = "streak_\(milestone)"
            if !firedContextKeys.contains(key) {
                return .streak(days: milestone)
            }
        }

        for threshold in categoryThresholds where currentKm >= threshold.km {
            let priorMax = prior.map { $0.distanceMeters / 1_000 }.max() ?? 0
            if priorMax < threshold.km {
                let key: String
                if threshold.km >= 21.0 { key = "category_first_21.1" }
                else if threshold.km >= 10.0 { key = "category_first_10" }
                else { key = "category_first_5" }
                if !firedContextKeys.contains(key) {
                    return .categoryFirst(distanceKm: threshold.km, label: threshold.label)
                }
            }
        }

        if let last = prior.sorted(by: { $0.startedAt > $1.startedAt }).first {
            let daysSince = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.startedAt), to: calendar.startOfDay(for: currentRun.startedAt)).day ?? 0
            if daysSince >= 7, !firedContextKeys.contains(where: { $0.hasPrefix("comeback_") }) {
                return .comeback(daysSince: daysSince)
            }
        }

        if currentKm >= 0.3, currentRun.averagePaceSecondsPerKm > 0 {
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: currentRun.startedAt) ?? currentRun.startedAt
            let recent = prior.filter { $0.startedAt >= thirtyDaysAgo && $0.distanceMeters >= 50 && $0.averagePaceSecondsPerKm > 0 }
            if recent.count >= 3 {
                let avgPace = recent.reduce(0.0) { $0 + $1.averagePaceSecondsPerKm } / Double(recent.count)
                let improvement = (avgPace - currentRun.averagePaceSecondsPerKm) / avgPace
                if improvement >= 0.08, !firedContextKeys.contains("high_effort") {
                    return .highEffort(percentAbove: Int((improvement * 100).rounded()))
                }
            }
        }

        let hour = calendar.component(.hour, from: currentRun.startedAt)
        let minute = calendar.component(.minute, from: currentRun.startedAt)
        if hour < 6 || (hour == 6 && minute < 30), !firedContextKeys.contains("early_morning") {
            return .earlyMorning(startedAt: currentRun.startedAt)
        }
        if hour >= 21, !firedContextKeys.contains("late_night") {
            return .lateNight(startedAt: currentRun.startedAt)
        }

        let weekStart = startOfWeek(for: currentRun.startedAt, calendar: calendar)
        let runsThisWeek = prior.filter { $0.startedAt >= weekStart }
        if runsThisWeek.count >= 2, !firedContextKeys.contains("third_run_week") {
            return .thirdRunWeek
        }

        return nil
    }

    static func computeStreak(runDates: [Date], calendar: Calendar = .current, now: Date = Date()) -> Int {
        let dayKeys = Set(runDates.map { calendar.startOfDay(for: $0) })
        guard !dayKeys.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: now)
        while dayKeys.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}
