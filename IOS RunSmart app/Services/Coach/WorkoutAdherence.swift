import Foundation

enum WorkoutAdherence: Equatable {
    case done, partial, missed, planned, extra

    static func classify(workout: CoachWorkoutSummary, run: CoachRunSummary?, today: String) -> Self {
        guard let run, run.workoutID == workout.id, run.athleteID == workout.athleteID else {
            return workout.scheduledDate < today ? .missed : .planned
        }
        if workout.plannedDistance > 0 {
            return run.distanceKm >= workout.plannedDistance * 0.8 ? .done : .partial
        }
        if let minutes = workout.plannedDurationMinutes, minutes > 0 {
            return Double(run.durationSeconds) >= Double(minutes) * 60 * 0.8 ? .done : .partial
        }
        return .done
    }

    static func classify(run: CoachRunSummary) -> Self? {
        run.workoutID == nil ? .extra : nil
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
        let workoutsByAthlete = Dictionary(grouping: workouts, by: \.athleteID)
        let runsByAthlete = Dictionary(grouping: runs, by: \.athleteID)
        return athletes.map { athlete in
            let athleteRuns = runsByAthlete[athlete.athleteID, default: []]
            let linkedRuns = Dictionary(grouping: athleteRuns, by: \.workoutID)
            let results = workoutsByAthlete[athlete.athleteID, default: []].map { workout in
                let states = linkedRuns[workout.id, default: []].map {
                    WorkoutAdherence.classify(workout: workout, run: $0, today: today)
                }
                let state = states.contains(.done) ? WorkoutAdherence.done
                    : states.first ?? WorkoutAdherence.classify(workout: workout, run: nil, today: today)
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
            if lhs.status == .behind, rhs.status == .behind {
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
