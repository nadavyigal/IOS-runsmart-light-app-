# FTUX Upgrade Plan — RunSmart iOS

> **Source of truth:** `docs/audits/first-time-user-journey-audit.md` (2026-07-13) + 12 evidence screenshots in `docs/audits/assets/ftux-2026-07-13/`.
> **For implementers:** work one story at a time. Each story ships on its own branch/PR with a focused XCTest (red→green), a Debug build, and device/simulator QA evidence, per `~/.claude/CLAUDE.md` and repo `CLAUDE.md`. Steps use checkbox syntax for tracking.

**Goal:** Close the two riskiest first-time-user moments (auth wall and post-onboarding plan-generation gap) and stop the trust-eroding inconsistencies, so activation tests measure the product instead of its rough edges.

**Approach:** Three prioritized work packets (WP-43 P0 "fix before more users", WP-44 P1 "next iteration", WP-45 instrumentation) plus an experiments track. Every story maps to a specific audit risk/defect and the screenshot that evidences it. No new dependencies. SwiftUI + existing services only.

**Tech stack:** SwiftUI, Supabase, PostHog (via xcconfig key), HealthKit, CoreLocation. iOS 26 target.

## Global constraints (from repo rules — every story inherits these)

- One story at a time: implement → lint/build → focused test → device/sim QA evidence → report → then next.
- Tests included in every story (repo requires a focused XCTest per story; red-state check before green).
- No new dependencies without asking; no secrets in code; no unrelated file changes (scope gate at >3 unexpected files).
- Validate with an Xcode Debug build + simulator/device smoke before "done".
- Prefer `.alert` over `confirmationDialog` for destructive confirmations (iOS 26 rendering lesson).
- Update `tasks/progress.md` after every commit; update `tasks/lessons.md` on any new recurring bug.

## How this maps to the audit

| Audit item | Where it's fixed |
|---|---|
| §4 Risk 1 — plan-generation gap | WP-43 S1 |
| §4 Risk 2 — auth wall before value | WP-44 S1 + Experiment E2 |
| §4 Risk 3 / B1 — raw SIWA error | WP-43 S2 |
| §4 Risk 4 / B8,B10,B11 — numeric contradictions | WP-44 S3 |
| §4 Risk 5 / B3,B4 — breakdown "21000 × 400 m" | WP-43 S4 |
| §4 Risk 6 / B2 — six-vs-eight weeks + overpromise | WP-43 S3 |
| §4 Risk 7 / B5,B6 — silent HealthKit connect / Generate Report | WP-44 S2 |
| §4 Risk 8 / B7 — Report blank load | WP-44 S2 |
| §4 Risk 9 / B15 — no-selection onboarding + hidden default goal | WP-43 S6 |
| §4 Risk 10 / B12 — dev-vocab badges ("Heuristic"/"Source: Real") | WP-43 S5 |
| §10 B13 — duplicate "Review manually" | WP-44 S2 |
| §10 B14 — Terms ejects to Safari | WP-44 S6 |
| §10 B16 — HRV up rendered red | WP-44 S3 |
| §11 — instrumentation gaps | WP-45 |
| §13 — experiments | Experiments track |

## Sequencing

```
WP-45 (analytics) ──► ships first or parallel (enables measurement of everything below)
WP-43 (P0) S1..S6  ──► fix before acquiring more users
WP-44 (P1) S1..S6  ──► next iteration
Experiments E1..E3 ──► after WP-43 lands + WP-45 events verified live
```

Do WP-45 first (or in parallel) so the P0 fixes are measurable. WP-43 stories are independent and can each ship alone; recommended order S2 → S4 → S3 → S5 → S6 → S1 (cheapest/highest-confidence copy+bug fixes first, the plan-gap state last because it's the largest).

---

## WP-43 — FTUX activation & trust hardening (P0: fix before acquiring more users)

### Task S1: Design the plan-generation waiting/failure state

**Audit ref:** §4 Risk 1 (Critical). Evidence: `10-demo-today.png` (blank Today mid-load), `docs/audits/...` narrative "Minute 4–5 — The gap".

**Files:**
- Modify: `IOS RunSmart app/App/RunSmartLiteAppShell.swift:429-450` (`presentFirstRunActivationIfNeeded`, `firstRunnableWorkoutAfterPlanGeneration` 45s poll)
- Modify: `IOS RunSmart app/Features/Today/TodayTabView.swift` (add generating/empty state)
- Modify: `IOS RunSmart app/Features/Plan/PlanTabView.swift` (add generating/empty state)
- Modify: `IOS RunSmart app/App/RunSmartLiteAppShell.swift:509-528` (`RunSmartPlanNotice` `.failed` copy)
- Test: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

**Change:**
- [ ] Add an explicit `planGenerationState` (`.idle/.generating/.ready/.failed`) surfaced on Today and Plan, driven by the existing `runSmartPlanGenerationStatusDidChange` notification.
- [ ] Render a dedicated "Coach is building your plan" card (progress + expected wait, ~30–45s) on both Today and Plan while `.generating`, instead of the current blank body / empty calendar.
- [ ] On `.failed`, show an **inline "Try again" button on Today/Plan itself** (calls the same regenerate path), not a transient banner that points to Profile-buried "Training Data".
- [ ] Rewrite the `.failed` `RunSmartPlanNotice.message` to not reference a screen a new user has never seen.

**Acceptance:** After onboarding, a user always sees either the generating card, the plan, or an inline retry — never a blank/empty screen with a vanished banner. Retry works without leaving Today/Plan.

**Test required:** `testPlanGenerationStateTransitionsGeneratingToReady` and `testPlanGenerationFailureExposesInlineRetry` (drive the notification, assert state). Red-state check: remove the `.generating` branch → generating test fails.

**Analytics:** emits `plan_generation_started/succeeded/failed/timed_out` (see WP-45).

**Effort:** L. **Depends on:** WP-45 S1 (for the events) recommended but not blocking.

---

### Task S2: Humanize Sign in with Apple failure copy

**Audit ref:** §4 Risk 3, §10 B1. Evidence: real-mode narrative "com.apple.AuthenticationServices.AuthorizationError error 1000".

**Files:**
- Modify: `IOS RunSmart app/Features/Auth/SignInView.swift:104-126` (`errorMessage = error.localizedDescription`)
- Test: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

**Change:**
- [ ] Map `ASAuthorizationError` cases to human copy. `.canceled` → no error shown (user backed out). Everything else → "Apple sign-in didn't finish. Nothing was created — tap to try again." Never render the raw `NSError.localizedDescription`.
- [ ] Log the raw domain/code to analytics (`sign_in_failed`, WP-45), not to the UI.

**Acceptance:** No `com.apple.*` / `error 1000` string ever reaches the screen; cancel is silent; other failures show retry-oriented copy.

**Test required:** `testSignInErrorMappingHidesRawNSError` (feed an `ASAuthorizationError(.failed)` and `.canceled`, assert mapped/empty copy). Red-state: revert to `localizedDescription` → test fails.

**Analytics:** `sign_in_failed(errorCode)`.

**Effort:** S. **Depends on:** none.

---

### Task S3: Fix the aha-timeline contradiction and remove the overpromise

**Audit ref:** §4 Risk 6, §10 B2. Evidence: aha screen "Six weeks from now… / 5K ready in 8 weeks / we know you'll finish".

**Files:**
- Modify: `IOS RunSmart app/Features/AhaMoments/GoalTimelineMomentView.swift:15` (hardcoded "Six weeks") and `:105` ("in \(timeline.weeks) weeks")
- Modify: subtitle copy "we know you'll finish"
- Test: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

**Change:**
- [ ] Derive the headline duration from the same `timeline.weeks` value used for the milestone (single source), so headline and milestone can never disagree across goals.
- [ ] Replace the guarantee ("we know you'll finish") with credible framing, e.g. "Runners who stick with this plan usually get there."

**Acceptance:** For every goal/experience combo, the headline duration equals the milestone duration; no guarantee language remains.

**Test required:** `testGoalTimelineHeadlineMatchesMilestoneWeeks` across goals (First 5K, 10K, Half, Marathon). Red-state: reintroduce the hardcoded "Six weeks" → test fails for the 8-week persona.

**Effort:** S. **Depends on:** none.

---

### Task S4: Fix the Workout Breakdown fabrication ("21000 × 400 m")

**Audit ref:** §4 Risk 5, §10 B3/B4. Evidence: workout detail sheet "Repeats: 21000 × 400 m · Target 4:45/km" vs card "8 × 400m · 5'15\"/km".

**Files:**
- Modify: `IOS RunSmart app/Services/StructuredWorkoutFactory.swift:124-137` (`intervalSteps`, `reps = max(4, Int((km/0.4).rounded()))`) and `:183-186` (`distanceKm(from:)` digit-strip parse)
- Test: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

**Change:**
- [ ] Parse structured rep count / rep distance from the workout model (e.g. "8 x 400m" → reps=8, repMeters=400), not from a digit-stripped total-distance string. The current parser turns "8 x 400m" into "8400" → 8400 km → 21000 reps.
- [ ] Where target paces are estimated (the hardcoded 4:45/5:15 defaults), label them "est." per value, and prefer the workout card's own pace chip when present so the sheet and card agree.

**Acceptance:** An "8 x 400m" interval renders 8 reps; no breakdown ever shows an implausible rep count; breakdown pace matches the card or is labeled estimated.

**Test required:** `testIntervalBreakdownParsesRepsFromStructure` ("8 x 400m" → 8 reps × 400 m) + `testBreakdownNeverExceedsPlausibleReps`. Red-state: restore digit-strip parse → first test asserts 21000, fails.

**Effort:** M. **Depends on:** none. **Note:** same fabrication class as the WP-37 S5 splits lesson — derive from structured data, don't synthesize.

---

### Task S5: Remove developer-vocabulary badges from trust surfaces

**Audit ref:** §4 Risk 10, §10 B12. Evidence: `11-demo-today2.png` ("Imported activity · Heuristic"), `31-report2.png` ("SOURCE: Real"), post-run "AI - GPS - RunSmart".

**Files:**
- Modify: `IOS RunSmart app/Features/Run/PostRunLearningCard.swift:28-32` (`PostRunLearningSource` raw values "Heuristic"/"Fallback"/"AI"/"Report" rendered as badges)
- Modify: `IOS RunSmart app/Features/Activity/ActivityTabView.swift:56` (hardcoded `"Real"` pill)
- Modify: `IOS RunSmart app/Features/Today/TodayTabView.swift:413` ("Coach safety · Heuristic")
- Test: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

**Change:**
- [ ] Map source tiers to user language for display (e.g. `.heuristic` → "Based on your plan", `.fallback` → "Quick take", `.ai` → "Coach analysis") via a display-only computed property; keep the raw enum for internal logic/analytics.
- [ ] Delete the "Source: Real" pill entirely (it invites "as opposed to fake?").

**Acceptance:** No "Heuristic", "Fallback", or "Source: Real" string appears in any user-facing surface; internal enum + analytics unchanged.

**Test required:** `testPostRunSourceDisplayLabelsAreUserFacing` (each case maps to a non-jargon string). Red-state: return `rawValue` → test fails.

**Effort:** S. **Depends on:** none.

---

### Task S6: Require a Goal/Experience selection and fix the hidden default

**Audit ref:** §4 Risk 9, §10 B15. Evidence: `OnboardingProfile.empty` sets `goal: "10K improvement"` (not one of the 5 visible options); page-style TabView allows undiscoverable swipe/skip.

**Files:**
- Modify: `IOS RunSmart app/Models/RunSmartModels.swift:1129-1143` (`OnboardingProfile.empty` default goal/experience)
- Modify: `IOS RunSmart app/Features/Onboarding/OnboardingView.swift:81-93` (goalStep/experienceStep Continue buttons; `.tabViewStyle(.page)` swipe)
- Test: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

**Change:**
- [ ] Disable the Goal and Experience "Continue" button until a visible option is selected (or preselect a visible option and add "you can change this later").
- [ ] Change `OnboardingProfile.empty.goal` to `""` (or the first visible option) so nothing is silently passed through as "10K improvement".
- [ ] Disable horizontal swipe navigation on the onboarding TabView (or add an explicit Back control) so users can't skip or land on the wrong step invisibly.

**Acceptance:** A user cannot leave Goal/Experience without an explicit visible choice; the plan is never built from an unseen default; forward-swipe skipping is not possible.

**Test required:** `testOnboardingRequiresVisibleGoalSelection` (empty goal → Continue disabled) + `testOnboardingDefaultGoalIsNotHiddenValue`. Red-state: restore "10K improvement" default → second test fails.

**Effort:** M. **Depends on:** none.

---

## WP-44 — FTUX polish (P1: next iteration)

### Task S1: Value preview before/around the auth wall

**Audit ref:** §4 Risk 2, §9. Evidence: `02-first-screen.png` (SIWA-only first screen). Pairs with Experiment E2.

**Files:**
- Modify: `IOS RunSmart app/Features/Auth/SignInView.swift`
- Modify: `IOS RunSmart app/App/RunSmartLiteAppShell.swift` (gate ordering)

**Change:**
- [ ] Add a 2–3 pane value preview (sample Today card + a "Why this workout?" example, or a short looping run-flow clip) reachable before sign-in, OR reorder so Goal + Experience are asked before SIWA ("so your coach is ready the moment you sign in").
- [ ] Replace the first-screen "Run guidance and cue previews" bullet and the HealthKit-compliance bullet with the daily-answer promise ("Know exactly what to run today").

**Acceptance:** A skeptical user can see a concrete example of the coaching before committing to Apple sign-in.

**Test required:** navigation/gate test asserting the preview is reachable pre-auth (or that goal/experience precede auth in the reordered flow).

**Effort:** L. **Depends on:** decide direction via Experiment E2 first (see Experiments track).

---

### Task S2: Loading & failure states for async CTAs

**Audit ref:** §4 Risk 7/8, §10 B5/B6/B7/B13. Evidence: `06-health-after-tap.png` (silent connect), `33-after-generate.png` (silent Generate Report + duplicate "Review manually"), Report blank-load narrative.

**Files:**
- Modify: `IOS RunSmart app/Features/Onboarding/OnboardingView.swift:220-231` (`connectHealthKit` — add failure branch)
- Modify: `IOS RunSmart app/Features/Activity/ActivityTabView.swift` (Report skeleton + Generate Report states; remove duplicate "Review manually")
- Test: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

**Change:**
- [ ] `connectHealthKit()` gets a failure branch: on non-connected result, surface "Couldn't connect Apple Health — you can try again from Profile" instead of silently resetting the button.
- [ ] Report tab renders skeleton rows / spinner while loading instead of ~10s of blank.
- [ ] "Generate Report" gets working/success/failure states (or auto-generate on save and demote manual regeneration to a power-user affordance).
- [ ] Remove the duplicate disabled "Review manually" button (keep one control).

**Acceptance:** Every async CTA shows progress and a failure message; Report never shows a blank screen; no duplicate controls.

**Test required:** `testHealthKitConnectSurfacesFailureState` (connect returns non-connected → error copy set). Red-state: remove failure branch → test fails.

**Effort:** M.

---

### Task S3: Numeric & semantic consistency pass

**Audit ref:** §4 Risk 4, §10 B8/B10/B11/B16. Evidence: `11-demo-today2.png` (Week 3 vs Week 4; HRV up in red), Profile "11-week" vs Today "11 day", Plan 86.20 km vs summed ~36 km, live pace 5:13 vs summary 7:24.

**Files:**
- Modify: single-source accessors for week number, streak, weekly distance across `Features/Today/*`, `Features/Plan/PlanTabView.swift`, `Features/Profile/ProfileTabView.swift`
- Modify: intensity taxonomy — reconcile card chips ("Easy"/pace) with breakdown ("Zone 3-4"/"Build") in `StructuredWorkoutFactory.swift` / `WorkoutCard.swift`
- Modify: pace labeling — distinguish "avg moving pace" vs live pace so 5:13 vs 7:24 is explained
- Modify: wearable trend coloring so a positive trend (HRV up) is not red (`Features/Today` wearable trends)

**Change:**
- [ ] One accessor per concept (week #, streak + unit, weekly distance) consumed by every surface; add a QA rule that any number rendered twice comes from one source.
- [ ] Collapse the intensity taxonomy to one vocabulary per workout (either effort words or zones, consistently on card + sheet).
- [ ] Color wearable trends by direction+goodness, not a fixed palette.

**Acceptance:** Week number, streak unit, weekly distance, and workout intensity are identical wherever they appear; positive trends never render in the alarm color.

**Test required:** `testWeeklyDistanceMatchesSummedWorkouts`, `testStreakUnitConsistentAcrossSurfaces`. Red-state: point one surface at a second source → test fails.

**Effort:** L. **Note:** several observed instances are demo-data artifacts, but the surfaces render from independent sources with no consistency layer, so the class ships to production — the fix is the single-source layer, verified against real data.

---

### Task S4: Onboarding polish

**Audit ref:** §7, §9, §10 B15. Evidence: "Privacy" step / "Confirm Privacy" CTA; no back affordance.

**Files:**
- Modify: `IOS RunSmart app/Features/Onboarding/OnboardingView.swift:130-146` (privacyStep title/CTA), progress/back affordance
- Modify: move Garmin `DevicePreviewRow` + `RookieChallengeCallout` out of onboarding to post-activation

**Change:**
- [ ] Rename the "Privacy" step to "Coaching" (it's tone + reminders); change "Confirm Privacy" → "Continue".
- [ ] Add a visible Back control; disable page-swipe skipping (shared with WP-43 S6).
- [ ] Defer Garmin mention and the 21-Day Rookie Challenge callout until after first activation.

**Acceptance:** Step titles match their content; back navigation exists; onboarding no longer front-loads Garmin/challenge marketing.

**Test required:** snapshot/label test asserting step title/CTA copy.

**Effort:** M.

---

### Task S5: Rest-day / no-workout Today state

**Audit ref:** §7 (core promise must never render empty). Evidence: Today greeting + blank body during load (`10-demo-today.png`).

**Files:**
- Modify: `IOS RunSmart app/Features/Today/TodayTabView.swift` / `WorkoutCard.swift`

**Change:**
- [ ] When today has no scheduled workout, render an explicit "Rest day — here's how to recover" answer (mobility/easy-walk guidance) rather than nothing, so "what should I do today?" always has an answer.

**Acceptance:** Today always answers the daily question, including rest days and no-plan states.

**Test required:** `testTodayRendersRestDayGuidanceWhenNoWorkout`.

**Effort:** M.

---

### Task S6: In-app Safari for Terms/Privacy

**Audit ref:** §10 B14. Evidence: Terms link ejected to external Safari at `runsmart-ai.com`.

**Files:**
- Modify: `IOS RunSmart app/Features/Auth/SignInView.swift` (Terms/Privacy links)

**Change:**
- [ ] Present Terms/Privacy via `SFSafariViewController` (in-app) so the user isn't thrown out of the app pre-auth.

**Acceptance:** Tapping Terms/Privacy keeps the user in the app.

**Test required:** interaction test asserting in-app presentation (or manual QA note if not unit-testable).

**Effort:** S.

---

## WP-45 — Instrumentation (do first / in parallel)

**Audit ref:** §11. Existing events inspected in `IOS RunSmart app/Services/Analytics/AnalyticsEvents.swift` (31 events — good base). These are the missing ones.

**Files:**
- Modify: `IOS RunSmart app/Services/Analytics/AnalyticsEvents.swift` (add event funcs)
- Modify: call sites listed per event
- Test: `IOS RunSmart appTests/RunSmartReadinessTests.swift` (assert payload keys, per repo's existing analytics test pattern)

**Add these events:**
- [ ] `sign_in_failed(errorDomain, errorCode)` — call site `SignInView.swift` (WP-43 S2)
- [ ] `onboarding_step_abandoned(lastStep, dwellSeconds)` — `OnboardingView`
- [ ] `permission_requested/granted/denied(kind)` for location + notifications — `RunRecorder` / `PushService` (currently only HealthKit *tap* is tracked, no outcomes)
- [ ] `healthkit_connect_failed(reason)` — `OnboardingView.connectHealthKit` (WP-44 S2)
- [ ] `plan_generation_started/succeeded/failed/timed_out(durationMs)` — `RunSmartLiteAppShell` / `SupabaseRunSmartServices.saveTrainingGoal` (WP-43 S1)
- [ ] `first_workout_viewed` — `TodayTabView` (complements existing `first_run_cta_viewed`)
- [ ] `run_report_generate_tapped/succeeded/failed` — `ActivityTabView` (WP-44 S2)
- [ ] `insight_expanded(surface)` for why-this-workout / week-in-review / coach-learned — measures whether the differentiator is consumed
- [ ] `share_progress_tapped/completed` — sharing surfaces
- [ ] Add person property `onboarding_completed_at` for D1/D7 cohort segmentation in PostHog

**Acceptance:** The full funnel from install → sign-in (incl. failures) → each onboarding step → permission outcomes → plan generation → first workout → run → report → insight consumption is observable in PostHog.

**Test required:** payload-key assertions per new event (repo pattern). 

**Effort:** M–L.

---

## Experiments track (after WP-43 lands + WP-45 verified live)

Full hypotheses/metrics/guardrails are in audit §13. Summary:

- [ ] **E1 — Coach preview to shorten time-to-value (required focus).** Render a deterministic client-side week-1 preview while real generation runs. Primary: % viewing first workout within 10 min of `onboarding_completed`. Guardrail: week-1 `flex_week` usage, D7 retention. Depends on WP-43 S1.
- [ ] **E2 — Move auth behind Goal+Experience.** Reorder onboarding; primary: install→`sign_in_completed`. Guardrail: onboarding completion, abandoned-after-answering. Feeds WP-44 S1 direction.
- [ ] **E3 — "What changed" adaptation receipts.** Next-morning one-line plan-diff on Today + return notification. Primary: D1 return of users with ≥1 completed run. Guardrail: notification opt-out, `insight_expanded`.

---

## Appendix A — Figma / visual-board frame structure

For the companion visual board (delivered as a hosted artifact; port to Figma as needed). One frame per journey stage; each frame pairs the screenshot with its findings and the WP-story that fixes it. Suggested Figma page = "FTUX Journey 2026-07-13", frames left→right in journey order:

| Frame | Screenshot | Primary finding(s) | Fixed by |
|---|---|---|---|
| 1. First screen | `02-first-screen.png` | Auth wall before value; compliance bullet; "cue previews" jargon | WP-44 S1 |
| 2. Apple Health step | `06-health-after-tap.png` | Silent connect failure | WP-44 S2 |
| 3. Today (loading) | `10-demo-today.png` | Blank body during plan gap | WP-43 S1 / WP-44 S5 |
| 4. Today (populated) | `11-demo-today2.png` | "Heuristic" badge; Week 3/4; HRV-up-in-red | WP-43 S5 / WP-44 S3 |
| 5. Run — pre | `20-run-tab.png` | Free-Run default even when a workout is planned | WP-44 S3 (planned-run entry) |
| 6. Run — permission | `21-after-start.png` | ✅ Strength: just-in-time permission + auto-start | keep / promote |
| 7. Run — recording | `22-run-recording.png` | ✅ Strength: honest GPS states, big targets | keep / promote |
| 8. Run — paused | `23-paused.png` | ✅ Strength: correct pause semantics | keep |
| 9. Report list | `31-report2.png` | 10s blank load; "Source: Real"; per-row delete | WP-43 S5 / WP-44 S2 |
| 10. Run report | `32-run-report.png` | ✅ Strength: RPE persisted, honest "—" HR | keep |
| 11. Coach Learned | `33-after-generate.png` | Silent Generate Report; duplicate "Review manually" | WP-44 S2 |
| 12. Profile | `40-profile.png` | "11-week" vs "11 day" streak; "10K focused/Level 14" vs beginner | WP-44 S3 |

Legend for the board: 🔴 Critical/High (WP-43) · 🟡 Medium (WP-44) · 🟢 Strength (keep & promote).

---

## Rollout & validation

- Ship WP-45 first (or parallel) so P0 fixes are measurable.
- Each story: branch → focused XCTest (red→green) → Debug build → iPhone 17 + iPhone SE sim QA (both, per SE-clipping lesson) → evidence under `docs/qa/reports/` → PR → update `tasks/progress.md`.
- After WP-43 lands and WP-45 events are confirmed live, start E1 (required time-to-value experiment).
- Definition of done for the epic: no audit §4 risk 1–6 reproducible; audit §10 B1–B7, B12–B13 closed; full funnel visible in PostHog.
