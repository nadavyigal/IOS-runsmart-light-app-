import Foundation
import SwiftUI

#if DEBUG
enum RunSmartDemoData {
    static let onboardingProfile = OnboardingProfile(
        displayName: "Alex Morgan",
        goal: "10K improvement",
        experience: "Intermediate",
        age: 34,
        averageWeeklyDistanceKm: 32.5,
        trainingDataSource: .garmin,
        trainingDataUpdatedAt: Date().addingTimeInterval(-3_600),
        weeklyRunDays: 4,
        preferredDays: ["Tue", "Thu", "Sat", "Sun"],
        units: "Metric",
        coachingTone: "Motivating",
        notificationsEnabled: true,
        planAdjustmentConfirmationsEnabled: true
    )

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
        coachMessage: "You've built great momentum this week. Let's keep it going with a smart challenge.",
        weeklyProgress: "3 of 4 runs complete",
        streak: "11",
        recovery: "Strong",
        hrv: "61 ms",
        rationale: "Body battery at 82 - you're fueled for a real effort. Tempo Builder lands well today."
    )

    static let activePlan = TrainingPlanSnapshot(
        id: UUID(uuidString: "42C3C9E6-7E37-4C1F-A1A2-E76D3B5E0312")!,
        title: "10K Speed Builder",
        startDate: Date().addingTimeInterval(-21 * 86_400),
        endDate: Date().addingTimeInterval(35 * 86_400),
        totalWeeks: 8,
        planType: "10K improvement"
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
                id: UUID(uuidString: String(format: "42C3C9E6-7E37-4C1F-A1A2-E76D3B5E%04d", config.offset + 100)) ?? UUID(),
                scheduledDate: date,
                planID: activePlan.id,
                weekday: weekday,
                date: "\(dayNum)",
                kind: config.kind,
                title: config.title,
                distance: config.distance,
                detail: config.detail,
                isToday: calendar.isDateInToday(date),
                isComplete: config.isComplete,
                durationMinutes: config.kind == .strength ? 45 : nil,
                targetPaceSecondsPerKm: config.kind == .tempo ? 315 : nil,
                intensity: config.kind == .tempo ? "Moderate-hard" : "Easy",
                trainingPhase: "Build",
                workoutStructure: config.kind == .tempo ? "15 min easy, 20 min tempo, 10 min easy" : nil
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
        id: "challenge-foundation",
        title: "21-Day Running Foundation",
        detail: "From zero to 30 minutes — daily coaching and a plan built around your body.",
        progress: 0.52,
        dayLabel: "Day 11 of 21",
        isActive: true
    )

    static let recovery = RecoverySnapshot(
        readiness: 82,
        bodyBattery: 76,
        sleep: "7h 48m",
        hrv: "Stable",
        hrvSource: .garmin,
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

    static let healthDailySummary = HealthDailySummary(
        steps: 8420,
        activeCalories: 540,
        sleepSeconds: 7 * 3600 + 48 * 60
    )

    static let wellnessTrends = WellnessTrendSeries(
        days: [
            DailyWellnessPoint(date: Date().addingTimeInterval(-6 * 86_400), hrvMilliseconds: 54, hrvSource: .garmin, trainingReadiness: 68, bodyBattery: 64),
            DailyWellnessPoint(date: Date().addingTimeInterval(-5 * 86_400), hrvMilliseconds: 52, hrvSource: .garmin, trainingReadiness: 66, bodyBattery: 62),
            DailyWellnessPoint(date: Date().addingTimeInterval(-4 * 86_400), hrvMilliseconds: 55, hrvSource: .garmin, trainingReadiness: 69, bodyBattery: 67),
            DailyWellnessPoint(date: Date().addingTimeInterval(-3 * 86_400), hrvMilliseconds: 57, hrvSource: .garmin, trainingReadiness: 71, bodyBattery: 69),
            DailyWellnessPoint(date: Date().addingTimeInterval(-2 * 86_400), hrvMilliseconds: 58, hrvSource: .garmin, trainingReadiness: 73, bodyBattery: 70),
            DailyWellnessPoint(date: Date().addingTimeInterval(-1 * 86_400), hrvMilliseconds: 60, hrvSource: .garmin, trainingReadiness: 75, bodyBattery: 72),
            DailyWellnessPoint(date: Date(), hrvMilliseconds: 61, hrvSource: .garmin, trainingReadiness: 77, bodyBattery: 74)
        ],
        hrvBars: [0.89, 0.85, 0.90, 0.93, 0.95, 0.98, 1.0],
        readinessBars: [0.88, 0.85, 0.90, 0.92, 0.95, 0.97, 1.0],
        hrvTrendSummary: "HRV is trending up",
        readinessTrendSummary: "Readiness is trending up",
        latestHRVDisplay: "61 ms",
        latestHRVSource: .garmin,
        latestReadinessDisplay: "77"
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
        runReportDetails[0].summary,
        runReportDetails[1].summary,
        runReportDetails[2].summary
    ]

    static let runReportDetails: [RunReportDetail] = [
        RunReportDetail(
            id: "report-tempo",
            runID: "demo-garmin-0",
            title: "Tempo Builder",
            dateLabel: "Yesterday",
            source: "Garmin",
            distance: "8.0 km",
            duration: "41:36",
            averagePace: "5:12 /km",
            averageHeartRate: "156 bpm",
            coachScore: 88,
            notes: CoachRunNotes(
                summary: "Great rhythm. Threshold work stayed controlled.",
                effort: "You sat in the right band for most of the tempo block and avoided the late-run surge that usually costs recovery.",
                recovery: "Readiness stayed high because sleep and HRV both supported the session.",
                nextSessionNudge: "Keep the next run easy so Saturday's long run feels smooth.",
                keyInsights: ["Tempo pace held within 4 sec/km", "Heart rate drift stayed low", "Cadence settled after the warmup"],
                pacing: "First 2 km relaxed, middle 4 km steady, final 2 km controlled.",
                biomechanics: "Cadence and vertical oscillation looked stable for the workload.",
                recoveryTimeline: ["Tonight: prioritize protein and hydration", "Tomorrow: easy 35-40 min", "Saturday: long run as planned"]
            ),
            structuredNextWorkout: StructuredNextWorkout(
                title: "Easy Aerobic Reset",
                dateLabel: "Tomorrow",
                distance: "6.0 km",
                target: "6:05-6:25 /km",
                notes: "Keep it conversational and finish feeling like you could add more."
            )
        ),
        RunReportDetail(
            id: "report-easy",
            runID: "demo-runsmart-1",
            title: "Easy Run",
            dateLabel: "Mon",
            source: "RunSmart",
            distance: "5.2 km",
            duration: "31:54",
            averagePace: "6:08 /km",
            averageHeartRate: "139 bpm",
            coachScore: 81,
            notes: CoachRunNotes(
                summary: "Aerobic load was right where it should be.",
                effort: "This was the kind of easy run that protects the rest of the week.",
                recovery: "Low stress and stable HRV suggest the effort was absorbed well.",
                nextSessionNudge: "Tempo work is appropriate if morning readiness stays above 70.",
                keyInsights: ["Conversational pace", "Low cardiac drift", "Good recovery signal"]
            ),
            structuredNextWorkout: nil
        ),
        RunReportDetail(
            id: "report-long",
            runID: "demo-garmin-2",
            title: "Long Run",
            dateLabel: "Sat",
            source: "Garmin",
            distance: "12.4 km",
            duration: "1:12:18",
            averagePace: "5:50 /km",
            averageHeartRate: "148 bpm",
            coachScore: 84,
            notes: CoachRunNotes(
                summary: "Endurance is building without a big recovery cost.",
                effort: "The final third stayed relaxed, which is the best signal from this run.",
                recovery: "You can keep the weekly progression, but avoid adding extra intensity.",
                nextSessionNudge: "Use the next quality day for tempo, not intervals.",
                keyInsights: ["Even effort", "Good long-run discipline", "Ready for a small progression"]
            ),
            structuredNextWorkout: nil
        )
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
            let latitude = startLat + Double(i) * 0.0004
            let longitudeOffset = Double(i % 3) * 0.0003 - 0.0003
            let timestamp = Date().addingTimeInterval(TimeInterval(i * 15))
            let altitude = 22 + Double(i % 5) * 2
            return RunRoutePoint(
                latitude: latitude,
                longitude: startLon + longitudeOffset,
                timestamp: timestamp,
                horizontalAccuracy: 8,
                altitude: altitude
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

    // MARK: - Route Suggestions

    static let routeSuggestions: [RouteSuggestion] = [
        RouteSuggestion(
            id: "preview-benchmark-1",
            name: "Riverside Loop",
            distanceKm: 8.2,
            elevationGainMeters: 48,
            estimatedDurationMinutes: 44,
            points: [],
            kind: .benchmark,
            recommendationReason: "Matches today's 8 km tempo",
            savedRouteID: UUID(),
            isFavorite: true
        ),
        RouteSuggestion(
            id: "preview-saved-1",
            name: "Park Circuit",
            distanceKm: 7.8,
            elevationGainMeters: 22,
            estimatedDurationMinutes: 41,
            points: [],
            kind: .saved,
            recommendationReason: "Saved · Favorite",
            savedRouteID: UUID(),
            isFavorite: true
        ),
        RouteSuggestion(
            id: "preview-saved-2",
            name: "Harbour Promenade",
            distanceKm: 5.5,
            elevationGainMeters: 10,
            estimatedDurationMinutes: 29,
            points: [],
            kind: .past,
            recommendationReason: "Ran 3 days ago · familiar route",
            savedRouteID: nil,
            isFavorite: false
        ),
        RouteSuggestion(
            id: "preview-generated-1",
            name: "8K Loop · nearby",
            distanceKm: 8.0,
            elevationGainMeters: 31,
            estimatedDurationMinutes: 43,
            points: [],
            kind: .generated,
            recommendationReason: "Low elevation · good for pace",
            savedRouteID: nil,
            isFavorite: false
        )
    ]

    static let deviceStatuses: [ConnectedDeviceStatus] = [
        ConnectedDeviceStatus(
            provider: "Garmin Connect",
            state: .connected,
            lastSuccessfulSync: Date().addingTimeInterval(-28 * 60),
            permissions: ["Activities", "Daily health stats", "Sleep", "HRV"],
            message: "Demo connected - no Garmin account is used."
        ),
        ConnectedDeviceStatus(
            provider: "HealthKit",
            state: .connected,
            lastSuccessfulSync: Date().addingTimeInterval(-54 * 60),
            permissions: ["Workouts", "Heart Rate", "Active Energy"],
            message: "Demo connected - no HealthKit data is read or written."
        )
    ]

    // MARK: - Recorded Runs

    static var recordedRuns: [RecordedRun] {
        let calendar = Calendar.current
        let distances = [5.0, 6.2, 4.8, 8.0, 5.4, 10.2, 6.7, 7.1]
        return distances.enumerated().map { index, distanceKm in
            let start = calendar.date(byAdding: .day, value: -index * 2, to: Date()) ?? Date()
            let moving = distanceKm * 330
            let source: RunSmartDataSource = index % 3 == 0 ? .garmin : (index % 3 == 1 ? .runSmart : .healthKit)
            return RecordedRun(
                id: UUID(uuidString: String(format: "5E1B7ED0-4A0C-44D8-98E0-000000000%03d", index)) ?? UUID(),
                providerActivityID: source == .runSmart ? nil : "demo-\(source.rawValue.lowercased())-\(index)",
                source: source,
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

typealias RunSmartPreviewData = RunSmartDemoData
#endif
