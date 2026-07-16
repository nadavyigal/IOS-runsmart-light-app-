import Foundation

enum DeterministicFlexWeekBuilder {

    static func restructure(
        week: [PlannedWorkout],
        reason: FlexWeekReason,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (restructuredWeek: [PlannedWorkout], changes: [FlexWeekChange]) {
        let sortedWeek = week.sorted { $0.scheduledDate < $1.scheduledDate }
        guard !sortedWeek.isEmpty else {
            return (sortedWeek, [])
        }

        if isTaperWeek(sortedWeek) {
            return (
                sortedWeek,
                [
                    FlexWeekChange(
                        workoutID: sortedWeek[0].id,
                        changeType: .rest,
                        rationale: "Taper week — locking the schedule."
                    )
                ]
            )
        }

        var updated = sortedWeek
        var changes: [FlexWeekChange] = []

        switch reason {
        case .tired:
            applyTiredRule(week: &updated, changes: &changes, now: now, calendar: calendar)
        case .traveling(let blockedDays):
            applyTravelingRule(
                week: &updated,
                changes: &changes,
                blockedDays: blockedDays.map { calendar.startOfDay(for: $0) },
                calendar: calendar
            )
        case .missedWorkout(let workoutID):
            applyMissedWorkoutRule(
                week: &updated,
                changes: &changes,
                workoutID: workoutID,
                now: now,
                calendar: calendar
            )
        case .sick(let daysOut):
            applySickRule(
                week: &updated,
                changes: &changes,
                daysOut: daysOut ?? 4,
                now: now,
                calendar: calendar
            )
        }

        if changes.isEmpty, let fallback = fallbackChange(in: updated, reason: reason) {
            changes.append(fallback)
        }

        return (updated, changes)
    }

    // MARK: - Rules

    private static func applyTiredRule(
        week: inout [PlannedWorkout],
        changes: inout [FlexWeekChange],
        now: Date,
        calendar: Calendar
    ) {
        if let todayIndex = indexOfToday(in: week, now: now, calendar: calendar) {
            let today = week[todayIndex]
            if isHardWorkout(today) {
                week[todayIndex] = downgradedEasy(from: today)
                changes.append(
                    FlexWeekChange(
                        workoutID: today.id,
                        changeType: .downgraded,
                        rationale: "RECOVERY — downgraded today's hard session to easy while you recharge."
                    )
                )
                return
            }
            if isRestDay(today) {
                if let nextHardIndex = nextHardWorkoutIndex(in: week, after: todayIndex) {
                    let workout = week[nextHardIndex]
                    week[nextHardIndex] = downgradedEasy(from: workout)
                    changes.append(
                        FlexWeekChange(
                            workoutID: workout.id,
                            changeType: .downgraded,
                            rationale: "RECOVERY — eased the next hard session so you can recover first."
                        )
                    )
                }
                return
            }
        }

        if let nextHardIndex = nextHardWorkoutIndex(in: week, after: nil) {
            let workout = week[nextHardIndex]
            week[nextHardIndex] = downgradedEasy(from: workout)
            changes.append(
                FlexWeekChange(
                    workoutID: workout.id,
                    changeType: .downgraded,
                    rationale: "RECOVERY — eased the next hard session based on how you're feeling."
                )
            )
        }
    }

    private static func applyTravelingRule(
        week: inout [PlannedWorkout],
        changes: inout [FlexWeekChange],
        blockedDays: [Date],
        calendar: Calendar
    ) {
        let blocked = Set(blockedDays.map { calendar.startOfDay(for: $0) })
        guard !blocked.isEmpty else { return }

        let originalMileage = weeklyMileage(for: week)
        var displaced: [(index: Int, workout: PlannedWorkout)] = []

        for index in week.indices {
            let day = calendar.startOfDay(for: week[index].scheduledDate)
            guard blocked.contains(day), !isRestDay(week[index]) else { continue }

            let workout = week[index]
            displaced.append((index, workout))
            week[index] = restDay(from: workout)
            changes.append(
                FlexWeekChange(
                    workoutID: workout.id,
                    changeType: .rest,
                    rationale: "Marked \(weekdayLabel(for: workout.scheduledDate, calendar: calendar)) as rest while you're traveling."
                )
            )
        }

        guard let candidate = displaced.first(where: { isHardWorkout($0.workout) || !isEasyWorkout($0.workout) }) else {
            return
        }

        let maxMileage = originalMileage * 1.10
        for index in week.indices {
            let day = calendar.startOfDay(for: week[index].scheduledDate)
            guard !blocked.contains(day), isRestDay(week[index]) || isEasyWorkout(week[index]) else { continue }
            guard !wouldCreateBackToBackHard(in: week, moving: candidate.workout, to: index, calendar: calendar) else { continue }

            var moved = reidentified(candidate.workout, id: week[index].id)
            moved.scheduledDate = week[index].scheduledDate
            moved.weekday = weekdayLabel(for: moved.scheduledDate, calendar: calendar).uppercased()
            moved.date = String(calendar.component(.day, from: moved.scheduledDate))
            week[index] = moved

            let projected = weeklyMileage(for: week)
            if projected <= maxMileage + 0.01 {
                changes.append(
                    FlexWeekChange(
                        workoutID: moved.id,
                        changeType: .moved,
                        rationale: "Shifted \(candidate.workout.title) to \(weekdayLabel(for: moved.scheduledDate, calendar: calendar)) to protect weekly mileage.",
                        originalWorkoutID: candidate.workout.id
                    )
                )
                return
            }
            week[index] = restDay(from: week[index])
        }
    }

    private static func applyMissedWorkoutRule(
        week: inout [PlannedWorkout],
        changes: inout [FlexWeekChange],
        workoutID: UUID,
        now: Date,
        calendar: Calendar
    ) {
        guard let missedIndex = week.firstIndex(where: { $0.id == workoutID }) else { return }
        let missed = week[missedIndex]

        if isEasyWorkout(missed) || isRestDay(missed) {
            week[missedIndex] = restDay(from: missed)
            changes.append(
                FlexWeekChange(
                    workoutID: missed.id,
                    changeType: .dropped,
                    rationale: "Dropped the missed easy session so you don't cram extra volume into the week."
                )
            )
            return
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let tomorrowIndex = week.firstIndex(where: { calendar.isDate($0.scheduledDate, inSameDayAs: tomorrow) })
        else {
            week[missedIndex] = restDay(from: missed)
            changes.append(
                FlexWeekChange(
                    workoutID: missed.id,
                    changeType: .rest,
                    rationale: "Converted the missed hard session to rest because tomorrow isn't open for a safe reschedule."
                )
            )
            return
        }

        let tomorrowWorkout = week[tomorrowIndex]
        if isHardWorkout(tomorrowWorkout) {
            week[missedIndex] = restDay(from: missed)
            changes.append(
                FlexWeekChange(
                    workoutID: missed.id,
                    changeType: .rest,
                    rationale: "Left the missed workout as rest to avoid stacking two hard days back-to-back."
                )
            )
            return
        }

        week[missedIndex] = restDay(from: missed)
        var rescheduled = reidentified(missed, id: tomorrowWorkout.id)
        rescheduled.scheduledDate = tomorrowWorkout.scheduledDate
        rescheduled.weekday = tomorrowWorkout.weekday
        rescheduled.date = tomorrowWorkout.date
        week[tomorrowIndex] = rescheduled

        changes.append(
            FlexWeekChange(
                workoutID: missed.id,
                changeType: .rest,
                rationale: "Converted the missed day to rest."
            )
        )
        changes.append(
            FlexWeekChange(
                workoutID: rescheduled.id,
                changeType: .moved,
                rationale: "Moved \(missed.title) to tomorrow because that slot was easy enough to absorb it safely.",
                originalWorkoutID: missed.id
            )
        )
    }

    private static func reidentified(_ workout: PlannedWorkout, id: UUID) -> PlannedWorkout {
        PlannedWorkout(
            id: id,
            scheduledDate: workout.scheduledDate,
            planID: workout.planID,
            weekday: workout.weekday,
            date: workout.date,
            kind: workout.kind,
            title: workout.title,
            distance: workout.distance,
            detail: workout.detail,
            isToday: workout.isToday,
            isComplete: workout.isComplete,
            durationMinutes: workout.durationMinutes,
            targetPaceSecondsPerKm: workout.targetPaceSecondsPerKm,
            intensity: workout.intensity,
            trainingPhase: workout.trainingPhase,
            workoutStructure: workout.workoutStructure,
            adjustedAt: workout.adjustedAt,
            adjustedReason: workout.adjustedReason
        )
    }

    private static func applySickRule(
        week: inout [PlannedWorkout],
        changes: inout [FlexWeekChange],
        daysOut: Int,
        now: Date,
        calendar: Calendar
    ) {
        let recoveryDays = max(3, min(daysOut, 7))
        let sickEnd = calendar.date(byAdding: .day, value: recoveryDays - 1, to: calendar.startOfDay(for: now)) ?? now
        var lastSickRestDay = calendar.startOfDay(for: now)

        for index in week.indices {
            let day = calendar.startOfDay(for: week[index].scheduledDate)
            guard day >= calendar.startOfDay(for: now), day <= sickEnd else { continue }
            guard !isRestDay(week[index]) else { continue }

            let workout = week[index]
            week[index] = restDay(from: workout)
            lastSickRestDay = day
            changes.append(
                FlexWeekChange(
                    workoutID: workout.id,
                    changeType: .rest,
                    rationale: "Rest while you recover — illness recovery comes before training load."
                )
            )
        }

        let returnDay = calendar.date(byAdding: .hour, value: 48, to: lastSickRestDay) ?? sickEnd
        if let returnIndex = week.firstIndex(where: {
            calendar.startOfDay(for: $0.scheduledDate) >= calendar.startOfDay(for: returnDay) && !isRestDay($0)
        }) {
            let workout = week[returnIndex]
            if isHardWorkout(workout) {
                week[returnIndex] = downgradedEasy(from: workout, title: "Easy Return Run")
                changes.append(
                    FlexWeekChange(
                        workoutID: workout.id,
                        changeType: .downgraded,
                        rationale: "Your first run back is an easy session to test how you feel."
                    )
                )
            }
        }
    }

    // MARK: - Helpers

    private static func isTaperWeek(_ week: [PlannedWorkout]) -> Bool {
        week.contains { workout in
            workout.trainingPhase?.localizedCaseInsensitiveContains("taper") == true
        }
    }

    private static func isHardWorkout(_ workout: PlannedWorkout) -> Bool {
        switch workout.kind {
        case .tempo, .intervals, .hills, .long, .race:
            return true
        default:
            return false
        }
    }

    private static func isEasyWorkout(_ workout: PlannedWorkout) -> Bool {
        switch workout.kind {
        case .easy, .recovery:
            return true
        default:
            return workout.intensity?.localizedCaseInsensitiveContains("easy") == true
        }
    }

    private static func isRestDay(_ workout: PlannedWorkout) -> Bool {
        !PlanPresentationModels.isWorkout(workout) ||
        workout.kind == .recovery && workout.distance.localizedCaseInsensitiveContains("rest")
    }

    private static func weeklyMileage(for week: [PlannedWorkout]) -> Double {
        week.reduce(0) { $0 + PlanPresentationModels.distanceKm(from: $1.distance) }
    }

    private static func downgradedEasy(from workout: PlannedWorkout, title: String = "Easy Run") -> PlannedWorkout {
        var updated = workout
        updated.kind = .easy
        updated.title = title
        updated.intensity = "easy"
        if updated.distance.localizedCaseInsensitiveContains("rest") {
            updated.distance = "5.0 km"
        }
        return updated
    }

    private static func restDay(from workout: PlannedWorkout) -> PlannedWorkout {
        var updated = workout
        updated.kind = .recovery
        updated.title = "Rest"
        updated.distance = "Rest"
        updated.intensity = "rest"
        updated.detail = "Recovery"
        return updated
    }

    private static func indexOfToday(
        in week: [PlannedWorkout],
        now: Date,
        calendar: Calendar
    ) -> Int? {
        week.firstIndex { calendar.isDate($0.scheduledDate, inSameDayAs: now) }
    }

    private static func nextHardWorkoutIndex(
        in week: [PlannedWorkout],
        after index: Int?
    ) -> Int? {
        let start = (index ?? -1) + 1
        guard start < week.count else { return nil }
        return week[start...].firstIndex(where: { isHardWorkout($0) && !isRestDay($0) })
    }

    private static func wouldCreateBackToBackHard(
        in week: [PlannedWorkout],
        moving workout: PlannedWorkout,
        to targetIndex: Int,
        calendar: Calendar
    ) -> Bool {
        guard isHardWorkout(workout) else { return false }
        let neighbors = [targetIndex - 1, targetIndex + 1].compactMap { idx -> PlannedWorkout? in
            guard week.indices.contains(idx) else { return nil }
            return week[idx]
        }
        return neighbors.contains(where: { isHardWorkout($0) })
    }

    private static func weekdayLabel(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func fallbackChange(in week: [PlannedWorkout], reason: FlexWeekReason) -> FlexWeekChange? {
        guard let workout = week.first(where: { !isRestDay($0) }) ?? week.first else { return nil }
        return FlexWeekChange(
            workoutID: workout.id,
            changeType: .downgraded,
            rationale: "RECOVERY — applied a conservative \(reason.displayTitle.lowercased()) adjustment for the rest of the week."
        )
    }
}
