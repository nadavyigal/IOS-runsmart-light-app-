import Foundation
import SwiftUI

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

    static let workouts: [WorkoutSummary] = [
        .init(weekday: "MON", date: "28", kind: .easy, title: "Easy Run", distance: "5 km", detail: "Done", isToday: false, isComplete: true),
        .init(weekday: "TUE", date: "29", kind: .intervals, title: "Intervals", distance: "8 x 400m", detail: "Done", isToday: false, isComplete: true),
        .init(weekday: "WED", date: "30", kind: .tempo, title: "Tempo Run", distance: "8.2 km", detail: "Today", isToday: true, isComplete: false),
        .init(weekday: "THU", date: "1", kind: .strength, title: "Strength", distance: "45 min", detail: "Gym", isToday: false, isComplete: false),
        .init(weekday: "FRI", date: "2", kind: .recovery, title: "Recovery", distance: "Rest", detail: "Easy", isToday: false, isComplete: false),
        .init(weekday: "SAT", date: "3", kind: .easy, title: "Easy Run", distance: "6 km", detail: "Base", isToday: false, isComplete: false),
        .init(weekday: "SUN", date: "4", kind: .long, title: "Long Run", distance: "14 km", detail: "Endurance", isToday: false, isComplete: false)
    ]

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
