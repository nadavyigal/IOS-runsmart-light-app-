import Foundation
import SwiftUI

enum RunSmartTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case plan = "Plan"
    case run = "Run"
    case profile = "Profile"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .plan: "calendar"
        case .run: "figure.run"
        case .profile: "person"
        }
    }
}

enum WorkoutKind: String {
    case easy = "Easy Run"
    case intervals = "Intervals"
    case tempo = "Tempo Run"
    case strength = "Strength"
    case recovery = "Recovery"
    case long = "Long Run"

    var symbol: String {
        switch self {
        case .easy, .intervals, .tempo, .long: "figure.run"
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

struct WorkoutSummary: Identifiable {
    let id = UUID()
    var weekday: String
    var date: String
    var kind: WorkoutKind
    var title: String
    var distance: String
    var detail: String
    var isToday: Bool
    var isComplete: Bool
}

struct TodayRecommendation {
    var readiness: Int
    var readinessLabel: String
    var workoutTitle: String
    var distance: String
    var pace: String
    var elevation: String
    var coachMessage: String
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
