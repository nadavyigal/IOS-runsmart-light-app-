import Foundation
import SwiftUI
import CoreLocation

enum RunSmartTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case plan = "Plan"
    case run = "Run"
    case report = "Report"
    case profile = "Profile"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .plan: "calendar"
        case .run: "figure.run"
        case .report: "chart.xyaxis.line"
        case .profile: "person"
        }
    }

    var filledSymbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .plan: "calendar.badge.clock"
        case .run: "figure.run.circle.fill"
        case .report: "chart.xyaxis.line"
        case .profile: "person.fill"
        }
    }
}

enum WorkoutKind: String, Hashable {
    case easy = "Easy Run"
    case intervals = "Intervals"
    case tempo = "Tempo Run"
    case hills = "Hills"
    case strength = "Strength"
    case recovery = "Recovery"
    case long = "Long Run"
    case race = "Race"
    case parkrun = "parkrun"

    var symbol: String {
        switch self {
        case .easy, .intervals, .tempo, .long, .race, .parkrun: "figure.run"
        case .hills: "mountain.2"
        case .strength: "dumbbell"
        case .recovery: "heart"
        }
    }
}

struct RunnerProfile {
    var name: String
    var goal: String
    var streak: String
    var level: String
    var totalRuns: Int
    var totalDistance: Int
    var totalTime: String
}

struct WorkoutSummary: Identifiable, Hashable {
    let id: UUID
    var scheduledDate: Date
    var planID: UUID?
    var weekday: String
    var date: String
    var kind: WorkoutKind
    var title: String
    var distance: String
    var detail: String
    var isToday: Bool
    var isComplete: Bool
    var durationMinutes: Int?
    var targetPaceSecondsPerKm: Int?
    var intensity: String?
    var trainingPhase: String?
    var workoutStructure: String?
    var adjustedAt: Date?
    var adjustedReason: String?
}

struct TrainingGoalRequest: Hashable {
    var displayName: String
    var goal: String
    var experience: String
    var age: Int? = nil
    var averageWeeklyDistanceKm: Double? = nil
    var trainingDataSource: TrainingDataSource? = nil
    var weeklyRunDays: Int
    var preferredDays: [String]
    var coachingTone: String
    var targetDate: Date
    var challenge: TrainingChallengeContext? = nil
}

struct TrainingChallengeContext: Hashable {
    var slug: String?
    var name: String
    var category: String
    var difficulty: String?
    var durationDays: Int
    var workoutPattern: String?
    var coachTone: String?
    var targetAudience: String?
    var promise: String?
}

struct WorkoutPatch: Hashable {
    var scheduledDate: Date?
    var kind: WorkoutKind?
    var distanceKm: Double?
    var durationMinutes: Int?
    var targetPaceSecondsPerKm: Int?
    var notes: String?
    var workoutStructure: String?

    init(
        scheduledDate: Date? = nil,
        kind: WorkoutKind? = nil,
        distanceKm: Double? = nil,
        durationMinutes: Int? = nil,
        targetPaceSecondsPerKm: Int? = nil,
        notes: String? = nil,
        workoutStructure: String? = nil
    ) {
        self.scheduledDate = scheduledDate
        self.kind = kind
        self.distanceKm = distanceKm
        self.durationMinutes = durationMinutes
        self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
        self.notes = notes
        self.workoutStructure = workoutStructure
    }
}

struct TrainingPlanSnapshot: Identifiable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var totalWeeks: Int
    var planType: String
}

struct TodayRecommendation {
    var readiness: Int
    var readinessLabel: String
    var workoutTitle: String
    var distance: String
    var pace: String
    var elevation: String
    var coachMessage: String
    var weeklyProgress: String = "--"
    var streak: String = "--"
    var recovery: String = "--"
    var hrv: String = "--"
    var rationale: String? = nil
    var safetyExplanation: SafetyExplanation? = nil
}

enum SafetyExplanationKind: String, Hashable {
    case readinessGate
    case lowBodyBattery
    case lowHRV
    case restAdvised
}

struct SafetyExplanation: Hashable {
    var kind: SafetyExplanationKind
    var headline: String
    var coachVoice: String
    var evidence: String
    var action: String?
}

enum TodayResolvedStateKind: Hashable {
    case plannedToday
    case completedToday
    case upNext
    case restDay
    case noPlan
}

struct TodayResolvedState: Hashable {
    var kind: TodayResolvedStateKind
    var primaryWorkout: WorkoutSummary
    var completedRun: RecordedRun?
    var upNextWorkout: WorkoutSummary?

    var showsStartAction: Bool {
        kind == .plannedToday || kind == .upNext
    }

    var showsTodayRoute: Bool {
        kind == .plannedToday
    }

    var headline: String {
        switch kind {
        case .completedToday:
            return "Run complete today"
        case .upNext:
            return "Up next"
        case .restDay:
            return "Recovery today"
        case .noPlan:
            return "Today"
        case .plannedToday:
            return "Today's Workout"
        }
    }

    var primaryActionTitle: String {
        switch kind {
        case .completedToday:
            return "Review Report"
        case .plannedToday:
            return "Start Workout"
        case .upNext:
            return "Start Next Run"
        default:
            return "Ask Coach"
        }
    }

    static func make(
        recommendation: TodayRecommendation,
        weekWorkouts: [WorkoutSummary],
        nextWorkouts: [WorkoutSummary],
        recentRuns: [RecordedRun],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayResolvedState {
        let plannedWorkouts = PlanExplanation.uniqueWorkoutsForTodayState([weekWorkouts, nextWorkouts])
        let startOfToday = calendar.startOfDay(for: now)
        let sameDayRun = recentRuns
            .filter { calendar.isDate($0.startedAt, inSameDayAs: now) && $0.distanceMeters > 0 }
            .sorted { $0.startedAt > $1.startedAt }
            .first
        let completedTodayWorkout = plannedWorkouts
            .filter { $0.isComplete && calendar.isDate($0.scheduledDate, inSameDayAs: now) && isWorkout($0) }
            .sorted { $0.scheduledDate > $1.scheduledDate }
            .first
        let plannedTodayWorkout = plannedWorkouts
            .filter { !$0.isComplete && calendar.isDate($0.scheduledDate, inSameDayAs: now) && isWorkout($0) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .first
        let futureWorkout = plannedWorkouts
            .filter { !$0.isComplete && isWorkout($0) && calendar.startOfDay(for: $0.scheduledDate) > startOfToday }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .first
        let todayRest = plannedWorkouts.first {
            calendar.isDate($0.scheduledDate, inSameDayAs: now) && !isWorkout($0)
        }

        if let sameDayRun {
            return TodayResolvedState(
                kind: .completedToday,
                primaryWorkout: completedTodayWorkout ?? workoutSummary(for: sameDayRun, recommendation: recommendation, calendar: calendar),
                completedRun: sameDayRun,
                upNextWorkout: futureWorkout
            )
        }

        if let completedTodayWorkout {
            return TodayResolvedState(
                kind: .completedToday,
                primaryWorkout: completedTodayWorkout,
                completedRun: nil,
                upNextWorkout: futureWorkout
            )
        }

        if let plannedTodayWorkout {
            return TodayResolvedState(kind: .plannedToday, primaryWorkout: plannedTodayWorkout, completedRun: nil, upNextWorkout: futureWorkout)
        }

        if let todayRest {
            return TodayResolvedState(kind: .restDay, primaryWorkout: todayRest, completedRun: nil, upNextWorkout: futureWorkout)
        }

        if let futureWorkout {
            return TodayResolvedState(kind: .upNext, primaryWorkout: futureWorkout, completedRun: nil, upNextWorkout: futureWorkout)
        }

        return TodayResolvedState(kind: .noPlan, primaryWorkout: fallbackWorkout(recommendation: recommendation, now: now), completedRun: nil, upNextWorkout: nil)
    }

    private static func workoutSummary(
        for run: RecordedRun,
        recommendation: TodayRecommendation,
        calendar: Calendar
    ) -> WorkoutSummary {
        let distanceKm = run.distanceMeters / 1_000
        return WorkoutSummary(
            id: run.id,
            scheduledDate: run.startedAt,
            planID: nil,
            weekday: "",
            date: "",
            kind: .easy,
            title: "Run complete today",
            distance: String(format: "%.1f km", distanceKm),
            detail: recommendation.coachMessage,
            isToday: true,
            isComplete: true,
            durationMinutes: run.movingTimeSeconds > 0 ? Int((run.movingTimeSeconds / 60).rounded()) : nil,
            targetPaceSecondsPerKm: run.averagePaceSecondsPerKm > 0 ? Int(run.averagePaceSecondsPerKm.rounded()) : nil,
            intensity: nil,
            trainingPhase: nil,
            workoutStructure: nil
        )
    }

    private static func fallbackWorkout(recommendation: TodayRecommendation, now: Date) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            scheduledDate: now,
            planID: nil,
            weekday: "",
            date: "",
            kind: .easy,
            title: recommendation.workoutTitle,
            distance: recommendation.distance,
            detail: recommendation.coachMessage,
            isToday: true,
            isComplete: false
        )
    }

    private static func isWorkout(_ workout: WorkoutSummary) -> Bool {
        distanceKm(from: workout.distance) > 0 || !workout.distance.localizedCaseInsensitiveContains("rest")
    }

    private static func distanceKm(from label: String) -> Double {
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "."))
        let token = label
            .components(separatedBy: allowed.inverted)
            .first { !$0.isEmpty } ?? ""
        return Double(token) ?? 0
    }
}

enum PlanExplanationTrigger: String, Hashable {
    case normal
    case completedRun = "completed_run"
    case missedWorkout = "missed_workout"
    case extraRun = "extra_run"
    case lowRecovery = "low_recovery"
    case importedActivity = "imported_activity"
    case manualEdit = "manual_edit"

    var displayName: String {
        switch self {
        case .normal: "Plan is on track"
        case .completedRun: "Recent run logged"
        case .missedWorkout: "Missed workout"
        case .extraRun: "Extra run added"
        case .lowRecovery: "Low recovery"
        case .importedActivity: "Imported activity"
        case .manualEdit: "Manual edit"
        }
    }
}

enum PlanExplanationSource: String, Hashable {
    case heuristic
    case ai = "AI"
    case fallback

    var displayName: String {
        switch self {
        case .heuristic: "Heuristic"
        case .ai: "AI"
        case .fallback: "Fallback"
        }
    }
}

struct PlanExplanation: Hashable {
    var trigger: PlanExplanationTrigger
    var evidence: String
    var recommendation: String
    var action: String?
    var source: PlanExplanationSource

    var isOnTrack: Bool {
        trigger == .normal || trigger == .completedRun || trigger == .importedActivity || trigger == .manualEdit
    }

    static func make(
        activePlan: TrainingPlanSnapshot?,
        todayWorkout: WorkoutSummary?,
        weekWorkouts: [WorkoutSummary],
        nextWorkouts: [WorkoutSummary],
        recentRuns: [RecordedRun],
        recovery: RecoverySnapshot,
        recommendation: TodayRecommendation,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PlanExplanation {
        let plannedWorkouts = uniqueWorkouts([weekWorkouts, nextWorkouts])
        let hasPlan = activePlan != nil || !plannedWorkouts.isEmpty
        let latestRun = recentRuns.sorted { $0.startedAt > $1.startedAt }.first
        let recentRun = latestRun.flatMap { run -> (RecordedRun, Int)? in
            guard let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: run.startedAt), to: calendar.startOfDay(for: now)).day else { return nil }
            return (run, daysAgo)
        }
        let missedWorkout = plannedWorkouts
            .filter { workout in
                !workout.isComplete &&
                isWorkout(workout) &&
                calendar.startOfDay(for: workout.scheduledDate) < calendar.startOfDay(for: now)
            }
            .sorted { $0.scheduledDate > $1.scheduledDate }
            .first
        let resolvedTodayWorkout = todayWorkout ?? plannedWorkouts.first(where: { calendar.isDate($0.scheduledDate, inSameDayAs: now) })
        let isRestDay = resolvedTodayWorkout.map { !isWorkout($0) } ?? isRestRecommendation(recommendation)

        if !hasPlan {
            return PlanExplanation(
                trigger: .normal,
                evidence: "No active training plan is loaded yet.",
                recommendation: "Start with an easy run or set a goal so Coach can explain a specific workout.",
                action: "Set a goal",
                source: .fallback
            )
        }

        if isLowRecovery(recovery, recommendation: recommendation) {
            return PlanExplanation(
                trigger: .lowRecovery,
                evidence: lowRecoveryEvidence(recovery, recommendation: recommendation),
                recommendation: "Keep today easy, shorten the session, or use the planned rest day.",
                action: "Amend workout",
                source: .heuristic
            )
        }

        if let (run, daysAgo) = recentRun, daysAgo == 0 {
            let runLabel = runDistanceLabel(run)
            if run.source != .runSmart {
                return PlanExplanation(
                    trigger: .importedActivity,
                    evidence: "Imported \(runLabel) from \(run.source.rawValue) today.",
                    recommendation: isRestDay ? "That load supports keeping today as recovery." : "Coach is counting today's imported activity before nudging the rest of the plan.",
                    action: nil,
                    source: .heuristic
                )
            }

            return PlanExplanation(
                trigger: .completedRun,
                evidence: "Today's \(runLabel) run is already in your training history.",
                recommendation: isRestDay ? "Today can stay as recovery." : "The plan can stay steady unless recovery changes.",
                action: nil,
                source: .heuristic
            )
        }

        if let missedWorkout {
            return PlanExplanation(
                trigger: .missedWorkout,
                evidence: "You still have \(missedWorkout.title) from \(relativeDayLabel(missedWorkout.scheduledDate, now: now, calendar: calendar)).",
                recommendation: "No stress. Move it forward only if your legs feel fresh; otherwise keep the week gentle.",
                action: "Reschedule",
                source: .heuristic
            )
        }

        if let (run, daysAgo) = recentRun, daysAgo <= 2 {
            let runLabel = runDistanceLabel(run)
            if run.source != .runSmart {
                return PlanExplanation(
                    trigger: .importedActivity,
                    evidence: "Imported \(runLabel) from \(run.source.rawValue) \(relativeRunLabel(daysAgo: daysAgo)).",
                    recommendation: isRestDay ? "That load supports keeping today as recovery." : "Coach is keeping today conservative because that imported activity already counts.",
                    action: nil,
                    source: .heuristic
                )
            }

            if let today = resolvedTodayWorkout, !calendar.isDate(run.startedAt, inSameDayAs: today.scheduledDate) {
                return PlanExplanation(
                    trigger: .extraRun,
                    evidence: "You added a \(runLabel) run \(relativeRunLabel(daysAgo: daysAgo)) outside the planned slot.",
                    recommendation: "Keep the next workout controlled so weekly load does not jump.",
                    action: "Review plan",
                    source: .heuristic
                )
            }

            return PlanExplanation(
                trigger: .completedRun,
                evidence: "Recent \(runLabel) run is already in your training history.",
                recommendation: isRestDay ? "Today can stay as recovery." : "The plan can stay steady unless recovery changes.",
                action: nil,
                source: .heuristic
            )
        }

        if let (run, daysAgo) = recentRun, run.source != .runSmart {
            return PlanExplanation(
                trigger: .importedActivity,
                evidence: "An older \(runDistanceLabel(run)) \(run.source.rawValue) activity is available from \(daysAgo) days ago.",
                recommendation: "It informs your background load, but it is old enough that today stays based on the current plan.",
                action: nil,
                source: .heuristic
            )
        }

        if isRestDay {
            return PlanExplanation(
                trigger: .normal,
                evidence: "No run is scheduled for today.",
                recommendation: "Use the rest day to absorb the week and keep the next workout higher quality.",
                action: nil,
                source: .heuristic
            )
        }

        let workoutTitle = resolvedTodayWorkout?.title ?? recommendation.workoutTitle
        let workoutDistance = resolvedTodayWorkout?.distance ?? recommendation.distance
        return PlanExplanation(
            trigger: .normal,
            evidence: "\(workoutTitle) \(workoutDistance) matches your current plan and available recovery signals.",
            recommendation: "Run it as planned and keep the effort honest.",
            action: nil,
            source: .heuristic
        )
    }

    private static func isLowRecovery(_ recovery: RecoverySnapshot, recommendation: TodayRecommendation) -> Bool {
        let recoveryText = [recovery.hrv, recovery.sleep, recovery.recommendation, recommendation.readinessLabel, recommendation.recovery, recommendation.hrv]
            .joined(separator: " ")
            .lowercased()
        let stressText = recovery.stress.lowercased()
        return (recovery.readiness > 0 && recovery.readiness < 45) ||
            (recovery.bodyBattery > 0 && recovery.bodyBattery < 35) ||
            recommendation.readiness < 45 ||
            stressText.contains("high") ||
            stressText.contains("elevated") ||
            recoveryText.contains("low") ||
            recoveryText.contains("lower") ||
            recoveryText.contains("tired")
    }

    private static func lowRecoveryEvidence(_ recovery: RecoverySnapshot, recommendation: TodayRecommendation) -> String {
        if recovery.readiness > 0 {
            return "Recovery readiness is \(recovery.readiness) and Coach sees \(recovery.hrv.lowercased()) HRV."
        }
        if recovery.bodyBattery > 0 {
            return "Body battery is \(recovery.bodyBattery) with \(recovery.hrv.lowercased()) HRV."
        }
        return "Today's readiness is \(recommendation.readiness) (\(recommendation.readinessLabel))."
    }

    private static func isRestRecommendation(_ recommendation: TodayRecommendation) -> Bool {
        let joined = "\(recommendation.workoutTitle) \(recommendation.distance)".lowercased()
        return joined.contains("rest") || joined.contains("--")
    }

    private static func uniqueWorkouts(_ collections: [[WorkoutSummary]]) -> [WorkoutSummary] {
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

    static func uniqueWorkoutsForTodayState(_ collections: [[WorkoutSummary]]) -> [WorkoutSummary] {
        uniqueWorkouts(collections)
    }

    private static func isWorkout(_ workout: WorkoutSummary) -> Bool {
        distanceKm(from: workout.distance) > 0 || !workout.distance.localizedCaseInsensitiveContains("rest")
    }

    private static func distanceKm(from label: String) -> Double {
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "."))
        let token = label
            .components(separatedBy: allowed.inverted)
            .first { !$0.isEmpty } ?? ""
        return Double(token) ?? 0
    }

    private static func runDistanceLabel(_ run: RecordedRun) -> String {
        String(format: "%.1f km", run.distanceMeters / 1_000)
    }

    private static func relativeRunLabel(daysAgo: Int) -> String {
        if daysAgo == 0 { return "today" }
        if daysAgo == 1 { return "yesterday" }
        return "\(daysAgo) days ago"
    }

    private static func relativeDayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "yesterday" }
        if days > 1 { return "\(days) days ago" }
        return "earlier today"
    }
}

struct MetricTile: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var unit: String
    var symbol: String
    var tint: Color
}

struct CoachMessage: Identifiable {
    let id = UUID()
    var text: String
    var time: String
    var isUser: Bool
}

enum CoachEntryPoint: String, CaseIterable, Identifiable, Hashable {
    case today
    case plan
    case run
    case report
    case profile

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: "Today"
        case .plan: "Plan"
        case .run: "Run"
        case .report: "Report"
        case .profile: "Profile"
        }
    }

    var contextLabel: String {
        "\(displayName) context"
    }

    init(label: String) {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "plan", "workout", "training plan":
            self = .plan
        case "run", "post-run", "post run":
            self = .run
        case "report", "reports", "progress":
            self = .report
        case "profile", "settings":
            self = .profile
        default:
            self = .today
        }
    }
}

struct TrainingContextSnapshot: Hashable {
    var generatedAt: Date
    var entryPoint: CoachEntryPoint
    var runner: TrainingContextRunnerSummary
    var today: TrainingContextTodaySummary
    var plan: TrainingContextPlanSummary
    var recovery: TrainingContextRecoverySummary
    var wellness: TrainingContextWellnessSummary
    var activity: TrainingContextActivitySummary
    var routes: [TrainingContextRouteSummary]
    var reports: [TrainingContextReportSummary]
    var limitations: [String]

    var contextChips: [String] {
        var chips: [String] = []
        if today.readiness > 0 { chips.append("Readiness \(today.readiness)") }
        if let title = plan.activePlanTitle, !title.isEmpty { chips.append(title) }
        if activity.recentRunCount > 0 { chips.append("\(activity.recentRunCount) recent runs") }
        if !routes.isEmpty { chips.append("\(routes.count) routes") }
        if !reports.isEmpty { chips.append("\(reports.count) reports") }
        return chips.isEmpty ? ["Limited context"] : chips
    }
}

struct TrainingContextRunnerSummary: Hashable {
    var name: String
    var goal: String
    var level: String
    var streak: String
    var totalRuns: Int
    var totalDistanceKm: Int
    var totalTime: String
}

struct TrainingContextTodaySummary: Hashable {
    var readiness: Int
    var readinessLabel: String
    var workoutTitle: String
    var distance: String
    var pace: String
    var coachMessage: String
    var weeklyProgress: String
    var recovery: String
    var hrv: String
}

struct TrainingContextPlanSummary: Hashable {
    var activePlanTitle: String?
    var planType: String?
    var totalWeeks: Int?
    var weeklyWorkoutCount: Int
    var upcomingWorkouts: [TrainingContextWorkoutSummary]
}

struct TrainingContextWorkoutSummary: Identifiable, Hashable {
    var id: UUID
    var scheduledDate: Date
    var title: String
    var kind: WorkoutKind
    var distance: String
    var detail: String
    var isToday: Bool
    var isComplete: Bool
}

struct TrainingContextRecoverySummary: Hashable {
    var readiness: Int
    var bodyBattery: Int
    var sleep: String
    var hrv: String
    var stress: String
    var recommendation: String
}

struct TrainingContextWellnessSummary: Hashable {
    var calories: String
    var hydration: String
    var soreness: String
    var mood: String
    var checkInStatus: String
}

struct TrainingContextActivitySummary: Hashable {
    var recentRunCount: Int
    var recentRuns: [TrainingContextRunSummary]
    var sources: [String]
    var averageWeeklyDistanceKm: Double?
}

struct TrainingContextRunSummary: Identifiable, Hashable {
    var id: UUID
    var source: RunSmartDataSource
    var startedAt: Date
    var distanceKm: Double
    var movingTimeSeconds: TimeInterval
    var paceLabel: String
    var averageHeartRateBPM: Int?
    var hasRoute: Bool
    var routePointCount: Int
}

struct TrainingContextRouteSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var distanceKm: Double
    var elevationGainMeters: Int
    var estimatedDurationMinutes: Int
    var kind: RouteKind
    var recommendationReason: String?
    var isFavorite: Bool
    var hasGeometry: Bool
}

struct TrainingContextReportSummary: Identifiable, Hashable {
    var id: String
    var title: String
    var dateLabel: String
    var distance: String
    var pace: String
    var score: Int
    var insight: String
    var hasGeneratedReport: Bool
}

struct Achievement: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
}

enum RunSmartDataSource: String, Codable {
    case runSmart = "RunSmart"
    case garmin = "Garmin"
    case healthKit = "HealthKit"
}

struct RunRoutePoint: Identifiable, Codable, Hashable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double
    var altitude: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RecordedRun: Identifiable, Codable, Hashable {
    var id: UUID
    var providerActivityID: String?
    var consolidatedActivityID: String? = nil
    var source: RunSmartDataSource
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    var movingTimeSeconds: TimeInterval
    var averagePaceSecondsPerKm: Double
    var averageHeartRateBPM: Int?
    var routePoints: [RunRoutePoint]
    var routeMatchResult: RouteMatchResult? = nil
    var syncedAt: Date?
    /// Garmin device model (e.g. "Garmin Forerunner 265"), when known. Required for the
    /// "Garmin [device model]" attribution on Garmin-sourced rows per brand guidelines.
    var sourceDeviceName: String? = nil
}

enum RunSmartAttribution {
    static func sourceLabel(for run: RecordedRun, fallbackGarminDeviceName: String? = nil) -> String {
        guard run.source == .garmin else { return run.source.rawValue }

        if let deviceName = normalizedDeviceName(run.sourceDeviceName) {
            return deviceName
        }

        if let fallback = normalizedDeviceName(fallbackGarminDeviceName) {
            return fallback
        }

        return run.source.rawValue
    }

    static func runReportTitle(for run: RecordedRun, fallbackGarminDeviceName: String? = nil) -> String {
        "\(sourceLabel(for: run, fallbackGarminDeviceName: fallbackGarminDeviceName)) Run Report"
    }

    private static func normalizedDeviceName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.localizedCaseInsensitiveCompare("Garmin") == .orderedSame {
            return "Garmin"
        }
        if trimmed.lowercased().hasPrefix("garmin ") {
            let model = trimmed.dropFirst("garmin".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return model.isEmpty ? "Garmin" : "Garmin \(model)"
        }
        return "Garmin \(trimmed)"
    }
}

enum RouteKind: String, Codable, Hashable {
    case past
    case generated
    case saved
    case benchmark
}

struct RouteSuggestion: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var distanceKm: Double
    var elevationGainMeters: Int
    var estimatedDurationMinutes: Int
    var points: [RunRoutePoint]
    var kind: RouteKind
    var recommendationReason: String? = nil
    var savedRouteID: UUID? = nil
    var isFavorite: Bool = false
}

enum RouteRecommendationUnavailableReason: String, Codable, Hashable {
    case noRoutes
    case noWorkoutDistance
    case noRouteNearWorkout

    nonisolated var title: String {
        switch self {
        case .noRoutes:
            return "No routes ready yet"
        case .noWorkoutDistance:
            return "No planned distance yet"
        case .noRouteNearWorkout:
            return "No close route match"
        }
    }

    nonisolated var message: String {
        switch self {
        case .noRoutes:
            return "Record a GPS run, save a Garmin route, or generate a nearby loop to get coached route picks."
        case .noWorkoutDistance:
            return "Pick a route from your library, or start the run and let GPS record today's path."
        case .noRouteNearWorkout:
            return "Your saved routes are not close to today's workout distance. Choose manually or generate a better fit."
        }
    }
}

struct RouteRecommendation: Codable, Hashable {
    var route: RouteSuggestion?
    var reason: String
    var fitScore: Int
    var warning: String?
    var unavailableReason: RouteRecommendationUnavailableReason?

    var isAvailable: Bool {
        route != nil
    }

    nonisolated static func unavailable(_ reason: RouteRecommendationUnavailableReason) -> RouteRecommendation {
        RouteRecommendation(
            route: nil,
            reason: reason.message,
            fitScore: 0,
            warning: nil,
            unavailableReason: reason
        )
    }
}

// MARK: - Saved Routes & Benchmarks

enum RouteSource: String, Codable, Hashable {
    case recorded
    case garmin
    case generated
    case manual
}

struct SavedRoute: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var distanceMeters: Double
    var elevationGainMeters: Int
    var points: [RunRoutePoint]
    var source: RouteSource
    var tags: [String]
    var notes: String
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    var distanceKm: Double { distanceMeters / 1_000 }
    var hasRoutePoints: Bool { !points.isEmpty }

    static func from(run: RecordedRun, name: String, tags: [String] = [], notes: String = "") -> SavedRoute {
        let source: RouteSource = run.source == .garmin ? .garmin : .recorded
        var gain = 0.0
        for pair in zip(run.routePoints, run.routePoints.dropFirst()) {
            if let a = pair.0.altitude, let b = pair.1.altitude, b > a {
                gain += b - a
            }
        }
        let now = Date()
        return SavedRoute(
            id: UUID(),
            name: name,
            distanceMeters: run.distanceMeters,
            elevationGainMeters: Int(gain.rounded()),
            points: run.routePoints,
            source: source,
            tags: tags,
            notes: notes,
            isFavorite: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct BenchmarkRoute: Identifiable, Codable, Hashable {
    var id: UUID
    var savedRouteID: UUID
    var enabledAt: Date
    var historicalRunCount: Int
    var personalBestSeconds: TimeInterval?
    var personalBestDate: Date?
    var averagePaceSecondsPerKm: Double?
    var averageDurationSeconds: TimeInterval?
}

enum RouteMatchConfidence: String, Codable, Hashable {
    case matched
    case possibleMatch
    case noMatch
}

struct RouteMatchResult: Codable, Hashable {
    var routeID: UUID?
    var candidateRouteID: UUID?
    var confidence: RouteMatchConfidence
    var distanceDeltaMeters: Double
    var startDeltaMeters: Double
    var endDeltaMeters: Double
    var shapeSimilarity: Double
    var isReversed: Bool
}

enum BenchmarkRouteTrend: String, Codable, Hashable {
    case improving
    case steady
    case slowing
    case notEnoughData
}

struct BenchmarkRunPerformance: Identifiable, Codable, Hashable {
    var id: UUID { runID }
    var runID: UUID
    var source: RunSmartDataSource
    var startedAt: Date
    var durationSeconds: TimeInterval
    var paceSecondsPerKm: Double
    var averageHeartRateBPM: Int?
}

struct BenchmarkPerformanceAverage: Codable, Hashable {
    var routeID: UUID
    var runCount: Int
    var averageDurationSeconds: TimeInterval
    var averagePaceSecondsPerKm: Double
    var bestPaceSecondsPerKm: Double
    var averageHeartRateBPM: Int?
}

struct MonthlyBenchmarkAverage: Codable, Hashable {
    var routeID: UUID
    var monthStart: Date
    var runCount: Int
    var averageDurationSeconds: TimeInterval
    var averagePaceSecondsPerKm: Double
    var bestPaceSecondsPerKm: Double
    var averageHeartRateBPM: Int?
    var hasEnoughData: Bool
}

struct BenchmarkRouteComparison: Codable, Hashable {
    var routeID: UUID
    var routeName: String
    var matchConfidence: RouteMatchConfidence
    var currentPerformance: BenchmarkRunPerformance
    var previousPerformance: BenchmarkRunPerformance?
    var personalBest: BenchmarkRunPerformance
    var allTimeAverage: BenchmarkPerformanceAverage
    var monthlyAverage: MonthlyBenchmarkAverage
    var recentTrend: BenchmarkRouteTrend

    var hasEnoughHistory: Bool {
        allTimeAverage.runCount >= 2
    }
}

struct OnboardingProfile: Codable, Equatable {
    var displayName: String
    var goal: String
    var experience: String
    var age: Int?
    var averageWeeklyDistanceKm: Double?
    var trainingDataSource: TrainingDataSource?
    var trainingDataUpdatedAt: Date?
    var weeklyRunDays: Int
    var preferredDays: [String]
    var units: String
    var coachingTone: String
    var notificationsEnabled: Bool
    var planAdjustmentConfirmationsEnabled: Bool

    static let empty = OnboardingProfile(
        displayName: "",
        goal: "10K improvement",
        experience: "Building base",
        age: nil,
        averageWeeklyDistanceKm: nil,
        trainingDataSource: nil,
        trainingDataUpdatedAt: nil,
        weeklyRunDays: 4,
        preferredDays: ["Tue", "Thu", "Sat", "Sun"],
        units: "Metric",
        coachingTone: "Motivating",
        notificationsEnabled: true,
        planAdjustmentConfirmationsEnabled: true
    )
}

enum TrainingDataSource: String, Codable, Hashable {
    case manual
    case garmin
    case runSmart

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .garmin: "Garmin"
        case .runSmart: "RunSmart runs"
        }
    }
}

enum TrainingDataBaseline {
    static func averageWeeklyDistanceKm(
        from runs: [RecordedRun],
        now: Date = Date(),
        windowWeeks: Int = 4,
        calendar: Calendar = .current
    ) -> Double? {
        let weeks = max(1, windowWeeks)
        guard let start = calendar.date(byAdding: .day, value: -(weeks * 7), to: now) else { return nil }
        let distanceKm = runs
            .filter { $0.startedAt >= start && $0.startedAt <= now && $0.distanceMeters > 0 }
            .reduce(0.0) { $0 + ($1.distanceMeters / 1_000) }
        guard distanceKm > 0 else { return nil }
        return (distanceKm / Double(weeks) * 10).rounded() / 10
    }

    static func planAverageWeeklyKm(saved: Double?, runs: [RecordedRun], now: Date = Date()) -> Double? {
        if let saved, saved > 0 { return saved }
        return averageWeeklyDistanceKm(from: runs, now: now)
    }

    static func inferredSource(from runs: [RecordedRun]) -> TrainingDataSource? {
        if runs.contains(where: { $0.source == .garmin }) { return .garmin }
        if runs.contains(where: { $0.source == .runSmart || $0.source == .healthKit }) { return .runSmart }
        return nil
    }
}

enum DeviceConnectionState: String, Codable {
    case disconnected
    case connecting
    case connected
    case error
}

struct ConnectedDeviceStatus: Identifiable, Codable, Hashable {
    var id: String { provider }
    var provider: String
    var state: DeviceConnectionState
    var lastSuccessfulSync: Date?
    var permissions: [String]
    var message: String?
    /// Garmin only reports device identity on activity records, never on daily/wellness
    /// summaries - this is the most recently seen device name, cached on garmin_connections.
    var deviceName: String? = nil
}

enum FirstSyncReviewProvider: String, Codable, Hashable {
    case garmin
    case healthKit

    var displayName: String {
        switch self {
        case .garmin: "Garmin"
        case .healthKit: "HealthKit"
        }
    }

    var serviceName: String {
        switch self {
        case .garmin: "Garmin Connect"
        case .healthKit: "HealthKit"
        }
    }

    init?(serviceName: String) {
        if serviceName == "Garmin Connect" || serviceName == "Garmin" {
            self = .garmin
        } else if serviceName == "HealthKit" {
            self = .healthKit
        } else {
            return nil
        }
    }
}

enum FirstSyncNextAction: String, Codable, Hashable {
    case today
    case report
    case plan

    var title: String {
        switch self {
        case .today: "Open Today"
        case .report: "Review Reports"
        case .plan: "Review Plan"
        }
    }
}

struct FirstSyncActivitySummary: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var dateLabel: String
    var distanceLabel: String
    var hasRoute: Bool

    nonisolated static func from(_ run: RecordedRun) -> FirstSyncActivitySummary {
        FirstSyncActivitySummary(
            id: run.providerActivityID ?? run.id.uuidString,
            title: "\(run.source.rawValue) run",
            dateLabel: run.startedAt.formatted(date: .abbreviated, time: .shortened),
            distanceLabel: String(format: "%.1f km", run.distanceMeters / 1_000),
            hasRoute: !run.routePoints.isEmpty
        )
    }
}

struct FirstSyncReview: Identifiable, Codable, Hashable {
    var id: String { provider.rawValue }
    var provider: FirstSyncReviewProvider
    var importedCount: Int
    var skippedDuplicateCount: Int
    var routeAvailabilityCount: Int
    var routeLessCount: Int
    var recentImportedActivities: [FirstSyncActivitySummary]
    var coachCanUse: [String]
    var nextAction: FirstSyncNextAction
    var seen: Bool
    var createdAt: Date

    var summary: String {
        if importedCount == 0, skippedDuplicateCount == 0 {
            return "No new running activities were available from \(provider.displayName) yet."
        }
        if importedCount == 0, skippedDuplicateCount > 0 {
            return "RunSmart found \(skippedDuplicateCount) already saved or hidden \(activityWord(skippedDuplicateCount)) and did not create duplicates."
        }
        let skipped = skippedDuplicateCount > 0 ? " and skipped \(skippedDuplicateCount) duplicate or hidden \(activityWord(skippedDuplicateCount))" : ""
        return "Imported \(importedCount) \(activityWord(importedCount))\(skipped)."
    }

    var routeSummary: String {
        if importedCount == 0 {
            return "No route data changed in this sync."
        }
        if routeAvailabilityCount == 0 {
            return "\(provider.displayName) did not provide GPS routes for these imports, so route maps and saved-route matching stay limited."
        }
        if routeLessCount == 0 {
            return "Routes are available for all imported activities."
        }
        return "Routes are available for \(routeAvailabilityCount) imported \(activityWord(routeAvailabilityCount)); \(routeLessCount) imported \(activityWord(routeLessCount)) came without route data."
    }

    static func make(
        provider: FirstSyncReviewProvider,
        importedRuns: [RecordedRun],
        skippedDuplicateCount: Int,
        seen: Bool = false,
        createdAt: Date = Date()
    ) -> FirstSyncReview {
        let routeCount = importedRuns.filter { !$0.routePoints.isEmpty }.count
        let routeLess = max(0, importedRuns.count - routeCount)
        let next: FirstSyncNextAction
        if importedRuns.isEmpty {
            next = .today
        } else if importedRuns.contains(where: { !$0.routePoints.isEmpty }) {
            next = .report
        } else {
            next = .plan
        }
        return FirstSyncReview(
            provider: provider,
            importedCount: importedRuns.count,
            skippedDuplicateCount: skippedDuplicateCount,
            routeAvailabilityCount: routeCount,
            routeLessCount: routeLess,
            recentImportedActivities: importedRuns
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(3)
                .map(FirstSyncActivitySummary.from),
            coachCanUse: coachUseItems(provider: provider, importedRuns: importedRuns),
            nextAction: next,
            seen: seen,
            createdAt: createdAt
        )
    }

    private static func coachUseItems(provider: FirstSyncReviewProvider, importedRuns: [RecordedRun]) -> [String] {
        var items: [String] = []
        if importedRuns.isEmpty {
            items.append("Connection status and future sync checks")
            if provider == .healthKit {
                items.append("Health wellness signals when permission allows")
            }
            return items
        }
        items.append("Recent distance, pace, and training history")
        if importedRuns.contains(where: { $0.averageHeartRateBPM != nil }) {
            items.append("Heart-rate context from imported workouts")
        }
        if importedRuns.contains(where: { !$0.routePoints.isEmpty }) {
            items.append("Route-aware run review when GPS route data exists")
        }
        if provider == .healthKit {
            items.append("Health wellness signals when permission allows")
        }
        return items
    }

    private func activityWord(_ count: Int) -> String {
        count == 1 ? "activity" : "activities"
    }
}

enum RunRecordingPhase: String {
    case idle
    case requestingPermission
    case acquiringLocation
    case ready
    case recording
    case paused
    case denied
    case failed
}

struct GoalSummary: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var progress: Double
    var target: String
    var daysRemaining: Int?
    var trendLabel: String
}

struct ChallengeSummary: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var progress: Double
    var dayLabel: String
    var isActive: Bool
}

enum HRVSource: String, Codable, Hashable {
    case garmin
    case appleHealth
    case unknown

    var attributionLabel: String? {
        switch self {
        case .garmin:
            return "Garmin"
        case .appleHealth:
            return "Apple Health"
        case .unknown:
            return nil
        }
    }
}

struct HRVReading: Hashable {
    var value: Double
    var source: HRVSource
}

enum HRVResolver {
    static func resolve(garminDirect: HRVReading?, healthKit: HRVReading?) -> HRVReading? {
        if let garminDirect {
            return HRVReading(value: garminDirect.value, source: .garmin)
        }
        guard let healthKit else { return nil }
        switch healthKit.source {
        case .garmin, .appleHealth:
            return healthKit
        case .unknown:
            return healthKit
        }
    }
}

struct RecoverySnapshot: Hashable {
    var readiness: Int
    var bodyBattery: Int
    var sleep: String
    var hrv: String
    var hrvSource: HRVSource = .unknown
    var stress: String
    var recommendation: String
}

struct WellnessSnapshot: Hashable {
    var calories: String
    var hydration: String
    var soreness: String
    var mood: String
    var checkInStatus: String
}

/// Today's activity metrics read from Apple HealthKit (steps, active calories, sleep).
/// These are HealthKit-sourced, so the UI attributes them to "Apple Health" (see HRV policy).
struct HealthDailySummary: Hashable {
    var steps: Int?
    var activeCalories: Int?
    var sleepSeconds: TimeInterval?

    static let empty = HealthDailySummary(steps: nil, activeCalories: nil, sleepSeconds: nil)

    var hasAnyData: Bool { steps != nil || activeCalories != nil || sleepSeconds != nil }

    var stepsDisplay: String {
        guard let steps else { return "--" }
        return steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000) : "\(steps)"
    }

    var caloriesDisplay: String { activeCalories.map { "\($0)" } ?? "--" }

    var sleepDisplay: String {
        guard let sleepSeconds, sleepSeconds > 0 else { return "--" }
        let totalMinutes = Int(sleepSeconds / 60)
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }
}

struct DailyWellnessPoint: Hashable {
    var date: Date
    var hrvMilliseconds: Double?
    var hrvSource: HRVSource = .unknown
    var trainingReadiness: Int?
    var bodyBattery: Int?
}

struct WellnessTrendSeries: Hashable {
    var days: [DailyWellnessPoint]
    var hrvBars: [CGFloat]
    var readinessBars: [CGFloat]
    var hrvTrendSummary: String
    var readinessTrendSummary: String
    var latestHRVDisplay: String
    var latestHRVSource: HRVSource = .unknown
    var latestReadinessDisplay: String

    static let empty = WellnessTrendSeries(
        days: [],
        hrvBars: [],
        readinessBars: [],
        hrvTrendSummary: "Need more synced days",
        readinessTrendSummary: "Need more synced days",
        latestHRVDisplay: "--",
        latestHRVSource: .unknown,
        latestReadinessDisplay: "--"
    )
}

struct ShoeSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var distanceKm: Double
    var limitKm: Double
    var status: String
}

struct ReminderPreference: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var enabled: Bool
}

struct RunReportSummary: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var dateLabel: String
    var distance: String
    var pace: String
    var score: Int
    var insight: String
    var source: String = ""
    var runID: String? = nil
    var duration: String = "—"
    var averageHeartRate: String = "—"
    var isGenerated: Bool? = true

    var hasGeneratedReport: Bool {
        isGenerated ?? true
    }
}

struct CoachRunNotes: Codable, Hashable {
    var summary: String
    var effort: String
    var recovery: String
    var nextSessionNudge: String
    var keyInsights: [String]? = nil
    var pacing: String? = nil
    var biomechanics: String? = nil
    var recoveryTimeline: [String]? = nil
}

struct StructuredNextWorkout: Codable, Hashable {
    var title: String
    var dateLabel: String?
    var distance: String?
    var target: String?
    var notes: String?
}

struct RunReportDetail: Identifiable, Codable, Hashable {
    var id: String
    var runID: String
    var title: String
    var dateLabel: String
    var source: String
    var distance: String
    var duration: String
    var averagePace: String
    var averageHeartRate: String
    var coachScore: Int?
    var notes: CoachRunNotes
    var structuredNextWorkout: StructuredNextWorkout?
    var isGenerated: Bool? = true

    var hasGeneratedReport: Bool {
        isGenerated ?? true
    }

    var summary: RunReportSummary {
        RunReportSummary(
            id: id,
            title: title,
            dateLabel: dateLabel,
            distance: distance,
            pace: averagePace,
            score: coachScore ?? 0,
            insight: notes.summary,
            source: source,
            runID: runID,
            duration: duration,
            averageHeartRate: averageHeartRate,
            isGenerated: isGenerated
        )
    }

    func withGarminDeviceFallback(for run: RecordedRun, fallbackGarminDeviceName: String?) -> RunReportDetail {
        guard run.source == .garmin else { return self }
        var copy = self
        let sourceLabel = RunSmartAttribution.sourceLabel(for: run, fallbackGarminDeviceName: fallbackGarminDeviceName)
        copy.source = sourceLabel
        copy.title = "\(sourceLabel) Run Report"
        return copy
    }
}

struct PostRunDebriefModel: Hashable {
    enum Source: String, Hashable {
        case ai
        case fallback
    }

    var headline: String
    var debrief: String
    var tomorrow: String
    var planImpact: String?
    var source: Source

    static func fallback(for run: RecordedRun?) -> PostRunDebriefModel {
        let distanceKm = (run?.distanceMeters ?? 0) / 1_000
        let durationMin = Int((run?.movingTimeSeconds ?? 0) / 60)
        let distanceStr = distanceKm > 0 ? String(format: "%.1f km", distanceKm) : "this effort"
        let durationStr = durationMin > 0 ? " in \(durationMin) min" : ""
        return PostRunDebriefModel(
            headline: "Run logged",
            debrief: "You covered \(distanceStr)\(durationStr). RunSmart has recorded this effort.",
            tomorrow: "Check Today tomorrow for your next recommended session.",
            planImpact: nil,
            source: .fallback
        )
    }
}

struct WeeklyProgressSummary: Hashable, Codable {
    enum Source: String, Hashable, Codable {
        case ai
        case fallback
    }

    var headline: String
    var narrative: String
    var forwardLook: String
    var weekLabel: String
    var generatedDate: Date
    var isoWeekKey: String         // e.g. "2026-W21" -- cache key
    var source: Source

    static func fallback(runsCompleted: Int, totalDistanceKm: Double) -> WeeklyProgressSummary {
        let distanceStr = String(format: "%.1f km", totalDistanceKm)
        let runWord = runsCompleted == 1 ? "run" : "runs"
        return WeeklyProgressSummary(
            headline: "\(runsCompleted) \(runWord) · \(distanceStr)",
            narrative: "A solid week of training. RunSmart has logged your effort.",
            forwardLook: "Check Today for your next recommended session.",
            weekLabel: "This week",
            generatedDate: Date(),
            isoWeekKey: WeeklyProgressSummary.currentISOWeekKey(),
            source: .fallback
        )
    }

    static func currentISOWeekKey() -> String {
        // ISO 8601 calendar guarantees deterministic week boundaries regardless of device locale.
        // Using .component(_:from:) returns Int directly — no optional unwrapping needed.
        var iso = Calendar(identifier: .iso8601)
        iso.locale = Locale(identifier: "en_US_POSIX")
        let year = iso.component(.yearForWeekOfYear, from: Date())
        let week = iso.component(.weekOfYear, from: Date())
        return String(format: "%04d-W%02d", year, week)
    }

    static func isNewWeek(since lastKey: String) -> Bool {
        currentISOWeekKey() != lastKey
    }
}

struct PostActivityOutcome: Hashable {
    var canonicalRun: RecordedRun
    var report: RunReportDetail?
    var completedWorkout: WorkoutSummary?
    var didCompletePlannedWorkout: Bool
    var debrief: PostRunDebriefModel?          // E6: AI post-run debrief
}

struct TrainingLoadSnapshot: Hashable {
    var loadLabel: String
    var loadValue: Int
    var acwr: String
    var consistency: Int
    var paceTrend: String
    var weeklyRecap: String
}

struct ShareableAchievement: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var symbol: String
    var tintName: String
}

extension GoalSummary {
    static let loading = GoalSummary(id: "", title: "—", detail: "", progress: 0, target: "—", daysRemaining: nil, trendLabel: "—")
}

extension ChallengeSummary {
    static let loading = ChallengeSummary(id: "", title: "—", detail: "", progress: 0, dayLabel: "—", isActive: false)
}

extension RecoverySnapshot {
    static let loading = RecoverySnapshot(readiness: 0, bodyBattery: 0, sleep: "—", hrv: "—", stress: "—", recommendation: "Loading recovery data…")
}

extension WellnessSnapshot {
    static let empty = WellnessSnapshot(calories: "—", hydration: "—", soreness: "—", mood: "—", checkInStatus: "No wellness check-in yet.")
}

extension TrainingLoadSnapshot {
    static let loading = TrainingLoadSnapshot(loadLabel: "—", loadValue: 0, acwr: "—", consistency: 0, paceTrend: "—", weeklyRecap: "Loading training data…")
}
