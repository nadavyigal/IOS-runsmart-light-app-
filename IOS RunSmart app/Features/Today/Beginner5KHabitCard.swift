import SwiftUI

enum HabitState: Equatable {
    case onTrack
    case restDay
    case missedRecently
    case weekComplete
}

struct Beginner5KHabitTrack {
    let currentWeek: Int
    let totalWeeks: Int
    let completedThisWeek: Int
    let plannedThisWeek: Int
    let state: HabitState
    let progressLabel: String
    let confidenceLabel: String
    let nextActionTitle: String
    let nextActionDetail: String

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

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
        let advancedGoals = ["10K PR", "Half Marathon", "Marathon", "Get Faster"]
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
                    dayLabel = Beginner5KHabitTrack.weekdayFormatter.string(from: next.scheduledDate)
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

struct Beginner5KHabitCard: View {
    var track: Beginner5KHabitTrack

    private var accentColor: Color {
        switch track.state {
        case .restDay:        return .accentRecovery
        case .missedRecently: return .accentAmber
        case .weekComplete:   return .accentSuccess
        case .onTrack:        return .accentPrimary
        }
    }

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 16, accent: accentColor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 34, height: 34)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FIRST 5K")
                            .font(.labelSM)
                            .tracking(1.6)
                            .foregroundStyle(Color.textSecondary)
                        Text(track.progressLabel)
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 0)

                    SessionDots(completed: track.completedThisWeek, total: track.plannedThisWeek, tint: accentColor)
                }

                Text(track.stateMessage)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.nextActionTitle)
                            .font(.bodyMD.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Text(track.nextActionDetail)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(track.confidenceLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(accentColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(accentColor.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }
}

private struct SessionDots: View {
    var completed: Int
    var total: Int
    var tint: Color

    var body: some View {
        let displayTotal = max(total, 1)
        HStack(spacing: 5) {
            ForEach(0..<displayTotal, id: \.self) { index in
                Circle()
                    .fill(index < completed ? tint : tint.opacity(0.22))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(tint.opacity(index < completed ? 0 : 0.5), lineWidth: 1))
            }
        }
    }
}
