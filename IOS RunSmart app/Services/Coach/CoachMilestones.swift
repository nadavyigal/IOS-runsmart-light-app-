import Foundation

// C7.16 Beginner milestones (MVP FR-20b, decision D13). "Coach" means a HUMAN coach (Coach Mode).
//
// Pure logic, no network. Milestones are worked out on the phone from the planned-workout read
// (`coach_get_athletes_workouts`, Epic 0 `completed`), so they come from completed workouts and not
// from raw runs (AC5). The runs read only supplies the run id a praise note is attached to.
// No migration: both reads already take any date range (STEP 1 check, see the PR body).

nonisolated enum CoachMilestoneKind: String, CaseIterable, Sendable {
    case firstRun = "first_run"
    case firstFullWeek = "first_full_week"
    case longestRun = "longest_run"
    /// Coach-only (AC2): never shown to the athlete, never sends a message.
    case quiet3Days = "quiet_3_days"

    var tag: String {
        switch self {
        case .firstRun: "First run"
        case .firstFullWeek: "First full week"
        case .longestRun: "Longest run"
        case .quiet3Days: "Quiet 3 days"
        }
    }

    var icon: String {
        switch self {
        case .firstRun: "figure.run"
        case .firstFullWeek: "calendar.badge.checkmark"
        case .longestRun: "arrow.up.right"
        case .quiet3Days: "moon.zzz"
        }
    }

    /// Quiet 3 days is a signal for the coach, not a moment to praise.
    var canPraise: Bool { self != .quiet3Days }
}

/// The three one-tap reactions. The text is saved as coach feedback exactly as written here.
nonisolated enum CoachReaction: String, CaseIterable, Identifiable, Sendable {
    case clap, fire, greatJob

    var id: String { rawValue }

    var text: String {
        switch self {
        case .clap: "👏"
        case .fire: "🔥"
        case .greatJob: "Great job"
        }
    }

    /// What VoiceOver reads for the button.
    var spoken: String {
        switch self {
        case .clap: "clapping hands"
        case .fire: "fire"
        case .greatJob: "Great job"
        }
    }
}

nonisolated struct CoachMilestone: Identifiable, Equatable, Sendable {
    let athleteID: UUID
    let kind: CoachMilestoneKind
    /// What the milestone is about, stable across refreshes: the workout id, or the week's first day.
    let subject: String
    /// Where a reaction is saved: the run (`runs.id`) or, when no run is known, the week. Nil for Quiet 3 days.
    let target: CoachFeedbackTarget?
    /// The workout's week, used when the run is gone by the time the reaction is sent.
    let fallbackTarget: CoachFeedbackTarget?
    var id: String { "\(athleteID.uuidString.lowercased())|\(kind.rawValue)|\(subject)" }
}

enum CoachMilestoneRules {
    /// A praise milestone stays on Today for this many days (today included), then disappears.
    static let recentDays = 7
    /// "Quiet 3 days": this many whole days before the missed cutoff with no planned workout done.
    static let quietDays = 3
    /// A "full week" needs at least this many workouts, so a one-run week is not a first full week.
    static let minimumWeekWorkouts = 2
    /// A longest run needs this many earlier completed workouts, so the first few runs are not all records.
    static let minimumEarlierWorkouts = 3

    /// Milestones per athlete, only for athletes that have one.
    /// - Parameters:
    ///   - workouts: every planned workout the coach can read, past and present (rest rows included).
    ///   - runs: runs from the recent window. Only used to find the run a workout was done in.
    static func milestones(
        athletes: [CoachAthleteSummary], workouts: [CoachWorkoutSummary], runs: [CoachRunSummary],
        now: Date, week: CoachAthleteWeek
    ) -> [UUID: [CoachMilestone]] {
        let calendar = week.calendar
        let workoutsByAthlete = Dictionary(grouping: workouts.filter(WorkoutAdherence.counts), by: \.athleteID)
        let runsByWorkout = Dictionary(
            runs.compactMap { run in run.workoutID.map { ($0, run) } }, uniquingKeysWith: { first, second in
                // Two runs for one workout: the earlier one is the run that did it.
                first.completedAt <= second.completedAt ? first : second
            }
        )
        let todayStart = calendar.startOfDay(for: now)
        let recentStart = calendar.date(byAdding: .day, value: -(recentDays - 1), to: todayStart)!
        let boundary = WorkoutAdherence.missedBoundary(now: now, calendar: calendar)

        func weekStartISO(_ iso: String) -> String? {
            guard let date = day(iso, calendar: calendar),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
            return CoachReadDay.iso(interval.start, calendar: calendar)
        }

        var result: [UUID: [CoachMilestone]] = [:]
        for athlete in athletes {
            let id = athlete.athleteID
            let counted = workoutsByAthlete[id, default: []]
            let linkDay = CoachReadDay.iso(athlete.linkedAt, calendar: calendar)
            var found: [CoachMilestone] = []

            // Completed workouts in the order they were done.
            let done: [(workout: CoachWorkoutSummary, at: Date)] = counted.compactMap { workout in
                guard workout.completed else { return nil }
                guard let at = workout.completedAt ?? day(workout.scheduledDate, calendar: calendar) else { return nil }
                return (workout, at)
            }
            .sorted { ($0.at, $0.workout.id.uuidString) < ($1.at, $1.workout.id.uuidString) }

            func runMilestone(_ kind: CoachMilestoneKind, _ workout: CoachWorkoutSummary) -> CoachMilestone {
                let weekTarget = weekStartISO(workout.scheduledDate).map(CoachFeedbackTarget.week)
                let target = runsByWorkout[workout.id].map { CoachFeedbackTarget.run(Int64($0.id)) } ?? weekTarget
                return CoachMilestone(
                    athleteID: id, kind: kind, subject: workout.id.uuidString.lowercased(),
                    target: target, fallbackTarget: weekTarget
                )
            }

            // First run: the earliest completed workout, while it is recent.
            if let first = done.first, first.at >= recentStart {
                found.append(runMilestone(.firstRun, first.workout))
            }

            // Longest run: the latest record, once there are enough earlier workouts to compare with.
            var best = 0.0
            var record: Int?
            for (index, item) in done.enumerated() {
                guard let km = item.workout.actualDistanceKm, km > 0 else { continue }
                if km > best {
                    if index >= minimumEarlierWorkouts, best > 0 { record = index }
                    best = km
                }
            }
            if let record, done[record].at >= recentStart {
                found.append(runMilestone(.longestRun, done[record].workout))
            }

            // First full week: the earliest week of this coach's plan with every workout done.
            let coached = counted.filter { $0.scheduledDate >= linkDay }
            let weeks = Dictionary(grouping: coached) { weekStartISO($0.scheduledDate) ?? "" }
            let fullWeeks = weeks.filter { key, items in
                !key.isEmpty && items.count >= minimumWeekWorkouts && items.allSatisfy(\.completed)
            }
            if let start = fullWeeks.keys.min(), let items = fullWeeks[start] {
                let finished = items.compactMap { $0.completedAt ?? day($0.scheduledDate, calendar: calendar) }.max()
                if let finished, finished >= recentStart {
                    found.append(CoachMilestone(
                        athleteID: id, kind: .firstFullWeek, subject: start,
                        target: .week(start), fallbackTarget: .week(start)
                    ))
                }
            }

            // Quiet 3 days: workouts were due in the last 3 whole days, and the athlete did none of them,
            // nor anything else from the plan. Rest days alone never make an athlete quiet. A new athlete
            // is not quiet before they have had 3 days with this coach.
            if athlete.hasActivePlan, let boundaryDate = day(boundary, calendar: calendar),
               let windowStart = calendar.date(byAdding: .day, value: -quietDays, to: boundaryDate) {
                let startISO = CoachReadDay.iso(windowStart, calendar: calendar)
                let due = counted.filter { $0.scheduledDate >= startISO && $0.scheduledDate < boundary }
                let didAnything = counted.contains { ($0.completedAt ?? .distantPast) >= windowStart }
                if startISO >= linkDay, !due.isEmpty, !didAnything, due.allSatisfy({ !$0.completed }) {
                    found.append(CoachMilestone(
                        athleteID: id, kind: .quiet3Days, subject: "quiet", target: nil, fallbackTarget: nil
                    ))
                }
            }

            if !found.isEmpty {
                let order = CoachMilestoneKind.allCases
                result[id] = found.sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
            }
        }
        return result
    }

    /// `yyyy-MM-dd` to the start of that day in `calendar`'s time zone.
    static func day(_ iso: String, calendar: Calendar) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
