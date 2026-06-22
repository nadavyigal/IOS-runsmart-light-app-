import Foundation
import SwiftUI
import Supabase
import MapKit

enum RunSmartCoachPersistenceError: Error {
    case conversationCreateReturnedNoRow
    case emptyAssistantResponse
}

// MARK: - SupabaseRunSmartServices

final class SupabaseRunSmartServices: RunSmartServiceProviding {
    static let shared = SupabaseRunSmartServices()

    private let supabase = SupabaseManager.client
    private let planRepo = TrainingPlanRepository()
    private let challengeRepo = ChallengeRepository()
    private let healthSync = HealthKitSyncService()
    private let store = RunSmartLocalStore.shared
    private let routeRemote: RouteRemoteStoring = SupabaseRouteRemoteStore()
    private var remoteRouteTablesUnavailable = false

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
        let todayWorkout = activePlan?.uncompletedTodayWorkout ?? activePlan?.nextActionableWorkout

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
        let resolvedHRV = HRVResolver.resolve(
            garminDirect: metrics?.hrv.map { HRVReading(value: $0, source: .garmin) },
            healthKit: healthSnapshot?.hrvMilliseconds.map { HRVReading(value: $0, source: healthSnapshot?.hrvSource ?? .unknown) }
        )
        let hrvLabel: String
        if let hrv = resolvedHRV?.value {
            hrvLabel = hrv > 50 ? "Stable" : "Lower"
        } else {
            hrvLabel = "--"
        }

        let planWeekIndex: Int? = {
            guard let plan = activePlan?.plan,
                  let startDate = ISO8601DateFormatter.shortDate.date(from: plan.startDate) else { return nil }
            return Calendar.current.dateComponents([.weekOfYear], from: startDate, to: Date()).weekOfYear
        }()

        let generatedRationale = TodayRationaleBuilder.rationale(
            bodyBattery: metrics?.bodyBattery,
            hrv: metrics?.hrv,
            sleepSeconds: healthSnapshot?.sleepSeconds,
            workoutTitle: todayWorkout?.workoutTitle ?? "Rest Day",
            isRestDay: todayWorkout == nil,
            planWeekIndex: planWeekIndex
        )

        let safetyExplanation = SafetyExplanationBuilder.explanation(
            readiness: readiness,
            bodyBattery: metrics?.bodyBattery,
            hrv: resolvedHRV?.value,
            workoutTitle: todayWorkout?.workoutTitle ?? "Rest Day",
            isRestDay: todayWorkout == nil
        )

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
            hrv: hrvLabel,
            rationale: generatedRationale,
            safetyExplanation: safetyExplanation
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
                    averageWeeklyKm: weeklyVolumeKm,
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
                Analytics.trackPlanGenerated(
                    planType: request.goal,
                    durationWeeks: planWeeks(until: request.targetDate) ?? 0
                )
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

    func applyFlexWeek(_ outcome: FlexWeekOutcome) async -> Bool {
        guard let userID = currentUserID else { return false }
        let applied = await planRepo.applyFlexWeek(authUserID: userID, outcome: outcome)
        guard applied else { return false }

        let notificationsEnabled = UserDefaults.standard.object(forKey: "runsmart.notifications.enabled") as? Bool ?? false
        let planAdjustmentConfirmationsEnabled = UserDefaults.standard.object(forKey: "runsmart.notifications.planAdjustmentConfirmations") as? Bool ?? true
        let tomorrowWorkout = Self.tomorrowWorkout(from: outcome.restructuredWeek)
        await PushService.shared.schedulePlanAdjustmentConfirmation(
            workout: tomorrowWorkout,
            notificationsEnabled: notificationsEnabled,
            planAdjustmentConfirmationsEnabled: planAdjustmentConfirmationsEnabled
        )
        return true
    }

    private static func tomorrowWorkout(from week: [PlannedWorkout]) -> WorkoutSummary? {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return nil }
        return week.first { calendar.isDate($0.scheduledDate, inSameDayAs: tomorrow) }
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
                .rpc(
                    "coach_messages_for_conversation",
                    params: DBCoachMessagesForConversationParams(
                        conversationID: conv.id.uuidString,
                        limit: 10,
                        assistantOnly: false
                    )
                )
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

    func send(message: String, context: TrainingContextSnapshot) async -> CoachMessage {
        let fallback = TrainingContextCoachResponder.response(to: message, context: context)
        let clientMessageID = UUID().uuidString
        guard let userID = currentUserID,
              let token = try? await supabase.auth.session.accessToken else {
            return fallback
        }

        do {
            let live = try await sendLiveCoachMessage(
                message,
                context: context,
                clientMessageID: clientMessageID,
                accessToken: token
            )
            return live
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] live coach endpoint unavailable, using fallback:", error)
            }
        }

        do {
            let conversation = try await coachConversation(for: userID)
            try await insertCoachTurn(
                conversationID: conversation.id,
                userMessage: message,
                assistantMessage: fallback.text,
                authUserID: userID.uuidString,
                clientMessageID: clientMessageID,
                source: "fallback",
                entryPoint: context.entryPoint.rawValue
            )
            return fallback
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] send coach message persistence error:", error)
            }
            return fallback
        }
    }

    private func sendLiveCoachMessage(
        _ message: String,
        context: TrainingContextSnapshot,
        clientMessageID: String,
        accessToken: String
    ) async throws -> CoachMessage {
        let request = RunSmartDTO.SendCoachMessageRequest(
            clientMessageId: clientMessageID,
            entryPoint: context.entryPoint,
            message: message,
            context: context
        )
        let body = try JSONEncoder().encode(request)
        let client = URLSessionRunSmartAPIClient(
            baseURL: SupabaseManager.functionsBaseURL,
            accessToken: accessToken,
            additionalHeaders: ["apikey": SupabaseManager.supabasePublishableKey]
        )
        let response = try await client.send(
            RunSmartAPI.Endpoint(path: "coach_message", method: .post, body: body),
            as: RunSmartDTO.SendCoachMessageResponse.self
        )
        let content = response.assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw RunSmartCoachPersistenceError.emptyAssistantResponse
        }
        return CoachMessage(
            text: content,
            time: formatRelativeTime(response.assistantMessage.createdAt).isEmpty ? "Now" : formatRelativeTime(response.assistantMessage.createdAt),
            isUser: false
        )
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
            let activities = await GarminBridge.shared.recentActivities(authUserID: userID, limit: limit * 2)
            let garminRuns = await GarminImportProcessor.normalizedRuns(
                from: activities,
                isHidden: store.isRunHidden,
                routePointLoader: { _ in [] }
            )
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
            do {
                try await supabase
                    .from("runs")
                    .upsert(DBRunInsert(run: run, identity: identity, kind: kind, notes: notes), onConflict: "source_provider,source_activity_id")
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
        return GarminDistanceBucket.representativeActivities(from: activities)
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
        await withTaskGroup(of: RouteSuggestion?.self) { group in
            for distanceKm in distancesKm {
                group.addTask {
                    await self.generatedLoopRoute(around: coordinate, distanceKm: distanceKm)
                }
            }
            var suggestions: [RouteSuggestion] = []
            for await route in group {
                if let route { suggestions.append(route) }
            }
            return suggestions
        }
    }

    func rankedRouteSuggestions(targetDistanceKm: Double?) async -> [RouteSuggestion] {
        let saved = store.loadSavedRoutes()
        let benchmarks = store.loadBenchmarkRoutes()
        let benchmarkRouteIDs = Set(benchmarks.map(\.savedRouteID))
        let calendar = Calendar.current
        var suggestions: [RouteSuggestion] = []

        for route in saved {
            let isBenchmark = benchmarkRouteIDs.contains(route.id)
            let kind: RouteKind = isBenchmark ? .benchmark : .saved
            let reason = RouteSuggestionRanker.reason(
                kind: kind, distanceKm: route.distanceKm,
                targetDistanceKm: targetDistanceKm,
                isFavorite: route.isFavorite, daysSinceLastRun: nil
            )
            suggestions.append(RouteSuggestion(
                id: route.id.uuidString, name: route.name,
                distanceKm: route.distanceKm,
                elevationGainMeters: route.elevationGainMeters,
                estimatedDurationMinutes: max(1, Int((route.distanceKm * 360.0).rounded()) / 60),
                points: route.points, kind: kind,
                recommendationReason: reason,
                savedRouteID: route.id, isFavorite: route.isFavorite
            ))
        }

        if let userID = currentUserID {
            let activities = await GarminBridge.shared.recentActivities(authUserID: userID, limit: 30)
                .filter { activity in
                    guard let run = activity.toRecordedRun() else { return false }
                    return !store.isRunHidden(run)
                }
            let pickedByBucket = GarminDistanceBucket.representativeActivities(from: activities)
            for (bucket, activity) in pickedByBucket.sorted(by: { $0.key < $1.key }) {
                guard let m = activity.distanceM else { continue }
                let km = m / 1000
                let days: Int? = {
                    guard let start = activity.startTime else { return nil }
                    let fmt = ISO8601DateFormatter()
                    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let date = fmt.date(from: start) ?? ISO8601DateFormatter().date(from: start)
                    return date.flatMap { calendar.dateComponents([.day], from: $0, to: Date()).day }
                }()
                let reason = RouteSuggestionRanker.reason(
                    kind: .past, distanceKm: km,
                    targetDistanceKm: targetDistanceKm,
                    isFavorite: false, daysSinceLastRun: days
                )
                suggestions.append(RouteSuggestion(
                    id: "garmin-\(activity.id)",
                    name: "\(bucket)K · from Garmin",
                    distanceKm: km,
                    elevationGainMeters: Int(activity.elevationGainM ?? 0),
                    estimatedDurationMinutes: max(1, Int((activity.durationS ?? (km * 360)) / 60)),
                    points: [], kind: .past,
                    recommendationReason: reason, savedRouteID: nil, isFavorite: false
                ))
            }
        }

        let filtered = RouteSuggestionRanker.filter(suggestions, targetDistanceKm: targetDistanceKm)
        return RouteSuggestionRanker.rank(filtered, targetDistanceKm: targetDistanceKm)
    }

    func savedRoutes() async -> [SavedRoute] {
        guard let userID = currentUserID else { return store.loadSavedRoutes() }
        let remote: [SavedRoute]
        if remoteRouteTablesUnavailable {
            remote = []
        } else {
            do {
                remote = try await routeRemote.fetchSavedRoutes(userID: userID)
            } catch {
                remoteRouteTablesUnavailable = true
                remote = []
            }
        }
        let merged = RouteSync.merge(remote: remote, local: store.loadSavedRoutes())
        for route in merged { store.saveSavedRoute(route) }
        return merged
    }

    func saveRoute(_ route: SavedRoute) async -> Bool {
        store.saveSavedRoute(route)
        if let userID = currentUserID {
            try? await routeRemote.upsertRoute(route, userID: userID)
        }
        postRouteChange()
        return true
    }

    func deleteRoute(_ routeID: UUID) async -> Bool {
        let removed = store.removeSavedRoute(routeID)
        if removed {
            if let userID = currentUserID {
                try? await routeRemote.deleteRoute(id: routeID, userID: userID)
            }
            store.refreshBenchmarkStats()
            postRouteChange()
        }
        return removed
    }

    func updateRoute(_ route: SavedRoute) async -> Bool {
        var updated = route
        updated.updatedAt = Date()
        store.saveSavedRoute(updated)
        if let userID = currentUserID {
            try? await routeRemote.upsertRoute(updated, userID: userID)
        }
        postRouteChange()
        return true
    }

    func benchmarkRoutes() async -> [BenchmarkRoute] {
        guard let userID = currentUserID else { return store.loadBenchmarkRoutes() }
        let remoteEntries: [(id: UUID, savedRouteID: UUID, enabledAt: Date)]
        if remoteRouteTablesUnavailable {
            remoteEntries = []
        } else {
            do {
                remoteEntries = try await routeRemote.fetchBenchmarkEntries(userID: userID)
            } catch {
                remoteRouteTablesUnavailable = true
                remoteEntries = []
            }
        }
        let merged = RouteSync.mergeBenchmarks(remoteEntries: remoteEntries, local: store.loadBenchmarkRoutes())
        for benchmark in merged { store.saveBenchmarkRoute(benchmark) }
        return merged
    }

    func enableBenchmark(for routeID: UUID) async -> Bool {
        let routes = store.loadSavedRoutes()
        guard routes.contains(where: { $0.id == routeID }) else { return false }
        let benchmarkID = UUID()
        let enabledAt = Date()
        let benchmark = BenchmarkRoute(
            id: benchmarkID,
            savedRouteID: routeID,
            enabledAt: enabledAt,
            historicalRunCount: 0,
            personalBestSeconds: nil,
            personalBestDate: nil,
            averagePaceSecondsPerKm: nil,
            averageDurationSeconds: nil
        )
        store.saveBenchmarkRoute(benchmark)
        if let userID = currentUserID {
            try? await routeRemote.upsertBenchmark(id: benchmarkID, savedRouteID: routeID, enabledAt: enabledAt, userID: userID)
        }
        store.refreshBenchmarkStats()
        postRouteChange()
        return true
    }

    func disableBenchmark(for routeID: UUID) async -> Bool {
        let removed = store.removeBenchmarkRoute(routeID)
        if removed {
            if let userID = currentUserID {
                try? await routeRemote.deleteBenchmark(savedRouteID: routeID, userID: userID)
            }
            store.refreshBenchmarkStats()
            postRouteChange()
        }
        return removed
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
        } catch let error as GarminError {
            print("[SupabaseServices] Garmin connect error:", error)
            if let userID = currentUserID {
                var status = await fetchGarminConnection(userID: userID)
                if status.state != .connected {
                    status = ConnectedDeviceStatus(
                        provider: status.provider,
                        state: status.state,
                        lastSuccessfulSync: status.lastSuccessfulSync,
                        permissions: status.permissions,
                        message: error.localizedDescription
                    )
                }
                return status
            }
            return ConnectedDeviceStatus(
                provider: provider,
                state: .disconnected,
                lastSuccessfulSync: nil,
                permissions: [],
                message: error.localizedDescription
            )
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
            let activities = await GarminBridge.shared.recentActivities(authUserID: userID, limit: 10)
            let runs = await GarminImportProcessor.normalizedRuns(
                from: activities,
                isHidden: store.isRunHidden,
                routePointLoader: { activityID in
                    await GarminBridge.shared.activityRoutePoints(activityID: activityID, authUserID: userID)
                }
            )
            let existingIDs = Set(store.loadRuns().compactMap(\.providerActivityID))
            let newRuns = runs.filter { run in
                guard let providerID = run.providerActivityID else { return true }
                return !existingIDs.contains(providerID)
            }
            for run in newRuns {
                _ = await processCompletedActivity(run)
            }
            saveFirstSyncReviewIfNeeded(
                provider: .garmin,
                status: status,
                importedRuns: newRuns,
                skippedDuplicateCount: max(0, runs.count - newRuns.count)
            )
            Analytics.trackGarminSyncCompleted(
                importedCount: newRuns.count,
                skippedCount: max(0, runs.count - newRuns.count)
            )
            return status
        }
        return await syncHealthData()
    }

    func disconnect(provider: String) async -> ConnectedDeviceStatus {
        guard let userID = currentUserID else {
            return ConnectedDeviceStatus(provider: provider, state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil)
        }

        if provider == "Garmin Connect" {
            GarminBridge.shared.invalidateActivityCache()
            do {
                try await supabase
                    .from("garmin_connections")
                    .delete()
                    .eq("auth_user_id", value: userID.uuidString)
                    .execute()
                try await supabase
                    .from("garmin_tokens")
                    .delete()
                    .eq("auth_user_id", value: userID.uuidString)
                    .execute()
            } catch {
                if !(error is CancellationError) {
                    print("[SupabaseServices] Garmin disconnect error:", error)
                }
                return ConnectedDeviceStatus(
                    provider: provider,
                    state: .error,
                    lastSuccessfulSync: nil,
                    permissions: [],
                    message: error.localizedDescription
                )
            }
            return ConnectedDeviceStatus(
                provider: provider,
                state: .disconnected,
                lastSuccessfulSync: nil,
                permissions: [],
                message: "Garmin disconnected."
            )
        }

        let disconnected = ConnectedDeviceStatus(
            provider: provider,
            state: .disconnected,
            lastSuccessfulSync: nil,
            permissions: [],
            message: "Disconnected"
        )
        if provider == HealthKitSyncService.providerName {
            store.saveDeviceStatus(disconnected)
        }
        return disconnected
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
        saveFirstSyncReviewIfNeeded(
            provider: .healthKit,
            status: status,
            importedRuns: result.runs,
            skippedDuplicateCount: result.skippedDuplicates
        )
        Analytics.trackHealthKitSyncCompleted(importedCount: result.runs.count)
        return status
    }

    func saveToHealth(_ run: RecordedRun) async {
        await healthSync.save(run)
    }

    func firstSyncReview(provider: String) async -> FirstSyncReview? {
        guard let provider = FirstSyncReviewProvider(serviceName: provider) else { return nil }
        return store.firstSyncReview(provider: provider)
    }

    func markFirstSyncReviewSeen(provider: String) async {
        guard let provider = FirstSyncReviewProvider(serviceName: provider) else { return }
        store.markFirstSyncReviewSeen(provider: provider)
    }

    private func saveFirstSyncReviewIfNeeded(
        provider: FirstSyncReviewProvider,
        status: ConnectedDeviceStatus,
        importedRuns: [RecordedRun],
        skippedDuplicateCount: Int
    ) {
        guard status.state == .connected, !store.hasSeenFirstSyncReview(provider: provider) else { return }
        store.saveFirstSyncReview(FirstSyncReview.make(
            provider: provider,
            importedRuns: importedRuns,
            skippedDuplicateCount: skippedDuplicateCount
        ))
    }

    // MARK: WebParityProviding

    func latestRunReports(limit: Int) async -> [RunReportSummary] {
        guard limit > 0 else { return [] }

        let runs = await recentRuns(limit: max(limit * 3, limit))
        let reports = await withTaskGroup(of: RunReportDetail.self) { group in
            for run in runs {
                group.addTask {
                    if let r = await self.runReport(for: run) { return r }
                    return await MainActor.run { Self.reportSkeleton(for: run) }
                }
            }
            var collected: [RunReportDetail] = []
            for await report in group {
                collected.append(report)
            }
            return collected
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
        for runID in Self.reportRunIDCandidates(for: run) {
            if let cached = store.cachedRunReport(runID: runID) {
                return cached
            }
        }
        return nil
    }

    func generateRunReportIfMissing(for run: RecordedRun) async -> RunReportDetail? {
        if let existing = await runReport(for: run) {
            return existing
        }

        let recent = Array((await recentRuns()).prefix(5))
        let upcoming = Array((await nextWorkouts(limit: 3)))
        let fallback = Self.fallbackRunReport(for: run, recentRuns: recent, upcomingWorkouts: upcoming)
        guard let token = try? await supabase.auth.session.accessToken else {
            await cacheRunReport(fallback)
            return fallback
        }

        do {
            let request = Self.reportRequest(for: run, recentRuns: recent, upcomingWorkouts: upcoming)
            let encoder = JSONEncoder()
            let body = try encoder.encode(request)
            let client = URLSessionRunSmartAPIClient(accessToken: token)
            let payload = try await client.send(
                RunSmartAPI.Endpoint(path: "api/run-report", method: .post, body: body),
                as: RunSmartDTO.RunReportResponse.self
            )
            let report = Self.report(from: payload.report, run: run)
            await cacheRunReport(report)
            await MainActor.run {
                NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            }
            return report
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] run report generation error:", error)
            }
            await cacheRunReport(fallback)
            return fallback
        }
    }

    func generateRunReportIfMissing(forRunID runID: String) async -> RunReportDetail? {
        guard let run = await run(matchingReportRunID: runID) else {
            return store.cachedRunReport(runID: runID)
        }
        return await generateRunReportIfMissing(for: run)
    }

    private func fetchRunDebrief(for run: RecordedRun) async -> PostRunDebriefModel {
        guard let token = try? await supabase.auth.session.accessToken else {
            return .fallback(for: run)
        }

        let distanceKm = run.distanceMeters / 1_000.0
        let durationSec = Int(run.movingTimeSeconds)
        let paceMinPerKm: Double? = distanceKm > 0 && run.movingTimeSeconds > 0
            ? (run.movingTimeSeconds / 60.0) / distanceKm
            : nil

        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let recentCount = store.loadRuns()
            .filter { $0.startedAt >= sevenDaysAgo }
            .count

        let request = RunSmartDTO.RunDebriefRequestDTO(
            runDistanceKm: distanceKm,
            runDurationSeconds: durationSec,
            averagePaceMinPerKm: paceMinPerKm,
            averageHeartRateBPM: run.averageHeartRateBPM,
            workoutType: "easy",
            planPhase: nil,
            recentLoadDays: recentCount,
            limitations: []
        )
        guard let body = try? JSONEncoder().encode(request) else {
            return .fallback(for: run)
        }
        let client = URLSessionRunSmartAPIClient(
            baseURL: SupabaseManager.functionsBaseURL,
            accessToken: token,
            additionalHeaders: ["apikey": SupabaseManager.supabasePublishableKey]
        )
        do {
            let response = try await withThrowingTaskGroup(of: RunSmartDTO.RunDebriefResponseDTO.self) { group in
                group.addTask {
                    try await client.send(
                        RunSmartAPI.Endpoint(path: "coach_message", method: .post, body: body),
                        as: RunSmartDTO.RunDebriefResponseDTO.self
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 12_000_000_000)
                    throw DebriefTimeoutError()
                }
                do {
                    guard let result = try await group.next() else { throw DebriefTimeoutError() }
                    group.cancelAll()
                    return result
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
            let headline = response.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            let debrief = response.debrief.trimmingCharacters(in: .whitespacesAndNewlines)
            let tomorrow = response.tomorrow.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headline.isEmpty, !debrief.isEmpty, !tomorrow.isEmpty else {
                print("[SupabaseServices] run_debrief: AI response missing required fields, using fallback")
                return .fallback(for: run)
            }
            let model = PostRunDebriefModel(
                headline: headline,
                debrief: debrief,
                tomorrow: tomorrow,
                planImpact: response.planImpact,
                source: .ai
            )
            await persistDebrief(model, for: run)
            return model
        } catch {
            switch error {
            case is DebriefTimeoutError:
                print("[SupabaseServices] run_debrief timed out after 12s, using fallback")
            case is CancellationError:
                break  // parent task was cancelled — silent
            default:
                print("[SupabaseServices] run_debrief fallback:", error)
            }
            return .fallback(for: run)
        }
    }

    func generateWeeklySummary() async -> WeeklyProgressSummary? {
        let currentKey = WeeklyProgressSummary.currentISOWeekKey()
        let cacheKey = "runsmart.weekly_summary.\(currentKey)"

        // Return cached summary if it exists for this week
        if let cached = UserDefaults.standard.data(forKey: cacheKey),
           let summary = try? JSONDecoder().decode(WeeklyProgressSummary.self, from: cached) {
            return summary
        }

        // Gather week stats from local store
        let cal = Calendar(identifier: .iso8601)
        let weekStartComponents = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        guard let weekStart = cal.date(from: weekStartComponents) else {
            print("[SupabaseServices] weekly_summary: could not compute ISO week start, skipping")
            return nil
        }
        let allRuns = store.visibleRuns(store.loadRuns())
        let weekRuns = allRuns.filter { $0.startedAt >= weekStart }

        // Guard: no card if zero runs this week
        guard !weekRuns.isEmpty else { return nil }

        let totalDistanceKm = weekRuns.reduce(0.0) { $0 + $1.distanceMeters / 1_000.0 }

        // Previous week distance for step-up context
        let prevWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        let prevWeekRuns = allRuns.filter { $0.startedAt >= prevWeekStart && $0.startedAt < weekStart }
        let prevDistanceKm = prevWeekRuns.isEmpty ? nil :
            prevWeekRuns.reduce(0.0) { $0 + $1.distanceMeters / 1_000.0 }

        // Fetch from AI
        guard let token = try? await supabase.auth.session.accessToken else {
            let fallback = WeeklyProgressSummary.fallback(
                runsCompleted: weekRuns.count,
                totalDistanceKm: totalDistanceKm
            )
            cacheWeeklySummary(fallback, forKey: cacheKey)
            return fallback
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let weekStartISO = formatter.string(from: weekStart)

        let request = RunSmartDTO.WeeklySummaryRequestDTO(
            weekStartDate: weekStartISO,
            runsCompleted: weekRuns.count,
            runsPlanned: 0,
            totalDistanceKm: totalDistanceKm,
            prevWeekDistanceKm: prevDistanceKm,
            planPhase: nil,
            isRecoveryWeek: false,
            readinessAverage: nil,
            limitations: []
        )
        guard let body = try? JSONEncoder().encode(request) else {
            print("[SupabaseServices] weekly_summary: failed to encode request, using fallback")
            let fallback = WeeklyProgressSummary.fallback(
                runsCompleted: weekRuns.count,
                totalDistanceKm: totalDistanceKm
            )
            cacheWeeklySummary(fallback, forKey: cacheKey)
            return fallback
        }

        let client = URLSessionRunSmartAPIClient(
            baseURL: SupabaseManager.functionsBaseURL,
            accessToken: token,
            additionalHeaders: ["apikey": SupabaseManager.supabasePublishableKey]
        )

        do {
            let response: RunSmartDTO.WeeklySummaryResponseDTO = try await withThrowingTaskGroup(of: RunSmartDTO.WeeklySummaryResponseDTO.self) { group in
                group.addTask {
                    try await client.send(
                        RunSmartAPI.Endpoint(path: "coach_message", method: .post, body: body),
                        as: RunSmartDTO.WeeklySummaryResponseDTO.self
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)  // iOS 13+ compatible
                    throw WeeklySummaryTimeoutError()
                }
                do {
                    guard let result = try await group.next() else { throw WeeklySummaryTimeoutError() }
                    group.cancelAll()
                    return result
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
            let headline = response.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            let narrative = response.narrative.trimmingCharacters(in: .whitespacesAndNewlines)
            let forwardLook = response.forwardLook.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headline.isEmpty, !narrative.isEmpty, !forwardLook.isEmpty else {
                print("[SupabaseServices] weekly_summary: AI response missing required fields, using fallback")
                let fallback = WeeklyProgressSummary.fallback(
                    runsCompleted: weekRuns.count,
                    totalDistanceKm: totalDistanceKm
                )
                cacheWeeklySummary(fallback, forKey: cacheKey)
                return fallback
            }
            let summary = WeeklyProgressSummary(
                headline: headline,
                narrative: narrative,
                forwardLook: forwardLook,
                weekLabel: response.weekLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                generatedDate: Date(),
                isoWeekKey: currentKey,
                source: .ai
            )
            cacheWeeklySummary(summary, forKey: cacheKey)
            return summary
        } catch {
            switch error {
            case is WeeklySummaryTimeoutError:
                print("[SupabaseServices] weekly_summary timed out after 5s, using fallback")
            case is CancellationError:
                return nil  // parent task was cancelled — don't cache stale fallback
            default:
                print("[SupabaseServices] weekly_summary fallback:", error)
            }
            let fallback = WeeklyProgressSummary.fallback(
                runsCompleted: weekRuns.count,
                totalDistanceKm: totalDistanceKm
            )
            cacheWeeklySummary(fallback, forKey: cacheKey)
            return fallback
        }
    }

    private func cacheWeeklySummary(_ summary: WeeklyProgressSummary, forKey key: String) {
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func flexCurrentWeek(_ request: FlexWeekRequest) async -> FlexWeekOutcome {
        guard let token = try? await supabase.auth.session.accessToken else {
            if let cached = FlexWeekServiceSupport.cachedOutcome(for: request, userID: currentUserID) {
                return cached
            }
            return FlexWeekServiceSupport.deterministicOutcome(for: request, source: .offlineQueued)
        }

        let requestDTO = FlexWeekServiceSupport.buildRequestDTO(from: request)
        guard let body = try? JSONEncoder().encode(requestDTO) else {
            return FlexWeekServiceSupport.deterministicOutcome(for: request)
        }

        let client = URLSessionRunSmartAPIClient(
            baseURL: SupabaseManager.functionsBaseURL,
            accessToken: token,
            additionalHeaders: ["apikey": SupabaseManager.supabasePublishableKey]
        )

        do {
            let response: RunSmartDTO.FlexWeekResponseDTO = try await withThrowingTaskGroup(of: RunSmartDTO.FlexWeekResponseDTO.self) { group in
                group.addTask {
                    try await client.send(
                        RunSmartAPI.Endpoint(path: "coach_message", method: .post, body: body),
                        as: RunSmartDTO.FlexWeekResponseDTO.self
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 6_500_000_000)
                    throw FlexWeekTimeoutError()
                }
                do {
                    guard let result = try await group.next() else { throw FlexWeekTimeoutError() }
                    group.cancelAll()
                    return result
                } catch {
                    group.cancelAll()
                    throw error
                }
            }

            if let outcome = FlexWeekServiceSupport.outcome(from: response, originalWeek: request.currentWeek) {
                FlexWeekServiceSupport.cacheResponse(response, for: request, userID: currentUserID)
                return outcome
            }

            print("[SupabaseServices] flex_week: AI response failed validation, using fallback")
            return FlexWeekServiceSupport.deterministicOutcome(for: request)
        } catch {
            switch error {
            case is FlexWeekTimeoutError:
                print("[SupabaseServices] flex_week timed out after 4s, using fallback")
            case is CancellationError:
                return FlexWeekServiceSupport.deterministicOutcome(for: request)
            default:
                print("[SupabaseServices] flex_week fallback:", error)
            }
            return FlexWeekServiceSupport.deterministicOutcome(for: request)
        }
    }

    private func persistDebrief(_ debrief: PostRunDebriefModel, for run: RecordedRun) async {
        guard let userID = currentUserID else { return }
        do {
            try await supabase
                .from("run_debriefs")
                .upsert(
                    DBRunDebriefUpsert(
                        authUserID: userID.uuidString,
                        runID: run.id.uuidString,
                        headline: debrief.headline,
                        debrief: debrief.debrief,
                        tomorrow: debrief.tomorrow,
                        planImpact: debrief.planImpact,
                        source: debrief.source.rawValue
                    ),
                    onConflict: "auth_user_id,run_id"
                )
                .execute()
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] persistDebrief error:", error)
            }
        }
    }

    func processCompletedActivity(_ run: RecordedRun) async -> PostActivityOutcome {
        let canonical = saveRouteMatch(for: ActivityConsolidationService.canonicalRun(for: run, in: await recentRuns(limit: 100)))
        await upsertCompletedRunIfPossible(canonical)
        store.refreshBenchmarkStats()
        async let reportTask = generateRunReportIfMissing(for: canonical)
        async let completedTask = completeMatchingWorkout(for: canonical)
        async let debriefTask = fetchRunDebrief(for: canonical)          // E6
        let (report, completed, debrief) = await (reportTask, completedTask, debriefTask)

        Analytics.trackCompletedRunIfNeeded(
            canonical,
            runType: completed?.kind.rawValue ?? canonical.source.rawValue
        )

        await MainActor.run {
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            NotificationCenter.default.post(name: .runSmartReportsDidChange, object: nil)
            NotificationCenter.default.post(name: .runSmartPlanDidChange, object: nil)
            if let completed {
                PushService.shared.cancelWorkoutReminder(workoutID: completed.id)
            }
        }

        return PostActivityOutcome(
            canonicalRun: canonical,
            report: report,
            completedWorkout: completed,
            didCompletePlannedWorkout: completed != nil,
            debrief: debrief                               // E6: AI post-run debrief
        )
    }

    func matchRoute(for run: RecordedRun) async -> RouteMatchResult? {
        RouteMatchingService.match(run: run, savedRoutes: store.loadSavedRoutes())
    }

    func benchmarkComparison(for run: RecordedRun) async -> BenchmarkRouteComparison? {
        BenchmarkRouteAnalyticsService.comparison(
            for: run,
            runs: store.visibleRuns(store.loadRuns()),
            savedRoutes: store.loadSavedRoutes(),
            benchmarkRoutes: store.loadBenchmarkRoutes()
        )
    }

    private func saveRouteMatch(for run: RecordedRun) -> RecordedRun {
        var matchedRun = run
        matchedRun.routeMatchResult = RouteMatchingService.match(run: run, savedRoutes: store.loadSavedRoutes())
        store.saveRun(matchedRun)
        return matchedRun
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
        let health = store.loadHealthKitDailySnapshot()
        guard let metrics = await latestGarminMetrics(userID: userID) else {
            guard let health else { return .loading }
            let sleep = health.sleepSeconds.map(formatDuration) ?? "—"
            let resolvedHRV = HRVResolver.resolve(
                garminDirect: nil,
                healthKit: health.hrvMilliseconds.map { HRVReading(value: $0, source: health.hrvSource) }
            )
            let hrv = resolvedHRV.map { String(format: "%.0f ms", $0.value) } ?? "—"
            let readiness = healthReadiness(from: health)
            return RecoverySnapshot(
                readiness: readiness,
                bodyBattery: readiness,
                sleep: sleep,
                hrv: hrv,
                hrvSource: resolvedHRV?.source ?? .unknown,
                stress: health.restingHeartRateBPM.map { "\($0) bpm resting" } ?? "—",
                recommendation: "Recovery data synced from Apple Health."
            )
        }
        let resolvedHRV = HRVResolver.resolve(
            garminDirect: metrics.hrv.map { HRVReading(value: $0, source: .garmin) },
            healthKit: health?.hrvMilliseconds.map { HRVReading(value: $0, source: health?.hrvSource ?? .unknown) }
        )
        return RecoverySnapshot(
            readiness: metrics.bodyBattery ?? 0,
            bodyBattery: metrics.bodyBattery ?? 0,
            sleep: metrics.sleepDurationS.map { String(format: "%dh %02dm", Int32($0 / 3600), Int32(($0 % 3600) / 60)) } ?? "—",
            hrv: resolvedHRV.map { String(format: "%.0f ms", $0.value) } ?? "—",
            hrvSource: resolvedHRV?.source ?? .unknown,
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

    func wellnessTrendSeries(days: Int = 7) async -> WellnessTrendSeries {
        guard let userID = currentUserID else { return .empty }
        let metrics = await GarminBridge.shared.dailyMetrics(authUserID: userID, lastDays: max(1, days))
        let garminSeries = WellnessTrendMapper.series(from: metrics, maxDays: max(1, days))
        if !garminSeries.days.isEmpty {
            return garminSeries
        }
        guard let health = store.loadHealthKitDailySnapshot(), let hrv = health.hrvMilliseconds else {
            return .empty
        }
        let point = DailyWellnessPoint(
            date: health.date,
            hrvMilliseconds: hrv,
            hrvSource: health.hrvSource,
            trainingReadiness: nil,
            bodyBattery: nil
        )
        return WellnessTrendSeries(
            days: [point],
            hrvBars: [1.0],
            readinessBars: [],
            hrvTrendSummary: "Need more synced days",
            readinessTrendSummary: "Need more synced days",
            latestHRVDisplay: String(format: "%.0f ms", hrv),
            latestHRVSource: health.hrvSource,
            latestReadinessDisplay: "--"
        )
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
            source: "garmin"
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
                    energy: Self.clampedCheckinScore(energy),
                    soreness: Self.clampedCheckinScore(soreness ?? 1),
                    mood: mood,
                    stress: stress.map(Self.clampedCheckinScore),
                    fatigue: fatigue.map(Self.clampedCheckinScore),
                    notes: notes,
                    source: Self.databaseCheckinSource(source)
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

    private static func clampedCheckinScore(_ value: Int) -> Int {
        max(1, min(10, value))
    }

    private static func databaseCheckinSource(_ source: String) -> String {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("garmin") { return "garmin" }
        return "manual"
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
        GarminBridge.shared.invalidateActivityCache()
        await MainActor.run {
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
        }
    }

    private func postReportsChanged() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .runSmartReportsDidChange, object: nil)
        }
    }

    private func cacheRunReport(_ report: RunReportDetail) async {
        store.saveRunReport(report)
        await postReportsChanged()
    }

    private func completeMatchingWorkout(for run: RecordedRun) async -> WorkoutSummary? {
        guard let userID = currentUserID else { return nil }
        return await planRepo.completeBestMatchingWorkout(authUserID: userID, for: run)
    }

    private func upsertCompletedRunIfPossible(_ run: RecordedRun) async {
        guard let userID = currentUserID else { return }
        let identity = await planRepo.identity(authUserID: userID)

        do {
            try await supabase
                .from("runs")
                .upsert(
                    DBRunInsert(run: run, identity: identity, kind: .easy, notes: "Completed activity from \(run.source.rawValue)"),
                    onConflict: "source_provider,source_activity_id"
                )
                .execute()
            var synced = run
            synced.syncedAt = Date()
            store.saveRun(synced)
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] completed run upsert error:", error)
            }
        }
    }

    private func upsertHealthKitRuns(_ runs: [RecordedRun]) async -> Int {
        guard let userID = currentUserID, !runs.isEmpty else { return 0 }
        let identity = await planRepo.identity(authUserID: userID)
        let inserts = runs.map {
            DBRunInsert(run: $0, identity: identity, kind: .easy, notes: "Imported from Apple Health")
        }

        do {
            try await supabase
                .from("runs")
                .upsert(inserts, onConflict: "source_provider,source_activity_id")
                .execute()
            return runs.count
        } catch {
            if error is CancellationError { return 0 }
            print("[SupabaseServices] HealthKit bulk run upsert error, retrying per run:", error)
        }

        var synced = 0
        for insert in inserts {
            do {
                try await supabase
                    .from("runs")
                    .upsert(insert, onConflict: "source_provider,source_activity_id")
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
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] fetchGarminConnection error:", error)
                return ConnectedDeviceStatus(
                    provider: "Garmin Connect",
                    state: .error,
                    lastSuccessfulSync: nil,
                    permissions: [],
                    message: error.localizedDescription
                )
            }
        }
        return ConnectedDeviceStatus(provider: "Garmin Connect", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil)
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
                .rpc(
                    "coach_messages_for_conversation",
                    params: DBCoachMessagesForConversationParams(
                        conversationID: conv.id.uuidString,
                        limit: 1,
                        assistantOnly: true
                    )
                )
                .execute()
                .value
            return messages.first?.content
        } catch { return nil }
    }

    private func coachConversation(for userID: UUID) async throws -> DBConversation {
        let existing: [DBConversation] = try await supabase
            .from("conversations")
            .select()
            .eq("profile_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        if let conversation = existing.first {
            return conversation
        }

        let inserted: [DBConversation]
        do {
            inserted = try await supabase
                .from("conversations")
                .insert(DBConversationInsert(profileId: userID.uuidString, authUserId: userID.uuidString, title: "RunSmart Coach"))
                .select()
                .execute()
                .value
        } catch {
            if isLikelyMissingCoachMessageColumns(error) {
                inserted = try await supabase
                    .from("conversations")
                    .insert(DBConversationInsert(profileId: userID.uuidString))
                    .select()
                    .execute()
                    .value
            } else {
                throw error
            }
        }

        guard let conversation = inserted.first else {
            throw RunSmartCoachPersistenceError.conversationCreateReturnedNoRow
        }
        return conversation
    }

    private func insertCoachTurn(
        conversationID: UUID,
        userMessage: String,
        assistantMessage: String,
        authUserID: String? = nil,
        clientMessageID: String? = nil,
        source: String = "fallback",
        entryPoint: String? = nil
    ) async throws {
        let userCreatedAt = ISO8601DateFormatter().string(from: Date())
        let assistantCreatedAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(0.001))
        let metadata = entryPoint.map { ["entryPoint": $0] }

        let newRows = [
            DBMessageInsert(
                conversationId: conversationID.uuidString,
                authUserId: authUserID,
                role: "user",
                content: userMessage,
                createdAt: userCreatedAt,
                clientMessageId: clientMessageID,
                source: "client",
                metadata: metadata
            ),
            DBMessageInsert(
                conversationId: conversationID.uuidString,
                authUserId: authUserID,
                role: "assistant",
                content: assistantMessage,
                createdAt: assistantCreatedAt,
                clientMessageId: clientMessageID.map { "\($0):assistant" },
                source: source,
                metadata: metadata
            )
        ]

        do {
            try await supabase
                .from("conversation_messages")
                .insert(newRows)
                .execute()
        } catch {
            if isLikelyMissingCoachMessageColumns(error) {
                try await insertLegacyCoachTurn(
                    conversationID: conversationID,
                    userMessage: userMessage,
                    assistantMessage: assistantMessage,
                    userCreatedAt: userCreatedAt,
                    assistantCreatedAt: assistantCreatedAt
                )
                return
            }

            if let clientMessageID {
                try await insertFallbackAssistantIfNeeded(
                    conversationID: conversationID,
                    assistantMessage: assistantMessage,
                    createdAt: assistantCreatedAt,
                    clientMessageID: "\(clientMessageID):assistant",
                    authUserID: authUserID,
                    source: source,
                    metadata: metadata
                )
                return
            }

            throw error
        }
    }

    private func insertFallbackAssistantIfNeeded(
        conversationID: UUID,
        assistantMessage: String,
        createdAt: String,
        clientMessageID: String,
        authUserID: String?,
        source: String,
        metadata: [String: String]?
    ) async throws {
        let existing: [DBMessage] = try await supabase
            .from("conversation_messages")
            .select()
            .eq("conversation_id", value: conversationID.uuidString)
            .eq("client_message_id", value: clientMessageID)
            .limit(1)
            .execute()
            .value

        guard existing.isEmpty else { return }

        try await supabase
            .from("conversation_messages")
            .insert(DBMessageInsert(
                conversationId: conversationID.uuidString,
                authUserId: authUserID,
                role: "assistant",
                content: assistantMessage,
                createdAt: createdAt,
                clientMessageId: clientMessageID,
                source: source,
                metadata: metadata
            ))
            .execute()
    }

    private func insertLegacyCoachTurn(
        conversationID: UUID,
        userMessage: String,
        assistantMessage: String,
        userCreatedAt: String,
        assistantCreatedAt: String
    ) async throws {
        try await supabase
            .from("conversation_messages")
            .insert([
                DBMessageInsert(
                    conversationId: conversationID.uuidString,
                    role: "user",
                    content: userMessage,
                    createdAt: userCreatedAt
                ),
                DBMessageInsert(
                    conversationId: conversationID.uuidString,
                    role: "assistant",
                    content: assistantMessage,
                    createdAt: assistantCreatedAt
                )
            ])
            .execute()
    }

    private func isLikelyMissingCoachMessageColumns(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains("client_message_id") || text.contains("source") || text.contains("auth_user_id")
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

    private func postRouteChange() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .runSmartRoutesDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let runSmartPlanDidChange = Notification.Name("RunSmartPlanDidChange")
    static let runSmartPlanGenerationStatusDidChange = Notification.Name("RunSmartPlanGenerationStatusDidChange")
    static let runSmartRunsDidChange = Notification.Name("RunSmartRunsDidChange")
    static let runSmartReportsDidChange = Notification.Name("RunSmartReportsDidChange")
    static let runSmartRoutesDidChange = Notification.Name("RunSmartRoutesDidChange")
}

private extension ISO8601DateFormatter {
    static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct DBRunInsert: Encodable {
    let profileID: Int?
    let authUserID: String
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

    init(run: RecordedRun, identity: RunSmartIdentity, kind: WorkoutKind, notes: String?) {
        let syncedAt = Date()
        self.profileID = identity.numericUserID
        self.authUserID = identity.authUserID.uuidString
        self.type = kind.supabaseType
        let distanceKm: Double = (run.distanceMeters / 1_000 * 1_000).rounded() / 1_000
        self.distance = distanceKm
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
        case authUserID = "auth_user_id"
        case type, distance, duration, pace, notes
        case heartRate = "heart_rate"
        case completedAt = "completed_at"
        case sourceProvider = "source_provider"
        case sourceActivityID = "source_activity_id"
        case lastSyncedAt = "last_synced_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(profileID, forKey: .profileID)
        try container.encode(authUserID, forKey: .authUserID)
        try container.encode(type, forKey: .type)
        try container.encode(distance, forKey: .distance)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(pace, forKey: .pace)
        try container.encodeIfPresent(heartRate, forKey: .heartRate)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(sourceProvider, forKey: .sourceProvider)
        try container.encode(sourceActivityID, forKey: .sourceActivityID)
        try container.encode(lastSyncedAt, forKey: .lastSyncedAt)
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

private struct DebriefTimeoutError: Error {}
private struct WeeklySummaryTimeoutError: Error {}
private struct FlexWeekTimeoutError: Error {}

private struct DBRunDebriefUpsert: Encodable {
    let authUserID: String
    let runID: String
    let headline: String
    let debrief: String
    let tomorrow: String
    let planImpact: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case authUserID = "auth_user_id"
        case runID = "run_id"
        case headline, debrief, tomorrow
        case planImpact = "plan_impact"
        case source
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
            Self.reportRunIDCandidates(for: run).contains(runID)
        }
    }

    static func reportRunID(for run: RecordedRun) -> String {
        run.consolidatedActivityID ?? run.providerActivityID ?? run.id.uuidString
    }

    static func reportRunIDCandidates(for run: RecordedRun) -> [String] {
        var seen = Set<String>()
        return [run.consolidatedActivityID, run.providerActivityID, run.id.uuidString]
            .compactMap { value in
                guard let value, !value.isEmpty, seen.insert(value).inserted else { return nil }
                return value
            }
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

    static func fallbackRunReport(
        for run: RecordedRun,
        recentRuns: [RecordedRun],
        upcomingWorkouts: [WorkoutSummary]
    ) -> RunReportDetail {
        let runID = reportRunID(for: run)
        let distanceKm = run.distanceMeters / 1_000
        let pace = RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm)
        let effort = fallbackEffort(for: run)
        let planned = upcomingWorkouts.first { Calendar.current.isDate($0.scheduledDate, inSameDayAs: run.startedAt) }
        let nextWorkout = upcomingWorkouts.first { $0.scheduledDate > run.startedAt } ?? upcomingWorkouts.first
        let comparison: String
        if let planned {
            comparison = "Compared with today's planned \(planned.title), this completed \(String(format: "%.1f", distanceKm)) km run gives the plan real activity data to work from."
        } else {
            comparison = "No planned workout was close enough to mark complete, so this counts as an extra completed run in your recent load."
        }
        let recentKm = recentRuns.reduce(0.0) { $0 + $1.distanceMeters } / 1_000

        return RunReportDetail(
            id: "report-\(runID)",
            runID: runID,
            title: "\(run.source.rawValue) Run Report",
            dateLabel: run.startedAt.formatted(date: .abbreviated, time: .omitted),
            source: run.source.rawValue,
            distance: String(format: "%.2f km", distanceKm),
            duration: RunRecorder.timeLabel(run.movingTimeSeconds),
            averagePace: pace,
            averageHeartRate: run.averageHeartRateBPM.map { "\($0) bpm" } ?? "—",
            coachScore: nil,
            notes: CoachRunNotes(
                summary: "Completed \(String(format: "%.1f", distanceKm)) km in \(RunRecorder.timeLabel(run.movingTimeSeconds)) at \(pace)/km. \(comparison)",
                effort: "Effort looks \(effort) from pace, duration, and distance. Use how it felt to adjust the next session if needed.",
                recovery: "This adds to recent load (\(String(format: "%.1f", recentKm)) km in the current report context). Keep the next run controlled if legs feel heavy.",
                nextSessionNudge: nextWorkout.map { "Next recommended: \($0.title), \($0.distance)." } ?? "Next recommended: an easy aerobic run or recovery day based on how you feel tomorrow.",
                keyInsights: [
                    "Benefit: aerobic endurance and weekly consistency.",
                    planned == nil ? "Plan impact: logged as extra training load." : "Plan impact: compared against today's planned workout.",
                    nextWorkout.map { "Next: \($0.title)." } ?? "Next: keep effort easy unless recovery is strong."
                ],
                pacing: "Average pace: \(pace)/km.",
                biomechanics: nil,
                recoveryTimeline: [
                    "Today: hydrate and refuel.",
                    "Next 24h: choose easy effort if soreness is elevated."
                ]
            ),
            structuredNextWorkout: nextWorkout.map {
                StructuredNextWorkout(
                    title: $0.title,
                    dateLabel: $0.scheduledDate.formatted(date: .abbreviated, time: .omitted),
                    distance: $0.distance,
                    target: $0.intensity ?? $0.detail,
                    notes: "Recommended from deterministic RunSmart report fallback."
                )
            },
            isGenerated: true
        )
    }

    private static func fallbackEffort(for run: RecordedRun) -> String {
        let pace = run.averagePaceSecondsPerKm
        if let heartRate = run.averageHeartRateBPM {
            if heartRate >= 165 { return "hard" }
            if heartRate >= 145 { return "moderate" }
            return "easy"
        }
        if pace <= 300 || run.movingTimeSeconds >= 75 * 60 { return "moderate" }
        if pace >= 420 { return "easy" }
        return "steady"
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

// MARK: - TodayRationaleBuilder

struct TodayRationaleBuilder {
    static func rationale(
        bodyBattery: Int?,
        hrv: Double?,
        sleepSeconds: Double?,
        workoutTitle: String,
        isRestDay: Bool,
        planWeekIndex: Int?
    ) -> String {
        if isRestDay {
            if let bb = bodyBattery, bb < 50 {
                return "Body battery at \(bb) — today's rest lets you recharge before the next block."
            }
            return "Rest is training too. Recovery today means a stronger effort tomorrow."
        }

        if let bb = bodyBattery {
            if bb > 70 {
                return "Body battery at \(bb) — you're fueled for a real effort. Today's run lands well."
            } else if bb > 40 {
                return "Body battery at \(bb). A controlled effort keeps your energy balanced this week."
            } else {
                return "Body battery is low at \(bb). Keep today easy — protecting your week matters more."
            }
        }

        if let hrv = hrv {
            let rounded = Int(hrv)
            if hrv > 50 {
                return "HRV is stable at \(rounded) ms — a good sign for a solid training effort today."
            } else {
                return "HRV is a bit lower at \(rounded) ms. An easy effort supports full recovery."
            }
        }

        if let sleep = sleepSeconds, sleep > 6 * 3600 {
            return "Good sleep last night. Your body is primed — make today's effort count."
        }

        if let week = planWeekIndex {
            if week <= 2 {
                return "Early in your plan. Easy efforts build the aerobic base that makes hard efforts possible."
            }
            if week >= 8 {
                return "You've put in serious work to get here. Today's effort is part of a bigger picture."
            }
        }

        return "Consistency is the foundation. Today's run keeps your training momentum going."
    }
}

// MARK: - SafetyExplanationBuilder

struct SafetyExplanationBuilder {
    static func explanation(
        readiness: Int,
        bodyBattery: Int?,
        hrv: Double?,
        workoutTitle: String,
        isRestDay: Bool
    ) -> SafetyExplanation? {
        guard readiness > 0 else { return nil }

        if readiness < 45 {
            let evidence = evidenceString(readiness: readiness, bodyBattery: bodyBattery, hrv: hrv)
            let coachVoice = isRestDay
                ? "Your readiness is at \(readiness) — your body is telling me it needs more time to absorb the last training block. Today's rest is doing real work."
                : "Your readiness is at \(readiness) — your body hasn't fully recovered yet. A lighter effort today protects the quality of your next hard session."
            return SafetyExplanation(
                kind: .readinessGate,
                headline: "Coach is keeping today easy",
                coachVoice: coachVoice,
                evidence: evidence,
                action: isRestDay ? nil : "Amend workout"
            )
        }

        if let bb = bodyBattery, bb < 35, readiness < 65 {
            let evidence = evidenceString(readiness: readiness, bodyBattery: bb, hrv: hrv)
            return SafetyExplanation(
                kind: .lowBodyBattery,
                headline: "Energy reserves are low",
                coachVoice: "Body battery is at \(bb). Your reserves are depleted — a controlled effort today keeps you from digging a hole that hurts the rest of the week.",
                evidence: evidence,
                action: "Amend workout"
            )
        }

        if let hrv = hrv, hrv < 40, readiness < 65 {
            let rounded = Int(hrv)
            let evidence = evidenceString(readiness: readiness, bodyBattery: bodyBattery, hrv: hrv)
            return SafetyExplanation(
                kind: .lowHRV,
                headline: "Nervous system still recovering",
                coachVoice: "HRV is lower than usual at \(rounded) ms — a sign your nervous system is still catching up. Today's run should stay at a fully conversational pace.",
                evidence: evidence,
                action: "Amend workout"
            )
        }

        return nil
    }

    private static func evidenceString(readiness: Int, bodyBattery: Int?, hrv: Double?) -> String {
        var parts: [String] = ["Readiness \(readiness)"]
        if let bb = bodyBattery { parts.append("body battery \(bb)") }
        if let hrv = hrv { parts.append("HRV \(Int(hrv)) ms") }
        return parts.joined(separator: " · ")
    }
}
