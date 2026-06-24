import Foundation

extension Analytics {
    private static let completedRunFlagKey = "analytics.hasCompletedRun"
    private static let completedRunKeyPrefix = "analytics.completedRun."

    // MARK: - Activation Funnel

    static func trackAppLaunched() {
        shared.track("app_launched", properties: ["session_id": UUID().uuidString])
    }

    static func trackSignInCompleted(method: String = "apple") {
        shared.track("sign_in_completed", properties: ["method": method])
    }

    static func trackOnboardingStarted() {
        shared.track("onboarding_started", properties: [:])
    }

    static func trackOnboardingStepCompleted(stepNumber: Int, stepName: String) {
        shared.track("onboarding_step_completed", properties: [
            "step_number": stepNumber,
            "step_name": stepName
        ])
    }

    static func trackOnboardingCompleted(goal: String, experience: String, daysPerWeek: Int) {
        shared.track("onboarding_completed", properties: [
            "goal": goal,
            "experience": experience,
            "days_per_week": daysPerWeek
        ])
    }

    static func trackPlanGenerated(planType: String, durationWeeks: Int) {
        shared.track("plan_generated", properties: [
            "plan_type": planType,
            "duration_weeks": durationWeeks
        ])
    }

    // MARK: - Run Engagement

    static func trackRunStarted(source: String) {
        shared.track("run_started", properties: ["source": source])
    }

    static func trackRunCompleted(
        distanceKm: Double,
        durationSeconds: Int,
        paceMinKm: Double,
        runType: String,
        isFirstRun: Bool = false
    ) {
        shared.track("run_completed", properties: [
            "distance_km": distanceKm,
            "duration_s": durationSeconds,
            "pace_min_km": paceMinKm,
            "run_type": runType,
            "is_first_run": isFirstRun
        ])
        if isFirstRun {
            shared.track("first_run_completed", properties: [
                "distance_km": distanceKm,
                "duration_s": durationSeconds,
                "run_type": runType
            ])
        }
    }

    static func trackCompletedRunIfNeeded(
        _ run: RecordedRun,
        runType: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        let key = completedRunKey(for: run)
        guard !defaults.bool(forKey: key) else { return }

        let isFirst = !defaults.bool(forKey: completedRunFlagKey)
        defaults.set(true, forKey: key)
        defaults.set(true, forKey: completedRunFlagKey)
        trackRunCompleted(
            distanceKm: run.distanceMeters / 1000,
            durationSeconds: Int(run.movingTimeSeconds),
            paceMinKm: run.averagePaceSecondsPerKm / 60,
            runType: runType ?? run.source.rawValue,
            isFirstRun: isFirst
        )
    }

    static func trackRunAbandoned(durationSeconds: Int, distanceKm: Double) {
        shared.track("run_abandoned", properties: [
            "duration_s": durationSeconds,
            "distance_km": distanceKm
        ])
    }

    static func trackPostRunCardViewed(hasBenchmark: Bool, hasPlanMatch: Bool) {
        shared.track("post_run_card_viewed", properties: [
            "has_benchmark": hasBenchmark,
            "has_plan_match": hasPlanMatch
        ])
    }

    // MARK: - Coach

    static func trackCoachThreadOpened(entryPoint: String) {
        shared.track("coach_thread_opened", properties: ["entry_point": entryPoint])
    }

    static func trackCoachMessageSent(entryPoint: String, messageLength: Int) {
        shared.track("coach_message_sent", properties: [
            "entry_point": entryPoint,
            "message_length": messageLength
        ])
    }

    // MARK: - Plan

    static func trackPlanViewed(weekNumber: Int?, hasActivePlan: Bool) {
        var props: [String: Any] = ["has_active_plan": hasActivePlan]
        if let week = weekNumber { props["week_number"] = week }
        shared.track("plan_viewed", properties: props)
    }

    static func trackPlanWorkoutTapped(workoutType: String, weekNumber: Int?) {
        var props: [String: Any] = ["workout_type": workoutType]
        if let week = weekNumber { props["week_number"] = week }
        shared.track("plan_workout_tapped", properties: props)
    }

    static func trackPlanRunCTATapped(
        source: String,
        workoutType: String,
        scheduledToday: Bool,
        hasPriorRuns: Bool
    ) {
        shared.track("plan_run_cta_tapped", properties: [
            "source": source,
            "workout_type": workoutType,
            "scheduled_today": scheduledToday,
            "has_prior_runs": hasPriorRuns
        ])
    }

    // MARK: - Routes

    static func trackRouteSelected(routeKind: String) {
        shared.track("route_selected", properties: ["route_kind": routeKind])
    }

    static func trackBenchmarkViewed(hasHistory: Bool, comparisonType: String) {
        shared.track("benchmark_viewed", properties: [
            "has_history": hasHistory,
            "comparison_type": comparisonType
        ])
    }

    static func trackRouteSaved(pointCount: Int) {
        shared.track("route_saved", properties: ["point_count": pointCount])
    }

    // MARK: - Feature Adoption

    static func trackTabViewed(tabName: String) {
        shared.track("tab_viewed", properties: ["tab_name": tabName])
    }

    static func trackGarminSyncCompleted(importedCount: Int, skippedCount: Int) {
        shared.track("garmin_sync_completed", properties: [
            "imported_count": importedCount,
            "skipped_count": skippedCount
        ])
    }

    static func trackGarminConnectTapped() {
        shared.track("garmin_connect_tapped", properties: [:])
    }

    static func trackHealthKitSyncCompleted(importedCount: Int) {
        shared.track("healthkit_sync_completed", properties: [
            "imported_count": importedCount
        ])
    }

    static func trackHealthKitDisclosureViewed(state: String) {
        shared.track("healthkit_disclosure_viewed", properties: [
            "connection_state": state
        ])
    }

    static func trackHealthKitConnectTapped() {
        shared.track("healthkit_connect_tapped", properties: [:])
    }

    // MARK: - User Identity

    static func identifyUser(userId: String) {
        shared.identify(userId: userId, traits: [:])
    }

    static func resetUser() {
        shared.reset()
    }

    // MARK: - Aha Moments

    static func trackAhaMomentFired(momentId: String, context: String? = nil) {
        var props: [String: Any] = [
            "moment_id": momentId,
            "variant": "C"
        ]
        if let context, !context.isEmpty {
            props["context"] = context
        }
        shared.track("aha_moment_fired", properties: props)
    }

    static func trackAhaMomentCTAClicked(momentId: String) {
        shared.track("aha_moment_cta_clicked", properties: [
            "moment_id": momentId,
            "variant": "C"
        ])
    }

    static func trackAhaMomentDismissed(momentId: String) {
        shared.track("aha_moment_dismissed", properties: [
            "moment_id": momentId,
            "variant": "C"
        ])
    }

    private static func completedRunKey(for run: RecordedRun) -> String {
        if let consolidatedID = run.consolidatedActivityID, !consolidatedID.isEmpty {
            return "\(completedRunKeyPrefix)\(run.source.rawValue).consolidated.\(consolidatedID)"
        }
        if let providerID = run.providerActivityID, !providerID.isEmpty {
            return "\(completedRunKeyPrefix)\(run.source.rawValue).provider.\(providerID)"
        }
        return "\(completedRunKeyPrefix)\(run.source.rawValue).local.\(run.id.uuidString)"
    }
}
