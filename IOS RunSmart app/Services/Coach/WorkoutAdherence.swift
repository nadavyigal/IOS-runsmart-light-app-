import Foundation

enum WorkoutAdherence: Equatable {
    case done, partial, missed, planned, extra

    static func classify(workout: CoachWorkoutSummary, run: CoachRunSummary?, today: String) -> Self {
        guard let run, run.workoutID == workout.id, run.athleteID == workout.athleteID else {
            return workout.scheduledDate < today ? .missed : .planned
        }
        return measure(workout: workout, run: run)
    }

    /// The 80% rule only: planned distance when set, otherwise planned duration.
    /// Callers decide whether the run belongs to the workout.
    static func measure(workout: CoachWorkoutSummary, run: CoachRunSummary) -> Self {
        if workout.plannedDistance > 0 {
            return run.distanceKm >= workout.plannedDistance * 0.8 ? .done : .partial
        }
        if let minutes = workout.plannedDurationMinutes, minutes > 0 {
            return Double(run.durationSeconds) >= Double(minutes) * 60 * 0.8 ? .done : .partial
        }
        return .done
    }

    /// One workout's state from all runs linked to it. Any done run wins; otherwise the first linked run.
    static func state(workout: CoachWorkoutSummary, linkedRuns: [CoachRunSummary], today: String) -> Self {
        let states = linkedRuns.map { classify(workout: workout, run: $0, today: today) }
        return states.contains(.done) ? .done : states.first ?? classify(workout: workout, run: nil, today: today)
    }

    static func classify(run: CoachRunSummary) -> Self? {
        run.workoutID == nil ? .extra : nil
    }

    /// Rest days are stored as workout rows with `type = "rest"`. They are not workouts to complete,
    /// so they never count as planned, done or missed.
    static func counts(_ workout: CoachWorkoutSummary) -> Bool {
        workout.type.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("rest") != .orderedSame
    }

    /// C7.1, UX spec A.3: a workout counts as missed once its day is over, or once today passes
    /// 20:00. The cutoff is read in `calendar`'s time zone. Pass the result as `today` to `classify`
    /// and `state`: before the cutoff it is today's date, after it is tomorrow's.
    static let missedCutoffHour = 20

    static func missedBoundary(now: Date, calendar: Calendar, cutoffHour: Int = missedCutoffHour) -> String {
        guard calendar.component(.hour, from: now) >= cutoffHour,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
            return CoachReadDay.iso(now, calendar: calendar)
        }
        return CoachReadDay.iso(tomorrow, calendar: calendar)
    }

    static func isBehind(_ results: [(date: String, state: Self)], today: String) -> Bool {
        let past = results.filter { $0.date < today }
        return !past.isEmpty && !past.contains { $0.state == .done || $0.state == .partial }
    }
}

struct CoachAthleteWeek {
    let calendar: Calendar
    let interval: DateInterval

    init(now: Date, locale: Locale = .current, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = locale.region?.identifier == "IL" ? 1 : 2
        self.calendar = calendar
        interval = calendar.dateInterval(of: .weekOfYear, for: now)!
    }

    var lastDay: Date { calendar.date(byAdding: .day, value: -1, to: interval.end)! }

    func contains(_ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }
}

struct CoachAthleteRow: Identifiable, Equatable {
    enum Status: String, CaseIterable {
        case behind = "Behind"
        case onTrack = "On track"
        case noPlan = "No plan yet"
        case joining = "Joining"

        var sortRank: Int {
            switch self {
            case .behind: 0
            case .onTrack: 1
            case .joining: 2
            case .noPlan: 3
            }
        }
    }

    let athlete: CoachAthleteSummary
    let status: Status
    let done: Int
    let planned: Int
    let missed: Int
    let lastRun: Date?
    var id: UUID { athlete.athleteID }

    static func make(
        athletes: [CoachAthleteSummary], workouts: [CoachWorkoutSummary],
        runs: [CoachRunSummary], latest: [UUID: Date], now: Date, week: CoachAthleteWeek
    ) -> [Self] {
        let today = CoachReadDay.iso(now, calendar: week.calendar)
        let workoutsByAthlete = Dictionary(grouping: workouts.filter(WorkoutAdherence.counts), by: \.athleteID)
        let runsByAthlete = Dictionary(grouping: runs, by: \.athleteID)
        return athletes.map { athlete in
            let athleteRuns = runsByAthlete[athlete.athleteID, default: []]
            let linkedRuns = Dictionary(grouping: athleteRuns, by: \.workoutID)
            let results = workoutsByAthlete[athlete.athleteID, default: []].map { workout in
                let state = WorkoutAdherence.state(
                    workout: workout, linkedRuns: linkedRuns[workout.id, default: []], today: today
                )
                return (date: workout.scheduledDate, state: state)
            }
            let status: Status
            if !athlete.hasActivePlan {
                status = (0..<600).contains(now.timeIntervalSince(athlete.linkedAt)) ? .joining : .noPlan
            } else {
                status = WorkoutAdherence.isBehind(results, today: today) ? .behind : .onTrack
            }
            return Self(
                athlete: athlete, status: status,
                done: results.count { $0.state == .done }, planned: results.count,
                missed: results.count { $0.state == .missed },
                lastRun: latest[athlete.athleteID] ?? athleteRuns.map(\.completedAt).max()
            )
        }.sorted { lhs, rhs in
            // Status group first, so the order is consistent across groups.
            if lhs.status.sortRank != rhs.status.sortRank { return lhs.status.sortRank < rhs.status.sortRank }
            if lhs.status == .behind {
                if lhs.missed != rhs.missed { return lhs.missed > rhs.missed }
                let lhsDay = lhs.lastRun.map { week.calendar.startOfDay(for: $0) } ?? .distantPast
                let rhsDay = rhs.lastRun.map { week.calendar.startOfDay(for: $0) } ?? .distantPast
                if lhsDay != rhsDay { return lhsDay < rhsDay }
            }
            let compared = lhs.athlete.displayName.localizedStandardCompare(rhs.athlete.displayName)
            return compared == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : compared == .orderedAscending
        }
    }
}
