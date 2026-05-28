# Analytics Instrumentation Spec — RunSmart iOS

> ⚠️ DO NOT add this code in a distribution session.
> This spec is for a separate product-code session. Read-only work produced this file.
> Instrument these three events before submitting to App Store to ensure activation funnel baseline exists.

PostHog SDK is wired (`RunSmartAnalytics.swift`). The pattern already used is:
```swift
PostHogSDK.shared.capture("event_name", properties: [...])
```
All three events below should follow this same pattern.

---

## Event: onboarding_completed

**File:** `IOS RunSmart app/Services/Supabase/SupabaseSession.swift`
**Line:** ~140 (inside `completeOnboarding(_:)`, after `hasCompletedOnboarding = true`)
**Where:** In the success branch of the upsert call, immediately after `hasCompletedOnboarding = true` is set and before the function returns.

**Code to add:**
```swift
RunSmartAnalytics.track("onboarding_completed", properties: [
    "goal": onboarding.supabaseGoal,
    "experience_level": onboarding.supabaseExperience,
    "weekly_run_days": onboarding.weeklyRunDays,
    "coaching_tone": onboarding.supabaseCoachingStyle,
    "notifications_enabled": onboarding.notificationsEnabled
])
```

**Notes:**
- `RunSmartAnalytics.track` does not exist yet — add a `track` static method or call `PostHogSDK.shared.capture(...)` directly, consistent with existing flex_week events.
- Only fires once per user (upsert is idempotent; `onboardingComplete = true` confirms first completion).

---

## Event: plan_generated

**File:** `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
**Line:** ~271 (inside `regenerateTrainingPlan(authUserID:request:)`, inside `if persisted { ... }`)
**Where:** Immediately after `let persisted = await planRepo.persistGeneratedPlan(...)` returns `true` and before the `NotificationCenter.default.post(.runSmartPlanDidChange)` call.

**Code to add:**
```swift
RunSmartAnalytics.track("plan_generated", properties: [
    "goal": request.supabaseGoal,
    "experience_level": request.supabaseExperience,
    "weekly_run_days": request.weeklyRunDays,
    "target_distance": generated.targetDistance as Any,
    "total_weeks": generated.totalWeeks
])
```

**Notes:**
- Covers both new plan creation and regeneration. Both go through `regenerateTrainingPlan` → `persistGeneratedPlan`.
- Fires each time a plan is created/regenerated. For activation funnel, the first fire is what matters.

---

## Event: run_logged

**File:** `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
**Line:** ~1420 (inside `processCompletedActivity(_:)`, just before the `return PostActivityOutcome(...)` statement)
**Where:** All async work is complete — run upserted, report generated, matching workout marked complete, notifications fired.

**Code to add:**
```swift
RunSmartAnalytics.track("run_logged", properties: [
    "source": canonical.source.rawValue,
    "distance_km": Double(round(canonical.distanceMeters / 10)) / 100,
    "duration_minutes": Int(canonical.movingTimeSeconds / 60),
    "has_route": !canonical.routePoints.isEmpty,
    "matched_planned_workout": completed != nil
])
```

**Notes:**
- `source.rawValue` will be "garmin", "healthKit", or "runSmart".
- Fires for GPS runs, Garmin imports, and HealthKit imports — correct for activation funnel.

---

## Adding the `track` Helper (Optional)

Option 1: Add individual typed methods (existing pattern).
Option 2: Add a generic `track` method (faster for these three events):
```swift
static func track(_ event: String, properties: [String: Any] = [:]) {
    PostHogSDK.shared.capture(event, properties: properties.isEmpty ? nil : properties)
}
```

---

## Instrumentation Priority

All three events should fire before the first real users see the app. The activation funnel
(`onboarding_completed` → `plan_generated` → `run_logged`) is the only way to measure whether
the app is working. Without these, the first 30 days of installs produce no actionable data.

Experiment reference: rs-analytics-001
