import Foundation
import SwiftUI
import CoreLocation

enum RunSmartTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case plan = "Plan"
    case run = "Run"
    case activity = "Activity"
    case profile = "Profile"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .plan: "calendar"
        case .run: "figure.run"
        case .activity: "chart.bar.xaxis"
        case .profile: "person"
        }
    }

    var filledSymbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .plan: "calendar.badge.clock"
        case .run: "figure.run.circle.fill"
        case .activity: "chart.bar.xaxis"
        case .profile: "person.fill"
        }
    }
}

enum WorkoutKind: String, Hashable {
    case easy = "Easy Run"
    case intervals = "Intervals"
    case tempo = "Tempo Run"
    case hills = "Hills"
    case strength = "Strength"
    case recovery = "Recovery"
    case long = "Long Run"
    case race = "Race"
    case parkrun = "parkrun"

    var symbol: String {
        switch self {
        case .easy, .intervals, .tempo, .long, .race, .parkrun: "figure.run"
        case .hills: "mountain.2"
        case .strength: "dumbbell"
        case .recovery: "heart"
        }
    }
}

struct RunnerProfile {
    var name: String
    var goal: String
    var streak: String
    var level: String
    var totalRuns: Int
    var totalDistance: Int
    var totalTime: String
}

struct WorkoutSummary: Identifiable, Hashable {
    let id: UUID
    var scheduledDate: Date
    var planID: UUID?
    var weekday: String
    var date: String
    var kind: WorkoutKind
    var title: String
    var distance: String
    var detail: String
    var isToday: Bool
    var isComplete: Bool
    var durationMinutes: Int?
    var targetPaceSecondsPerKm: Int?
    var intensity: String?
    var trainingPhase: String?
    var workoutStructure: String?
}

struct TrainingPlanSnapshot: Identifiable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var totalWeeks: Int
    var planType: String
}

struct TodayRecommendation {
    var readiness: Int
    var readinessLabel: String
    var workoutTitle: String
    var distance: String
    var pace: String
    var elevation: String
    var coachMessage: String
    var weeklyProgress: String = "--"
    var streak: String = "--"
    var recovery: String = "--"
    var hrv: String = "--"
}

struct MetricTile: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var unit: String
    var symbol: String
    var tint: Color
}

struct CoachMessage: Identifiable {
    let id = UUID()
    var text: String
    var time: String
    var isUser: Bool
}

struct Achievement: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
}

enum RunSmartDataSource: String, Codable {
    case runSmart = "RunSmart"
    case garmin = "Garmin"
    case healthKit = "HealthKit"
}

struct RunRoutePoint: Identifiable, Codable, Hashable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double
    var altitude: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RecordedRun: Identifiable, Codable, Hashable {
    var id: UUID
    var providerActivityID: String?
    var source: RunSmartDataSource
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    var movingTimeSeconds: TimeInterval
    var averagePaceSecondsPerKm: Double
    var averageHeartRateBPM: Int?
    var routePoints: [RunRoutePoint]
    var syncedAt: Date?
}

enum RouteKind: String, Codable, Hashable {
    case past
    case generated
}

struct RouteSuggestion: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var distanceKm: Double
    var elevationGainMeters: Int
    var estimatedDurationMinutes: Int
    var points: [RunRoutePoint]
    var kind: RouteKind
}

struct OnboardingProfile: Codable, Equatable {
    var displayName: String
    var goal: String
    var experience: String
    var weeklyRunDays: Int
    var preferredDays: [String]
    var units: String
    var coachingTone: String
    var notificationsEnabled: Bool

    static let empty = OnboardingProfile(
        displayName: "",
        goal: "10K improvement",
        experience: "Building base",
        weeklyRunDays: 4,
        preferredDays: ["Tue", "Thu", "Sat", "Sun"],
        units: "Metric",
        coachingTone: "Motivating",
        notificationsEnabled: false
    )
}

enum DeviceConnectionState: String, Codable {
    case disconnected
    case connecting
    case connected
    case error
}

struct ConnectedDeviceStatus: Identifiable, Codable, Hashable {
    var id: String { provider }
    var provider: String
    var state: DeviceConnectionState
    var lastSuccessfulSync: Date?
    var permissions: [String]
    var message: String?
}

enum RunRecordingPhase: String {
    case idle
    case requestingPermission
    case ready
    case recording
    case paused
    case denied
    case failed
}

struct GoalSummary: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var progress: Double
    var target: String
    var daysRemaining: Int?
    var trendLabel: String
}

struct ChallengeSummary: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var progress: Double
    var dayLabel: String
    var isActive: Bool
}

struct RecoverySnapshot: Hashable {
    var readiness: Int
    var bodyBattery: Int
    var sleep: String
    var hrv: String
    var stress: String
    var recommendation: String
}

struct WellnessSnapshot: Hashable {
    var calories: String
    var hydration: String
    var soreness: String
    var mood: String
    var checkInStatus: String
}

struct ShoeSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var distanceKm: Double
    var limitKm: Double
    var status: String
}

struct ReminderPreference: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var enabled: Bool
}

struct RunReportSummary: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var dateLabel: String
    var distance: String
    var pace: String
    var score: Int
    var insight: String
    var source: String = ""
    var runID: String? = nil
    var duration: String = "—"
    var averageHeartRate: String = "—"
}

struct CoachRunNotes: Codable, Hashable {
    var summary: String
    var effort: String
    var recovery: String
    var nextSessionNudge: String
}

struct StructuredNextWorkout: Codable, Hashable {
    var title: String
    var dateLabel: String?
    var distance: String?
    var target: String?
    var notes: String?
}

struct RunReportDetail: Identifiable, Codable, Hashable {
    var id: String
    var runID: String
    var title: String
    var dateLabel: String
    var source: String
    var distance: String
    var duration: String
    var averagePace: String
    var averageHeartRate: String
    var coachScore: Int?
    var notes: CoachRunNotes
    var structuredNextWorkout: StructuredNextWorkout?

    var summary: RunReportSummary {
        RunReportSummary(
            id: id,
            title: title,
            dateLabel: dateLabel,
            distance: distance,
            pace: averagePace,
            score: coachScore ?? 0,
            insight: notes.summary,
            source: source,
            runID: runID,
            duration: duration,
            averageHeartRate: averageHeartRate
        )
    }
}

struct TrainingLoadSnapshot: Hashable {
    var loadLabel: String
    var loadValue: Int
    var acwr: String
    var consistency: Int
    var paceTrend: String
    var weeklyRecap: String
}

struct ShareableAchievement: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var symbol: String
    var tintName: String
}

extension GoalSummary {
    static let loading = GoalSummary(id: "", title: "—", detail: "", progress: 0, target: "—", daysRemaining: nil, trendLabel: "—")
}

extension ChallengeSummary {
    static let loading = ChallengeSummary(id: "", title: "—", detail: "", progress: 0, dayLabel: "—", isActive: false)
}

extension RecoverySnapshot {
    static let loading = RecoverySnapshot(readiness: 0, bodyBattery: 0, sleep: "—", hrv: "—", stress: "—", recommendation: "Loading recovery data…")
}

extension WellnessSnapshot {
    static let empty = WellnessSnapshot(calories: "—", hydration: "—", soreness: "—", mood: "—", checkInStatus: "No wellness check-in yet.")
}

extension TrainingLoadSnapshot {
    static let loading = TrainingLoadSnapshot(loadLabel: "—", loadValue: 0, acwr: "—", consistency: 0, paceTrend: "—", weeklyRecap: "Loading training data…")
}
