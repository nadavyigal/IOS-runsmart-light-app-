**FTUX Audit — First-time-user journey audit (docs-only), 2026-07-13:** Full fresh-install product/UX audit as a skeptical first-time user on a clean iOS 26.5 iPhone 17 Pro simulator: real mode (sign-in wall, SIWA failure copy), onboarding replay (all 6 steps + aha moments), and demo mode (Today/Plan/Run/Report/Profile, live GPS run via `simctl location`, post-run, coach chat). Backed every observed issue with code inspection. Deliverable: `docs/audits/first-time-user-journey-audit.md` (14 sections: journey map, 10 ranked abandonment risks, activation analysis, 16 reproducible defects, instrumentation gaps vs existing PostHog events, 3 experiments, scorecard 5.5/10) + 12 evidence screenshots under `docs/audits/assets/ftux-2026-07-13/`. Key confirmed code defects: raw `ASAuthorizationError 1000` shown to users (`SignInView.swift:126`); "Six weeks" vs "in 8 weeks" contradiction (`GoalTimelineMomentView.swift:15` vs `:105`); Workout Breakdown "21000 × 400 m" from digit-strip parse of "8 x 400m" (`StructuredWorkoutFactory.swift:183` + `:128`); hardcoded "Source: Real" pill (`ActivityTabView.swift:56`); silent HealthKit connect failure (no failure branch in `OnboardingView.connectHealthKit()`); hidden default goal "10K improvement" not among visible options (`OnboardingProfile.empty`). Top product risk: undesigned post-onboarding plan-generation gap (45s poll, transient failure banner pointing at Profile-buried "Training Data"). **Validation:** audit-only session — no production code, config, analytics, or copy changed; app built and driven on simulator (Debug), no tests required. **Simulator limits documented, not skipped:** SIWA completion, Garmin OAuth, real plan generation.

**WP-40 S1 — Apple Health connect in primary onboarding flow (P0), 2026-07-10:** Added a skippable Apple Health step before onboarding completion, replacing the prior informational-only HealthKit preview. The step reuses the existing `services.connect(provider: HealthKitSyncService.providerName)` route, emits the existing disclosure/connect analytics, refreshes stored connection state, and only advances automatically for a matching connected HealthKit status. Added stable accessibility identifiers for Connect/Skip and a focused red/green XCTest contract. **Validation:** focused XCTest passed (1/1); Debug simulator build succeeded on iPhone 17; onboarding replay exposed both actions; Skip reached Ready; Connect followed the real HealthKit route (current simulator was already authorized, with preserved fresh-permission evidence at `docs/qa/reports/wp40-18-after-wait.png`). `git diff --check` passed. Branch remains uncommitted with pre-existing partial S2 service changes and QA artifacts; S2–S4 are not claimed complete.

**WP-38 S14a–d — Stretch bundle: screen awake, Live Activity, haptics, accessibility (P3), 2026-07-09:** Closed WP-38 packet stretch items as four independent diffs. **S14a:** `RunScreenAwakePolicy` disables idle timer during `.recording`/`.paused`, restores on finish/discard/tab exit. **S14b:** Added `RunSmartRunLiveActivityExtension` widget target with lock-screen/Dynamic Island Live Activity showing distance/moving time/pace plus Pause/Resume + Finish intents (`PauseRunLiveActivityIntent`, `FinishRunLiveActivityIntent`) wired via notifications to `RunTabView`; `RunLiveActivityController` syncs from recorder metrics; shared `RunRecordingLiveActivityAttributes` in `RunSmartShared`. **S14c:** Haptic pass — start medium, pause/resume light, finish light on tap + medium on confirm, discard light on dialog open + medium on confirm (no duplicate fire on single action). **S14d:** VoiceOver labels/hints on `PreRunView`, `LiveRunView` (metrics, controls, KM splits), `PostRunSummaryView`, `RPESelector`; largest Dynamic Type smoke on live HUD without layout clip (existing ScrollView + scale factors). **CodeRabbit fixes (PR #83):** pause a11y hint corrected; `RunTabView.onAppear` restores awake/Live Activity after tab return; DEBUG logging for Activity.request failures; Dynamic Island respects paused state; removed redundant `INFOPLIST_KEY_NSSupportsLiveActivities`. **Validation:** no stray `* 2.*` under app source; Debug build **SUCCEEDED** with embedded extension; sim evidence `docs/qa/reports/assets-2026-07-09-wp38-s14/`. **Merged to main as `f9d7c89` via PR #83 (2026-07-09).**

**WP-38 S12 — Live per-km splits during recording (P2), 2026-07-09:** Surfaced real GPS-derived kilometer splits in the live run HUD as each km boundary completes. Added `LiveKmSplitsPanel` to `LiveRunView` — collapsed-by-default compact row below the map (latest split pace + chevron); expands to list all completed splits. Uses `RunRecorder.kilometerSplits(from: recorder.routePoints)` only (same helper as post-run `PostRunSummaryView.splitRows`); full `routePoints` passed separately from map `displayRoutePoints`. No new pace math. DEBUG-only `-AUTO_START_RUN` (demo mode) for simulator QA automation. **Validation:** no stray `* 2.*` duplicates under app source; Debug build **SUCCEEDED**; WP-37 S5 split unit tests **PASSED**; iPhone 17 sim + `simctl location` 3.5 km path: at 1.21 km live HUD shows **KM SPLITS `0:47 km 1`**; at 2.22 km shows **`0:41 km 2`**; post-run save 2.55 km uses same `kilometerSplits` path. Evidence: `docs/qa/reports/assets-2026-07-09-wp38-s12/`. Branch `claude/wp38-runsmart-s12-live-km-splits`.

**WP-38 S11 — Delete-dialog Garmin copy cleanup (P3), 2026-07-09:** Post-run and Report delete confirmations still mentioned Garmin even for phone-recorded runs (`"It will not delete anything from Garmin."` / `"Garmin runs are hidden..."`). Copy-only fix: both surfaces now use identical source-neutral copy — title `Delete this run?`, message `This removes the run from your RunSmart history.`, destructive `Delete Run`. Also switched both from `.confirmationDialog` to `.alert` so Cancel stays visible on iOS 26 (same WP-37 S4 lesson). Hide-vs-delete behavior unchanged. Old Garmin strings saved in `tasks/garmin-deferred-copy-restore.md` for when Garmin reconnects. **Validation:** Debug build **SUCCEEDED**; device QA on iPhone 17 Report trash → alert shows neutral copy with Cancel + Delete Run, no Garmin wording (`docs/qa/reports/assets-2026-07-09-wp38-s11/`). Batched with S9+S10 for one PR.

**WP-38 S10 — Fix `timeLabel` for runs ≥1 hour (P3), 2026-07-09:** `RunRecorder.timeLabel` always printed zero-padded `MM:SS`, so a 90-minute run rendered as `90:00` instead of `1:30:00`. Fix: branch at `>= 3600` to `H:MM:SS` (`%d:%02d:%02d`); keep existing `MM:SS` under an hour. All live HUD / post-run / history / report-skeleton call sites inherit via the shared helper. Also pointed `PostRunSummaryScaffold`'s local formatter at `RunRecorder.timeLabel`, and fixed demo-mode `runReport(for:)` so unmatched local/seeded runs use `reportSkeleton` (real `timeLabel`) instead of falling back to an unrelated Tempo Builder fixture (`41:36`) — that fallback was masking S10 device QA. Added DEBUG `-OPEN_SECONDARY addActivity` for Add Activity deep-link. Unit tests added: `testTimeLabelUsesHourFormatAtAndAboveOneHour`, `testTimeLabelKeepsMinuteFormatUnderOneHour`. **Validation:** Debug build **SUCCEEDED** on iPhone 17; `build-for-testing` **SUCCEEDED** (dedicated DerivedData); simulator XCTest launch stalled (IDERunDestination empty / install hang — known infra, not a test failure); device QA seeded 5400s + 2700s runs into sim prefs: report detail shows **MOVING TIME `1:30:00`** (90 min) and **`45:00`** (45 min). Evidence: `docs/qa/reports/assets-2026-07-09-wp38-s10/`. Still batched with S9 for one PR after S11.

**WP-38 S9 — Rename "Time" to "Moving time" (P3), 2026-07-09:** Copy-only relabel of every user-facing `"Time"` title whose value is moving-time (`movingLabel` / `movingTimeSeconds` / report duration from that field). Touched live HUD (`RunTabView` metric tile), post-run summary + share fallback (`PostRunSummaryView`), Report totals pill (`ActivityTabView`), run-report / Garmin / scaffold badges (`SecondaryFlowView`), save-route sheet, share card, and the matching `currentRunMetrics` tiles in production/Supabase/demo/live mappers. PreRun already said `"Moving time"`; left banner copy `"Time is running now."` and code identifiers (`timeLabel`, `movingTimeSeconds`) alone. No elapsed-time tracking added. **Validation:** no source `* 2.*` duplicates under app/tasks/docs/supabase; baseline + post-change Debug builds on iPhone 17 sim **SUCCEEDED**. Device-QA with `-RUNSMART_DEMO_MODE` + `simctl location` City Run: live HUD shows **MOVING TIME** (iPhone 17 + SE); post-run summary shows **MOVING TIME**; Report Last-14-Days pill shows **MOVING TIME**. Evidence under `docs/qa/reports/assets-2026-07-09-wp38-s9/`. Branch `claude/wp38-runsmart-s9-moving-time-label`. No unit test (copy-only). PR not opened yet — awaiting founder preference (S9 alone vs batch S9–S11).

**WP-37 S8 — PreRun honesty: real preview, visible Last Run (P2), 2026-07-08:** Fixed the PreRun screen making a decorative route sketch look like live GPS data while the Last Run card could sit below the fold on short screens. Root cause confirmed exactly as scoped: `PreRunView` used a non-scrolling `VStack` inside `GeometryReader`, and the decorative `RunSmartRoutePreview` was labeled `GPS preview` with the GPS icon even though it was not connected to current location. Fix: wrapped the PreRun content in `ScrollView(showsIndicators: false)`, kept the existing tall-screen feel with `minHeight: proxy.size.height`, and relabeled the decorative preview to `Route sketch` with the map icon (`showGPS: false`). No new map/location feature was added. **Validation:** clean worktree `/tmp/rs-wp37-s8` (branched off fresh `origin/main` at `79bc39f`); Debug build on iPhone 17 sim **SUCCEEDED** (known HealthKit `HKWorkout` initializer deprecation warning and run-script dependency note only). No unit test added because this is pure SwiftUI layout/copy honesty. Device-QA on **both** iPhone 17 and iPhone SE simulators using `-RUNSMART_DEMO_MODE -INITIAL_TAB Run`: iPhone 17 shows `Route sketch` and `Last Run` visible/reachable; iPhone SE shows `Route sketch`, and after one scroll the `Last Run` card is reachable and visible. Evidence screenshots saved under `docs/qa/reports/assets-2026-07-08-wp37-s8/`.

**WP-37 S7 — Persist RPE or stop pretending (P2), 2026-07-08:** Fixed the post-run "How did that feel?" selector pretending every run was pre-rated 6/10 while discarding the selected value. Root cause confirmed exactly as scoped: `PostRunSummaryView` initialized `rpe = 6`, `RPESelector` required a non-optional value, and no save path wrote that rating back to the recorded run. Fix: made the selector optional/unset by default (`Not rated`), added `RecordedRun.rpe`, persisted RPE through `RunSmartLocalStore.updateRunRPE`, wired the RunLogging service path for production/Supabase/demo services, and surfaces saved RPE on activity history rows plus run report detail. The post-run coach card now uses neutral "Not rated" copy until the runner makes an explicit selection. The demo service also surfaces locally saved simulator runs ahead of preview fixtures so compressed `-RUNSMART_DEMO_MODE` QA can verify persistence in Report without weakening production visibility rules. **Validation:** clean worktree `/tmp/rs-wp37-s7` (branched off fresh `origin/main` at `cfeb854`); focused XCTest `RunSmartReadinessTests/testLocalStorePersistsRunRPESelection` **PASSED**; red-state check confirmed the test **FAILS** when `saveRun(updated)` is removed from `RunSmartLocalStore.updateRunRPE`, then **PASSES** again after restoring the fix. Debug build on iPhone 17 sim **SUCCEEDED**. Device-QA on **both** iPhone 17 and iPhone SE simulators using `-RUNSMART_DEMO_MODE` and real `RunRecorder`/CoreLocation: saved a run, confirmed the summary starts `Not rated`, selected RPE 8 and saw `8/10`, relaunched into Report and confirmed the saved history row shows `RPE 8/10`. Evidence screenshots saved under `docs/qa/reports/assets-2026-07-08-wp37-s7/`.

**WP-37 S6 — Live map current position is not Finish (P2), 2026-07-08:** Fixed `RouteMapView` marking the live runner position as a red "Finish" flag mid-run. Root cause confirmed exactly as scoped: the shared map component always rendered `Marker("Finish", systemImage: "flag.fill", coordinate: last)` for the final route point, and `LiveRunView` used that same default behavior while recording. Fix: added an `isLive` flag to `RouteMapView` that defaults to `false`; live maps render the first point as Start and the latest point as an unlabeled current-position dot, while all existing post-run/route-library call sites keep Start/Finish markers unchanged. `LiveRunView` is the only caller passing `isLive: true`. **Validation:** clean worktree `/tmp/rs-wp37-s6` (branched off fresh `origin/main` at `825e8d9`); Debug build on iPhone 17 sim **SUCCEEDED** (known HealthKit `HKWorkout` initializer deprecation warning only). No unit test added because this is pure SwiftUI Map annotation presentation with no existing testable logic boundary; visual device-QA covered the acceptance. Device-QA on **both** iPhone 17 and iPhone SE simulators using `-RUNSMART_DEMO_MODE` and real `RunRecorder`/CoreLocation: started simulated GPS recording and confirmed the live map shows Start + an unlabeled current-position dot with no "Finish" marker; finished/saved on iPhone 17 and confirmed the completed route summary still shows Start + Finish flags. Evidence screenshots saved under `docs/qa/reports/assets-2026-07-08-wp37-s6/`.

**WP-37 S4 + SE-clipping follow-up — Dialogs must show a visible cancel button; control row must fit iPhone SE (P1), 2026-07-08:** Fixed two device-confirmed bugs scoped together per founder instruction. (1) `RunTabView`'s Finish and Discard `confirmationDialog`s rendered with only the destructive/primary button on this iOS 26 environment — "Keep Workout"/"Keep Recording" never appeared, leaving a mid-run mis-tap with no visible way back (confirmed via zoomed device screenshot, not simulator-only speculation). Fix: switched both dialogs from `.confirmationDialog` to `.alert`, preserving identical copy, button labels, and roles (`Button("Discard Workout", role: .destructive)` / `Button("Keep Workout", role: .cancel)`; `Button("Finish and Save")` / `Button("Keep Recording", role: .cancel)`). (2) The same smoke pass found `LiveRunView`'s bottom control-row labels ("Pause"/"Finish"/"Coach", "Resume"/"Finish"/"Discard") clipped off-screen on iPhone SE (375×667pt) — a non-scrolling `GeometryReader`+`VStack` with fixed-height-floor panels (`max(174, min(218, proxy.size.height * 0.25))`) left less room than the row needed, with no scroll fallback. Fix: wrapped the body `VStack` in `ScrollView(showsIndicators: false)` and changed its frame modifier from `maxHeight: .infinity` to `minHeight: proxy.size.height`, preserving the existing bottom-pinned button layout (via `Spacer(minLength: 0)`) on tall screens while making short screens scroll instead of clip. **Validation:** clean worktree `/tmp/rs-wp37-s4` (branched off post-S1/S2/S3/S5 `main` at `77441fd`); full `RunSmartReadinessTests` suite build+test on iPhone 17 sim **PASSED** (no new tests — both fixes are pure SwiftUI presentation/layout, unchanged by any existing test target). Live device-QA on **both** iPhone 17 and iPhone SE simulators: started a run, confirmed the Finish alert shows both "Finish and Save" and "Keep Recording", tapped "Keep Recording" and confirmed the run kept recording without state loss; paused, confirmed the Discard alert shows both "Discard Workout" and "Keep Workout". On iPhone SE specifically: confirmed "Pause"/"Finish"/"Coach" and "Resume"/"Finish"/"Discard" labels are now fully visible after a scroll gesture (previously clipped past the screen edge with no way to reveal them), and confirmed both dialogs render both buttons on SE as well as iPhone 17.

**WP-37 S3 — Paused control row must fit the screen (P1), 2026-07-08:** Fixed `LiveRunView`'s paused control row overflowing every supported width. Root cause confirmed exactly as scoped: Resume(112) + Finish(78) + Coach(78) + Discard(78) + 3×18 spacing + 36 padding = 436pt, wider than iPhone 17's 402pt (worse on smaller phones). Fix (smallest diff, exactly per WP-37's proposed change): the row never shows 4 buttons — while `.paused`, Discard replaces Coach instead of appending a fourth button (Coach/mute is inert while paused since `VoiceCoachService` is itself paused, so there's nothing to mute). New max width: 112+78+78+2×18+36 = 340pt on every phase. **Validation:** clean worktree `/tmp/rs-wp37-s3` (branched off post-S1/S2 `main`), Debug build on iPhone 17 sim **SUCCEEDED**. No existing unit/UI tests target `LiveRunView` (pure layout, no store); the diff only swaps which button renders in the paused branch — `onPauseResume`/`onFinish`/`onDiscard`/voice-coach action closures are untouched. **Merged to main as `45aec7b` via PR #75 (2026-07-08).**

**WP-37 S5 — Remove fabricated KM splits (P1), 2026-07-08:** Fixed `PostRunSummaryView.splitRows` presenting invented paces as real "KM SPLITS". Root cause confirmed exactly as scoped: `let drift = Double((km % 3) - 1) * 4; let pace = max(1, run.averagePaceSecondsPerKm + drift)` — every split was the run's average pace plus a fixed synthetic wobble, not derived from GPS data at all. Fix: added `RunRecorder.kilometerSplits(from: routePoints, maxSplits: 8)`, a pure function that walks route-point GPS distance (`CLLocation.distance(from:)`, same pattern as `RouteMatchingService`) and only emits a split for kilometer N once the recorded route actually crosses N×1000m, with the real elapsed time between crossings as the pace — a run that never completes a full km now correctly returns zero splits instead of one fabricated "filler" split (the old `max(1, Int(distanceMeters/1000))` guaranteed at least 1 split for any run ≥500m, even a 600m run that never ran a full km). New `KilometerSplit` result type added next to `RunRoutePoint` in the models file. Updated the now-inaccurate empty-state copy from "Splits appear after at least 500m" to "...once you complete 1 km" to match the real threshold. `SplitPreviewCard`/`SplitRow` (presentation) untouched. **Validation:** clean worktree `/tmp/rs-wp37-s5` (branched off post-S1/S2/S3 `main`), iPhone 17 sim — full app build **SUCCEEDED**, 2 new focused tests PASS (`testKilometerSplitsComputesRealPaceFromRoutePointCrossings` — exact real pace math over GPS-crossing fixtures, 5:00/km then 5:30/km; `testKilometerSplitsReturnsEmptyWhenRouteNeverCompletesAKilometer`); red-state check confirmed the pace-math test FAILS when a wrong/fabricated value is substituted for the real elapsed-time computation. **Rebased onto post-S3 main (`45aec7b`) 2026-07-08 to resolve conflict with S3's progress.md entry; source files had zero conflicts (disjoint from LiveRunView.swift).**

**WP-37 S1 — Zombie recorder reset (P0), 2026-07-08:** Fixed the frozen "Recording" screen after finish/discard/delete. Root cause: `RunRecorder.finish()`/`discard()` delegated post-run phase reset to `updatePhaseForAuthorization()`, which never resets phase out of `.recording`/`.paused` when authorized (only `.idle/.requestingPermission/.denied/.failed`); the existing discard test passed only because the test host is `.notDetermined`. Fix: added `resolveTerminalPhase()` (always exits the live state → `.ready`/`.denied`/`.idle` by authorization), called from `finish()` and `discard()`; `finish()` now also calls `resetCurrentRun()` to clear stale metrics; kept `updatePhaseForAuthorization()` on the auth-change callback so a mid-run permission change can't yank an active run. Added an injectable `authorizationStatusProvider` seam so the authorized-path P0 is testable. **Validation:** clean worktree `/tmp/rs-wp37-s1` (main's `* 2.swift` dupes excluded), iPhone 17 sim — 3 focused tests PASS (`testRunRecorderFinishReturnsToReadyPhaseWhenAuthorized`, `testRunRecorderPauseThenDiscardReturnsToReadyPhaseWhenAuthorized`, existing `testRunRecorderDiscardResetsCurrentWorkoutWithoutSaving`); red-state check confirmed the finish test FAILS when the bug is reintroduced. **Merged to main as `b97064c` via PR #73 (2026-07-08).**

**WP-37 S2 — Don't abort a run on transient GPS errors (P0), 2026-07-08:** Fixed `RunRecorder.locationManager(_:didFailWithError:)` unconditionally setting `phase = .failed` on any error while recording/paused, which silently kicked an active run back to PreRun and lost it on a transient `kCLErrorLocationUnknown`-class failure. Fix: while `.recording`/`.paused`, only an explicit `CLError.denied` stops the run (`stopTracking()`, `phase = .denied`); every other error keeps recording and surfaces "Weak GPS signal. RunSmart keeps recording and will reconnect automatically." via `lastErrorMessage`; `acceptRecordingLocation` clears `lastErrorMessage` on the next good fix so the pill doesn't stay stale. Non-recording states keep the prior any-error→`.failed` behavior unchanged. **Validation:** clean worktree `/tmp/rs-wp37-s2` (branched fresh off `main`, independent of S1), iPhone 17 sim — 3 new focused tests PASS (`testRunRecorderIgnoresTransientGPSErrorWhileRecording`, `testRunRecorderStopsSafelyWhenPermissionDeniedWhileRecording`, `testRunRecorderStillFailsOnErrorWhenNotRecording`); red-state check confirmed both new tests FAIL when the old unconditional-fail behavior is reintroduced. **Corroborating finding (fixed by S1/PR #73, already merged):** while validating, found the pre-existing `testRunRecorderDiscardResetsCurrentWorkoutWithoutSaving` failing on **unmodified `main`** in this environment — verified in an isolated pristine worktree with zero edits — because this Mac's iPhone 17 simulator has drifted to real `.authorizedWhenInUse` location authorization instead of `.notDetermined`, which is exactly the S1 zombie-phase root cause manifesting live in the existing suite; S1 was already merged by the time S2 rebased onto `main`, so this test now passes again post-rebase. **Rebased onto post-S1 `main` (`b97064c`) 2026-07-08 to resolve merge conflicts with S1's changes to the same file; both fixes coexist and verified together.** **Device QA still owed (both S1 and S2):** record ≥1 min → Save → confirm Run tab shows PreRun with Start + tab bar; repeat via View Report and Delete; pause→discard→PreRun; start a second run, metrics from 0. Switch `simctl location` scenarios mid-run (or toggle location) → run keeps recording, pill shows degraded-GPS copy, no data loss; denying permission mid-run still stops safely. Branch `claude/wp37-runsmart-s2-gps-transient-errors`. Files: `Services/Production/RunSmartProductionServices.swift`, `IOS RunSmart appTests/RunSmartReadinessTests.swift`. Next: S3–S8 not started.

Status: **1.0.8 (22) approved by App Review and live on the App Store (2026-07-13).** WP-37 **COMPLETE**. WP-38 **COMPLETE**. WP-40 **COMPLETE**. Handoff: `docs/qa/reports/release-1.0.8-build22-handoff.md`.
Current Phase: PHASE 2 — Release 1.0.8 (22) (WP-37/38/40 bundle) — live.
Active Story: FTUX audit delivered (docs/audits/first-time-user-journey-audit.md); awaiting founder review of prioritized fixes.
Last Completed Story: 2026-07-13 — First-time-user journey audit report + evidence committed (docs-only).
Next Recommended Story: Triage the audit's 'Fix before acquiring more users' list (plan-generation state, SIWA error copy, aha-timeline contradiction, breakdown parser) into the next work packet.
Blockers: None.
Last Validation: 2026-07-13 — Audit walkthrough on fresh iPhone 17 Pro sim (Debug build SUCCEEDED, live GPS run recorded and saved); no code changes to validate.
Last Updated: 2026-07-13

---

## 2026-07-13 — RunSmart 1.0.8 (22) approved and live

| Field | Value |
|---|---|
| **Version** | 1.0.8 |
| **Build number** | 22 |
| **Approval/live date** | 2026-07-13 (founder-confirmed) |
| **Includes** | WP-37 run reliability, WP-38 run UX (splits, Live Activity), WP-40 HealthKit onboarding + auto-import |
| **ASC status** | **Approved — live on the App Store** |
| **Handoff** | `docs/qa/reports/release-1.0.8-build22-handoff.md` |
| **Replaces** | 1.0.7 (21) on ASC (~2026-07-05) |

---

## 2026-07-12 — RunSmart 1.0.8 (22) archived

| Field | Value |
|---|---|
| **Version** | 1.0.8 |
| **Build number** | 22 |
| **Archive date (UTC+3)** | 2026-07-12 |
| **Includes** | WP-37 run reliability, WP-38 run UX (splits, Live Activity), WP-40 HealthKit onboarding + auto-import |
| **ASC status** | Archived locally; waiting for review (superseded — see 2026-07-13 entry above) |
| **Handoff** | `docs/qa/reports/release-1.0.8-build22-handoff.md` |
| **Replaces** | 1.0.7 (21) on ASC (~2026-07-05) |

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
