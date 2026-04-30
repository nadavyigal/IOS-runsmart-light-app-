import Foundation
import SwiftUI
import CoreLocation

protocol TodayProviding {
    func todayRecommendation() async -> TodayRecommendation
}

protocol PlanProviding {
    func weeklyPlan() async -> [WorkoutSummary]
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

struct MockRunSmartServices: TodayProviding, PlanProviding, CoachChatting, ProfileProviding, RunLogging {
    func todayRecommendation() async -> TodayRecommendation {
        RunSmartPreviewData.today
    }

    func weeklyPlan() async -> [WorkoutSummary] {
        RunSmartPreviewData.workouts
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
