import Foundation

extension Analytics {
    private static let completedRunFlagKey = "analytics.hasCompletedRun"
    private static let completedRunKeyPrefix = "analytics.completedRun."

    // MARK: - Activation Funnel

    static func trackAppLaunched() {
        shared.track("app_launched", properties: ["session_id": UUID().uuidString])
    }

    // MARK: - Sign-in wall (activation cliff plan, S1)

    // Every event on this screen carries an explicit `screen` name: SwiftUI
    // `$screen` autocapture emits the same generic `UIHostingController<...>`
    // string for every screen, so it cannot distinguish the wall from anything
    // else. See `SignInWallTracker` for the viewed/tapped/abandoned semantics.

    static func trackSignInWallViewed() {
        shared.track("sign_in_wall_viewed", properties: [
            "screen": SignInWallTracker.screenName
        ])
    }

    static func trackSignInWallTapped() {
        // A wall tap is the explicit boundary for a new onboarding lifecycle.
        // Do not use resetUser() for this: authentication itself may reset the
        // anonymous PostHog identity before the same onboarding view remounts.
        didTrackOnboardingStart = false
        shared.track("sign_in_wall_tapped", properties: [
            "screen": SignInWallTracker.screenName
        ])
    }

    static func trackSignInWallAbandoned(dwellSeconds: Int) {
        shared.track("sign_in_wall_abandoned", properties: [
            "screen": SignInWallTracker.screenName,
            "dwell_seconds": dwellSeconds
        ])
    }

    static func trackSignInCompleted(method: String = "apple") {
        shared.track("sign_in_completed", properties: [
            "method": method,
            "screen": SignInWallTracker.screenName
        ])
    }

    // `error_domain`/`error_code` are the whole point of this event: the open P0
    // is whether the seven observed `ASAuthorizationError` code-1000 failures are
    // a production outage or environment noise. Carrying them on every wall
    // failure makes that answer itself for future users without a device repro.
    //
    // WP-52a adds the unwrapped `NSUnderlyingErrorKey`. WP-52 cleared all five
    // Apple configuration links with artifacts, so code 1000 (`.unknown`) is a
    // wrapper around the only remaining lead. `has_underlying_error` is emitted
    // unconditionally and deliberately: a genuinely bare 1000 escalates to the
    // guest path, while a 1000 we merely failed to unwrap is an instrumentation
    // bug, and those two were indistinguishable in the data before this.
    static func trackSignInFailed(error: Error) {
        let nsError = error as NSError
        var properties: [String: Any] = [
            "screen": SignInWallTracker.screenName,
            "error_domain": nsError.domain,
            "error_code": nsError.code
        ]

        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        properties["has_underlying_error"] = underlying != nil

        if let underlying {
            properties["underlying_error_domain"] = underlying.domain
            properties["underlying_error_code"] = underlying.code
            properties["underlying_error_description"] =
                redactedForAnalytics(underlying.localizedDescription)
        }

        shared.track("sign_in_failed", properties: properties)
    }

    /// Strips user identifiers from an error description before it leaves the device.
    ///
    /// `trackSignInFailed` fires from the sign-in wall's catch-all, so it also sees
    /// Supabase and URL-loading errors whose descriptions can embed the runner's
    /// email or a bearer token. Redacting in the emitter rather than at the call
    /// site means a future `catch` cannot reintroduce the leak by forgetting.
    /// Exposed for tests.
    static func redactedForAnalytics(_ text: String) -> String {
        let patterns = [
            // Email, before the generic run rule — the local part alone would
            // otherwise survive as a short token.
            ("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "[redacted-email]"),
            // JWT: three base64url segments. Matched ahead of the run rule so the
            // whole token collapses to one marker instead of three.
            ("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+", "[redacted-token]"),
            // Any remaining opaque run — session ids, raw tokens, UUIDs without
            // hyphens. Real words in Apple's error copy do not reach 20 characters.
            ("[A-Za-z0-9_-]{20,}", "[redacted]")
        ]

        var redacted = text
        for (pattern, replacement) in patterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression]
            )
        }
        // Descriptions are diagnostic, not payloads; cap so a pathological error
        // cannot bloat every event on the wall.
        return String(redacted.prefix(300))
    }

    /// Guards `onboarding_started` against SwiftUI re-appearance.
    ///
    /// The emitter is `OnboardingView.onAppear` gated on `step == 0`, and `onAppear`
    /// runs on every appearance: re-mount, tab switch, and return from background.
    /// Observed 2026-07-20 in a single founder session — `onboarding_started` at
    /// 09:22:11 and again at 09:23:59 (immediately after `aha_moment_cta_clicked`)
    /// against one `onboarding_completed`, which halves the apparent completion rate.
    ///
    /// Cleared when a distinct sign-in-wall attempt begins so a genuinely new
    /// onboarding lifecycle on the same install is still counted.
    private static var didTrackOnboardingStart = false

    static func trackOnboardingStarted() {
        guard !didTrackOnboardingStart else { return }
        didTrackOnboardingStart = true
        shared.track("onboarding_started", properties: [:])
    }

    /// Test seam for the once-per-user guard above.
    static func resetOnboardingStartGuardForTesting() {
        didTrackOnboardingStart = false
    }

    static func trackOnboardingStepCompleted(stepNumber: Int, stepName: String) {
        shared.track("onboarding_step_completed", properties: [
            "step_number": stepNumber,
            "step_name": stepName
        ])
    }

    static func trackOnboardingCompleted(goal: String, experience: String, daysPerWeek: Int, completedAt: Date = Date()) {
        shared.track("onboarding_completed", properties: [
            "goal": goal,
            "experience": experience,
            "days_per_week": daysPerWeek,
            // WP-45: person property for D1/D7 cohort segmentation in PostHog.
            "$set": ["onboarding_completed_at": ISO8601DateFormatter().string(from: completedAt)]
        ])
    }

    // WP-45: the funnel had no signal for users who left mid-onboarding — only
    // completed steps were tracked, so an abandon at step 3 was invisible.
    static func trackOnboardingStepAbandoned(lastStep: String, dwellSeconds: Int) {
        shared.track("onboarding_step_abandoned", properties: [
            "last_step": lastStep,
            "dwell_seconds": dwellSeconds
        ])
    }

    // MARK: - Permission outcomes (WP-45)

    // Only the HealthKit *tap* was tracked before; location and notification
    // outcomes were invisible, so a user who denied GPS at first run looked
    // identical to one who never tried.
    static func trackPermissionRequested(kind: String) {
        shared.track("permission_requested", properties: ["kind": kind])
    }

    static func trackPermissionGranted(kind: String) {
        shared.track("permission_granted", properties: ["kind": kind])
    }

    static func trackPermissionDenied(kind: String) {
        shared.track("permission_denied", properties: ["kind": kind])
    }

    static func trackHealthKitConnectFailed(reason: String) {
        shared.track("healthkit_connect_failed", properties: ["reason": reason])
    }

    static func trackPlanGenerated(planType: String, durationWeeks: Int) {
        shared.track("plan_generated", properties: [
            "plan_type": planType,
            "duration_weeks": durationWeeks
        ])
    }

    // MARK: - Plan generation lifecycle (WP-45)

    static func trackPlanGenerationStarted() {
        shared.track("plan_generation_started", properties: [:])
    }

    static func trackPlanGenerationSucceeded(durationMs: Int?) {
        shared.track("plan_generation_succeeded", properties: durationProperties(durationMs))
    }

    static func trackPlanGenerationFailed(durationMs: Int?) {
        shared.track("plan_generation_failed", properties: durationProperties(durationMs))
    }

    static func trackPlanGenerationTimedOut(durationMs: Int?) {
        shared.track("plan_generation_timed_out", properties: durationProperties(durationMs))
    }

    private static func durationProperties(_ durationMs: Int?) -> [String: Any] {
        guard let durationMs else { return [:] }
        return ["duration_ms": durationMs]
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
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                AppStoreReviewPrompt.requestAfterFirstRunIfNeeded()
            }
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

    static func trackFirstRunCTAViewed(workoutType: String, scheduledToday: Bool) {
        shared.track("first_run_cta_viewed", properties: [
            "workout_type": workoutType,
            "scheduled_today": scheduledToday
        ])
    }

    static func trackFirstRunCTATapped(action: String, workoutType: String) {
        shared.track("first_run_cta_tapped", properties: [
            "action": action,
            "workout_type": workoutType
        ])
    }

    static func trackFirstRunReminderScheduled(source: String, workoutType: String) {
        shared.track("first_run_reminder_scheduled", properties: [
            "source": source,
            "workout_type": workoutType
        ])
    }

    // WP-45: complements first_run_cta_viewed — fires the first time the user
    // actually sees their first planned workout rendered on Today.
    static func trackFirstWorkoutViewed(workoutType: String, defaults: UserDefaults = .standard) {
        let key = "analytics.hasViewedFirstWorkout"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        shared.track("first_workout_viewed", properties: ["workout_type": workoutType])
    }

    // MARK: - Run report generation (WP-45)

    static func trackRunReportGenerateTapped(source: String) {
        shared.track("run_report_generate_tapped", properties: ["source": source])
    }

    static func trackRunReportGenerateSucceeded(source: String) {
        shared.track("run_report_generate_succeeded", properties: ["source": source])
    }

    static func trackRunReportGenerateFailed(source: String) {
        shared.track("run_report_generate_failed", properties: ["source": source])
    }

    // MARK: - Insight consumption (WP-45)

    // Measures whether the differentiator (coaching insight) is actually
    // consumed, not just rendered.
    static func trackInsightExpanded(surface: String) {
        shared.track("insight_expanded", properties: ["surface": surface])
    }

    // MARK: - Progress sharing (WP-45)

    static func trackShareProgressTapped(payloadKind: String) {
        shared.track("share_progress_tapped", properties: ["payload_kind": payloadKind])
    }

    // share_progress_completed is deliberately NOT defined: ShareLink exposes no
    // completion callback, so a tracker here would be dead code that reads as a
    // wired event (the exact defect plan_generation_timed_out had). Add it only
    // with the UIActivityViewController migration that can observe completion.

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

    static func resetUser(bundle: Bundle = .main) {
        shared.reset()
        registerBuildIdentity(bundle: bundle)
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
