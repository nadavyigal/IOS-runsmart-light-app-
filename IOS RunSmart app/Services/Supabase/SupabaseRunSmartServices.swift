import Foundation
import SwiftUI
import Supabase
import MapKit

// MARK: - SupabaseRunSmartServices

final class SupabaseRunSmartServices: RunSmartServiceProviding {
    static let shared = SupabaseRunSmartServices()

    private let supabase = SupabaseManager.client
    private let planRepo = TrainingPlanRepository()
    private let challengeRepo = ChallengeRepository()
    private let healthSync = HealthKitSyncService()
    private let store = RunSmartLocalStore.shared

    private var currentUserID: UUID? { supabase.auth.currentUser?.id }

    // MARK: TodayProviding

    func todayRecommendation() async -> TodayRecommendation {
        guard let userID = currentUserID else {
            return TodayRecommendation.placeholder
        }

        async let profileTask = fetchProfile(userID: userID)
        async let metricsTask = latestGarminMetrics(userID: userID)
        async let streakTask = fetchStreak(userID: userID)

        let (dbProfile, metrics, streak) = await (profileTask, metricsTask, streakTask)
        guard dbProfile != nil else { return TodayRecommendation.placeholder }

        let activePlan = await planRepo.activePlan(authUserID: userID)
        let todayWorkout = activePlan?.todayWorkout ?? activePlan?.nextActionableWorkout

        let readiness: Int
        let readinessLabel: String

        if let bb = metrics?.bodyBattery {
            readiness = min(100, bb)
            readinessLabel = bb > 70 ? "Ready to train" : bb > 40 ? "Moderate energy" : "Low energy — easy day"
        } else if let health = store.loadHealthKitDailySnapshot() {
            readiness = healthReadiness(from: health)
            readinessLabel = readiness > 80 ? "Ready from Health" : readiness > 60 ? "Moderate from Health" : "Low recovery signals"
        } else {
            let weeklyKm = activePlan?.completedKmThisWeek ?? 0
            readiness = min(95, max(55, 72 + min(18, Int(weeklyKm))))
            readinessLabel = readiness > 80 ? "Ready to train" : "Moderate"
        }

        let coachMessage = await latestCoachMessage(profileID: userID)
            ?? "Ready for your next run. Let's make today count."

        let weeklyDone = String(format: "%.1f", Double(activePlan?.completedKmThisWeek ?? 0.0))
        let weeklyTotal = String(format: "%.1f", Double(activePlan?.totalKmThisWeek ?? 0.0))
        let streakDays = streak?.currentStreak ?? 0
        let healthSnapshot = store.loadHealthKitDailySnapshot()
        let sleepHours = metrics?.sleepDurationS.map {
            let totalSeconds = Int($0)
            return String(format: "%dh %02dm", Int32(totalSeconds / 3600), Int32((totalSeconds % 3600) / 60))
        } ?? healthSnapshot?.sleepSeconds.map(formatDuration) ?? "--"
        let hrvLabel: String
        if let hrv = metrics?.hrv ?? healthSnapshot?.hrvMilliseconds {
            hrvLabel = hrv > 50 ? "Stable" : "Lower"
        } else {
            hrvLabel = "--"
        }

        return TodayRecommendation(
            readiness: readiness,
            readinessLabel: readinessLabel,
            workoutTitle: todayWorkout?.workoutTitle ?? "Rest Day",
            distance: todayWorkout.map { String(format: "%.1f km", $0.distance) } ?? "--",
            pace: todayWorkout?.paceLabel ?? "--:--",
            elevation: "--",
            coachMessage: coachMessage,
            weeklyProgress: "\(weeklyDone) / \(weeklyTotal) km",
            streak: "\(streakDays) days",
            recovery: sleepHours,
            hrv: hrvLabel
        )
    }

    // MARK: PlanProviding

    func weeklyPlan() async -> [WorkoutSummary] {
        guard let userID = currentUserID else { return [] }
        guard let activePlan = await planRepo.activePlan(authUserID: userID) else { return [] }
        return activePlan.currentWeekWorkouts.primaryWorkoutPerDay().map { $0.toWorkoutSummary() }
    }

    func activeTrainingPlan() async -> TrainingPlanSnapshot? {
        guard let userID = currentUserID else { return nil }
        guard let activePlan = await planRepo.activePlan(authUserID: userID) else { return nil }
        let plan = activePlan.plan
        let startDate = ISO8601DateFormatter.shortDate.date(from: plan.startDate) ?? Date()
        let endDate = ISO8601DateFormatter.shortDate.date(from: plan.endDate) ?? Date()
        return TrainingPlanSnapshot(
            id: plan.id,
            title: plan.title,
            startDate: startDate,
            endDate: endDate,
            totalWeeks: plan.totalWeeks,
            planType: plan.planType
        )
    }

    func planWorkouts(from startDate: Date, to endDate: Date) async -> [WorkoutSummary] {
        guard let userID = currentUserID else { return [] }
        let workouts = await planRepo.planWorkouts(authUserID: userID, from: startDate, to: endDate)
        return workouts.primaryWorkoutPerDay().map { $0.toWorkoutSummary() }
    }

    func nextWorkouts(limit: Int) async -> [WorkoutSummary] {
        guard let userID = currentUserID else { return [] }
        guard let activePlan = await planRepo.activePlan(authUserID: userID) else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        return activePlan.workouts
            .filter { w in
                guard let date = w.scheduledDateAsDate else { return false }
                return date >= today && !w.completed
            }
            .primaryWorkoutPerDay()
            .prefix(limit)
            .map { $0.toWorkoutSummary() }
    }

    func saveTrainingGoal(_ request: TrainingGoalRequest) async -> Bool {
        guard let userID = currentUserID else { return false }
        let saved = await planRepo.saveTrainingGoal(authUserID: userID, request: request)
        guard saved else { return false }

        await MainActor.run {
            NotificationCenter.default.post(name: .runSmartPlanGenerationStatusDidChange, object: RunSmartPlanGenerationStatus.generating)
            NotificationCenter.default.post(name: .runSmartPlanDidChange, object: nil)
        }

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let regenerated = await self.regenerateTrainingPlan(request)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .runSmartPlanGenerationStatusDidChange,
                    object: regenerated ? RunSmartPlanGenerationStatus.amended : RunSmartPlanGenerationStatus.failed
                )
            }
        }

        return true
    }

    func regenerateTrainingPlan(_ request: TrainingGoalRequest) async -> Bool {
        guard let userID = currentUserID,
              let token = try? await supabase.auth.session.accessToken else {
            return false
        }

        do {
            let recent = await recentRuns(limit: 50)
            let planAverageWeeklyKm = TrainingDataBaseline.planAverageWeeklyKm(
                saved: request.averageWeeklyDistanceKm,
                runs: recent
            )
            let recentSevenDayKm = recentWeeklyKm(runs: recent)
            let weeklyVolumeKm = planAverageWeeklyKm ?? recentSevenDayKm
            let identity = await planRepo.identity(authUserID: userID)
            let payload = RunSmartDTO.GeneratePlanRequest(
                userContext: .init(
                    userId: identity.numericUserID,
                    goal: request.webPlanGoal,
                    experience: request.supabaseExperience,
                    age: request.age,
                    daysPerWeek: request.weeklyRunDays,
                    preferredTimes: request.preferredDays.isEmpty ? ["morning"] : request.preferredDays,
                    coachingStyle: request.supabaseCoachingStyle,
                    averageWeeklyKm: planAverageWeeklyKm,
                    trainingDataSource: request.trainingDataSource?.rawValue
                ),
                trainingHistory: .init(
                    weeklyVolumeKm: weeklyVolumeKm,
                    consistencyScore: min(100, recent.count * 10),
                    recentRuns: recent.prefix(10).map { run in
                        .init(
                            date: ISO8601DateFormatter.shortDate.string(from: run.startedAt),
                            distanceKm: run.distanceMeters / 1_000,
                            durationMinutes: max(1, Int(run.movingTimeSeconds / 60)),
                            avgPace: RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm),
                            rpe: nil,
                            notes: run.source.rawValue
                        )
                    }
                ),
                goals: .init(primaryGoal: .init(
                    title: request.goal,
                    goalType: request.webPlanGoal,
                    category: request.supabaseGoal,
                    target: request.goal,
                    deadline: ISO8601DateFormatter.shortDate.string(from: request.targetDate),
                    progressPercentage: 0
                )),
                challenge: request.challenge.map {
                    .init(
                        slug: $0.slug,
                        name: $0.name,
                        category: $0.category,
                        difficulty: $0.difficulty,
                        durationDays: $0.durationDays,
                        workoutPattern: $0.workoutPattern,
                        coachTone: $0.coachTone,
                        targetAudience: $0.targetAudience,
                        promise: $0.promise
                    )
                },
                targetDistance: targetDistanceSlug(for: request.goal),
                totalWeeks: planWeeks(until: request.targetDate),
                planPreferences: .init(
                    trainingDays: request.preferredDays,
                    availableDays: request.preferredDays,
                    longRunDay: request.preferredDays.last,
                    trainingVolume: "progressive",
                    difficulty: "balanced"
                )
            )

            let body = try JSONEncoder().encode(payload)
            let client = URLSessionRunSmartAPIClient(accessToken: token)
            let response = try await client.send(
                RunSmartAPI.Endpoint(path: "api/generate-plan", method: .post, body: body),
                as: RunSmartDTO.GeneratePlanResponse.self
            )

            guard let generated = response.plan else {
                print("[SupabaseServices] generate-plan returned no plan:", response.error ?? "unknown")
                return false
            }

            let persisted = await planRepo.persistGeneratedPlan(authUserID: userID, request: request, generated: generated)
            if persisted {
                await MainActor.run {
                    NotificationCenter.default.post(name: .runSmartPlanDidChange, object: nil)
                }
            }
            return persisted
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] regenerateTrainingPlan error:", error)
            }
            return false
        }
    }

    func moveWorkout(workoutID: UUID, to date: Date) async -> Bool {
        let moved = await planRepo.moveWorkout(workoutID: workoutID, to: date)
        if moved {
            await MainActor.run {
                NotificationCenter.default.post(name: .runSmartPlanDidChange, object: nil)
            }
        }
        return moved
    }

    func pushWorkoutTomorrow(workoutID: UUID) async -> Bool {
        let pushed = await planRepo.pushWorkoutTomorrow(workoutID: workoutID)
        if pushed {
            await MainActor.run {
                NotificationCenter.default.post(name: .runSmartPlanDidChange, object: nil)
            }
        }
        return pushed
    }

    func amendWorkout(workoutID: UUID, patch: WorkoutPatch) async -> Bool {
        let amended = await planRepo.amendWorkout(workoutID: workoutID, patch: patch)
        if amended {
            await MainActor.run {
                NotificationCenter.default.post(name: .runSmartPlanDidChange, object: nil)
            }
        }
        return amended
    }

    func removeWorkout(workoutID: UUID) async -> Bool {
        let removed = await planRepo.removeWorkout(workoutID: workoutID)
        if removed {
            await MainActor.run {
                NotificationCenter.default.post(name: .runSmartPlanDidChange, object: nil)
            }
        }
        return removed
    }

    func saveSuggestedWorkout(_ suggestion: StructuredNextWorkout, from report: RunReportDetail) async -> Bool {
        guard let userID = currentUserID else { return false }
        let saved = await planRepo.saveSuggestedWorkout(authUserID: userID, suggestion: suggestion, report: report)
        if saved {
            await MainActor.run {
                NotificationCenter.default.post(name: .runSmartPlanDidChange, object: nil)
            }
        }
        return saved
    }

    // MARK: CoachChatting

    func recentMessages() async -> [CoachMessage] {
        guard let userID = currentUserID else { return [] }
        do {
            let conversations: [DBConversation] = try await supabase
                .from("conversations")
                .select()
                .eq("profile_id", value: userID.uuidString)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let conv = conversations.first else { return [] }

            let messages: [DBMessage] = try await supabase
                .from("conversation_messages")
                .select()
                .eq("conversation_id", value: conv.id.uuidString)
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value

            return messages.reversed().map { msg in
                CoachMessage(
                    text: msg.content,
                    time: formatRelativeTime(msg.createdAt),
                    isUser: msg.role == "user"
                )
            }
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] recentMessages error:", error)
            }
            return []
        }
    }

    func send(message: String) async -> CoachMessage {
        CoachMessage(text: message, time: "Just now", isUser: true)
    }

    // MARK: ProfileProviding

    func runnerProfile() async -> RunnerProfile {
        guard let userID = currentUserID,
              let profile = await fetchProfile(userID: userID) else {
            return RunnerProfile(name: "Runner", goal: "--", streak: "--", level: "--", totalRuns: 0, totalDistance: 0, totalTime: "--")
        }

        async let streakTask = fetchStreak(userID: userID)
        async let runsTask = recentRuns(limit: 250)
        let (streak, runs) = await (streakTask, runsTask)

        let totalRuns = runs.count
        let totalMeters = runs.reduce(0.0) { $0 + $1.distanceMeters }
        let totalSeconds = runs.reduce(0.0) { $0 + $1.movingTimeSeconds }
        let totalTime = formatTotalTime(seconds: totalSeconds)

        return RunnerProfile(
            name: profile.name ?? "Runner",
            goal: profile.goal.capitalized,
            streak: "\(streak?.currentStreak ?? 0) day streak",
            level: profile.experience.capitalized,
            totalRuns: totalRuns,
            totalDistance: Int(totalMeters / 1000),
            totalTime: totalTime
        )
    }

    private func formatTotalTime(seconds: Double) -> String {
        guard seconds > 0 else { return "--" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        return String(format: "%dh %02dm", hours, minutes)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
    }

    private func healthReadiness(from snapshot: HealthKitDailySnapshot) -> Int {
        var score = 65
        if let sleep = snapshot.sleepSeconds {
            score += sleep >= 25_200 ? 15 : sleep >= 21_600 ? 8 : -8
        }
        if let hrv = snapshot.hrvMilliseconds {
            score += hrv >= 50 ? 10 : hrv >= 35 ? 4 : -6
        }
        if let resting = snapshot.restingHeartRateBPM {
            score += resting <= 55 ? 6 : resting <= 70 ? 2 : -5
        }
        return max(20, min(95, score))
    }

    func achievements() async -> [Achievement] {
        let runs = await recentRuns()
        guard !runs.isEmpty else { return [] }
        let totalKm = runs.reduce(0.0) { $0 + $1.distanceMeters } / 1_000
        let longestKm = (runs.map(\.distanceMeters).max() ?? 0) / 1_000
        return [
            Achievement(title: "Total Volume", subtitle: "\(Int(totalKm.rounded())) km", symbol: "chart.bar.fill", tint: Color.lime),
            Achievement(title: "Longest Run", subtitle: String(format: "%.1f km", longestKm), symbol: "flag.checkered", tint: .orange),
            Achievement(title: "Manual Logs", subtitle: "\(runs.filter { $0.source == .runSmart }.count)", symbol: "plus.circle.fill", tint: .cyan)
        ]
    }

    // MARK: RunLogging

    func currentRunMetrics() async -> [MetricTile] {
        guard let last = await recentRuns().first else { return [] }
        return [
            MetricTile(title: "Distance", value: String(format: "%.2f", last.distanceMeters / 1_000), unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: Color.lime),
            MetricTile(title: "Pace", value: RunRecorder.paceLabel(secondsPerKm: last.averagePaceSecondsPerKm), unit: "/km", symbol: "timer", tint: Color.lime),
            MetricTile(title: "Time", value: RunRecorder.timeLabel(last.movingTimeSeconds), unit: "", symbol: "stopwatch", tint: .white),
            MetricTile(title: "Source", value: last.source.rawValue, unit: "", symbol: "sensor.tag.radiowaves.forward", tint: .cyan)
        ]
    }

    func recentRuns() async -> [RecordedRun] {
        await recentRuns(limit: 100)
    }

    private func recentRuns(limit: Int) async -> [RecordedRun] {
        var runs = store.visibleRuns(store.loadRuns())
        if let userID = currentUserID {
            let garminRuns = store.visibleRuns(await GarminBridge.shared
                .recentActivities(authUserID: userID, limit: limit)
                .compactMap { $0.toRecordedRun() })
            runs.append(contentsOf: garminRuns)
        }

        return Array(ActivityConsolidationService.userVisibleRecentRuns(runs).prefix(limit))
    }

    func saveManualRun(kind: WorkoutKind, date: Date, distanceKm: Double, durationMinutes: Int, averageHeartRateBPM: Int?, notes: String) async -> RecordedRun {
        let movingTime = TimeInterval(max(1, durationMinutes) * 60)
        let distanceMeters = max(0.1, distanceKm) * 1_000
        var run = RecordedRun(
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
            syncedAt: Date()
        )

        if let userID = currentUserID {
            let identity = await planRepo.identity(authUserID: userID)
            if let profileID = identity.numericUserID {
                do {
                    try await supabase
                        .from("runs")
                        .upsert(DBRunInsert(run: run, profileID: profileID, kind: kind, notes: notes), onConflict: "source_provider,source_activity_id")
                        .execute()
                    run.syncedAt = Date()
                } catch {
                    if !(error is CancellationError) {
                        print("[SupabaseServices] saveManualRun Supabase error:", error)
                    }
                    run.syncedAt = nil
                }
            } else {
                run.syncedAt = nil
            }
        } else {
            run.syncedAt = nil
        }

        store.saveRun(run)
        await postRunsChanged()
        return run
    }

    func removeRun(_ run: RecordedRun) async -> Bool {
        let removedLocally = store.removeRun(run)

        guard run.source == .runSmart else {
            await postRunsChanged()
            return removedLocally
        }

        do {
            _ = try await supabase
                .from("runs")
                .delete()
                .eq("source_provider", value: "runsmart_ios")
                .eq("source_activity_id", value: run.id.uuidString)
                .execute()
            await postRunsChanged()
            return true
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] removeRun Supabase error:", error)
            }
            await postRunsChanged()
            return removedLocally
        }
    }

    func finishRun() async {}

    // MARK: RouteProviding

    func routeSuggestions() async -> [RouteSuggestion] {
        guard let userID = currentUserID else { return [] }
        let activities = await GarminBridge.shared.recentActivities(authUserID: userID, limit: 30)
            .filter { activity in
                guard let run = activity.toRecordedRun() else { return false }
                return !store.isRunHidden(run)
            }
        // Bucket by rounded distance (in km), keep one representative per bucket.
        let buckets = [3, 5, 8, 10, 15]
        var pickedByBucket: [Int: DBGarminActivity] = [:]
        for activity in activities {
            guard let m = activity.distanceM, m > 0 else { continue }
            let km = m / 1000
            let bucket = buckets.min(by: { abs(Double($0) - km) < abs(Double($1) - km) }) ?? Int(km.rounded())
            if pickedByBucket[bucket] == nil {
                pickedByBucket[bucket] = activity
            }
        }
        return pickedByBucket
            .sorted(by: { $0.key < $1.key })
            .compactMap { (bucket, activity) -> RouteSuggestion? in
                guard let m = activity.distanceM else { return nil }
                let km = m / 1000
                let elevation = Int(activity.elevationGainM ?? 0)
                let durationS = activity.durationS ?? (km * 360)
                return RouteSuggestion(
                    id: "garmin-\(activity.id)",
                    name: "\(bucket)K · from Garmin",
                    distanceKm: km,
                    elevationGainMeters: elevation,
                    estimatedDurationMinutes: Int(durationS / 60),
                    points: [],
                    kind: .past
                )
            }
    }

    func nearbyLoopRoutes(around coordinate: CLLocationCoordinate2D, distancesKm: [Double]) async -> [RouteSuggestion] {
        var suggestions: [RouteSuggestion] = []
        for distanceKm in distancesKm {
            if let route = await generatedLoopRoute(around: coordinate, distanceKm: distanceKm) {
                suggestions.append(route)
            }
        }
        return suggestions
    }

    // MARK: DeviceSyncing

    func deviceStatuses() async -> [ConnectedDeviceStatus] {
        guard let userID = currentUserID else {
            return [
                ConnectedDeviceStatus(provider: "Garmin Connect", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil),
                ConnectedDeviceStatus(provider: "HealthKit", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: "Tap Connect to grant HealthKit access.")
            ]
        }

        let garmin = await fetchGarminConnection(userID: userID)
        let health = store.loadDeviceStatuses().first(where: { $0.provider == "HealthKit" }) ?? ConnectedDeviceStatus(
            provider: "HealthKit",
            state: .disconnected,
            lastSuccessfulSync: nil,
            permissions: [],
            message: "Tap Connect to grant HealthKit access."
        )
        return [garmin, health]
    }

    func connect(provider: String) async -> ConnectedDeviceStatus {
        guard provider == "Garmin Connect" else {
            let status = await healthSync.requestAccess()
            store.saveDeviceStatus(status)
            return status
        }
        do {
            try await GarminBridge.shared.connect()
        } catch {
            print("[SupabaseServices] Garmin connect error:", error)
        }
        if let userID = currentUserID {
            return await fetchGarminConnection(userID: userID)
        }
        return ConnectedDeviceStatus(provider: provider, state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil)
    }

    func syncNow(provider: String) async -> ConnectedDeviceStatus {
        guard let userID = currentUserID else {
            return ConnectedDeviceStatus(provider: provider, state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil)
        }
        if provider == "Garmin Connect" {
            let status = await fetchGarminConnection(userID: userID)
            if let run = await GarminBridge.shared
                .recentActivities(authUserID: userID, limit: 3)
                .compactMap({ $0.toRecordedRun() })
                .first {
                _ = await processCompletedActivity(run)
            }
            return status
        }
        return await syncHealthData()
    }

    func disconnect(provider: String) async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: provider, state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: "Disconnected")
    }

    // MARK: HealthSyncing

    func requestHealthAccess() async -> ConnectedDeviceStatus {
        let status = await healthSync.requestAccess()
        store.saveDeviceStatus(status)
        return status
    }

    func syncHealthData() async -> ConnectedDeviceStatus {
        let result = await healthSync.importHealthData(localStore: store)
        var status = result.status
        if !result.runs.isEmpty {
            let syncedCount = await upsertHealthKitRuns(result.runs)
            status.message = "Imported \(result.runs.count) Health workouts. Synced \(syncedCount) to RunSmart."
            if result.skippedDuplicates > 0 {
                status.message?.append(" Skipped \(result.skippedDuplicates) already saved or hidden.")
            }
            if let newest = result.runs.sorted(by: { $0.startedAt > $1.startedAt }).first {
                _ = await processCompletedActivity(newest)
            } else {
                await postRunsChanged()
            }
        }
        store.saveDeviceStatus(status)
        return status
    }

    func saveToHealth(_ run: RecordedRun) async {
        await healthSync.save(run)
    }

    // MARK: WebParityProviding

    func latestRunReports(limit: Int) async -> [RunReportSummary] {
        guard limit > 0 else { return [] }

        var reports: [RunReportDetail] = []
        let runs = await recentRuns(limit: max(limit * 3, limit))
        for run in runs {
            reports.append(await runReport(for: run) ?? Self.reportSkeleton(for: run))
        }

        var seen = Set<String>()
        return reports
            .sorted { $0.sortDate > $1.sortDate }
            .filter { report in
                guard !seen.contains(report.runID) else { return false }
                seen.insert(report.runID)
                return true
            }
            .prefix(limit)
            .map(\.summary)
    }

    func runReport(for run: RecordedRun) async -> RunReportDetail? {
        if run.source == .garmin,
           let activityID = run.providerActivityID,
           let insight = await fetchPostRunInsight(activityID: activityID),
           let report = Self.report(from: insight, run: run) {
            return report
        }

        return store.cachedRunReport(runID: Self.reportRunID(for: run))
    }

    func generateRunReportIfMissing(for run: RecordedRun) async -> RunReportDetail? {
        if let existing = await runReport(for: run) {
            return existing
        }

        guard let token = try? await supabase.auth.session.accessToken else {
            return nil
        }

        do {
            let recent = Array((await recentRuns()).prefix(5))
            let upcoming = Array((await nextWorkouts(limit: 3)))
            let request = Self.reportRequest(for: run, recentRuns: recent, upcomingWorkouts: upcoming)
            let encoder = JSONEncoder()
            let body = try encoder.encode(request)
            let client = URLSessionRunSmartAPIClient(accessToken: token)
            let payload = try await client.send(
                RunSmartAPI.Endpoint(path: "api/run-report", method: .post, body: body),
                as: RunSmartDTO.RunReportResponse.self
            )
            let report = Self.report(from: payload.report, run: run)
            store.saveRunReport(report)
            await MainActor.run {
                NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            }
            return report
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] run report generation error:", error)
            }
            return nil
        }
    }

    func generateRunReportIfMissing(forRunID runID: String) async -> RunReportDetail? {
        guard let run = await run(matchingReportRunID: runID) else {
            return store.cachedRunReport(runID: runID)
        }
        return await generateRunReportIfMissing(for: run)
    }

    func processCompletedActivity(_ run: RecordedRun) async -> PostActivityOutcome {
        let canonical = ActivityConsolidationService.canonicalRun(for: run, in: await recentRuns(limit: 100))
        async let reportTask = generateRunReportIfMissing(for: canonical)
        async let completedTask = completeMatchingWorkout(for: canonical)
        let (report, completed) = await (reportTask, completedTask)

        await MainActor.run {
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            if completed != nil {
                NotificationCenter.default.post(name: .runSmartPlanDidChange, object: nil)
            }
        }

        return PostActivityOutcome(
            canonicalRun: canonical,
            report: report,
            completedWorkout: completed,
            didCompletePlannedWorkout: completed != nil
        )
    }

    func activeGoal() async -> GoalSummary {
        guard let plan = await activeTrainingPlan() else { return .loading }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: plan.endDate).day
        return GoalSummary(
            id: plan.id.uuidString,
            title: plan.title,
            detail: plan.planType.capitalized,
            progress: planProgress(plan),
            target: plan.endDate.formatted(date: .abbreviated, time: .omitted),
            daysRemaining: days.map { max(0, $0) },
            trendLabel: "Active plan"
        )
    }

    func activeChallenge() async -> ChallengeSummary {
        guard let userID = currentUserID else { return .loading }
        return await challengeRepo.activeChallenge(authUserID: userID)
    }

    func recoverySnapshot() async -> RecoverySnapshot {
        guard let userID = currentUserID else { return .loading }
        guard let metrics = await latestGarminMetrics(userID: userID) else {
            guard let health = store.loadHealthKitDailySnapshot() else { return .loading }
            let sleep = health.sleepSeconds.map(formatDuration) ?? "—"
            let hrv = health.hrvMilliseconds.map { String(format: "%.0f ms", $0) } ?? "—"
            let readiness = healthReadiness(from: health)
            return RecoverySnapshot(
                readiness: readiness,
                bodyBattery: readiness,
                sleep: sleep,
                hrv: hrv,
                stress: health.restingHeartRateBPM.map { "\($0) bpm resting" } ?? "—",
                recommendation: "Recovery data synced from Apple Health."
            )
        }
        return RecoverySnapshot(
            readiness: metrics.bodyBattery ?? 0,
            bodyBattery: metrics.bodyBattery ?? 0,
            sleep: metrics.sleepDurationS.map { String(format: "%dh %02dm", Int32($0 / 3600), Int32(($0 % 3600) / 60)) } ?? "—",
            hrv: metrics.hrv.map { String(format: "%.0f ms", $0) } ?? "—",
            stress: "—",
            recommendation: (metrics.bodyBattery ?? 0) >= 50 ? "Recovery data synced from Garmin." : "Keep this one easy until recovery improves."
        )
    }

    func wellnessSnapshot() async -> WellnessSnapshot {
        guard let userID = currentUserID else { return .empty }

        async let metricsTask = latestGarminMetrics(userID: userID)
        async let checkinTask = latestMorningCheckin(userID: userID)
        let (metrics, checkin) = await (metricsTask, checkinTask)

        if let checkin {
            return WellnessSnapshot(
                calories: metrics?.steps.map { "\($0) steps" } ?? "—",
                hydration: metrics?.bodyBattery.map { "\($0) body battery" } ?? "—",
                soreness: checkin.soreness.map { "\($0)/10" } ?? "—",
                mood: checkin.mood ?? "—",
                checkInStatus: "Manual check-in saved for \(checkin.checkinDate)."
            )
        }

        if let metrics {
            let sleep = metrics.sleepDurationS.map { String(format: "%dh %02dm sleep", Int32($0 / 3600), Int32(($0 % 3600) / 60)) } ?? "Garmin synced"
            return WellnessSnapshot(
                calories: metrics.steps.map { "\($0) steps" } ?? "—",
                hydration: metrics.bodyBattery.map { "\($0) body battery" } ?? "—",
                soreness: "Garmin",
                mood: metrics.stress.map { String(format: "Stress %.0f", $0) } ?? "—",
                checkInStatus: sleep
            )
        }

        if let health = store.loadHealthKitDailySnapshot() {
            return WellnessSnapshot(
                calories: health.steps.map { "\($0) steps" } ?? "—",
                hydration: health.activeEnergyKilocalories.map { String(format: "%.0f kcal active", $0) } ?? "—",
                soreness: "Apple Health",
                mood: health.restingHeartRateBPM.map { "\($0) bpm resting" } ?? "—",
                checkInStatus: health.sleepSeconds.map { "\(formatDuration($0)) sleep from Health." } ?? "Apple Health synced."
            )
        }

        return .empty
    }
    func shoes() async -> [ShoeSummary] { [] }
    func reminders() async -> [ReminderPreference] { [] }

    func trainingLoadSnapshot() async -> TrainingLoadSnapshot {
        let runs = await recentRuns()
        guard !runs.isEmpty else { return .loading }
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentKm = runs.filter { $0.startedAt >= sevenDaysAgo }.reduce(0.0) { $0 + $1.distanceMeters } / 1_000
        return TrainingLoadSnapshot(
            loadLabel: String(format: "%.1f km", recentKm),
            loadValue: min(100, Int(recentKm * 4)),
            acwr: "Real activity",
            consistency: min(100, runs.count * 10),
            paceTrend: runs.first.map { RunRecorder.paceLabel(secondsPerKm: $0.averagePaceSecondsPerKm) } ?? "—",
            weeklyRecap: "Based on synced Garmin, HealthKit, and local runs."
        )
    }

    func shareableAchievements() async -> [ShareableAchievement] { [] }

    func shouldPresentManualMorningCheckin() async -> Bool {
        guard let userID = currentUserID else { return true }
        if await hasMorningCheckinToday(userID: userID) { return false }

        let connection = await fetchGarminConnection(userID: userID)
        guard connection.state == .connected else { return true }

        _ = await latestGarminMetrics(userID: userID)
        return true
    }

    func approveGarminMorningCheckin() async -> Bool {
        guard let userID = currentUserID,
              let metrics = await latestGarminMetrics(userID: userID),
              isFreshMorningMetricDate(metrics.date) else {
            return false
        }

        let bodyBattery = metrics.bodyBattery ?? 50
        let energy = max(1, min(10, Int((Double(bodyBattery) / 10.0).rounded())))
        let stress = metrics.stress.map { max(1, min(10, Int(($0 / 10.0).rounded()))) }
        let fatigue = metrics.sleepDurationS.map { sleepSeconds in
            sleepSeconds >= 25_200 ? 2 : sleepSeconds >= 21_600 ? 4 : 7
        }

        return await saveMorningCheckin(
            energy: energy,
            soreness: nil,
            mood: "Garmin approved",
            stress: stress,
            fatigue: fatigue,
            notes: "Approved Garmin morning metrics from \(metrics.date).",
            source: "garmin_approved"
        )
    }

    func saveMorningCheckin(energy: Int, soreness: Int, mood: String, stress: Int?, fatigue: Int?, notes: String?) async -> Bool {
        await saveMorningCheckin(
            energy: energy,
            soreness: soreness,
            mood: mood,
            stress: stress,
            fatigue: fatigue,
            notes: notes,
            source: "manual"
        )
    }

    private func saveMorningCheckin(energy: Int, soreness: Int?, mood: String, stress: Int?, fatigue: Int?, notes: String?, source: String) async -> Bool {
        guard let userID = currentUserID else { return false }
        do {
            try await supabase
                .from("wellness_checkins")
                .upsert(DBWellnessCheckinUpsert(
                    authUserID: userID.uuidString,
                    checkinDate: localDateString(Date()),
                    energy: energy,
                    soreness: soreness ?? 0,
                    mood: mood,
                    stress: stress,
                    fatigue: fatigue,
                    notes: notes,
                    source: source
                ), onConflict: "auth_user_id,checkin_date")
                .execute()
            return true
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] saveMorningCheckin error:", error)
            }
            return false
        }
    }

    // MARK: Private helpers

    private func fetchProfile(userID: UUID) async -> DBProfile? {
        do {
            let rows: [DBProfile] = try await supabase
                .from("profiles")
                .select()
                .eq("auth_user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch { return nil }
    }

    private func postRunsChanged() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
        }
    }

    private func completeMatchingWorkout(for run: RecordedRun) async -> WorkoutSummary? {
        guard let userID = currentUserID else { return nil }
        return await planRepo.completeBestMatchingWorkout(authUserID: userID, for: run)
    }

    private func upsertHealthKitRuns(_ runs: [RecordedRun]) async -> Int {
        guard let userID = currentUserID else { return 0 }
        let identity = await planRepo.identity(authUserID: userID)
        guard let profileID = identity.numericUserID else { return 0 }

        var synced = 0
        for run in runs {
            do {
                try await supabase
                    .from("runs")
                    .upsert(
                        DBRunInsert(run: run, profileID: profileID, kind: .easy, notes: "Imported from Apple Health"),
                        onConflict: "source_provider,source_activity_id"
                    )
                    .execute()
                synced += 1
            } catch {
                if !(error is CancellationError) {
                    print("[SupabaseServices] HealthKit run upsert error:", error)
                }
            }
        }
        return synced
    }

    private func latestGarminMetrics(userID: UUID) async -> DBGarminDailyMetrics? {
        do {
            let rows: [DBGarminDailyMetrics] = try await supabase
                .from("garmin_daily_metrics_deduped")
                .select()
                .eq("auth_user_id", value: userID.uuidString)
                .order("date", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch { return nil }
    }

    private func fetchStreak(userID: UUID) async -> DBUserStreak? {
        do {
            let rows: [DBUserStreak] = try await supabase
                .from("user_streaks")
                .select()
                .eq("auth_user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch { return nil }
    }

    private func fetchGarminConnection(userID: UUID) async -> ConnectedDeviceStatus {
        do {
            let rows: [DBGarminConnection] = try await supabase
                .from("garmin_connections")
                .select()
                .eq("auth_user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value

            if let conn = rows.first {
                let lastSync = (conn.lastSuccessfulSyncAt ?? conn.lastSyncAt).flatMap { parseISO8601Date($0) }
                let state: DeviceConnectionState = conn.status == "connected" ? .connected : .disconnected
                return ConnectedDeviceStatus(
                    provider: "Garmin Connect",
                    state: state,
                    lastSuccessfulSync: lastSync,
                    permissions: conn.scopes ?? [],
                    message: nil
                )
            }
        } catch {}
        return ConnectedDeviceStatus(provider: "Garmin Connect", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil)
    }

    private func fetchPostRunInsight(activityID: String) async -> DBAIInsight? {
        do {
            let rows: [DBAIInsight] = try await supabase
                .from("ai_insights")
                .select()
                .eq("activity_id", value: activityID)
                .eq("type", value: "post_run")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            return nil
        }
    }

    private func planProgress(_ plan: TrainingPlanSnapshot) -> Double {
        let total = max(1, plan.endDate.timeIntervalSince(plan.startDate))
        let elapsed = Date().timeIntervalSince(plan.startDate)
        return min(1, max(0, elapsed / total))
    }

    private func latestCoachMessage(profileID: UUID) async -> String? {
        do {
            let conversations: [DBConversation] = try await supabase
                .from("conversations")
                .select()
                .eq("profile_id", value: profileID.uuidString)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let conv = conversations.first else { return nil }

            let messages: [DBMessage] = try await supabase
                .from("conversation_messages")
                .select()
                .eq("conversation_id", value: conv.id.uuidString)
                .eq("role", value: "assistant")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return messages.first?.content
        } catch { return nil }
    }

    private func recentWeeklyKm(runs: [RecordedRun]) -> Double {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return runs.filter { $0.startedAt >= start }.reduce(0.0) { $0 + $1.distanceMeters } / 1_000
    }

    private func targetDistanceSlug(for goal: String) -> String? {
        let lower = goal.lowercased()
        if lower.contains("5k") { return "5k" }
        if lower.contains("10k") { return "10k" }
        if lower.contains("half") { return "half-marathon" }
        if lower.contains("marathon") { return "marathon" }
        return nil
    }

    private func hasMorningCheckinToday(userID: UUID) async -> Bool {
        do {
            let rows: [DBWellnessCheckin] = try await supabase
                .from("wellness_checkins")
                .select("id,checkin_date,energy,soreness,mood,source")
                .eq("auth_user_id", value: userID.uuidString)
                .eq("checkin_date", value: localDateString(Date()))
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    private func latestMorningCheckin(userID: UUID) async -> DBWellnessCheckin? {
        do {
            let rows: [DBWellnessCheckin] = try await supabase
                .from("wellness_checkins")
                .select("id,checkin_date,energy,soreness,mood,source")
                .eq("auth_user_id", value: userID.uuidString)
                .order("checkin_date", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            return nil
        }
    }

    private func isFreshMorningMetricDate(_ dateString: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        guard let metricDate = formatter.date(from: dateString) else { return false }
        let calendar = Calendar.current
        return calendar.isDateInToday(metricDate) || calendar.isDateInYesterday(metricDate)
    }

    private func localDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func planWeeks(until targetDate: Date) -> Int? {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0
        guard days > 0 else { return nil }
        return max(1, min(16, Int(ceil(Double(days) / 7.0))))
    }

    private func generatedLoopRoute(around coordinate: CLLocationCoordinate2D, distanceKm: Double) async -> RouteSuggestion? {
        let bearings = [0.0, 120.0, 240.0]
        var closest: RouteSuggestion?
        var closestDelta = Double.greatestFiniteMagnitude

        for bearing in bearings {
            guard let candidate = await outAndBackRoute(around: coordinate, distanceKm: distanceKm, bearingDegrees: bearing) else {
                continue
            }
            let delta = abs(candidate.distanceKm - distanceKm)
            if delta / distanceKm <= 0.15 {
                return candidate
            }
            if delta < closestDelta {
                closest = candidate
                closestDelta = delta
            }
        }

        return closest
    }

    private func outAndBackRoute(around coordinate: CLLocationCoordinate2D, distanceKm: Double, bearingDegrees: Double) async -> RouteSuggestion? {
        let midpoint = coordinate.destination(distanceMeters: distanceKm * 500, bearingDegrees: bearingDegrees)
        do {
            async let outboundTask = directions(from: coordinate, to: midpoint)
            async let inboundTask = directions(from: midpoint, to: coordinate)
            let (outbound, inbound) = try await (outboundTask, inboundTask)
            let totalMeters = outbound.distance + inbound.distance
            guard totalMeters > 0 else { return nil }
            let coordinates = outbound.polyline.coordinates + inbound.polyline.coordinates.dropFirst()
            guard coordinates.count >= 2 else { return nil }
            let points = coordinates.enumerated().map { index, coord in
                RunRoutePoint(
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    timestamp: Date().addingTimeInterval(Double(index)),
                    horizontalAccuracy: 0,
                    altitude: nil
                )
            }
            let actualKm = totalMeters / 1000
            return RouteSuggestion(
                id: "nearby-\(Int(distanceKm * 10))-\(Int(bearingDegrees))-\(coordinate.latitude)-\(coordinate.longitude)",
                name: "\(Int(distanceKm.rounded()))K loop · nearby",
                distanceKm: actualKm,
                elevationGainMeters: 0,
                estimatedDurationMinutes: max(1, Int((actualKm * 360).rounded() / 60)),
                points: points,
                kind: .generated
            )
        } catch {
            return nil
        }
    }

    private func directions(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .walking
        request.requestsAlternateRoutes = true
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.min(by: { $0.distance < $1.distance }) else {
            throw MKError(.directionsNotFound)
        }
        return route
    }

    private func formatRelativeTime(_ isoString: String?) -> String {
        guard let str = isoString, let date = parseISO8601Date(str) else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }

    private func parseISO8601Date(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: str) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }
}

extension Notification.Name {
    static let runSmartPlanDidChange = Notification.Name("RunSmartPlanDidChange")
    static let runSmartPlanGenerationStatusDidChange = Notification.Name("RunSmartPlanGenerationStatusDidChange")
    static let runSmartRunsDidChange = Notification.Name("RunSmartRunsDidChange")
}

private extension ISO8601DateFormatter {
    static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct DBRunInsert: Encodable {
    let profileID: Int
    let type: String
    let distance: Double
    let duration: Int
    let pace: Double?
    let heartRate: Int?
    let notes: String?
    let completedAt: String
    let sourceProvider: String
    let sourceActivityID: String
    let lastSyncedAt: String

    init(run: RecordedRun, profileID: Int, kind: WorkoutKind, notes: String?) {
        let syncedAt = Date()
        self.profileID = profileID
        self.type = kind.supabaseType
        self.distance = Double((run.distanceMeters / 1_000 * 1000).rounded()) / 1000
        self.duration = Int(run.movingTimeSeconds.rounded())
        self.pace = run.averagePaceSecondsPerKm.isFinite ? run.averagePaceSecondsPerKm : nil
        self.heartRate = run.averageHeartRateBPM
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = trimmedNotes?.isEmpty == false ? trimmedNotes : nil
        self.completedAt = ISO8601DateFormatter.internet.string(from: run.startedAt)
        self.sourceProvider = run.supabaseSourceProvider
        self.sourceActivityID = run.providerActivityID ?? run.id.uuidString
        self.lastSyncedAt = ISO8601DateFormatter.internet.string(from: syncedAt)
    }

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case type, distance, duration, pace, notes
        case heartRate = "heart_rate"
        case completedAt = "completed_at"
        case sourceProvider = "source_provider"
        case sourceActivityID = "source_activity_id"
        case lastSyncedAt = "last_synced_at"
    }
}

private extension RecordedRun {
    var supabaseSourceProvider: String {
        switch source {
        case .runSmart:
            return "runsmart_ios"
        case .garmin:
            return "garmin"
        case .healthKit:
            return "healthkit"
        }
    }
}

private struct DBWellnessCheckinUpsert: Encodable {
    let authUserID: String
    let checkinDate: String
    let energy: Int
    let soreness: Int
    let mood: String
    let stress: Int?
    let fatigue: Int?
    let notes: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case authUserID = "auth_user_id"
        case checkinDate = "checkin_date"
        case energy, soreness, mood, stress, fatigue, notes, source
    }
}

private struct DBWellnessCheckin: Decodable {
    let id: UUID
    let checkinDate: String
    let energy: Int?
    let soreness: Int?
    let mood: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id
        case checkinDate = "checkin_date"
        case energy, soreness, mood, source
    }
}

extension SupabaseRunSmartServices {
    private func run(matchingReportRunID runID: String) async -> RecordedRun? {
        await recentRuns(limit: 100).first { run in
            Self.reportRunID(for: run) == runID ||
            run.providerActivityID == runID ||
            run.id.uuidString == runID
        }
    }

    static func reportRunID(for run: RecordedRun) -> String {
        run.consolidatedActivityID ?? run.providerActivityID ?? run.id.uuidString
    }

    static func reportSkeleton(for run: RecordedRun) -> RunReportDetail {
        let runID = reportRunID(for: run)
        return RunReportDetail(
            id: "report-\(runID)",
            runID: runID,
            title: "\(run.source.rawValue) Run",
            dateLabel: run.startedAt.formatted(date: .abbreviated, time: .omitted),
            source: run.source.rawValue,
            distance: String(format: "%.2f km", run.distanceMeters / 1_000),
            duration: RunRecorder.timeLabel(run.movingTimeSeconds),
            averagePace: RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm),
            averageHeartRate: run.averageHeartRateBPM.map { "\($0) bpm" } ?? "—",
            coachScore: nil,
            notes: CoachRunNotes(
                summary: "No coach report yet.",
                effort: "Open the report to generate notes from this activity.",
                recovery: "No recovery note yet.",
                nextSessionNudge: "No next-run recommendation yet."
            ),
            structuredNextWorkout: nil,
            isGenerated: false
        )
    }

    static func report(from insight: DBAIInsight, run: RecordedRun) -> RunReportDetail? {
        let text = insight.content ?? insight.summary ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if let data = text.data(using: .utf8),
           let payload = try? JSONDecoder().decode(RunSmartDTO.RunReportPayload.self, from: data) {
            return report(from: payload, run: run)
        }

        let runID = reportRunID(for: run)
        return RunReportDetail(
            id: insight.id?.uuidString ?? "insight-\(runID)",
            runID: runID,
            title: "\(run.source.rawValue) Run Report",
            dateLabel: run.startedAt.formatted(date: .abbreviated, time: .omitted),
            source: run.source.rawValue,
            distance: String(format: "%.2f km", run.distanceMeters / 1_000),
            duration: RunRecorder.timeLabel(run.movingTimeSeconds),
            averagePace: RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm),
            averageHeartRate: run.averageHeartRateBPM.map { "\($0) bpm" } ?? "—",
            coachScore: nil,
            notes: CoachRunNotes(
                summary: firstMarkdownSection(named: "summary", in: text) ?? text,
                effort: firstMarkdownSection(named: "effort", in: text) ?? "Effort notes are included in the coach summary.",
                recovery: firstMarkdownSection(named: "recovery", in: text) ?? "No recovery note stored.",
                nextSessionNudge: firstMarkdownSection(named: "next", in: text) ?? "No next-run recommendation stored.",
                keyInsights: firstMarkdownListSection(named: "insight", in: text),
                pacing: firstMarkdownSection(named: "pacing", in: text),
                biomechanics: firstMarkdownSection(named: "biomechan", in: text),
                recoveryTimeline: nil
            ),
            structuredNextWorkout: nil,
            isGenerated: true
        )
    }

    static func report(from payload: RunSmartDTO.RunReportPayload, run: RecordedRun) -> RunReportDetail {
        let runID = reportRunID(for: run)
        return RunReportDetail(
            id: "report-\(runID)",
            runID: runID,
            title: "\(run.source.rawValue) Run Report",
            dateLabel: run.startedAt.formatted(date: .abbreviated, time: .omitted),
            source: run.source.rawValue,
            distance: String(format: "%.2f km", run.distanceMeters / 1_000),
            duration: RunRecorder.timeLabel(run.movingTimeSeconds),
            averagePace: RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm),
            averageHeartRate: run.averageHeartRateBPM.map { "\($0) bpm" } ?? "—",
            coachScore: payload.coachScore,
            notes: CoachRunNotes(
                summary: payload.summary ?? "No coach report yet.",
                effort: payload.effort ?? "No effort note yet.",
                recovery: payload.recovery ?? "No recovery note yet.",
                nextSessionNudge: payload.nextSessionNudge ?? "No next-run recommendation yet.",
                keyInsights: payload.keyInsights,
                pacing: payload.pacing,
                biomechanics: payload.biomechanics,
                recoveryTimeline: payload.recoveryTimeline
            ),
            structuredNextWorkout: payload.structuredNextWorkout,
            isGenerated: true
        )
    }

    static func reportRequest(for run: RecordedRun, recentRuns: [RecordedRun], upcomingWorkouts: [WorkoutSummary]) -> RunSmartDTO.RunReportRequest {
        let routePoints = run.routePoints
        let averageAccuracy = routePoints.isEmpty ? nil : routePoints.reduce(0.0) { $0 + $1.horizontalAccuracy } / Double(routePoints.count)
        let isoFormatter = ISO8601DateFormatter()
        let shortDateFormatter = ISO8601DateFormatter.shortDate
        let weekly7Start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekly28Start = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let week7 = recentRuns.filter { $0.startedAt >= weekly7Start }
        let week28 = recentRuns.filter { $0.startedAt >= weekly28Start }
        let webRun = RunSmartDTO.RunReportRequest.WebRun(
            id: reportRunID(for: run),
            type: "easy",
            distanceKm: run.distanceMeters / 1_000,
            durationSeconds: Int(run.movingTimeSeconds.rounded()),
            avgPaceSecondsPerKm: run.averagePaceSecondsPerKm > 0 ? run.averagePaceSecondsPerKm : nil,
            completedAt: isoFormatter.string(from: run.endedAt),
            notes: run.source.rawValue,
            heartRateBpm: run.averageHeartRateBPM
        )
        let gps = RunSmartDTO.RunReportRequest.GPSContext(
            points: routePoints.count,
            startAccuracy: routePoints.first?.horizontalAccuracy,
            endAccuracy: routePoints.last?.horizontalAccuracy,
            averageAccuracy: averageAccuracy
        )
        let workoutContexts: [RunSmartDTO.WorkoutReportContext] = upcomingWorkouts.map { workout in
            let targetPace = workout.targetPaceSecondsPerKm.map { RunRecorder.paceLabel(secondsPerKm: Double($0)) }
            return RunSmartDTO.WorkoutReportContext(
                date: shortDateFormatter.string(from: workout.scheduledDate),
                sessionType: workout.title,
                durationMinutes: workout.durationMinutes,
                targetPace: targetPace,
                targetHrZone: workout.intensity,
                notes: workout.detail.isEmpty ? nil : workout.detail,
                tags: [workout.kind.rawValue],
                workoutID: workout.id.uuidString,
                scheduledDateISO8601: isoFormatter.string(from: workout.scheduledDate),
                title: workout.title,
                distanceLabel: workout.distance,
                targetPaceSecondsPerKm: workout.targetPaceSecondsPerKm
            )
        }
        let historicalRuns: [RunSmartDTO.RunReportRequest.HistoricalRun] = recentRuns.map { recent in
            RunSmartDTO.RunReportRequest.HistoricalRun(
                type: recent.source.rawValue,
                distanceKm: recent.distanceMeters / 1_000,
                paceSecPerKm: recent.averagePaceSecondsPerKm > 0 ? recent.averagePaceSecondsPerKm : nil,
                date: shortDateFormatter.string(from: recent.startedAt),
                effort: nil
            )
        }
        let historicalContext = RunSmartDTO.RunReportRequest.HistoricalContext(
            recentRuns: historicalRuns,
            weeklyVolume7d: week7.reduce(0.0) { $0 + $1.distanceMeters } / 1_000,
            weeklyVolume28d: week28.reduce(0.0) { $0 + $1.distanceMeters } / 1_000,
            weeklyRunCount7d: week7.count,
            recoveryScore: nil,
            readinessScore: nil
        )

        return RunSmartDTO.RunReportRequest(
            run: webRun,
            gps: gps,
            paceData: nil,
            upcomingWorkouts: workoutContexts,
            historicalContext: historicalContext
        )
    }

    static func firstMarkdownSection(named name: String, in text: String) -> String? {
        let lowerName = name.lowercased()
        let lines = text.components(separatedBy: .newlines)
        var capture = false
        var collected: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#*: "))
            if heading.lowercased().contains(lowerName) {
                capture = true
                continue
            }
            if capture && trimmed.hasPrefix("#") {
                break
            }
            if capture && !trimmed.isEmpty {
                collected.append(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-* ")))
            }
        }

        let value = collected.joined(separator: " ")
        return value.isEmpty ? nil : value
    }

    static func firstMarkdownListSection(named name: String, in text: String) -> [String]? {
        guard let section = firstMarkdownSection(named: name, in: text) else { return nil }
        let values = section
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }
}

private extension RunReportDetail {
    var sortDate: Date {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.date(from: dateLabel) ?? .distantPast
    }
}

private extension CLLocationCoordinate2D {
    func destination(distanceMeters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let radius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let angularDistance = distanceMeters / radius

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

// MARK: - TodayRecommendation with extra stats

extension TodayRecommendation {
    static let placeholder = TodayRecommendation(
        readiness: 0,
        readinessLabel: "Loading",
        workoutTitle: "Loading",
        distance: "--",
        pace: "--:--",
        elevation: "--",
        coachMessage: "Loading your training data…"
    )
}
