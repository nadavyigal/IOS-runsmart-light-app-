import Foundation

#if DEBUG
enum RunSmartAdaptivePreviewData {
    static func workouts(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkoutSummary] {
        let startOfToday = calendar.startOfDay(for: now)
        let planID = UUID(uuidString: "A64A11E0-04FE-49AF-965E-B1D300000001")!
        let configs: [(Int, WorkoutKind, String, String, String, Bool, String)] = [
            (-1, .intervals, "Intervals", "8 x 400m", "Missed", false, "Hard"),
            (0, .recovery, "Recovery Reset", "Rest", "Today", false, "Recovery"),
            (1, .easy, "Easy Run", "5.0 km", "Conversational", false, "Easy"),
            (2, .strength, "Strength", "35 min", "Mobility + core", false, "Moderate"),
            (3, .tempo, "Tempo Run", "7.0 km", "Controlled", false, "Moderate-hard"),
            (4, .recovery, "Recovery", "Rest", "Absorb the work", false, "Recovery"),
            (5, .long, "Long Run", "12.0 km", "Endurance", false, "Easy")
        ]

        return configs.enumerated().compactMap { index, config in
            guard let date = calendar.date(byAdding: .day, value: config.0, to: startOfToday) else {
                return nil
            }
            let weekdayIndex = calendar.component(.weekday, from: date) - 1
            return WorkoutSummary(
                id: UUID(uuidString: String(format: "A64A11E0-04FE-49AF-965E-B1D30000%04d", index + 10))!,
                scheduledDate: date,
                planID: planID,
                weekday: calendar.shortWeekdaySymbols[weekdayIndex].uppercased(),
                date: "\(calendar.component(.day, from: date))",
                kind: config.1,
                title: config.2,
                distance: config.3,
                detail: config.4,
                isToday: calendar.isDate(date, inSameDayAs: now),
                isComplete: config.5,
                durationMinutes: config.1 == .strength ? 35 : nil,
                targetPaceSecondsPerKm: config.1 == .tempo ? 320 : nil,
                intensity: config.6,
                trainingPhase: "Build",
                workoutStructure: config.1 == .intervals ? "15 min easy, 8 x 400m, 10 min easy" : nil,
                adjustedAt: nil,
                adjustedReason: nil
            )
        }
    }

    static let todayRecommendation = TodayRecommendation(
        readiness: 72,
        readinessLabel: "Good",
        workoutTitle: "Recovery Reset",
        distance: "Rest",
        pace: "—",
        elevation: "—",
        coachMessage: "Yesterday did not go to plan. Let's protect your progress and reshape the week safely.",
        weeklyProgress: "Adaptive preview",
        streak: "11",
        recovery: "Steady",
        hrv: "59 ms",
        rationale: "The missed interval session changes the load pattern. Review a safer week before accepting anything."
    )
}

enum AdaptivePreviewPresentation {
    static func shouldShowCard(for variant: RunSmartAppVariant) -> Bool {
        variant == .adaptivePreview
    }

    static func preselectedReason(
        in workouts: [WorkoutSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FlexWeekReason? {
        guard let missed = FlexWeekPresentation.mostRecentMissedWorkout(
            in: workouts,
            now: now,
            calendar: calendar
        ) else {
            return nil
        }
        return .missedWorkout(workoutID: missed.id)
    }
}
#endif
