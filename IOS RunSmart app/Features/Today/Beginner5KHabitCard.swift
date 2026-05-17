import Foundation

enum HabitState: Equatable {
    case onTrack
    case restDay
    case missedRecently
    case weekComplete
}

struct Beginner5KHabitTrack {
    var currentWeek: Int
    var totalWeeks: Int
    var completedThisWeek: Int
    var plannedThisWeek: Int
    var state: HabitState
    var progressLabel: String
    var confidenceLabel: String
    var nextActionTitle: String
    var nextActionDetail: String

    var stateMessage: String {
        switch state {
        case .onTrack:        return "Keep building. Every run counts."
        case .restDay:        return "Rest is training. Your body is adapting right now."
        case .missedRecently: return "Life happens. This week can still count."
        case .weekComplete:   return "Week done. You're making it real."
        }
    }

    // MARK: - Detection

    static func isBeginnerFirst5K(profile: OnboardingProfile) -> Bool {
        if profile.goal == "First 5K" { return true }
        let advancedGoals = ["10K PR", "Half Marathon", "Marathon"]
        if advancedGoals.contains(profile.goal) { return false }
        return profile.experience == "Getting started"
    }

    // MARK: - Factory

    static func make(
        weekWorkouts: [WorkoutSummary],
        activePlan: TrainingPlanSnapshot?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Beginner5KHabitTrack {
        let runningWorkouts = weekWorkouts.filter { isRunningWorkout($0) }
        let completedThisWeek = runningWorkouts.filter { $0.isComplete }.count
        let plannedThisWeek = runningWorkouts.count

        let totalWeeks = activePlan?.totalWeeks ?? 8
        let currentWeek: Int
        if let plan = activePlan {
            let components = calendar.dateComponents(
                [.weekOfYear],
                from: calendar.startOfDay(for: plan.startDate),
                to: calendar.startOfDay(for: now)
            )
            currentWeek = max(1, min((components.weekOfYear ?? 0) + 1, totalWeeks))
        } else {
            currentWeek = 1
        }

        let state = resolveState(
            runningWorkouts: runningWorkouts,
            completedThisWeek: completedThisWeek,
            plannedThisWeek: plannedThisWeek,
            weekWorkouts: weekWorkouts,
            now: now,
            calendar: calendar
        )

        let progressLabel: String
        if plannedThisWeek == 0 {
            progressLabel = "Week \(currentWeek) of \(totalWeeks)"
        } else {
            progressLabel = "Week \(currentWeek) of \(totalWeeks) · \(completedThisWeek) of \(plannedThisWeek) runs done"
        }

        let confidenceLabel: String
        if plannedThisWeek > 0 && completedThisWeek == plannedThisWeek {
            confidenceLabel = "Great week"
        } else if completedThisWeek >= 2 {
            confidenceLabel = "Staying consistent"
        } else {
            confidenceLabel = "Building fitness"
        }

        let nextActionTitle: String
        let nextActionDetail: String
        switch state {
        case .restDay:
            nextActionTitle = "Rest today"
            nextActionDetail = "Recovery is part of the plan. Your next run is coming up."
        case .missedRecently:
            nextActionTitle = "Get back out there"
            nextActionDetail = "A gentle run today still counts toward your 5K."
        case .weekComplete:
            nextActionTitle = "Week complete"
            nextActionDetail = "Rest up and prepare for next week."
        case .onTrack:
            let upcoming = runningWorkouts
                .filter { !$0.isComplete && $0.scheduledDate >= calendar.startOfDay(for: now) }
                .sorted { $0.scheduledDate < $1.scheduledDate }
                .first
            if let next = upcoming {
                let dayLabel: String
                if calendar.isDateInToday(next.scheduledDate) {
                    dayLabel = "today"
                } else if calendar.isDateInTomorrow(next.scheduledDate) {
                    dayLabel = "tomorrow"
                } else {
                    let f = DateFormatter()
                    f.dateFormat = "EEEE"
                    dayLabel = f.string(from: next.scheduledDate)
                }
                nextActionTitle = "Run \(dayLabel)"
                nextActionDetail = "\(next.title) · \(next.distance)"
            } else {
                nextActionTitle = "Keep going"
                nextActionDetail = "Check your plan for the next session."
            }
        }

        return Beginner5KHabitTrack(
            currentWeek: currentWeek,
            totalWeeks: totalWeeks,
            completedThisWeek: completedThisWeek,
            plannedThisWeek: plannedThisWeek,
            state: state,
            progressLabel: progressLabel,
            confidenceLabel: confidenceLabel,
            nextActionTitle: nextActionTitle,
            nextActionDetail: nextActionDetail
        )
    }

    // MARK: - Private helpers

    private static func resolveState(
        runningWorkouts: [WorkoutSummary],
        completedThisWeek: Int,
        plannedThisWeek: Int,
        weekWorkouts: [WorkoutSummary],
        now: Date,
        calendar: Calendar
    ) -> HabitState {
        if plannedThisWeek > 0 && completedThisWeek == plannedThisWeek {
            return .weekComplete
        }
        let hasMissed = runningWorkouts.contains {
            !$0.isComplete &&
            calendar.startOfDay(for: $0.scheduledDate) < calendar.startOfDay(for: now)
        }
        if hasMissed { return .missedRecently }
        let hasTodayRun = runningWorkouts.contains {
            calendar.isDate($0.scheduledDate, inSameDayAs: now)
        }
        if !hasTodayRun { return .restDay }
        return .onTrack
    }

    private static func isRunningWorkout(_ workout: WorkoutSummary) -> Bool {
        switch workout.kind {
        case .strength, .recovery: return false
        default: return true
        }
    }
}
