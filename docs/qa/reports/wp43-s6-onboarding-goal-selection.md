# WP-43 S6 — Require a Goal selection and fix the hidden default

**Date:** 2026-07-14
**Branch:** `claude/bold-noyce-678ace`
**Audit ref:** §4 Risk 9, §10 B15 — `OnboardingProfile.empty` set `goal: "10K improvement"`, which is **not** one of the five visible options ("First 5K", "10K PR", "Half Marathon", "Marathon", "Just Run More"); page-style TabView allowed undiscoverable swipe/skip.

## Change

1. **`RunSmartModels.swift`** — `OnboardingProfile.empty.goal` changed from `"10K improvement"` to `""`, so a plan is never silently built around a value the user never saw.
2. **`OnboardingView.swift`** —
   - Promoted the option lists to `static let goalOptions` / `experienceOptions` and added pure predicates `canAdvanceFromGoal(_:)` / `canAdvanceFromExperience(_:)` (`options.contains(profile.X)`).
   - Goal and Experience "Continue" now pass `isEnabled:` from those predicates; `OnboardingPrimaryButton` gained an `isEnabled` param (default `true`, so other call sites are untouched) applying `.disabled(!isEnabled)` + 0.45 opacity.
   - Replaced the page-style `TabView` with a `switch` that renders only the active step, so swiping past a required step is structurally impossible and steps advance only via explicit Continue.

     **Revised after CodeRabbit review (PR #88).** The first implementation kept the paged `TabView` and blocked swipes with `.gesture(DragGesture())`. CodeRabbit flagged (Major) that this intercepts *all* drags in the subtree, which would also swallow the vertical scrolling inside `OnboardingStepShell`'s `ScrollView` — on a short screen or at large Dynamic Type that can strand the Continue button off-screen. This matched the exact risk this report already carried as its top open risk, so it was accepted and fixed structurally. Their alternative suggestion, `.scrollDisabled(true)`, was **not** used: it propagates through the environment and would risk disabling the child ScrollViews too.

**Scope note:** `experience` keeps its `"Building base"` default because that **is** a visible option — the plan explicitly allows the "preselect a visible option" path. Only `goal` had a hidden default. The predicate is applied to both steps regardless.

## Validation

**Focused XCTest:** `testOnboardingRequiresVisibleGoalSelection`, `testOnboardingDefaultGoalIsNotHiddenValue`.
- **Red confirmed (assertion-level, exactly as the plan specifies):** restored `goal: "10K improvement"` → `** TEST FAILED **` on the default test: *`XCTAssertNotEqual failed: ("10K improvement") is equal to ("10K improvement") - the default goal must not be a hidden value never shown to the user`* and *`the default goal must be empty (forcing a choice) or a visible option; got '10K improvement'`*. `testOnboardingRequiresVisibleGoalSelection` passed in that state (the hidden value is correctly rejected by the predicate). Restored the fix.
- **Green:** both pass. The selection test asserts empty → cannot advance, `"10K improvement"` (hidden) → cannot advance, `"First 5K"` (visible) → can advance.

**Full regression:** `RunSmartReadinessTests` + `StriverPersonaGateTests` — **174 tests, 0 failures**. Notably `StriverPersonaGateTests` and several reminder/plan tests build on `OnboardingProfile.empty`; the default change caused no regression (they override goal or don't read it).

**Debug build:** app target compiled clean as part of the test build.

**Simulator QA (iPhone 17, demo + `-RUNSMART_RECORD_ONBOARDING -RUNSMART_ONBOARDING_STEP 0`):** `assets-2026-07-14-wp43-s6/onboarding-goal-step.png` — the Goal step renders correctly, the five visible options are shown (confirming "10K improvement" was never among them), and Continue is fully enabled/bright with a valid visible selection ("First 5K"), i.e. the positive half of the predicate.

**QA limitation:** the debug onboarding-replay flag seeds `RunSmartRecordingMode.onboardingProfile` with `goal: "First 5K"` pre-filled, so the *empty-goal disabled* state and the swipe-block can't be reached through it without adding QA-only code (out of scope). Those behaviors are covered by the red→green predicate test (empty/hidden/visible) and, for the swipe, by code review of the added `.gesture(DragGesture())`. Interactive tap/swipe QA was not scriptable this session (`simctl` has no tap; `idb`/`cliclick` absent; computer-use Simulator control declined).

## Risks

Low, after the CodeRabbit-driven revision. Replacing the paged `TabView` with a `switch` removes the gesture-interference class of bug entirely: each step keeps its own native `ScrollView`, so vertical scrolling is untouched and swipe-skipping is structurally impossible rather than suppressed. Post-fix QA: Goal step renders with Continue visible and reachable on **iPhone 17** (`onboarding-goal-step.png`) and **iPhone SE** (`onboarding-goal-step-se.png`), and the full suite stays green (178 tests, 0 failures).

Residual: the *empty-goal disabled* Continue still hasn't been seen on-device (the debug replay flag prefills the goal), and the step transition animation changed from a horizontal page slide to a crossfade. A founder smoke of the real onboarding flow is still worth doing before release.
