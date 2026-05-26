import Foundation
import CryptoKit

/// Alias used across Flex Week specs; the app’s live plan rows are `WorkoutSummary`.
typealias PlannedWorkout = WorkoutSummary

// MARK: - Reason & request

enum FlexWeekReason: Hashable {
    case tired
    case traveling(blockedDays: [Date])
    case missedWorkout(workoutID: UUID)
    case sick(daysOut: Int?)

    var displayTitle: String {
        switch self {
        case .tired: "I'm tired"
        case .traveling: "I'm traveling"
        case .missedWorkout: "I missed a workout"
        case .sick: "I'm sick"
        }
    }

    var icon: String {
        switch self {
        case .tired: "battery.25"
        case .traveling: "airplane"
        case .missedWorkout: "calendar.badge.exclamationmark"
        case .sick: "heart.text.square"
        }
    }

    var kind: FlexWeekReasonKind {
        switch self {
        case .tired: .tired
        case .traveling: .traveling
        case .missedWorkout: .missedWorkout
        case .sick: .sick
        }
    }
}

enum FlexWeekReasonKind: String, Hashable, CaseIterable {
    case tired
    case traveling
    case missedWorkout
    case sick
}

struct ReadinessContext: Hashable {
    var readiness: Int
    var readinessLabel: String
    var bodyBattery: Int
    var hrv: String
    var sleep: String
    var recommendation: String

    static func make(recovery: RecoverySnapshot, recommendation: TodayRecommendation) -> ReadinessContext {
        ReadinessContext(
            readiness: recommendation.readiness > 0 ? recommendation.readiness : recovery.readiness,
            readinessLabel: recommendation.readinessLabel,
            bodyBattery: recovery.bodyBattery,
            hrv: recovery.hrv,
            sleep: recovery.sleep,
            recommendation: recovery.recommendation
        )
    }

    var tiredEvidence: String? {
        guard readiness > 0 else { return nil }
        return "Today's readiness is \(readiness) (\(readinessLabel))."
    }
}

struct FlexWeekRequest: Hashable {
    var reason: FlexWeekReason
    var currentWeek: [PlannedWorkout]
    var readinessContext: ReadinessContext?
}

// MARK: - Outcome (Stories 3–6)

enum FlexWeekOutcomeSource: String, Hashable {
    case ai
    case deterministicFallback
    case offlineQueued
}

enum FlexWeekChangeType: String, Hashable {
    case moved
    case downgraded
    case rest
    case dropped
    case added
}

struct FlexWeekChange: Hashable, Identifiable {
    var id: UUID
    var workoutID: UUID
    var changeType: FlexWeekChangeType
    var rationale: String
    var originalWorkoutID: UUID?

    init(
        workoutID: UUID,
        changeType: FlexWeekChangeType,
        rationale: String,
        originalWorkoutID: UUID? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.workoutID = workoutID
        self.changeType = changeType
        self.rationale = rationale
        self.originalWorkoutID = originalWorkoutID
    }
}

struct FlexWeekOutcome: Hashable {
    var restructuredWeek: [PlannedWorkout]
    var changes: [FlexWeekChange]
    var safetyWarnings: [String]
    var source: FlexWeekOutcomeSource

    var applicationHash: String {
        FlexWeekAppliedHash.digest(for: self)
    }
}

enum FlexWeekAppliedHash {
    private static let defaultsKeyPrefix = "runsmart.flexWeek.appliedHash."

    static func digest(for outcome: FlexWeekOutcome) -> String {
        let rows = outcome.restructuredWeek
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { workout in
                [
                    workout.id.uuidString,
                    ISO8601DateFormatter.shortDate.string(from: workout.scheduledDate),
                    workout.kind.rawValue,
                    workout.distance,
                    workout.title,
                    workout.intensity ?? ""
                ].joined(separator: "|")
            }
        let changeRows = outcome.changes
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { change in
                [
                    change.workoutID.uuidString,
                    change.changeType.rawValue,
                    change.rationale,
                    change.originalWorkoutID?.uuidString ?? ""
                ].joined(separator: "|")
            }
        let payload = (rows + changeRows).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isApplied(hash: String, planID: UUID) -> Bool {
        UserDefaults.standard.string(forKey: key(planID: planID)) == hash
    }

    static func markApplied(hash: String, planID: UUID) {
        UserDefaults.standard.set(hash, forKey: key(planID: planID))
    }

    private static func key(planID: UUID) -> String {
        defaultsKeyPrefix + planID.uuidString
    }
}

struct FlexWeekRecord: Hashable, Identifiable, Codable {
    var id: UUID
    var reason: String
    var confirmedAt: Date
    var changesCount: Int

    init(id: UUID = UUID(), reason: String, confirmedAt: Date, changesCount: Int) {
        self.id = id
        self.reason = reason
        self.confirmedAt = confirmedAt
        self.changesCount = changesCount
    }
}

enum FlexWeekEntryPoint: String, Hashable {
    case planPill
    case todayLink
    case missedWorkoutReschedule
    case planExplanation
}

struct FlexWeekLaunchContext: Identifiable, Hashable {
    let id = UUID()
    var preselectedReason: FlexWeekReason?
    var entryPoint: FlexWeekEntryPoint = .planPill

    static func == (lhs: FlexWeekLaunchContext, rhs: FlexWeekLaunchContext) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum FlexWeekEntryPresentation {
    static func shouldShowTodayLink(
        readiness: Int,
        weekWorkouts: [PlannedWorkout],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if readiness > 0 && readiness < 60 {
            return true
        }
        return FlexWeekPresentation.mostRecentMissedWorkout(in: weekWorkouts, now: now, calendar: calendar) != nil
    }

    static func preselectedMissedReason(
        from week: [PlannedWorkout],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FlexWeekReason? {
        guard let missed = FlexWeekPresentation.mostRecentMissedWorkout(in: week, now: now, calendar: calendar) else {
            return nil
        }
        return .missedWorkout(workoutID: missed.id)
    }
}

// MARK: - Helpers

enum FlexWeekPresentation {
    static func currentWeekDays(calendar: Calendar = .current, now: Date = Date()) -> [Date] {
        guard let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    static func mostRecentMissedWorkout(
        in week: [PlannedWorkout],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PlannedWorkout? {
        week
            .filter { workout in
                !workout.isComplete &&
                PlanPresentationModels.isWorkout(workout) &&
                calendar.startOfDay(for: workout.scheduledDate) < calendar.startOfDay(for: now)
            }
            .sorted { $0.scheduledDate > $1.scheduledDate }
            .first
    }

    static func workout(in week: [PlannedWorkout], id: UUID) -> PlannedWorkout? {
        week.first { $0.id == id }
    }

    static func weekdayLabel(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    static func shortDateLabel(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    static func missedWorkoutChipLabel(_ workout: PlannedWorkout) -> String {
        "\(workout.title) · \(shortDateLabel(for: workout.scheduledDate))"
    }

    static func isValid(_ reason: FlexWeekReason, week: [PlannedWorkout]) -> Bool {
        switch reason {
        case .tired, .sick:
            return true
        case .traveling(let blockedDays):
            return !blockedDays.isEmpty
        case .missedWorkout(let workoutID):
            return workout(in: week, id: workoutID) != nil
        }
    }
}
