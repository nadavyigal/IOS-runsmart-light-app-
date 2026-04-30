import Foundation
import SwiftUI
import CoreLocation

protocol TodayProviding {
    func todayRecommendation() async -> TodayRecommendation
}

protocol PlanProviding {
    func weeklyPlan() async -> [WorkoutSummary]
    func activeTrainingPlan() async -> TrainingPlanSnapshot?
    func planWorkouts(from startDate: Date, to endDate: Date) async -> [WorkoutSummary]
    func nextWorkouts(limit: Int) async -> [WorkoutSummary]
}

protocol CoachChatting {
    func recentMessages() async -> [CoachMessage]
    func send(message: String) async -> CoachMessage
}

protocol ProfileProviding {
    func runnerProfile() async -> RunnerProfile
    func achievements() async -> [Achievement]
}

protocol RunLogging {
    func currentRunMetrics() async -> [MetricTile]
    func recentRuns() async -> [RecordedRun]
    func saveManualRun(kind: WorkoutKind, date: Date, distanceKm: Double, durationMinutes: Int, averageHeartRateBPM: Int?, notes: String) async -> RecordedRun
    func finishRun() async
}

protocol WebParityProviding {
    func activeGoal() async -> GoalSummary
    func activeChallenge() async -> ChallengeSummary
    func recoverySnapshot() async -> RecoverySnapshot
    func wellnessSnapshot() async -> WellnessSnapshot
    func shoes() async -> [ShoeSummary]
    func reminders() async -> [ReminderPreference]
    func latestRunReports() async -> [RunReportSummary]
    func trainingLoadSnapshot() async -> TrainingLoadSnapshot
    func shareableAchievements() async -> [ShareableAchievement]
}

extension WebParityProviding {
    func activeGoal() async -> GoalSummary { RunSmartPreviewData.activeGoal }
    func activeChallenge() async -> ChallengeSummary { RunSmartPreviewData.activeChallenge }
    func recoverySnapshot() async -> RecoverySnapshot { RunSmartPreviewData.recovery }
    func wellnessSnapshot() async -> WellnessSnapshot { RunSmartPreviewData.wellness }
    func shoes() async -> [ShoeSummary] { RunSmartPreviewData.shoes }
    func reminders() async -> [ReminderPreference] { RunSmartPreviewData.reminders }
    func latestRunReports() async -> [RunReportSummary] { RunSmartPreviewData.runReports }
    func trainingLoadSnapshot() async -> TrainingLoadSnapshot { RunSmartPreviewData.trainingLoad }
    func shareableAchievements() async -> [ShareableAchievement] { RunSmartPreviewData.shareableAchievements }
}

struct MockRunSmartServices: TodayProviding, PlanProviding, CoachChatting, ProfileProviding, RunLogging {
    func todayRecommendation() async -> TodayRecommendation {
        RunSmartPreviewData.today
    }

    func weeklyPlan() async -> [WorkoutSummary] {
        RunSmartPreviewData.workouts
    }

    func activeTrainingPlan() async -> TrainingPlanSnapshot? { nil }

    func planWorkouts(from startDate: Date, to endDate: Date) async -> [WorkoutSummary] {
        RunSmartPreviewData.workouts.filter {
            $0.scheduledDate >= startDate && $0.scheduledDate <= endDate
        }
    }

    func nextWorkouts(limit: Int) async -> [WorkoutSummary] {
        Array(RunSmartPreviewData.workouts.prefix(limit))
    }

    func recentMessages() async -> [CoachMessage] {
        RunSmartPreviewData.coachMessages
    }

    func send(message: String) async -> CoachMessage {
        CoachMessage(text: message, time: "Just now", isUser: true)
    }

    func runnerProfile() async -> RunnerProfile {
        RunSmartPreviewData.runner
    }

    func achievements() async -> [Achievement] {
        RunSmartPreviewData.achievements
    }

    func currentRunMetrics() async -> [MetricTile] {
        [
            MetricTile(title: "Distance", value: "5.24", unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: Color.lime),
            MetricTile(title: "Pace", value: "5:08", unit: "/km", symbol: "timer", tint: Color.lime),
            MetricTile(title: "Time", value: "26:54", unit: "", symbol: "stopwatch", tint: .white),
            MetricTile(title: "Heart Rate", value: "154", unit: "bpm", symbol: "heart", tint: .red)
        ]
    }

    func recentRuns() async -> [RecordedRun] {
        RunSmartPreviewData.recordedRuns
    }

    func saveManualRun(kind: WorkoutKind, date: Date, distanceKm: Double, durationMinutes: Int, averageHeartRateBPM: Int?, notes: String) async -> RecordedRun {
        let movingTime = TimeInterval(max(1, durationMinutes) * 60)
        let distanceMeters = max(0.1, distanceKm) * 1_000
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: date,
            endedAt: date.addingTimeInterval(movingTime),
            distanceMeters: distanceMeters,
            movingTimeSeconds: movingTime,
            averagePaceSecondsPerKm: movingTime / max(distanceKm, 0.1),
            averageHeartRateBPM: averageHeartRateBPM,
            routePoints: [],
            syncedAt: nil
        )
    }

    func finishRun() async {}

    func routeSuggestions() async -> [RouteSuggestion] {
        []
    }

    func nearbyLoopRoutes(around coordinate: CLLocationCoordinate2D, distancesKm: [Double]) async -> [RouteSuggestion] {
        []
    }

    func deviceStatuses() async -> [ConnectedDeviceStatus] {
        [
            ConnectedDeviceStatus(provider: "Garmin Connect", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: "Preview only"),
            ConnectedDeviceStatus(provider: "HealthKit", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: "Preview only")
        ]
    }

    func connect(provider: String) async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: provider, state: .connected, lastSuccessfulSync: Date(), permissions: ["Preview"], message: "Preview connected")
    }

    func syncNow(provider: String) async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: provider, state: .connected, lastSuccessfulSync: Date(), permissions: ["Preview"], message: "Preview synced")
    }

    func disconnect(provider: String) async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: provider, state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: "Preview disconnected")
    }

    func requestHealthAccess() async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: "HealthKit", state: .connected, lastSuccessfulSync: nil, permissions: ["Preview"], message: "Preview HealthKit")
    }

    func saveToHealth(_ run: RecordedRun) async {}
}
