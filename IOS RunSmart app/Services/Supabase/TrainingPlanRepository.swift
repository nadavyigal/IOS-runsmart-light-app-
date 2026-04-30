import Foundation
import Supabase
import SwiftUI

// MARK: - Active plan bundle

struct ActivePlan {
    let plan: DBPlan
    let workouts: [DBWorkout]

    var todayWorkout: DBWorkout? {
        let todayDate = ISO8601DateFormatter.shortDate.string(from: Date())
        return workouts.first { $0.scheduledDate == todayDate && !$0.completed }
            ?? workouts.first { $0.scheduledDate == todayDate }
    }

    var currentWeekWorkouts: [DBWorkout] {
        let calendar = Calendar.current
        let today = Date()
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today)
        return workouts.filter { w in
            guard let date = w.scheduledDateAsDate else { return false }
            return weekInterval?.contains(date) == true
        }
    }

    var completedKmThisWeek: Double {
        currentWeekWorkouts.filter { $0.completed }.reduce(0) { $0 + $1.distance }
    }

    var totalKmThisWeek: Double {
        currentWeekWorkouts.reduce(0) { $0 + $1.distance }
    }
}

extension DBWorkout {
    var scheduledDateAsDate: Date? {
        ISO8601DateFormatter.shortDate.date(from: scheduledDate)
    }
}

extension ISO8601DateFormatter {
    static let shortDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}

// MARK: - Repository

final class TrainingPlanRepository {
    private let supabase = SupabaseManager.client

    func activePlan(profileID: UUID) async -> ActivePlan? {
        do {
            let plans: [DBPlan] = try await supabase
                .from("plans")
                .select()
                .eq("profile_id", value: profileID.uuidString)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value

            guard let plan = plans.first else { return nil }

            let workouts: [DBWorkout] = try await supabase
                .from("workouts")
                .select()
                .eq("plan_id", value: plan.id.uuidString)
                .order("scheduled_date")
                .execute()
                .value

            return ActivePlan(plan: plan, workouts: workouts)
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] error:", error)
            }
            return nil
        }
    }
}

// MARK: - DBWorkout → WorkoutSummary

extension DBWorkout {
    func toWorkoutSummary() -> WorkoutSummary {
        let date = scheduledDateAsDate ?? Date()
        let calendar = Calendar.current
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        let dayNum = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)

        return WorkoutSummary(
            weekday: weekday,
            date: "\(dayNum)",
            kind: workoutKind,
            title: workoutTitle,
            distance: String(format: "%.1f km", distance),
            detail: notes ?? "",
            isToday: isToday,
            isComplete: completed
        )
    }

    var workoutKind: WorkoutKind {
        switch type {
        case "easy": return .easy
        case "tempo", "race-pace", "fartlek": return .tempo
        case "intervals": return .intervals
        case "hill", "hills": return .hills
        case "long": return .long
        case "race": return .race
        case "parkrun": return .parkrun
        case "recovery", "rest": return .recovery
        default: return .easy
        }
    }

    var workoutTitle: String {
        switch type {
        case "easy": return String(format: "Easy %.0f km", distance)
        case "tempo": return String(format: "Tempo %.0f km", distance)
        case "race-pace": return String(format: "Race Pace %.0f km", distance)
        case "intervals": return "Interval Session"
        case "hill": return "Hill Repeats"
        case "long": return String(format: "Long Run %.0f km", distance)
        case "recovery": return "Recovery Run"
        case "rest": return "Rest Day"
        case "fartlek": return "Fartlek Run"
        default: return type.capitalized
        }
    }

    var paceLabel: String {
        guard let paceSeconds = pace, paceSeconds > 0 else { return "--:--" }
        let mins = paceSeconds / 60
        let secs = paceSeconds % 60
        return String(format: "%d:%02d", Int32(mins), Int32(secs))
    }
}
