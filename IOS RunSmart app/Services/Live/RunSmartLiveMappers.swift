import Foundation
import SwiftUI

enum RunSmartDTOMapper {
    static func runnerProfile(from dto: RunSmartDTO.UserProfile) -> RunnerProfile {
        RunnerProfile(
            name: dto.displayName,
            goal: dto.goal,
            streak: dto.streakLabel,
            level: dto.level,
            totalRuns: dto.stats.totalRuns,
            totalDistance: dto.stats.totalDistanceKm,
            totalTime: dto.stats.totalTimeLabel
        )
    }

    static func todayRecommendation(from dto: RunSmartDTO.TodayPayload) -> TodayRecommendation {
        TodayRecommendation(
            readiness: dto.readinessScore,
            readinessLabel: dto.readinessLabel,
            workoutTitle: dto.workoutTitle,
            distance: dto.plannedDistanceLabel,
            pace: dto.targetPaceLabel,
            elevation: dto.elevationLabel,
            coachMessage: dto.coachMessage
        )
    }

    static func workoutSummary(from dto: RunSmartDTO.WorkoutItem) -> WorkoutSummary {
        WorkoutSummary(
            weekday: dto.weekday,
            date: dto.dateLabel,
            kind: workoutKind(from: dto.kind),
            title: dto.title,
            distance: dto.distanceLabel,
            detail: dto.detailLabel,
            isToday: dto.isToday,
            isComplete: dto.isComplete
        )
    }

    static func coachMessage(from dto: RunSmartDTO.CoachChatMessage) -> CoachMessage {
        CoachMessage(
            text: dto.text,
            time: dto.timeLabel,
            isUser: dto.role.lowercased() == "user"
        )
    }

    static func metricTiles(from dto: RunSmartDTO.CurrentRunMetricsPayload) -> [MetricTile] {
        [
            MetricTile(title: "Distance", value: dto.distanceKm, unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: Color.lime),
            MetricTile(title: "Pace", value: dto.pacePerKm, unit: "/km", symbol: "timer", tint: Color.lime),
            MetricTile(title: "Time", value: dto.elapsedTime, unit: "", symbol: "stopwatch", tint: .white),
            MetricTile(title: "Heart Rate", value: dto.heartRateBPM, unit: "bpm", symbol: "heart", tint: .red)
        ]
    }

    private static func workoutKind(from rawKind: String) -> WorkoutKind {
        switch rawKind.lowercased() {
        case "easy", "easy_run":
            return .easy
        case "intervals", "interval":
            return .intervals
        case "tempo", "tempo_run":
            return .tempo
        case "strength":
            return .strength
        case "recovery":
            return .recovery
        case "long", "long_run":
            return .long
        default:
            return .easy
        }
    }
}
