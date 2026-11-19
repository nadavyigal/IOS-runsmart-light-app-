import Foundation

/// The marker a coach sees on one day of the week strip (C5).
enum CoachDayMarker: Equatable {
    case done, partial, missed, extra, planned, rest
    // Story 4.x adds `skippedByCoach` and `draftChange`; nothing produces them yet.

    var label: String {
        switch self {
        case .done: "Done"
        case .partial: "Partial"
        case .missed: "Missed"
        case .extra: "Extra"
        case .planned: "Planned"
        case .rest: "Rest day"
        }
    }

    var icon: String {
        switch self {
        case .done: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .missed: "minus.circle"
        case .extra: "plus.circle"
        case .planned: "circle.dotted"
        case .rest: "moon"
        }
    }
}

/// One planned workout on a day, with the run that counts for it.
struct CoachDayWorkout: Identifiable, Equatable {
    let workout: CoachWorkoutSummary
    let state: WorkoutAdherence
    let run: CoachRunSummary?
    /// A legacy run with no `workout_id`, paired by date with a workout marked completed (before Story 0.2).
    let matchedByDate: Bool
    var id: UUID { workout.id }
}

struct CoachDay: Identifiable, Equatable {
    let date: Date
    let iso: String
    let workouts: [CoachDayWorkout]
    let extraRuns: [CoachRunSummary]
    var id: String { iso }

    var marker: CoachDayMarker {
        let states = workouts.map(\.state)
        if states.contains(.missed) { return .missed }
        if states.contains(.partial) { return .partial }
        if states.contains(.planned) { return .planned }
        if states.contains(.done) { return .done }
        return extraRuns.isEmpty ? .rest : .extra
    }
}

struct CoachAthleteWeekDays: Equatable {
    let start: Date
    let days: [CoachDay]
}

enum CoachAthleteDays {
    /// Builds the current and previous week for one athlete, in the coach's week order.
    /// Rest rows are dropped (they are not workouts). Runs are placed on the coach's local day.
    static func weeks(
        workouts: [CoachWorkoutSummary], runs: [CoachRunSummary], now: Date, week: CoachAthleteWeek
    ) -> (current: CoachAthleteWeekDays, previous: CoachAthleteWeekDays) {
        let calendar = week.calendar
        let today = CoachReadDay.iso(now, calendar: calendar)
        let previousStart = calendar.date(byAdding: .day, value: -7, to: week.interval.start)!
        let counted = workouts.filter(WorkoutAdherence.counts)
        let runsInRange = runs.filter { $0.completedAt >= previousStart && $0.completedAt < week.interval.end && $0.completedAt <= now }
        let linkedIDs = Set(runsInRange.compactMap(\.workoutID))
        let workoutIDs = Set(counted.map(\.id))
        let byWorkout = Dictionary(grouping: runsInRange.filter { $0.workoutID != nil }, by: \.workoutID)

        // Extra runs: no `workout_id`, or linked to a workout this screen does not show (in practice a
        // rest row, which is not a workout). Either way it is a real run with no planned workout here.
        // Only runs with a null `workout_id` can be "Matched by date".
        var unlinked = runsInRange.filter { $0.workoutID == nil || !workoutIDs.contains($0.workoutID!) }
            .sorted { $0.completedAt < $1.completedAt }
        var pairs: [UUID: CoachRunSummary] = [:]
        // "Matched by date": a completed workout no run links to, and an unlinked run on the same day.
        for workout in counted.sorted(by: { $0.scheduledDate < $1.scheduledDate })
        where workout.completed && !linkedIDs.contains(workout.id) {
            if let index = unlinked.firstIndex(where: {
                $0.workoutID == nil && CoachReadDay.iso($0.completedAt, calendar: calendar) == workout.scheduledDate
            }) {
                pairs[workout.id] = unlinked.remove(at: index)
            }
        }

        func days(from start: Date) -> CoachAthleteWeekDays {
            let list = (0..<7).map { offset -> CoachDay in
                let date = calendar.date(byAdding: .day, value: offset, to: start)!
                let iso = CoachReadDay.iso(date, calendar: calendar)
                let dayWorkouts = counted.filter { $0.scheduledDate == iso }.map { workout -> CoachDayWorkout in
                    if let matched = pairs[workout.id] {
                        return CoachDayWorkout(
                            workout: workout, state: WorkoutAdherence.measure(workout: workout, run: matched),
                            run: matched, matchedByDate: true
                        )
                    }
                    let linked = byWorkout[workout.id, default: []]
                    let state = WorkoutAdherence.state(workout: workout, linkedRuns: linked, today: today)
                    let run = linked.first { WorkoutAdherence.classify(workout: workout, run: $0, today: today) == state }
                        ?? linked.first
                    return CoachDayWorkout(workout: workout, state: state, run: run, matchedByDate: false)
                }
                let extras = unlinked.filter { CoachReadDay.iso($0.completedAt, calendar: calendar) == iso }
                return CoachDay(date: date, iso: iso, workouts: dayWorkouts, extraRuns: extras)
            }
            return CoachAthleteWeekDays(start: start, days: list)
        }
        return (days(from: week.interval.start), days(from: previousStart))
    }
}

/// Text for planned vs actual. Every value is wrapped in a directional isolate so it keeps its order in RTL.
enum CoachMetricFormat {
    static func isolate(_ text: String) -> String { "\u{2068}\(text)\u{2069}" }

    static func distance(_ km: Double) -> String { isolate(String(format: "%.1f km", km)) }

    static func duration(seconds: Int) -> String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, secs = seconds % 60
        return isolate(hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
                       : String(format: "%d:%02d", minutes, secs))
    }

    /// Pace in whole seconds per km, as `workouts.pace` and `workouts.actual_pace` store it.
    static func pace(secondsPerKm: Int) -> String {
        isolate(String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60))
    }

    /// Actual pace is computed from the run's duration and distance, because `runs.pace` has no fixed unit.
    static func paceSeconds(for run: CoachRunSummary) -> Int? {
        guard run.distanceKm > 0, run.durationSeconds > 0 else { return nil }
        return Int((Double(run.durationSeconds) / run.distanceKm).rounded())
    }

    static func heartRate(_ bpm: Int) -> String { isolate("\(bpm) bpm") }

    static func distanceDifference(planned: Double, actual: Double) -> String? {
        let diff = (actual - planned) * 10
        guard planned > 0, diff.rounded() != 0 else { return nil }
        return isolate(String(format: "%@%.1f km", diff < 0 ? "−" : "+", abs(diff.rounded()) / 10))
    }

    static func durationDifference(plannedMinutes: Int, actualSeconds: Int) -> String? {
        let diff = actualSeconds - plannedMinutes * 60
        guard plannedMinutes > 0, abs(diff) >= 60 else { return nil }
        return isolate("\(diff < 0 ? "−" : "+")\(abs(diff) / 60) min")
    }

    static func workoutTitle(_ type: String) -> String {
        switch type.lowercased() {
        case "easy": "Easy run"
        case "tempo": "Tempo run"
        case "race-pace": "Race pace run"
        case "intervals": "Intervals"
        case "hill": "Hill repeats"
        case "long": "Long run"
        case "recovery": "Recovery run"
        case "fartlek": "Fartlek run"
        default: type.capitalized
        }
    }

    /// One VoiceOver sentence per day cell, for example
    /// "Tuesday 11 November, tempo run, planned 5 kilometres, completed 4.8 kilometres, partial."
    static func spokenDay(_ day: CoachDay, calendar: Calendar, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        var parts = [formatter.string(from: day.date)]
        if day.workouts.isEmpty && day.extraRuns.isEmpty { return parts[0] + ", rest day." }
        for item in day.workouts {
            parts.append(workoutTitle(item.workout.type).lowercased())
            if item.workout.plannedDistance > 0 {
                parts.append("planned \(spokenKm(item.workout.plannedDistance))")
            } else if let minutes = item.workout.plannedDurationMinutes, minutes > 0 {
                parts.append("planned \(minutes) minutes")
            }
            if let run = item.run { parts.append("completed \(spokenKm(run.distanceKm))") }
            parts.append(CoachDayMarker(item.state).label.lowercased())
        }
        for run in day.extraRuns {
            parts.append("extra run, \(spokenKm(run.distanceKm))")
        }
        return parts.joined(separator: ", ") + "."
    }

    private static func spokenKm(_ km: Double) -> String {
        let value = km.rounded() == km ? String(Int(km)) : String(format: "%.1f", km)
        return "\(value) kilometres"
    }
}

extension CoachDayMarker {
    init(_ state: WorkoutAdherence) {
        switch state {
        case .done: self = .done
        case .partial: self = .partial
        case .missed: self = .missed
        case .planned: self = .planned
        case .extra: self = .extra
        }
    }
}
