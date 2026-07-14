# WP-43 S1 — Plan-generation waiting/failure state

**Date:** 2026-07-14
**Branch:** `claude/bold-noyce-678ace`
**Audit ref:** §4 Risk 1 (Critical) — after onboarding, `saveTrainingGoal` kicks off async generation; Today/Plan rendered a blank body / empty calendar for ~30-45s and the only signal was a transient banner that vanished, whose failure copy pointed at a Profile-buried "Training Data" screen a new user has never seen.

## Change

**New — `Services/PlanGenerationStore.swift`**
- `PlanGenerationState` (`.idle/.generating/.ready/.failed`) with UI-contract properties `showsGeneratingCard` / `showsInlineRetry`.
- `PlanGenerationStore: ObservableObject` observes the existing `runSmartPlanGenerationStatusDidChange` notification and maps status → state (`.generating`→`.generating`, `.amended`→`.ready`, `.failed`→`.failed`). Uses `queue: nil` so delivery is synchronous on the posting thread — every post happens inside `MainActor.run` (SupabaseRunSmartServices), so updates stay on main and tests stay deterministic. `markGenerating()` lets an inline retry show the card immediately.
- Emits WP-45 analytics: `plan_generation_started` / `_succeeded` / `_failed` with `duration_ms`.

**New — `Features/Plan/PlanGenerationStatusCard.swift`**
- `.generating`: "Coach is building your plan" + spinner + "This usually takes 30 to 45 seconds".
- `.failed`: "We couldn't build your plan" / "Nothing was lost" + an inline **Try again** button (`planGenerationRetryButton`).

**Wiring**
- `RunSmartLiteAppShell`: `@StateObject planGeneration` + `.environmentObject(planGeneration)`.
- `TodayTabView` / `PlanTabView`: `@EnvironmentObject planGeneration`; render the card right after the header while `.generating`/`.failed`; `retryPlanGeneration()` calls `services.saveTrainingGoal(TrainingGoalRequest.onboardingDefault(from: session.onboardingProfile))` without leaving the screen.
- `TrainingGoalRequest.onboardingDefault(from:)` extracted from the shell's onboarding completion so both it and the retry build an identical request.
- `RunSmartPlanNotice.failed` copy rewritten: no longer says "Open Training Data to retry" → "Your details are saved. Tap Try again on Today or Plan to rebuild your plan."

## Validation

**Focused XCTest** (plan's two required tests + a copy guard):
- **Red confirmed, exactly per the plan's instruction** ("remove the `.generating` branch → generating test fails"): mapped `.generating` → `.idle`, re-ran → `** TEST FAILED **`: *`XCTAssertEqual failed: ("idle") is not equal to ("generating") - the generating notification must surface the waiting state`* and *`Today/Plan must show the generating card, never a blank body`*. Restored.
- **Green:** `testPlanGenerationStateTransitionsGeneratingToReady` (idle → generating → ready, card shows then hides), `testPlanGenerationFailureExposesInlineRetry` (failed → inline retry, and `markGenerating()` returns to the card without leaving the screen), `testPlanGenerationFailedNoticeDoesNotPointAtBuriedScreen` (notice must not contain "Training Data").

**Full regression:** `RunSmartReadinessTests` + `StriverPersonaGateTests` — **178 tests, 0 failures**.

**Debug build:** app target compiled clean (new files auto-included via the project's `PBXFileSystemSynchronizedRootGroup`).

**Simulator QA (iPhone 17, demo mode):** the main runtime risk was the new `@EnvironmentObject` — an un-injected environment object crashes the view at runtime. Both tabs render correctly:
- Today: `assets-2026-07-14-wp43-s1/today-tab.png`
- Plan: `assets-2026-07-14-wp43-s1/plan-tab.png`

State is `.idle` in demo (no generation runs), so no card shows — correct. The generating/failed card states can't be driven in the simulator without a live Supabase generation cycle; they're covered by the red→green state tests.

## Bonus fix — completes WP-43 S5's acceptance

The Plan-tab QA screenshot exposed **"Imported activity · Heuristic"** still rendering — the audit's actual §10 B12 evidence string. It comes from a *third* enum, `PlanExplanationSource.displayName` (TodayTabView:511), not the two sites S5's plan listed. Mapped it to user language (`.heuristic` → "Based on your plan", `.ai` → "Coach analysis", `.fallback` → "Quick take") and added `testPlanExplanationSourceDisplayNamesAreUserFacing`. Verified in the re-captured Plan screenshot: now reads **"Imported activity · Based on your plan"**. Raw enum untouched (a test asserts `explanation.source == .heuristic`).

## Risks / follow-ups

- The generating and failed card states have not been seen on a real device (they need a live generation cycle). A founder smoke — complete onboarding on device, watch Today during the ~30-45s gap, and force a failure — is worth doing before release.
- `plan_generation_timed_out` is defined in analytics but not yet emitted; the existing 45s poll in `firstRunnableWorkoutAfterPlanGeneration` is where it belongs. Left unwired rather than guessing at the semantics.
