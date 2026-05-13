import Foundation
import SwiftUI

#if DEBUG
enum RunSmartPreviewData {
    static let runner = RunnerProfile(
        name: "Alex Morgan",
        goal: "10K focused",
        streak: "11-week streak",
        level: "Peak Performer",
        totalRuns: 128,
        totalDistance: 842,
        totalTime: "83h 21m"
    )

    static let today = TodayRecommendation(
        readiness: 82,
        readinessLabel: "High",
        workoutTitle: "Tempo Builder",
        distance: "8.2 km",
        pace: "5'15\" /km",
        elevation: "128 m",
        coachMessage: "You've built great momentum this week. Let's keep it going with a smart challenge."
    )

    static let workouts: [WorkoutSummary] = {
        let calendar = Calendar.current
        let today = Date()
        guard let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) else { return [] }

        let configs: [(offset: Int, kind: WorkoutKind, title: String, distance: String, detail: String, isComplete: Bool)] = [
            (0, .easy,      "Easy Run",   "5.0 km",   "Done",       true),
            (1, .intervals, "Intervals",  "8 x 400m", "Done",       true),
            (2, .tempo,     "Tempo Run",  "8.2 km",   "Today",      false),
            (3, .strength,  "Strength",   "45 min",   "Gym",        false),
            (4, .recovery,  "Recovery",   "Rest",     "Easy",       false),
            (5, .easy,      "Easy Run",   "6.0 km",   "Base",       false),
            (6, .long,      "Long Run",   "14.0 km",  "Endurance",  false)
        ]

        return configs.compactMap { config in
            guard let date = calendar.date(byAdding: .day, value: config.offset, to: weekStart) else { return nil }
            let weekdayIdx = calendar.component(.weekday, from: date) - 1
            let weekday = calendar.shortWeekdaySymbols[weekdayIdx].uppercased()
            let dayNum = calendar.component(.day, from: date)
            return WorkoutSummary(
                id: UUID(),
                scheduledDate: date,
                weekday: weekday,
                date: "\(dayNum)",
                kind: config.kind,
                title: config.title,
                distance: config.distance,
                detail: config.detail,
                isToday: calendar.isDateInToday(date),
                isComplete: config.isComplete
            )
        }
    }()

    static let coachMessages: [CoachMessage] = [
        .init(text: "Focus on relaxed effort in the middle miles. You've got this.", time: "7:30 AM", isUser: false),
        .init(text: "Thanks coach! Feeling strong.", time: "7:32 AM", isUser: true)
    ]

    static let achievements: [Achievement] = [
        .init(title: "Threshold PR", subtitle: "New", symbol: "sun.max", tint: Color.lime),
        .init(title: "Early Riser", subtitle: "4 AM", symbol: "alarm", tint: .cyan),
        .init(title: "Consistency", subtitle: "10K", symbol: "checkmark.seal", tint: .green),
        .init(title: "Long Run", subtitle: "15K", symbol: "shoeprints.fill", tint: .orange),
        .init(title: "Week Warrior", subtitle: "5 days", symbol: "sparkles", tint: .mint)
    ]

    static let activeGoal = GoalSummary(
        id: "goal-10k",
        title: "10K Improvement",
        detail: "Bring your 10K from 49:12 to 46:30 with controlled tempo work.",
        progress: 0.64,
        target: "46:30",
        daysRemaining: 38,
        trendLabel: "On track"
    )

    static let activeChallenge = ChallengeSummary(
        id: "challenge-consistency",
        title: "21-Day Consistency",
        detail: "Complete the daily training prompt and keep your plan synced.",
        progress: 0.52,
        dayLabel: "Day 11 of 21",
        isActive: true
    )

    static let recovery = RecoverySnapshot(
        readiness: 82,
        bodyBattery: 76,
        sleep: "7h 48m",
        hrv: "Stable",
        stress: "Low",
        recommendation: "Your recovery is strong enough for a controlled tempo session."
    )

    static let wellness = WellnessSnapshot(
        calories: "2,640",
        hydration: "Good",
        soreness: "Mild calves",
        mood: "Motivated",
        checkInStatus: "Morning check-in complete"
    )

    static let shoes: [ShoeSummary] = [
        .init(id: "shoe-pegasus", name: "Nike Pegasus 41", distanceKm: 314, limitKm: 650, status: "Healthy"),
        .init(id: "shoe-speed", name: "Saucony Endorphin Speed", distanceKm: 226, limitKm: 500, status: "Tempo pair")
    ]

    static let reminders: [ReminderPreference] = [
        .init(id: "checkin", title: "Morning check-in", detail: "07:15 on training days", enabled: true),
        .init(id: "workout", title: "Workout reminder", detail: "90 min before planned run", enabled: true),
        .init(id: "recovery", title: "Recovery prompt", detail: "Evening after hard sessions", enabled: false)
    ]

    static let runReports: [RunReportSummary] = [
        .init(id: "report-tempo", title: "Tempo Builder", dateLabel: "Yesterday", distance: "8.0 km", pace: "5:12 /km", score: 88, insight: "Great rhythm. Threshold work stayed controlled."),
        .init(id: "report-easy", title: "Easy Run", dateLabel: "Mon", distance: "5.2 km", pace: "6:08 /km", score: 81, insight: "Aerobic load was right where it should be.")
    ]

    static let trainingLoad = TrainingLoadSnapshot(
        loadLabel: "Productive",
        loadValue: 72,
        acwr: "0.94",
        consistency: 92,
        paceTrend: "-0:03 /km",
        weeklyRecap: "31 km complete, two quality sessions, recovery holding steady."
    )

    static let shareableAchievements: [ShareableAchievement] = [
        .init(id: "share-threshold", title: "Threshold PR", subtitle: "New badge", symbol: "sun.max.fill", tintName: "lime"),
        .init(id: "share-10k", title: "10K Streak", subtitle: "11 days", symbol: "sparkles", tintName: "success"),
        .init(id: "share-long", title: "Long Run", subtitle: "15K", symbol: "flag.checkered", tintName: "amber")
    ]

    // MARK: - Saved Routes & Benchmarks

    private static func sampleRoutePoints(startLat: Double, startLon: Double, count: Int) -> [RunRoutePoint] {
        (0..<count).map { i in
            RunRoutePoint(
                latitude: startLat + Double(i) * 0.0004,
                longitude: startLon + Double(i % 3) * 0.0003 - 0.0003,
                timestamp: Date().addingTimeInterval(TimeInterval(i * 15)),
                horizontalAccuracy: 8,
                altitude: 22 + Double(i % 5) * 2
            )
        }
    }

    static let savedRouteIDs = (UUID(), UUID(), UUID())

    static let savedRoutes: [SavedRoute] = {
        let now = Date()
        return [
            SavedRoute(
                id: savedRouteIDs.0,
                name: "Park Loop",
                distanceMeters: 5200,
                elevationGainMeters: 34,
                points: sampleRoutePoints(startLat: 32.0853, startLon: 34.7818, count: 40),
                source: .recorded,
                tags: ["easy", "flat"],
                notes: "Nice morning route through the park.",
                isFavorite: true,
                createdAt: now.addingTimeInterval(-86400 * 14),
                updatedAt: now.addingTimeInterval(-86400 * 2)
            ),
            SavedRoute(
                id: savedRouteIDs.1,
                name: "River Trail 8K",
                distanceMeters: 8100,
                elevationGainMeters: 62,
                points: sampleRoutePoints(startLat: 32.0700, startLon: 34.7700, count: 55),
                source: .recorded,
                tags: ["tempo", "trail"],
                notes: "",
                isFavorite: false,
                createdAt: now.addingTimeInterval(-86400 * 10),
                updatedAt: now.addingTimeInterval(-86400 * 5)
            ),
            SavedRoute(
                id: savedRouteIDs.2,
                name: "Garmin Beach Run",
                distanceMeters: 6400,
                elevationGainMeters: 12,
                points: sampleRoutePoints(startLat: 32.0900, startLon: 34.7650, count: 48),
                source: .garmin,
                tags: ["flat", "scenic"],
                notes: "Imported from Garmin.",
                isFavorite: true,
                createdAt: now.addingTimeInterval(-86400 * 7),
                updatedAt: now.addingTimeInterval(-86400 * 3)
            )
        ]
    }()

    static let benchmarkRoutes: [BenchmarkRoute] = [
        BenchmarkRoute(
            id: UUID(),
            savedRouteID: savedRouteIDs.0,
            enabledAt: Date().addingTimeInterval(-86400 * 10),
            historicalRunCount: 5,
            personalBestSeconds: 1560,
            personalBestDate: Date().addingTimeInterval(-86400 * 3),
            averagePaceSecondsPerKm: 318,
            averageDurationSeconds: 1640
        ),
        BenchmarkRoute(
            id: UUID(),
            savedRouteID: savedRouteIDs.1,
            enabledAt: Date().addingTimeInterval(-86400 * 7),
            historicalRunCount: 2,
            personalBestSeconds: 2430,
            personalBestDate: Date().addingTimeInterval(-86400 * 5),
            averagePaceSecondsPerKm: 312,
            averageDurationSeconds: 2520
        )
    ]

    // MARK: - Recorded Runs

    static var recordedRuns: [RecordedRun] {
        let calendar = Calendar.current
        let distances = [5.0, 6.2, 4.8, 8.0, 5.4, 10.2, 6.7, 7.1]
        return distances.enumerated().map { index, distanceKm in
            let start = calendar.date(byAdding: .day, value: -index * 2, to: Date()) ?? Date()
            let moving = distanceKm * 330
            return RecordedRun(
                id: UUID(),
                providerActivityID: "preview-\(index)",
                source: .runSmart,
                startedAt: start,
                endedAt: start.addingTimeInterval(moving),
                distanceMeters: distanceKm * 1_000,
                movingTimeSeconds: moving,
                averagePaceSecondsPerKm: moving / distanceKm,
                averageHeartRateBPM: 142 + index,
                routePoints: [],
                syncedAt: nil
            )
        }
    }
}
#endif
