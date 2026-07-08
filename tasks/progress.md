**WP-37 S7 — Persist RPE or stop pretending (P2), 2026-07-08:** Fixed the post-run "How did that feel?" selector pretending every run was pre-rated 6/10 while discarding the selected value. Root cause confirmed exactly as scoped: `PostRunSummaryView` initialized `rpe = 6`, `RPESelector` required a non-optional value, and no save path wrote that rating back to the recorded run. Fix: made the selector optional/unset by default (`Not rated`), added `RecordedRun.rpe`, persisted RPE through `RunSmartLocalStore.updateRunRPE`, wired the RunLogging service path for production/Supabase/demo services, and surfaces saved RPE on activity history rows plus run report detail. The post-run coach card now uses neutral "Not rated" copy until the runner makes an explicit selection. The demo service also surfaces locally saved simulator runs ahead of preview fixtures so compressed `-RUNSMART_DEMO_MODE` QA can verify persistence in Report without weakening production visibility rules. **Validation:** clean worktree `/tmp/rs-wp37-s7` (branched off fresh `origin/main` at `cfeb854`); focused XCTest `RunSmartReadinessTests/testLocalStorePersistsRunRPESelection` **PASSED**; red-state check confirmed the test **FAILS** when `saveRun(updated)` is removed from `RunSmartLocalStore.updateRunRPE`, then **PASSES** again after restoring the fix. Debug build on iPhone 17 sim **SUCCEEDED**. Device-QA on **both** iPhone 17 and iPhone SE simulators using `-RUNSMART_DEMO_MODE` and real `RunRecorder`/CoreLocation: saved a run, confirmed the summary starts `Not rated`, selected RPE 8 and saw `8/10`, relaunched into Report and confirmed the saved history row shows `RPE 8/10`. Evidence screenshots saved under `docs/qa/reports/assets-2026-07-08-wp37-s7/`.

**WP-37 S6 — Live map current position is not Finish (P2), 2026-07-08:** Fixed `RouteMapView` marking the live runner position as a red "Finish" flag mid-run. Root cause confirmed exactly as scoped: the shared map component always rendered `Marker("Finish", systemImage: "flag.fill", coordinate: last)` for the final route point, and `LiveRunView` used that same default behavior while recording. Fix: added an `isLive` flag to `RouteMapView` that defaults to `false`; live maps render the first point as Start and the latest point as an unlabeled current-position dot, while all existing post-run/route-library call sites keep Start/Finish markers unchanged. `LiveRunView` is the only caller passing `isLive: true`. **Validation:** clean worktree `/tmp/rs-wp37-s6` (branched off fresh `origin/main` at `825e8d9`); Debug build on iPhone 17 sim **SUCCEEDED** (known HealthKit `HKWorkout` initializer deprecation warning only). No unit test added because this is pure SwiftUI Map annotation presentation with no existing testable logic boundary; visual device-QA covered the acceptance. Device-QA on **both** iPhone 17 and iPhone SE simulators using `-RUNSMART_DEMO_MODE` and real `RunRecorder`/CoreLocation: started simulated GPS recording and confirmed the live map shows Start + an unlabeled current-position dot with no "Finish" marker; finished/saved on iPhone 17 and confirmed the completed route summary still shows Start + Finish flags. Evidence screenshots saved under `docs/qa/reports/assets-2026-07-08-wp37-s6/`.

**WP-37 S4 + SE-clipping follow-up — Dialogs must show a visible cancel button; control row must fit iPhone SE (P1), 2026-07-08:** Fixed two device-confirmed bugs scoped together per founder instruction. (1) `RunTabView`'s Finish and Discard `confirmationDialog`s rendered with only the destructive/primary button on this iOS 26 environment — "Keep Workout"/"Keep Recording" never appeared, leaving a mid-run mis-tap with no visible way back (confirmed via zoomed device screenshot, not simulator-only speculation). Fix: switched both dialogs from `.confirmationDialog` to `.alert`, preserving identical copy, button labels, and roles (`Button("Discard Workout", role: .destructive)` / `Button("Keep Workout", role: .cancel)`; `Button("Finish and Save")` / `Button("Keep Recording", role: .cancel)`). (2) The same smoke pass found `LiveRunView`'s bottom control-row labels ("Pause"/"Finish"/"Coach", "Resume"/"Finish"/"Discard") clipped off-screen on iPhone SE (375×667pt) — a non-scrolling `GeometryReader`+`VStack` with fixed-height-floor panels (`max(174, min(218, proxy.size.height * 0.25))`) left less room than the row needed, with no scroll fallback. Fix: wrapped the body `VStack` in `ScrollView(showsIndicators: false)` and changed its frame modifier from `maxHeight: .infinity` to `minHeight: proxy.size.height`, preserving the existing bottom-pinned button layout (via `Spacer(minLength: 0)`) on tall screens while making short screens scroll instead of clip. **Validation:** clean worktree `/tmp/rs-wp37-s4` (branched off post-S1/S2/S3/S5 `main` at `77441fd`); full `RunSmartReadinessTests` suite build+test on iPhone 17 sim **PASSED** (no new tests — both fixes are pure SwiftUI presentation/layout, unchanged by any existing test target). Live device-QA on **both** iPhone 17 and iPhone SE simulators: started a run, confirmed the Finish alert shows both "Finish and Save" and "Keep Recording", tapped "Keep Recording" and confirmed the run kept recording without state loss; paused, confirmed the Discard alert shows both "Discard Workout" and "Keep Workout". On iPhone SE specifically: confirmed "Pause"/"Finish"/"Coach" and "Resume"/"Finish"/"Discard" labels are now fully visible after a scroll gesture (previously clipped past the screen edge with no way to reveal them), and confirmed both dialogs render both buttons on SE as well as iPhone 17.

**WP-37 S3 — Paused control row must fit the screen (P1), 2026-07-08:** Fixed `LiveRunView`'s paused control row overflowing every supported width. Root cause confirmed exactly as scoped: Resume(112) + Finish(78) + Coach(78) + Discard(78) + 3×18 spacing + 36 padding = 436pt, wider than iPhone 17's 402pt (worse on smaller phones). Fix (smallest diff, exactly per WP-37's proposed change): the row never shows 4 buttons — while `.paused`, Discard replaces Coach instead of appending a fourth button (Coach/mute is inert while paused since `VoiceCoachService` is itself paused, so there's nothing to mute). New max width: 112+78+78+2×18+36 = 340pt on every phase. **Validation:** clean worktree `/tmp/rs-wp37-s3` (branched off post-S1/S2 `main`), Debug build on iPhone 17 sim **SUCCEEDED**. No existing unit/UI tests target `LiveRunView` (pure layout, no store); the diff only swaps which button renders in the paused branch — `onPauseResume`/`onFinish`/`onDiscard`/voice-coach action closures are untouched. **Merged to main as `45aec7b` via PR #75 (2026-07-08).**

**WP-37 S5 — Remove fabricated KM splits (P1), 2026-07-08:** Fixed `PostRunSummaryView.splitRows` presenting invented paces as real "KM SPLITS". Root cause confirmed exactly as scoped: `let drift = Double((km % 3) - 1) * 4; let pace = max(1, run.averagePaceSecondsPerKm + drift)` — every split was the run's average pace plus a fixed synthetic wobble, not derived from GPS data at all. Fix: added `RunRecorder.kilometerSplits(from: routePoints, maxSplits: 8)`, a pure function that walks route-point GPS distance (`CLLocation.distance(from:)`, same pattern as `RouteMatchingService`) and only emits a split for kilometer N once the recorded route actually crosses N×1000m, with the real elapsed time between crossings as the pace — a run that never completes a full km now correctly returns zero splits instead of one fabricated "filler" split (the old `max(1, Int(distanceMeters/1000))` guaranteed at least 1 split for any run ≥500m, even a 600m run that never ran a full km). New `KilometerSplit` result type added next to `RunRoutePoint` in the models file. Updated the now-inaccurate empty-state copy from "Splits appear after at least 500m" to "...once you complete 1 km" to match the real threshold. `SplitPreviewCard`/`SplitRow` (presentation) untouched. **Validation:** clean worktree `/tmp/rs-wp37-s5` (branched off post-S1/S2/S3 `main`), iPhone 17 sim — full app build **SUCCEEDED**, 2 new focused tests PASS (`testKilometerSplitsComputesRealPaceFromRoutePointCrossings` — exact real pace math over GPS-crossing fixtures, 5:00/km then 5:30/km; `testKilometerSplitsReturnsEmptyWhenRouteNeverCompletesAKilometer`); red-state check confirmed the pace-math test FAILS when a wrong/fabricated value is substituted for the real elapsed-time computation. **Rebased onto post-S3 main (`45aec7b`) 2026-07-08 to resolve conflict with S3's progress.md entry; source files had zero conflicts (disjoint from LiveRunView.swift).**

**WP-37 S1 — Zombie recorder reset (P0), 2026-07-08:** Fixed the frozen "Recording" screen after finish/discard/delete. Root cause: `RunRecorder.finish()`/`discard()` delegated post-run phase reset to `updatePhaseForAuthorization()`, which never resets phase out of `.recording`/`.paused` when authorized (only `.idle/.requestingPermission/.denied/.failed`); the existing discard test passed only because the test host is `.notDetermined`. Fix: added `resolveTerminalPhase()` (always exits the live state → `.ready`/`.denied`/`.idle` by authorization), called from `finish()` and `discard()`; `finish()` now also calls `resetCurrentRun()` to clear stale metrics; kept `updatePhaseForAuthorization()` on the auth-change callback so a mid-run permission change can't yank an active run. Added an injectable `authorizationStatusProvider` seam so the authorized-path P0 is testable. **Validation:** clean worktree `/tmp/rs-wp37-s1` (main's `* 2.swift` dupes excluded), iPhone 17 sim — 3 focused tests PASS (`testRunRecorderFinishReturnsToReadyPhaseWhenAuthorized`, `testRunRecorderPauseThenDiscardReturnsToReadyPhaseWhenAuthorized`, existing `testRunRecorderDiscardResetsCurrentWorkoutWithoutSaving`); red-state check confirmed the finish test FAILS when the bug is reintroduced. **Merged to main as `b97064c` via PR #73 (2026-07-08).**

**WP-37 S2 — Don't abort a run on transient GPS errors (P0), 2026-07-08:** Fixed `RunRecorder.locationManager(_:didFailWithError:)` unconditionally setting `phase = .failed` on any error while recording/paused, which silently kicked an active run back to PreRun and lost it on a transient `kCLErrorLocationUnknown`-class failure. Fix: while `.recording`/`.paused`, only an explicit `CLError.denied` stops the run (`stopTracking()`, `phase = .denied`); every other error keeps recording and surfaces "Weak GPS signal. RunSmart keeps recording and will reconnect automatically." via `lastErrorMessage`; `acceptRecordingLocation` clears `lastErrorMessage` on the next good fix so the pill doesn't stay stale. Non-recording states keep the prior any-error→`.failed` behavior unchanged. **Validation:** clean worktree `/tmp/rs-wp37-s2` (branched fresh off `main`, independent of S1), iPhone 17 sim — 3 new focused tests PASS (`testRunRecorderIgnoresTransientGPSErrorWhileRecording`, `testRunRecorderStopsSafelyWhenPermissionDeniedWhileRecording`, `testRunRecorderStillFailsOnErrorWhenNotRecording`); red-state check confirmed both new tests FAIL when the old unconditional-fail behavior is reintroduced. **Corroborating finding (fixed by S1/PR #73, already merged):** while validating, found the pre-existing `testRunRecorderDiscardResetsCurrentWorkoutWithoutSaving` failing on **unmodified `main`** in this environment — verified in an isolated pristine worktree with zero edits — because this Mac's iPhone 17 simulator has drifted to real `.authorizedWhenInUse` location authorization instead of `.notDetermined`, which is exactly the S1 zombie-phase root cause manifesting live in the existing suite; S1 was already merged by the time S2 rebased onto `main`, so this test now passes again post-rebase. **Rebased onto post-S1 `main` (`b97064c`) 2026-07-08 to resolve merge conflicts with S1's changes to the same file; both fixes coexist and verified together.** **Device QA still owed (both S1 and S2):** record ≥1 min → Save → confirm Run tab shows PreRun with Start + tab bar; repeat via View Report and Delete; pause→discard→PreRun; start a second run, metrics from 0. Switch `simctl location` scenarios mid-run (or toggle location) → run keeps recording, pill shows degraded-GPS copy, no data loss; denying permission mid-run still stops safely. Branch `claude/wp37-runsmart-s2-gps-transient-errors`. Files: `Services/Production/RunSmartProductionServices.swift`, `IOS RunSmart appTests/RunSmartReadinessTests.swift`. Next: S3–S8 not started.

Status: WP-15 fix shipped to App Store Connect as **1.0.7 (21)** on 2026-07-05. Post-fix activation cohort readout is **pending** (needs ~3–7 days live on build 21). WP-34 Garmin credential-guard: closed, explicitly parked per EXD-019 (2026-07-05) — commit unrecoverable, not being reimplemented; revisit 2026-08-01 with EXD-015 reread. WP-27 Garmin Gate-4 evidence cleanup complete on main; founder-run screenshots still pending.
Current Phase: PHASE 2 — Activation diagnostics + Garmin maintenance (EXD-015).
Active Story: WP-15 — monitor `plan_generated -> plan_run_cta_tapped -> run_started -> run_completed` on build 21 cohort (target >=20% plan-to-run).
Last Completed Story: 2026-07-05 — WP-15 release: archived and uploaded **1.0.7 (21)** with `firstRunnableWorkoutAfterPlanGeneration()` poll fix (commit `6ed8b97`).
Next Recommended Story: Re-run PostHog funnel on **2026-07-08+** for build-21-only users (`filterTestAccounts=true`). Then WP-27 Gate-4 screenshots if Garmin path resumes.
Estimated Completion: Post-fix funnel gate opens ~2026-07-08 (3 days after ASC upload) once enough onboarding→plan completions mature.
Blockers: (1) Post-fix cohort not yet measurable same-day as upload. (2) Local main worktree has Finder duplicate `* 2.swift` files that block archive — release built from clean detached worktree at `6ed8b97`; clean duplicates before next local archive.
Last Validation: 2026-07-05 — Release archive **SUCCEEDED** (clean worktree, ~10 min). ASC upload **SUCCEEDED** (`ExportOptionsAppStoreUpload.plist`). Archive metadata: `RunSmart` / `com.runsmart.lite` / `1.0.7` / `21` / `ITSAppUsesNonExemptEncryption=false` / dSYM present. Known HKWorkout deprecation warning only.
PM Artifacts: Activation funnel events in `.agent-os/distribution/analytics-instrumentation-spec.md`; WP-34 incident in `tasks/ERRORS.md`.
Last Updated: 2026-07-05

---

## 2026-07-05 — WP-15 build 21 submitted to App Store Connect

| Field | Value |
|---|---|
| **Version** | 1.0.7 |
| **Build number** | 21 |
| **Fix commit** | `6ed8b97` (WP-15 first-run sheet poll) |
| **Submission date (UTC+3)** | 2026-07-05 ~20:18 |
| **Upload method** | `xcodebuild -exportArchive` + `ExportOptionsAppStoreUpload.plist` |
| **Archive path** | `/tmp/runsmart-wp15-release-1783271110/build/RunSmart-v1.0.7-build21-WP15-AppStore-20260705.xcarchive` |
| **ASC status** | Upload succeeded; package processing |

**Pre-submission checklist:** `tasks/lessons.md` + `docs/qa/testflight-checklist.md` + `docs/qa/app-store-readiness-checklist.md` reviewed. Secrets present (`RunSmartSecrets.xcconfig`). First archive from dirty main worktree failed on duplicate Finder `* 2.swift` compile crash; retried from clean detached worktree (no duplicates). DerivedData cleaned before retry.

**Build bump:** `CURRENT_PROJECT_VERSION` 20 → 21 (local/uncommitted on main worktree `project.pbxproj`).

---

## WP-15 activation readout — D7 baseline vs build 21 (in progress)

### PostHog query (project 171597 — Running coach)

Tool: PostHog MCP `query-funnel` after `switch-project` → **171597**.

```json
{
  "kind": "FunnelsQuery",
  "series": [
    { "kind": "EventsNode", "event": "plan_generated" },
    { "kind": "EventsNode", "event": "plan_run_cta_tapped" },
    { "kind": "EventsNode", "event": "run_started" },
    { "kind": "EventsNode", "event": "run_completed" }
  ],
  "dateRange": { "date_from": "2026-06-19", "date_to": "2026-07-05" },
  "funnelsFilter": {
    "funnelOrderType": "ordered",
    "funnelVizType": "steps",
    "funnelWindowInterval": 7,
    "funnelWindowIntervalUnit": "day"
  },
  "filterTestAccounts": true
}
```

Supporting diagnostic (confirms sheet skip):

```json
{
  "kind": "FunnelsQuery",
  "series": [
    { "kind": "EventsNode", "event": "plan_generated" },
    { "kind": "EventsNode", "event": "first_run_cta_viewed" },
    { "kind": "EventsNode", "event": "first_run_cta_tapped" },
    { "kind": "EventsNode", "event": "run_started" },
    { "kind": "EventsNode", "event": "run_completed" }
  ],
  "dateRange": { "date_from": "2026-06-19", "date_to": "2026-07-05" },
  "funnelsFilter": { "funnelOrderType": "ordered", "funnelWindowInterval": 7, "funnelWindowIntervalUnit": "day" },
  "filterTestAccounts": true
}
```

### Before (pre-fix baseline — D7 Readout #2 + PostHog 2026-06-19→2026-07-05)

| Metric | D7 Readout #2 (2026-07-05) | PostHog funnel (same window, test accounts excluded) |
|---|---|---|
| Mature cohort `run_completed` (7d) | **0 / 12** | 0 users at `run_completed` |
| Onboarding drop | **94.7%** | (separate funnel; not WP-15 chain) |
| `plan_generated` | some reached plan | **1** user |
| `plan_run_cta_tapped` | — | **0** (0%) |
| `run_started` | — | **0** (0%) |
| `run_completed` | **0** | **0** (0%) |
| **Plan → run conversion** | **0%** | **0%** (0/1) |
| `first_run_cta_viewed` | — | **0** (sheet never shown — matches race root cause) |

**Interpretation (pre-fix):** Users who generated a plan never saw the first-run activation sheet (`first_run_cta_viewed`=0) because `presentFirstRunActivationIfNeeded` ran before async `regenerateTrainingPlan` finished. No bridge CTA, no run start. The 94.7% onboarding drop is a **separate upstream wall** (sign-in + 5 onboarding steps + 2 aha screens).

### After (build 21 cohort — pending)

| Metric | Value |
|---|---|
| Submission date | 2026-07-05 |
| Earliest readout date | **2026-07-08** (3+ days live usage) |
| Same-day PostHog (2026-07-05 only) | No data (expected — upload just completed) |
| Plan → run conversion | **TBD** — re-run query with `date_from: 2026-07-05`, filter to build 21 installs when `$app_version` / build property visible |

**WP-15 completion gate:** >=20% `plan_generated` → `run_completed` (via `plan_run_cta_tapped` + `run_started`) on next usable build-21 cohort.

### If the wall persists after build 21 (next likely causes, with evidence)

1. **Onboarding attrition (94.7%)** — still upstream; fix does not shorten onboarding. Users never reach `plan_generated`.
2. **Today `upNext` routing** — if first workout is not today, user may land on Today without obvious run CTA even after sheet fix (partially addressed PR #62; verify on device).
3. **Location / HealthKit denial at run start** — not instrumented; secondary for users who reach CTA but fail GPS/Health gate.
4. **Funnel timing** — `onboarding_completed` fires before async plan save finishes; can skew step-to-step timing in dashboards (instrumentation nuance, not the sheet race).

**Verdict (2026-07-05):** Fix shipped; **too early to measure post-fix lift**. Pre-fix PostHog confirms 0% plan-to-run and 0 `first_run_cta_viewed`, consistent with the diagnosed race. Re-query **2026-07-08+**.
