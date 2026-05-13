import Foundation

struct PlanWeekSummary: Identifiable, Hashable {
    var id: String
    var weekNumber: Int
    var startDate: Date
    var endDate: Date
    var workouts: [WorkoutSummary]
    var isCurrentWeek: Bool

    var dateRangeLabel: String {
        let startMonth = DateFormatter.shortMonthUpper.string(from: startDate).uppercased()
        let endMonth = DateFormatter.shortMonthUpper.string(from: endDate).uppercased()
        let startDay = Calendar.current.component(.day, from: startDate)
        let endDay = Calendar.current.component(.day, from: endDate)
        if startMonth == endMonth {
            return "\(startMonth) \(startDay) - \(endDay)"
        }
        return "\(startMonth) \(startDay) - \(endMonth) \(endDay)"
    }

    var totalWorkouts: Int {
        visibleWorkouts.count
    }

    var totalDistanceKm: Double {
        visibleWorkouts.reduce(0) { $0 + PlanPresentationModels.distanceKm(from: $1.distance) }
    }

    var totalDistanceLabel: String {
        String(format: "%.2fkm", totalDistanceKm)
    }

    var visibleWorkouts: [WorkoutSummary] {
        workouts.filter { PlanPresentationModels.isWorkout($0) }
    }
}

enum PlanPresentationModels {
    static func monthQueryBounds(for month: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return (month, month)
        }
        let monthStartWeek = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start ?? interval.start
        let lastMonthDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let monthEndWeek = calendar.dateInterval(of: .weekOfYear, for: lastMonthDay)?.end ?? interval.end
        let end = calendar.date(byAdding: .second, value: -1, to: monthEndWeek) ?? monthEndWeek
        return (monthStartWeek, end)
    }

    static func makeWeeks(
        displayedMonth: Date,
        workouts: [WorkoutSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PlanWeekSummary] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let bounds = monthQueryBounds(for: displayedMonth, calendar: calendar)
        var weekStart = bounds.start
        var summaries: [PlanWeekSummary] = []
        var index = 1

        while weekStart <= bounds.end {
            let weekEndExclusive = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let weekEnd = calendar.date(byAdding: .second, value: -1, to: weekEndExclusive) ?? weekEndExclusive
            let overlapsMonth = weekEnd >= monthInterval.start && weekStart < monthInterval.end
            let weekWorkouts = workouts
                .filter { $0.scheduledDate >= weekStart && $0.scheduledDate < weekEndExclusive }
                .sorted { $0.scheduledDate < $1.scheduledDate }

            if overlapsMonth, !weekWorkouts.isEmpty {
                summaries.append(
                    PlanWeekSummary(
                        id: ISO8601DateFormatter.shortDate.string(from: weekStart),
                        weekNumber: index,
                        startDate: weekStart,
                        endDate: weekEnd,
                        workouts: weekWorkouts,
                        isCurrentWeek: now >= weekStart && now < weekEndExclusive
                    )
                )
            }

            weekStart = weekEndExclusive
            index += 1
        }

        return summaries
    }

    static func uniqueWorkouts(_ collections: [[WorkoutSummary]]) -> [WorkoutSummary] {
        var seen = Set<String>()
        return collections
            .flatMap { $0 }
            .filter { workout in
                let key = [
                    workout.id.uuidString,
                    ISO8601DateFormatter.shortDate.string(from: workout.scheduledDate),
                    workout.title,
                    workout.distance
                ].joined(separator: "|")
                let fallbackKey = [
                    ISO8601DateFormatter.shortDate.string(from: workout.scheduledDate),
                    workout.title,
                    workout.distance
                ].joined(separator: "|")
                guard !seen.contains(key), !seen.contains(fallbackKey) else { return false }
                seen.insert(key)
                seen.insert(fallbackKey)
                return true
            }
    }

    static func distanceKm(from label: String) -> Double {
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "."))
        let token = label
            .components(separatedBy: allowed.inverted)
            .first { !$0.isEmpty } ?? ""
        return Double(token) ?? 0
    }

    static func isWorkout(_ workout: WorkoutSummary) -> Bool {
        distanceKm(from: workout.distance) > 0 || !workout.distance.localizedCaseInsensitiveContains("rest")
    }
}

struct TodayWorkoutDisplayModel {
    var workoutType: String
    var title: String
    var distance: String
    var targetPace: String
    var duration: String
    var intensity: String
    var weekLabel: String
    var steps: [WorkoutStep]

    static func make(
        recommendation: TodayRecommendation,
        workout: WorkoutSummary,
        calendar: Calendar = .current
    ) -> TodayWorkoutDisplayModel {
        let pace = StructuredWorkoutFactory.derivedPaceLabel(workout: workout)
            ?? normalizedPace(recommendation.pace)
        let steps = StructuredWorkoutFactory.makeSteps(for: workout) ?? []
        return TodayWorkoutDisplayModel(
            workoutType: "\(workout.kind.rawValue.uppercased()) · OUTDOOR",
            title: workout.title.isEmpty ? recommendation.workoutTitle : workout.title,
            distance: workout.distance.isEmpty || workout.distance == "Rest" ? recommendation.distance : workout.distance,
            targetPace: pace,
            duration: durationLabel(workout: workout, pace: pace),
            intensity: workout.intensity?.isEmpty == false ? workout.intensity! : fallbackIntensity(for: workout.kind),
            weekLabel: weekLabel(for: workout, calendar: calendar),
            steps: steps
        )
    }

    private static func normalizedPace(_ pace: String) -> String {
        let trimmed = pace.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "--:--" || trimmed.localizedCaseInsensitiveContains("gps") {
            return "6:10 /km"
        }
        return trimmed.contains("/km") ? trimmed : "\(trimmed) /km"
    }

    private static func durationLabel(workout: WorkoutSummary, pace: String) -> String {
        if let minutes = workout.durationMinutes, minutes > 0 {
            return "~\(minutes) min"
        }
        let distance = PlanPresentationModels.distanceKm(from: workout.distance)
        let secondsPerKm = paceSecondsPerKm(from: pace)
        if distance > 0, secondsPerKm > 0 {
            return "~\(Int((distance * Double(secondsPerKm) / 60).rounded())) min"
        }
        switch workout.kind {
        case .tempo, .intervals: return "~50 min"
        case .long: return "~75 min"
        case .recovery: return "~30 min"
        default: return "~45 min"
        }
    }

    private static func paceSecondsPerKm(from pace: String) -> Int {
        let parts = pace
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
        guard parts.count >= 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]) else { return 0 }
        return minutes * 60 + seconds
    }

    private static func fallbackIntensity(for kind: WorkoutKind) -> String {
        switch kind {
        case .recovery: return "Zone 1"
        case .easy, .long, .parkrun: return "Zone 2"
        case .tempo, .hills: return "Zone 3"
        case .intervals, .race: return "Zone 4"
        case .strength: return "Strength"
        }
    }

    private static func weekLabel(for workout: WorkoutSummary, calendar: Calendar) -> String {
        if let phase = workout.trainingPhase,
           let number = phase.components(separatedBy: CharacterSet.decimalDigits.inverted).first(where: { !$0.isEmpty }) {
            return "Week \(number)"
        }
        return "Week \(calendar.component(.weekOfMonth, from: workout.scheduledDate))"
    }
}

private extension DateFormatter {
    static let shortMonthUpper: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
}
