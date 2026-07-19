import Foundation
import SwiftUI
import CoreLocation

protocol TodayProviding {
    func todayRecommendation() async -> TodayRecommendation
}

protocol PlanProviding {
    func weeklyPlan() async -> [WorkoutSummary]
    func activeTrainingPlan() async -> TrainingPlanSnapshot?
    func planWorkouts(from startDate: Date, to endDate: Date) async -> [WorkoutSummary]
    func nextWorkouts(limit: Int) async -> [WorkoutSummary]
    func saveTrainingGoal(_ request: TrainingGoalRequest) async -> Bool
    func regenerateTrainingPlan(_ request: TrainingGoalRequest) async -> Bool
    func moveWorkout(workoutID: UUID, to date: Date) async -> Bool
    func pushWorkoutTomorrow(workoutID: UUID) async -> Bool
    func amendWorkout(workoutID: UUID, patch: WorkoutPatch) async -> Bool
    func removeWorkout(workoutID: UUID) async -> Bool
    func applyFlexWeek(_ outcome: FlexWeekOutcome) async -> Bool
    func saveSuggestedWorkout(_ suggestion: StructuredNextWorkout, from report: RunReportDetail) async -> Bool
}

enum RunSmartPlanGenerationStatus {
    case generating
    case amended
    case failed
}

extension PlanProviding {
    func saveTrainingGoal(_ request: TrainingGoalRequest) async -> Bool { false }
    func regenerateTrainingPlan(_ request: TrainingGoalRequest) async -> Bool { false }
    func moveWorkout(workoutID: UUID, to date: Date) async -> Bool { false }
    func pushWorkoutTomorrow(workoutID: UUID) async -> Bool { false }
    func amendWorkout(workoutID: UUID, patch: WorkoutPatch) async -> Bool { false }
    func removeWorkout(workoutID: UUID) async -> Bool { false }
    func applyFlexWeek(_ outcome: FlexWeekOutcome) async -> Bool { false }
    func saveSuggestedWorkout(_ suggestion: StructuredNextWorkout, from report: RunReportDetail) async -> Bool { false }
}

protocol CoachChatting {
    func recentMessages() async -> [CoachMessage]
    func send(message: String) async -> CoachMessage
    func send(message: String, context: TrainingContextSnapshot) async -> CoachMessage
}

extension CoachChatting {
    func send(message: String, context: TrainingContextSnapshot) async -> CoachMessage {
        TrainingContextCoachResponder.response(to: message, context: context)
    }
}

protocol ProfileProviding {
    func runnerProfile() async -> RunnerProfile
    func achievements() async -> [Achievement]
}

protocol RunLogging {
    func currentRunMetrics() async -> [MetricTile]
    func recentRuns() async -> [RecordedRun]
    func saveManualRun(kind: WorkoutKind, date: Date, distanceKm: Double, durationMinutes: Int, averageHeartRateBPM: Int?, notes: String) async -> RecordedRun
    func updateRunRPE(_ run: RecordedRun, rpe: Int?) async -> RecordedRun
    func removeRun(_ run: RecordedRun) async -> Bool
    func finishRun() async
}

extension RunLogging {
    func updateRunRPE(_ run: RecordedRun, rpe: Int?) async -> RecordedRun {
        var updated = run
        updated.rpe = rpe
        return updated
    }
}

protocol TrainingContextProviding {
    func trainingContext(for entryPoint: CoachEntryPoint) async -> TrainingContextSnapshot
}

protocol WebParityProviding {
    func activeGoal() async -> GoalSummary
    func activeChallenge() async -> ChallengeSummary
    func recoverySnapshot() async -> RecoverySnapshot
    func wellnessSnapshot() async -> WellnessSnapshot
    func wellnessTrendSeries(days: Int) async -> WellnessTrendSeries
    func todayHealthSummary() async -> HealthDailySummary
    func shoes() async -> [ShoeSummary]
    func reminders() async -> [ReminderPreference]
    func latestRunReports(limit: Int) async -> [RunReportSummary]
    func runReport(for run: RecordedRun) async -> RunReportDetail?
    func generateRunReportIfMissing(for run: RecordedRun) async -> RunReportDetail?
    func generateRunReportIfMissing(forRunID runID: String) async -> RunReportDetail?
    func processCompletedActivity(_ run: RecordedRun) async -> PostActivityOutcome
    func matchRoute(for run: RecordedRun) async -> RouteMatchResult?
    func benchmarkComparison(for run: RecordedRun) async -> BenchmarkRouteComparison?
    func trainingLoadSnapshot() async -> TrainingLoadSnapshot
    func shareableAchievements() async -> [ShareableAchievement]
    func shouldPresentManualMorningCheckin() async -> Bool
    func approveGarminMorningCheckin() async -> Bool
    func saveMorningCheckin(energy: Int, soreness: Int, mood: String, stress: Int?, fatigue: Int?, notes: String?) async -> Bool
    func generateWeeklySummary() async -> WeeklyProgressSummary?
    func flexCurrentWeek(_ request: FlexWeekRequest) async -> FlexWeekOutcome
    func adjustmentHistoryWithin(_ window: TimeInterval) async -> [FlexWeekRecord]
}

extension WebParityProviding {
    func activeGoal() async -> GoalSummary { .loading }
    func activeChallenge() async -> ChallengeSummary { .loading }
    func recoverySnapshot() async -> RecoverySnapshot { .loading }
    func wellnessSnapshot() async -> WellnessSnapshot { .empty }
    func wellnessTrendSeries(days: Int = 7) async -> WellnessTrendSeries { .empty }
    func todayHealthSummary() async -> HealthDailySummary { .empty }
    func shoes() async -> [ShoeSummary] { [] }
    func reminders() async -> [ReminderPreference] { [] }
    func latestRunReports(limit: Int) async -> [RunReportSummary] { [] }
    func runReport(for run: RecordedRun) async -> RunReportDetail? { nil }
    func generateRunReportIfMissing(for run: RecordedRun) async -> RunReportDetail? { nil }
    func generateRunReportIfMissing(forRunID runID: String) async -> RunReportDetail? { nil }
    func processCompletedActivity(_ run: RecordedRun) async -> PostActivityOutcome {
        PostActivityOutcome(canonicalRun: run, report: nil, completedWorkout: nil, didCompletePlannedWorkout: false, debrief: nil)
    }
    func matchRoute(for run: RecordedRun) async -> RouteMatchResult? { nil }
    func benchmarkComparison(for run: RecordedRun) async -> BenchmarkRouteComparison? { nil }
    func trainingLoadSnapshot() async -> TrainingLoadSnapshot { .loading }
    func shareableAchievements() async -> [ShareableAchievement] { [] }
    func shouldPresentManualMorningCheckin() async -> Bool { true }
    func approveGarminMorningCheckin() async -> Bool { false }
    func saveMorningCheckin(energy: Int, soreness: Int, mood: String, stress: Int?, fatigue: Int?, notes: String?) async -> Bool { false }
    func generateWeeklySummary() async -> WeeklyProgressSummary? { nil }

    func flexCurrentWeek(_ request: FlexWeekRequest) async -> FlexWeekOutcome {
        FlexWeekServiceSupport.deterministicOutcome(for: request)
    }

    func adjustmentHistoryWithin(_ window: TimeInterval) async -> [FlexWeekRecord] {
        FlexWeekAdjustmentHistory.historyWithin(window)
    }

    func latestRunReports() async -> [RunReportSummary] {
        await latestRunReports(limit: 3)
    }
}

extension TrainingContextProviding where Self: TodayProviding & PlanProviding & ProfileProviding & RunLogging & WebParityProviding & RouteProviding {
    func trainingContext(for entryPoint: CoachEntryPoint) async -> TrainingContextSnapshot {
        async let runnerTask = runnerProfile()
        async let todayTask = todayRecommendation()
        async let activePlanTask = activeTrainingPlan()
        async let weekTask = weeklyPlan()
        async let nextTask = nextWorkouts(limit: 3)
        async let recoveryTask = recoverySnapshot()
        async let wellnessTask = wellnessSnapshot()
        async let runsTask = recentRuns()
        async let routesTask = rankedRouteSuggestions(targetDistanceKm: nil)
        async let reportsTask = latestRunReports(limit: 3)

        let (runner, today, activePlan, week, next, recovery, wellness, runs, routes, reports) = await (
            runnerTask,
            todayTask,
            activePlanTask,
            weekTask,
            nextTask,
            recoveryTask,
            wellnessTask,
            runsTask,
            routesTask,
            reportsTask
        )

        let limitedRuns = Array(runs.prefix(5))
        let limitedRoutes = Array(routes.prefix(3))
        let limitedReports = Array(reports.prefix(3))
        let runSources = Array(Set(limitedRuns.map(\.source.rawValue))).sorted()

        let planSummary = TrainingContextPlanSummary(
            activePlanTitle: activePlan?.title,
            planType: activePlan?.planType,
            totalWeeks: activePlan?.totalWeeks,
            weeklyWorkoutCount: week.count,
            upcomingWorkouts: next.prefix(3).map(Self.workoutContext)
        )
        let activitySummary = TrainingContextActivitySummary(
            recentRunCount: runs.count,
            recentRuns: limitedRuns.map(Self.runContext),
            sources: runSources,
            averageWeeklyDistanceKm: TrainingDataBaseline.averageWeeklyDistanceKm(from: runs)
        )

        return TrainingContextSnapshot(
            generatedAt: Date(),
            entryPoint: entryPoint,
            runner: TrainingContextRunnerSummary(
                name: runner.name,
                goal: runner.goal,
                level: runner.level,
                streak: runner.streak,
                totalRuns: runner.totalRuns,
                totalDistanceKm: runner.totalDistance,
                totalTime: runner.totalTime
            ),
            today: TrainingContextTodaySummary(
                readiness: today.readiness,
                readinessLabel: today.readinessLabel,
                workoutTitle: today.workoutTitle,
                distance: today.distance,
                pace: today.pace,
                coachMessage: today.coachMessage,
                weeklyProgress: today.weeklyProgress,
                recovery: today.recovery,
                hrv: today.hrv
            ),
            plan: planSummary,
            recovery: TrainingContextRecoverySummary(
                readiness: recovery.readiness,
                bodyBattery: recovery.bodyBattery,
                sleep: recovery.sleep,
                hrv: recovery.hrv,
                stress: recovery.stress,
                recommendation: recovery.recommendation
            ),
            wellness: TrainingContextWellnessSummary(
                calories: wellness.calories,
                hydration: wellness.hydration,
                soreness: wellness.soreness,
                mood: wellness.mood,
                checkInStatus: wellness.checkInStatus
            ),
            activity: activitySummary,
            routes: limitedRoutes.map(Self.routeContext),
            reports: limitedReports.map(Self.reportContext),
            limitations: Self.limitations(
                today: today,
                activePlan: activePlan,
                week: week,
                next: next,
                recovery: recovery,
                wellness: wellness,
                runs: runs,
                routes: routes,
                reports: reports
            )
        )
    }

    private static func workoutContext(_ workout: WorkoutSummary) -> TrainingContextWorkoutSummary {
        TrainingContextWorkoutSummary(
            id: workout.id,
            scheduledDate: workout.scheduledDate,
            title: workout.title,
            kind: workout.kind,
            distance: workout.distance,
            detail: workout.detail,
            isToday: workout.isToday,
            isComplete: workout.isComplete
        )
    }

    private static func runContext(_ run: RecordedRun) -> TrainingContextRunSummary {
        TrainingContextRunSummary(
            id: run.id,
            source: run.source,
            startedAt: run.startedAt,
            distanceKm: (run.distanceMeters / 1_000 * 10).rounded() / 10,
            movingTimeSeconds: run.movingTimeSeconds,
            paceLabel: RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm),
            averageHeartRateBPM: run.averageHeartRateBPM,
            hasRoute: !run.routePoints.isEmpty,
            routePointCount: run.routePoints.count
        )
    }

    private static func routeContext(_ route: RouteSuggestion) -> TrainingContextRouteSummary {
        TrainingContextRouteSummary(
            id: route.id,
            name: route.name,
            distanceKm: route.distanceKm,
            elevationGainMeters: route.elevationGainMeters,
            estimatedDurationMinutes: route.estimatedDurationMinutes,
            kind: route.kind,
            recommendationReason: route.recommendationReason,
            isFavorite: route.isFavorite,
            hasGeometry: !route.points.isEmpty
        )
    }

    private static func reportContext(_ report: RunReportSummary) -> TrainingContextReportSummary {
        TrainingContextReportSummary(
            id: report.id,
            title: report.title,
            dateLabel: report.dateLabel,
            distance: report.distance,
            pace: report.pace,
            score: report.score,
            insight: report.insight,
            hasGeneratedReport: report.hasGeneratedReport
        )
    }

    private static func limitations(
        today: TodayRecommendation,
        activePlan: TrainingPlanSnapshot?,
        week: [WorkoutSummary],
        next: [WorkoutSummary],
        recovery: RecoverySnapshot,
        wellness: WellnessSnapshot,
        runs: [RecordedRun],
        routes: [RouteSuggestion],
        reports: [RunReportSummary]
    ) -> [String] {
        var values: [String] = []
        if today.readiness <= 0 {
            values.append("Readiness is not available yet.")
        }
        if activePlan == nil && week.isEmpty && next.isEmpty {
            values.append("No active training plan is available yet.")
        }
        if runs.isEmpty {
            values.append("No recent runs are available yet.")
        }
        if recovery.readiness <= 0 && isBlank(recovery.sleep) && isBlank(recovery.hrv) {
            values.append("Recovery data is limited until Garmin or HealthKit syncs.")
        }
        if isBlank(wellness.mood) && wellness.checkInStatus == WellnessSnapshot.empty.checkInStatus {
            values.append("No wellness check-in is available yet.")
        }
        if routes.isEmpty {
            values.append("No saved or suggested routes are available yet.")
        }
        if reports.isEmpty {
            values.append("No run reports are available yet.")
        }
        return values
    }

    private static func isBlank(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "--" || trimmed == "—" || trimmed.lowercased() == "loading"
    }
}

enum TrainingContextCoachResponder {
    static func response(to message: String, context: TrainingContextSnapshot) -> CoachMessage {
        if containsMedicalCaution(message) {
            return CoachMessage(
                text: "If you are feeling pain, dizziness, chest pain, fainting, or severe symptoms, stop the activity and consult a qualified professional. Keep today's choice conservative and do not try to push through it.",
                time: "Now",
                isUser: false
            )
        }

        let text: String
        switch context.entryPoint {
        case .today:
            if context.today.readiness > 0 {
                text = "Today I see readiness at \(context.today.readiness) (\(context.today.readinessLabel)). \(nextWorkoutSentence(context))"
            } else {
                text = "Today context is limited. Add a plan, recent run, or recovery signal and I can give a sharper recommendation."
            }
        case .plan:
            if let next = context.plan.upcomingWorkouts.first {
                text = "For the plan, your next workout is \(next.title) at \(next.distance). I would keep the week anchored around that unless recovery changes."
            } else if let plan = context.plan.activePlanTitle {
                text = "I can see your \(plan) plan, but there are no upcoming workouts loaded yet."
            } else {
                text = "I do not see an active plan yet. Set a goal or sync plan data before making workout changes."
            }
        case .run:
            if let run = context.activity.recentRuns.first {
                text = "Your latest run was \(String(format: "%.1f", run.distanceKm)) km at \(run.paceLabel) /km. I would use that with recovery before changing the next session."
            } else {
                text = "I do not see a recent run yet. Record, import, or manually add one so I can coach from actual activity."
            }
        case .report:
            if let report = context.reports.first {
                text = "Your latest report says: \(report.insight) Use that trend alongside the next planned workout."
            } else {
                text = "No run report is available yet. Finish a run or import an activity to unlock report-aware coaching."
            }
        case .profile:
            text = "I have your goal as \(context.runner.goal) and your level as \(context.runner.level). Training changes should stay aligned with that profile."
        }

        _ = message
        return CoachMessage(text: text, time: "Now", isUser: false)
    }

    private static func containsMedicalCaution(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("pain")
            || lower.contains("dizzy")
            || lower.contains("dizziness")
            || lower.contains("chest pain")
            || lower.contains("faint")
            || lower.contains("severe")
    }

    private static func nextWorkoutSentence(_ context: TrainingContextSnapshot) -> String {
        if let next = context.plan.upcomingWorkouts.first {
            return "Next up: \(next.title) \(next.distance)."
        }
        if !context.today.workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Today's recommendation is \(context.today.workoutTitle) \(context.today.distance)."
        }
        return "I do not see a loaded workout yet."
    }
}

#if DEBUG
struct DemoRunSmartServices: TodayProviding, PlanProviding, CoachChatting, ProfileProviding, RunLogging {
    private let store = RunSmartLocalStore.shared

    func todayRecommendation() async -> TodayRecommendation {
        RunSmartPreviewData.todayRecommendation(
            adaptiveCoachQAEnabled: ProcessInfo.processInfo.arguments.contains("-RUNSMART_ADAPTIVE_COACH")
        )
    }

    func weeklyPlan() async -> [WorkoutSummary] {
        RunSmartPreviewData.workouts
    }

    func activeTrainingPlan() async -> TrainingPlanSnapshot? { RunSmartDemoData.activePlan }

    func planWorkouts(from startDate: Date, to endDate: Date) async -> [WorkoutSummary] {
        RunSmartPreviewData.workouts.filter {
            $0.scheduledDate >= startDate && $0.scheduledDate <= endDate
        }
    }

    func nextWorkouts(limit: Int) async -> [WorkoutSummary] {
        Array(RunSmartPreviewData.workouts.prefix(limit))
    }

    func saveTrainingGoal(_ request: TrainingGoalRequest) async -> Bool { true }
    func regenerateTrainingPlan(_ request: TrainingGoalRequest) async -> Bool { true }
    func moveWorkout(workoutID: UUID, to date: Date) async -> Bool { true }
    func pushWorkoutTomorrow(workoutID: UUID) async -> Bool { true }
    func amendWorkout(workoutID: UUID, patch: WorkoutPatch) async -> Bool { true }
    func removeWorkout(workoutID: UUID) async -> Bool { true }
    func applyFlexWeek(_ outcome: FlexWeekOutcome) async -> Bool { true }
    func saveSuggestedWorkout(_ suggestion: StructuredNextWorkout, from report: RunReportDetail) async -> Bool { true }

    func recentMessages() async -> [CoachMessage] {
        RunSmartPreviewData.coachMessages
    }

    func send(message: String) async -> CoachMessage {
        CoachMessage(text: message, time: "Just now", isUser: true)
    }

    func runnerProfile() async -> RunnerProfile {
        RunSmartPreviewData.runner
    }

    func achievements() async -> [Achievement] {
        RunSmartPreviewData.achievements
    }

    func currentRunMetrics() async -> [MetricTile] {
        [
            MetricTile(title: "Distance", value: "5.24", unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: Color.lime),
            MetricTile(title: "Pace", value: "5:08", unit: "/km", symbol: "timer", tint: Color.lime),
            MetricTile(title: "Moving time", value: "26:54", unit: "", symbol: "stopwatch", tint: .white),
            MetricTile(title: "Heart Rate", value: "154", unit: "bpm", symbol: "heart", tint: .red)
        ]
    }

    func recentRuns() async -> [RecordedRun] {
        let localRuns = store.visibleRuns(store.loadRuns()).sorted { $0.startedAt > $1.startedAt }
        guard !localRuns.isEmpty else { return RunSmartPreviewData.recordedRuns }
        return localRuns + RunSmartPreviewData.recordedRuns
    }

    func saveManualRun(kind: WorkoutKind, date: Date, distanceKm: Double, durationMinutes: Int, averageHeartRateBPM: Int?, notes: String) async -> RecordedRun {
        let movingTime = TimeInterval(max(1, durationMinutes) * 60)
        let distanceMeters = max(0.1, distanceKm) * 1_000
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: date,
            endedAt: date.addingTimeInterval(movingTime),
            distanceMeters: distanceMeters,
            movingTimeSeconds: movingTime,
            averagePaceSecondsPerKm: movingTime / max(distanceKm, 0.1),
            averageHeartRateBPM: averageHeartRateBPM,
            routePoints: [],
            syncedAt: nil
        )
    }

    func removeRun(_ run: RecordedRun) async -> Bool { false }

    func updateRunRPE(_ run: RecordedRun, rpe: Int?) async -> RecordedRun {
        store.updateRunRPE(run, rpe: rpe)
    }

    func finishRun() async {}

    func activeGoal() async -> GoalSummary { RunSmartPreviewData.activeGoal }
    func activeChallenge() async -> ChallengeSummary { RunSmartPreviewData.activeChallenge }
    func recoverySnapshot() async -> RecoverySnapshot { RunSmartPreviewData.recovery }
    func wellnessSnapshot() async -> WellnessSnapshot { RunSmartPreviewData.wellness }
    func wellnessTrendSeries(days: Int = 7) async -> WellnessTrendSeries { RunSmartPreviewData.wellnessTrends }
    func todayHealthSummary() async -> HealthDailySummary { RunSmartPreviewData.healthDailySummary }
    func shoes() async -> [ShoeSummary] { RunSmartPreviewData.shoes }
    func reminders() async -> [ReminderPreference] { RunSmartPreviewData.reminders }
    func latestRunReports(limit: Int) async -> [RunReportSummary] { Array(RunSmartDemoData.runReports.prefix(limit)) }
    func runReport(for run: RecordedRun) async -> RunReportDetail? {
        let keys = [run.providerActivityID, run.id.uuidString].compactMap { $0 }
        // Prefer a matching demo fixture; otherwise build a skeleton from the
        // real run so local/seeded simulator runs (WP-38 S10 hour-boundary QA)
        // show RunRecorder.timeLabel output instead of an unrelated fixture.
        return RunSmartDemoData.runReportDetails.first { detail in
            keys.contains(detail.runID) || keys.contains(detail.id)
        } ?? SupabaseRunSmartServices.reportSkeleton(for: run)
    }
    func generateRunReportIfMissing(for run: RecordedRun) async -> RunReportDetail? { await runReport(for: run) }
    func generateRunReportIfMissing(forRunID runID: String) async -> RunReportDetail? {
        if let detail = RunSmartDemoData.runReportDetails.first(where: { $0.runID == runID || $0.id == runID }) {
            return detail
        }
        let runs = await recentRuns()
        if let run = runs.first(where: { $0.id.uuidString == runID || $0.providerActivityID == runID }) {
            return SupabaseRunSmartServices.reportSkeleton(for: run)
        }
        return nil
    }
    func matchRoute(for run: RecordedRun) async -> RouteMatchResult? { nil }
    func benchmarkComparison(for run: RecordedRun) async -> BenchmarkRouteComparison? { nil }
    func trainingLoadSnapshot() async -> TrainingLoadSnapshot { RunSmartPreviewData.trainingLoad }
    func shareableAchievements() async -> [ShareableAchievement] { RunSmartPreviewData.shareableAchievements }
    func approveGarminMorningCheckin() async -> Bool { true }

    func routeSuggestions() async -> [RouteSuggestion] {
        RunSmartDemoData.routeSuggestions
    }

    func rankedRouteSuggestions(targetDistanceKm: Double?) async -> [RouteSuggestion] {
        let routes = RunSmartDemoData.routeSuggestions
        guard let targetDistanceKm else { return routes }
        return routes.sorted { lhs, rhs in
            abs(lhs.distanceKm - targetDistanceKm) < abs(rhs.distanceKm - targetDistanceKm)
        }
    }

    func nearbyLoopRoutes(around coordinate: CLLocationCoordinate2D, distancesKm: [Double]) async -> [RouteSuggestion] {
        RunSmartDemoData.routeSuggestions.filter { route in
            distancesKm.isEmpty || distancesKm.contains { abs($0 - route.distanceKm) <= 1.0 }
        }
    }

    func savedRoutes() async -> [SavedRoute] {
        RunSmartPreviewData.savedRoutes
    }

    func saveRoute(_ route: SavedRoute) async -> Bool { false }
    func deleteRoute(_ routeID: UUID) async -> Bool { false }
    func updateRoute(_ route: SavedRoute) async -> Bool { false }

    func benchmarkRoutes() async -> [BenchmarkRoute] {
        RunSmartPreviewData.benchmarkRoutes
    }

    func enableBenchmark(for routeID: UUID) async -> Bool { true }
    func disableBenchmark(for routeID: UUID) async -> Bool { true }

    func deviceStatuses() async -> [ConnectedDeviceStatus] {
#if DEBUG
        if RunSmartGate4ScreenshotMode.garminDisconnected {
            return [
                ConnectedDeviceStatus(
                    provider: "Garmin Connect",
                    state: .disconnected,
                    lastSuccessfulSync: nil,
                    permissions: [],
                    message: "Connect Garmin to import activities and recovery data."
                ),
                RunSmartDemoData.deviceStatuses.first(where: { $0.provider == "HealthKit" })
                    ?? ConnectedDeviceStatus(
                        provider: "HealthKit",
                        state: .disconnected,
                        lastSuccessfulSync: nil,
                        permissions: [],
                        message: "Tap Connect to grant HealthKit access."
                    )
            ]
        }
#endif
        return RunSmartDemoData.deviceStatuses
    }

    func connect(provider: String) async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: provider, state: .connected, lastSuccessfulSync: Date(), permissions: ["Demo"], message: "Demo connected locally. No provider auth was started.")
    }

    func syncNow(provider: String) async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: provider, state: .connected, lastSuccessfulSync: Date(), permissions: ["Demo"], message: "Demo sync completed locally. No network call was made.")
    }

    func disconnect(provider: String) async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: provider, state: .connected, lastSuccessfulSync: Date(), permissions: ["Demo"], message: "Disconnect is disabled in Demo Mode.")
    }

    func firstSyncReview(provider: String) async -> FirstSyncReview? {
        guard let provider = FirstSyncReviewProvider(serviceName: provider) else { return nil }
        return FirstSyncReview.make(
            provider: provider,
            importedRuns: Array(RunSmartDemoData.recordedRuns.prefix(3)),
            skippedDuplicateCount: 0,
            seen: true
        )
    }

    func markFirstSyncReviewSeen(provider: String) async {}

    func requestHealthAccess() async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: "HealthKit", state: .connected, lastSuccessfulSync: Date(), permissions: ["Demo"], message: "Demo HealthKit access. No permission prompt was shown.")
    }

    func syncHealthData() async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: "HealthKit", state: .connected, lastSuccessfulSync: Date(), permissions: ["Demo"], message: "Demo HealthKit sync. No HealthKit data was read.")
    }

    func saveToHealth(_ run: RecordedRun) async {}

    func generateWeeklySummary() async -> WeeklyProgressSummary? {
        WeeklyProgressSummary(
            headline: "3 runs · 22.4 km",
            narrative: "Strong consistency this week — you held easy effort across all three sessions as total distance stepped up 12%. Your aerobic base is absorbing the load well.",
            forwardLook: "Next week's long run is where this base starts to pay off. Keep the easy pace and let fitness compound.",
            weekLabel: "Week 4 of your plan",
            generatedDate: Date(),
            isoWeekKey: WeeklyProgressSummary.currentISOWeekKey(),
            source: .ai
        )
    }
}

typealias MockRunSmartServices = DemoRunSmartServices
#endif
