# Session Log

## 2026-07-24 - 1.1.3 (28) release prep: package the merged route feature

### Outcome
Route feature merged to `main` (PR #116, `8cbb928`), so 1.1.3 is a release-packaging commit, not a code change. Bumped `MARKETING_VERSION` 1.1.2 → 1.1.3 and `CURRENT_PROJECT_VERSION` 27 → 28 across all 6 configurations (grep-verified 6/6, 0 stale, diff is exactly the 12 version lines), and rewrote `fastlane/metadata/en-US/release_notes.txt` to user-facing route copy. This is the first build that actually uses the `user_saved_routes` / `user_benchmark_routes` tables applied to production 2026-07-23, so cloud route persistence stops being a silent no-op for users.

### Changes (branch claude/release-1.1.3-routes)
- `IOS RunSmart app.xcodeproj/project.pbxproj`: version 1.1.2 → 1.1.3, build 27 → 28 (all 6 configs).
- `fastlane/metadata/en-US/release_notes.txt`: rewritten for the route feature (Use This Route, reachable route/benchmark detail, cloud sync survives reinstall, full-height screens).
- `tasks/progress.md`, `tasks/todo.md`, `tasks/session-log.md`: status updated.

### Validation
- Version bump grep-verified (6 of each new value, 0 stale; diff is the 12 version lines only).
- Release build for `generic/platform=iOS` (Release config, CODE_SIGNING_ALLOWED=NO, derivedDataPath under /private/tmp): see progress.md Last Validation.
- Route code unchanged from the 2026-07-23 merge validation (327 passed / 1 pre-existing Hebrew-locale flaky).

### Open (founder-only)
- Device-smoke the record → save → benchmark → re-run → comparison loop once on real hardware (the one gate the route QA report left open); now also verifies cloud persistence survives delete + reinstall.
- Archive 1.1.3 (28) in Xcode → upload → submit. No DB gate remains.

## 2026-07-23 - Route feature review: root cause found (missing Supabase tables), creator/benchmark loop repaired

### Outcome
Founder asked why the Route Creator and Route Benchmark feature "designed a while ago disappeared." Root cause: `user_saved_routes` / `user_benchmark_routes` were never created in the Supabase project (the SQL only existed as a code comment), so cloud sync silently no-ops, saved routes/benchmarks live only in UserDefaults, and a delete/reinstall wipes them. On top of that, three UX breaks made the surviving local feature near-unusable: the Route Creator had no "use this route" action (dead end), the Route Detail screen (Make Benchmark / Favorite / Delete / benchmark stats) was unreachable from any surface, and the demo/QA services hardcoded the save/match/comparison loop dead.

### Changes (branch claude/route-feature-review-d15198)
- Route Creator: primary "Use This Route" CTA -> starts a run with the selected route; Generate demoted to secondary.
- "Details" chip on saved/benchmark route cards (creator + selector) -> opens the previously unreachable RouteDetailScaffold.
- Demo/QA services now seed preview fixtures into the local store once and run real production route logic; save -> benchmark -> match -> comparison is simulator-QA-able.
- Route screens present at .large detent (route list was below the fold at .medium).
- New `route_used_for_run` analytics event (source: route_creator | route_selector | today_card).
- QA hook: `-OPEN_SECONDARY routeCreator|routeSelector`.
- Staged migration `supabase/migrations/20260723120000_create_user_route_tables.sql` — NOT applied; founder decision.

### Validation
- New `RouteLibraryDemoServiceTests` (3): confirmed failing against the pre-fix implementation, passing after.
- Full iOS suite result recorded in tasks/progress.md.
- Simulator walk-through (iPhone 17, demo mode) with screenshots; report at `docs/qa/reports/route-feature-review-2026-07-23.md`.

### Open
- Founder: approve/apply the route-tables migration (client heals automatically once tables exist).
- Founder: device smoke — record a run, save as benchmark, re-run it, confirm the comparison card.
- Follow-ups recorded in tasks/todo.md: Garmin past-route points, Today card only shows for planned workouts, generated "loops" are out-and-backs with elevation 0, no route polyline on LiveRunView.

## 2026-07-22 - Build 27 prepared; first-time Apple sign-in proven working

### Outcome
The revoke-and-retry test (Stop Using Apple ID -> delete -> reinstall public 1.1.1 (25)) completed a genuine first-time Sign in with Apple at 10:34:21Z with zero sign_in_failed. This refutes the earlier "first-time sign-in has been broken since 2026-06-18" conclusion. Sign-in is broken for some users, not all.

### Prepared for archive: 1.1.2 (27)
- has_underlying_error / underlying_error_* on sign_in_failed (merged as 853953d via PR #113).
- Sign-in failure copy now names iCloud so a blocked user has something to act on.
- Sign in with Apple button ignores a second tap while Apple is presenting; re-arms on completion or foreground return.
- CURRENT_PROJECT_VERSION 26 -> 27 across all six configurations; MARKETING_VERSION stays 1.1.2.
- Release notes rewritten to cover build 26 and 27 content together.

### Validation
- Full suite 324 passed / 0 failed / 0 skipped, xcresult-verified.
- Release build for generic/platform=iOS succeeded; built Info.plist confirms 1.1.2 (27) with a non-empty POSTHOG_API_KEY.
- Instrumentation strings confirmed present in the compiled binary; short event names are absent from `strings` output only because of Swift small-string optimization, not because they are missing.

### Open
- Device smoke of the sign-in button guard before submitting (only change on the critical auth path).
- No email/guest fallback in this build; users who cannot complete Sign in with Apple still have no alternative route.

## 2026-07-21 - Public 1.1.1 founder journey correlated in PostHog

### Outcome
The App Store reinstall journey succeeded mechanically: one Sign in with Apple tap completed, onboarding and HealthKit completed, plan generation emitted one start and one success, and the first-run CTA/workout became visible. Standard SDK version/build properties are correct and no app-supplied PII was found.

S0 remains blocked because the attempt occurred on the existing founder iPhone and there is no confirmation that the Apple ID had never authorized RunSmart, plus no screenshot. Founder traffic remains excluded from activation cohorts.

### Production evidence
- Public physical session: `2026-07-21T07:27:24Z` to `07:29:10Z`, 1.1.1 (25), non-emulator/non-TestFlight/non-sideloaded.
- `sign_in_completed` at `07:27:35.933Z`, method Apple, screen sign-in wall; zero failures.
- `onboarding_completed` once; HealthKit sync completed.
- `plan_generation_started` once; `plan_generated` once; `plan_generation_succeeded` once in 8294 ms; zero failed terminals.
- `first_run_cta_viewed` and `first_workout_viewed` present.

### Findings / bounded follow-up
- Unprefixed `app_version/app_build` are absent on the public unauthenticated path while SDK `$app_version/$app_build` remain correct. Earlier authenticated sideload traffic carried both; re-register after reset is the leading repair boundary.
- `onboarding_started` fired twice in one session/person despite the release guard.
- Notification permission emitted request x2 and both denied/granted 39 ms apart. Static inspection found concurrent `PushService.requestAuthorization()` callers can both observe `.notDetermined`; serialize one in-flight request and emit one terminal outcome.
- No code or production state changed in this diagnostic session.

## 2026-07-21 - Public 1.1.1 (25) S0 verification blocked at Apple ID eligibility

### Task Summary
Prepared the controlled first-time Sign in with Apple S0 observation against the public App Store build. Confirmed public 1.1.1, physical bundle version 25, two reachable physical devices, and PostHog project 171597. Stopped before install or sign-in because the clean candidate's Apple Account authorization list could not be inspected from this environment.

### Evidence
- Apple US and IL public lookup: version 1.1.1, release `2026-07-20T20:38:19Z`.
- Physical device inventory: iPhone 13 / iOS 26.5.2 has 1.1.1 (25); iPhone 13 Pro / iOS 18.6 has no RunSmart app.
- PostHog privacy-minimized query: no RunSmart 1.1.1 (25) `sign_in_completed`, `sign_in_failed`, or target activation rows after release. Other-product rows in the shared project were excluded.
- Report: `docs/qa/reports/release-1.1.1-build25-s0-device-test-2026-07-21.md`.

### Blocked / not done
- Apple ID never-authorized eligibility was not confirmed; sign-in taps = 0.
- No screenshot, onboarding, HealthKit, plan generation, S6, S1 retry, or first-run evidence.
- No production, ASC, backend, analytics, dependency, deploy, upload, or submission changes.

## 2026-07-21 - 1.1.2 held for weekly release cadence

### Decision
- Founder set a one-App-Store-submission-per-week cadence; 1.1.1 became Ready for Distribution on 2026-07-20.
- Do not submit 1.1.2 on 2026-07-21 solely to accelerate telemetry verification.

### App Store Connect evidence
- Public RunSmart 1.1.1 is `Ready for Distribution`.
- TestFlight lists `Version 1.1.2`, confirming build 26 finished upload/processing sufficiently to appear.
- No 1.1.2 App Store version was created, attached, or submitted in this session.

### Next
- Keep build 26 as the next weekly candidate, subject to deliberate scope review.
- Once the weekly release is public, run an excluded physical App Store session and verify the three repaired event shapes in PostHog.

## 2026-07-21 - 1.1.2 (26) merged, archived, and uploaded

### Review and merge
- PR #110 merged to `main` as `d72aa6d`.
- Local code review: no blocking finding.
- GitGuardian passed. CodeRabbit was rate-limited and supplied no review.
- Fresh release-tree suite: 320 passed, 0 failed, 0 skipped.

### Archive and upload
- Exact merged commit asserted before archive.
- Archive: `/tmp/runsmart-archives/RunSmart-1.1.2-build26-20260721.xcarchive` — succeeded.
- App and extension both 1.1.2 (26); bundle identifier correct; analytics configuration present; signatures and dSYMs verified.
- App Store Connect upload succeeded at `2026-07-21T08:59:13Z`; package processing began.

### Blocked / next
Superseded later the same day: the founder authenticated, confirmed 1.1.1 is Ready for Distribution, and chose to hold 1.1.2 for the next weekly release rather than submit daily. Post-live excluded physical verification remains gated on a public binary containing the repair.


## 2026-07-21 - S0 passed; bounded clean-install telemetry repair

### Outcome
Founder confirmed the Apple ID used for the public 1.1.1 (25) attempt had never authorized RunSmart. The matching physical App Store session has one successful sign-in and no failure, so S0 is PASS. Founder traffic remains excluded from activation cohorts, and no screenshot was supplied.

### Repair
- Re-register build-only super properties immediately after analytics identity reset.
- Keep `onboarding_started` dedupe intact across authentication resets; a distinct sign-in-wall tap begins a new onboarding lifecycle.
- Serialize notification authorization through one in-flight task so concurrent callers share one prompt result and analytics terminal.
- Added four regression tests covering the three public-session defects.

### Validation
- Red phase: new tests failed to compile against the old interfaces at the intended reset and notification seams.
- Post-fix `build-for-testing`: passed.
- Focused telemetry regressions: **4 passed / 0 failed**.
- Full iOS suite: **320 passed / 0 failed / 0 skipped**, xcresult-verified on iPhone SE (3rd generation) / iOS 26.5 Simulator.
- `git diff --check`: passed.
- Release candidate bumped across all targets to **1.1.2 (26)**; release notes updated.
- Fresh 1.1.2 release-tree rerun: **320 passed / 0 failed / 0 skipped**, xcresult `/tmp/runsmart-112-telemetry-tests-20260721.xcresult`.

### Not done
No production configuration, event names, backend, dependency, App Store metadata, deployment, upload, submission, S2, or E1 work. S6 empty-goal and S1 plan-failure/retry physical evidence remain open.

## 2026-07-20 - 1.1.1 (25) archived and submitted to App Store Connect

### Task Summary
Founder archived from the primary checkout (branch switched to `main` at `c7849c0`, Any iOS Device destination) and submitted build 25 to App Store Connect. Awaiting Apple App Review. Live App Store build remains 1.1.0 (24) until approval.

### Release notes submitted to ASC
"Improved analytics and stability behind the scenes to help us better understand and fix account sign-in issues. No user-facing changes."

### Preconditions verified this session before submission
- Full suite 317/317 on the PR commit, confirmed identical (no `.swift`/`.pbxproj`/`.plist`/`.entitlements` diff) to what shipped.
- PostHog super property confirmed landing on physical hardware (see WP-51 device verification entry below).
- Built `Info.plist` matched expected `1.1.1`/`25`/`RUNSMART_ADAPTIVE_COACH_ENABLED=YES` on the pre-archive test build.

### Ordering note
The session packet's original order gated ASC submission on S0 passing first. The founder chose to submit ahead of S0. Not a deviation to flag as a problem — just recording that the sequence differs from the packet as written, since a future session reading `tasks/progress.md` chronologically should not assume S0 passed before this submission.

### Not done
S0 (never-authorized Apple ID test), S6/S1 device evidence. Both remain the next actions once 1.1.1 is live, or sooner if the founder wants to run S0 against a still-available prior build.

---

## 2026-07-20 - WP-51 device verification (packet step 2 CLOSED), 1.1.1 archive-ready

### Task Summary
Founder connected a physical device mid-session, which made packet step 2 executable. Built `origin/main` (`9bc2e29`) to an iPhone 13 / iOS 26.5.2 and confirmed the WP-51 super properties land on real hardware. Steps 3, 4, 5 remain founder-only.

### Evidence
Launched 11:36:39 UTC. PostHog 171597, events 11:36:47-53 UTC, `os_version=26.5.2` / `iPhone14,5` (distinguishes device traffic from the three pre-existing simulator runs at 09:58-10:03 on OS 26.5):

| event | app_version | app_build | source path |
|---|---|---|---|
| `$screen` | 1.1.1 | 25 | autocapture |
| `app_launched` | 1.1.1 | 25 | `track()` wrapper |
| `Application Opened` | 1.1.1 | 25 | autocapture |
| `adaptive_coach_shown` | 1.1.1 | 25 | direct `PostHogSDK.capture` |

12 of 13 events tagged. This is stronger than the unit tests: it exercises all three event sources the PR's design note argued super properties were required for, which no host-app-free test could reach.

### New finding: install/update events cannot carry build identity
`Application Installed` (7/7 untagged over 2 days) and `Application Updated` (5/5 untagged, including this session) fire inside `PostHogSDK.shared.setup(config)`, which returns before the `register()` call on the following lines. Not a WP-51 regression and not a release blocker, but **install counts cannot be split by build** — which matters to the activation-cliff work, whose whole subject is new installs producing zero events. `register()` before `setup()` is a documented no-op, so the fix is either capturing those events manually after registration or splitting installs by first-seen `app_launched`. Logged as a follow-up, not fixed.

### Environment trap (cost a build, would have caused a false negative)
The first device build produced an app with an **empty** `POSTHOG_API_KEY`. `RunSmartConfig.xcconfig` commits it empty and pulls the real value from `#include? "RunSmartSecrets.xcconfig"`, which is gitignored and therefore absent from this fresh worktree. That build would have initialized no analytics at all and emitted nothing — indistinguishable from "the super property does not work." Caught by inspecting the built `Info.plist` for a resolved key before launching, rather than launching and trusting an empty PostHog result. Build was killed, the secrets file copied from the primary checkout, and the build redone.

### Release readiness for step 5
`git diff 5d3942e origin/main` touches no `.swift`, `.pbxproj`, `.plist`, or `.entitlements` file — docs and task memory only. The **317/317** suite result therefore applies to `main`'s binary unchanged. Built `Info.plist` verified: `CFBundleShortVersionString=1.1.1`, `CFBundleVersion=25`, `RUNSMART_ADAPTIVE_COACH_ENABLED=YES`.

### Also noted
The auto Stop hook date-stamped a **historical** 1.0.9-era entry in `tasks/progress.md` (`Last Updated: 2026-07-15` → `2026-07-20`) rather than the current one. Reverted. The hook appears to stamp the last matching line in the file, which lands in an archived section now that entries are prepended.

### Not done
Packet steps 3 (S0), 4 (S6/S1 device evidence), 5 (archive + ASC submit). The device now carries a **Debug** build, so S0 requires deleting it and reinstalling the live App Store build first.

---

## 2026-07-20 - WP-51 merge + stale PR triage (consolidated session packet)

### Task Summary
Executed the Agentic OS session packet `2026-07-20-runsmart-session.md`. Completed step 1 (review + merge PR #105) and step 6 (triage three stale PRs). Steps 2-5 are device- and founder-gated and were not performed: no physical device, no never-authorized Apple ID, no ASC access from this environment.

### What was verified, not assumed
- **Store version:** Apple lookup API returns `1.1.0`, released `2026-07-19T21:48:08Z`. Matches the packet. Per ERRORS.md, never stated from memory.
- **Release-blocker rationale:** queried PostHog 171597 directly rather than trusting the PR body. **8 of 3,828 events (0.2%)** carried `app_version` over 60 days; the PR cited 2 of 3,813. Same conclusion, drift explained by the moving window.
- **Test evidence:** ran both sides. `main` = 313/313. PR commit `5d3942e` = **317/317**, with all four new WP-51 tests confirmed present *by name* in the xcresult bundle.

### The false green (important)
The first suite run reported a clean 313/313 and looked like a pass. It was not testing the PR. `git checkout claude/wp51-app-version-super-property` had failed silently inside the worktree — that branch was already checked out in the primary worktree at `/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app` — so the run tested `main` at `18b8764`. The `&&`/`||` chain swallowed it and the build proceeded normally.

It was caught only because the xcresult total (313) contradicted the PR's claimed 317, and because grepping the bundle for the four new test names returned nothing. Re-run on a detached checkout of `5d3942e` gave the real 317/317.

Silver lining: the accidental run independently corroborates the PR's "313 baseline" figure, so both sides of `313 + 4 = 317` are now verified rather than asserted.

### Files changed
- Merged via PR #105 (`5aafffc`): `AnalyticsService.swift` (`buildIdentityProperties`, `PostHogSDK.register` after `setup`), `AnalyticsEvents.swift` (`didTrackOnboardingStart` guard, cleared by `resetUser()`), `RunSmartReadinessTests.swift` (+4 tests).
- PR #106 (new, docs only): 15 files salvaged from #96 and #87.
- `tasks/progress.md`, `tasks/todo.md`, `tasks/session-log.md`, `tasks/lessons.md`.

### Code review notes on #105
- `didTrackOnboardingStart` is an unsynchronized `static var`, but the project is Swift 5 language mode and both call sites (`OnboardingView.onAppear`, `RunSmartLiteAppShell.onChange`) are SwiftUI modifiers on the main thread. Safe in practice.
- The guard is process-lifetime, not persisted, so `testOnboardingStartedFiresOncePerUser` proves once-per-*process*. A mid-onboarding relaunch would still re-fire. Fixes the observed bug (two fires 108s apart in one session); logged as non-blocking follow-up.
- `register()` correctly placed after `setup(config)` — it is a no-op before the SDK is configured.

### Stale PR triage
All three carried a snapshot of `tasks/progress.md` frozen at 1.0.9-era state (2026-07-16). #87's *only* merge conflict against `main` was that file. Merging #96 or #87 as-is would have silently reverted the live 1.1.0/1.1.1 state file — a hazard the packet did not flag.

- **#96** closed, evidence report salvaged into #106. Version superseded, but the report records the E1 BLOCKED verdict and the `run_completed`-without-`run_started` HealthKit finding.
- **#87** closed, audit + 12 screenshots + upgrade plan salvaged into #106. FTUX track is still live (S6/S1 open), so it remains the reference doc.
- **#97** closed as parked. Adaptive Phase 2 is deferred by the packet's own constraints; the draft was 24 commits behind and touched `project.pbxproj`. Branch `codex/runsmart-adaptive-preview` is intact.

### Not done
Packet steps 2, 3, 4, 5 in full — no device verification that `app_version` lands on a live event, no S0 with a never-authorized Apple ID, no S6/S1 device evidence, no archive, no ASC upload or submission. No edge-function deploy. No new SPM dependencies.

---

## 2026-07-20 - WP-47 S1: instrument the sign-in wall, fix the plan-generation double-fire (1.1.1)

### Task Summary
Executed S1 of the activation-cliff plan as the first content of 1.1.1: made the sign-in wall measurable (`sign_in_wall_viewed` / `_tapped` / `_abandoned` with explicit screen names and error metadata) and fixed the `plan_generation_failed`/`succeeded` double-fire. Analysis-to-code only; no device, archive, ASC, or edge-function state changed.

### Files changed
- `IOS RunSmart app/Services/Analytics/SignInWallTracker.swift` (new) - session-scoped viewed/tapped/abandoned state machine, injectable clock.
- `IOS RunSmart app/Services/Analytics/AnalyticsEvents.swift` - three wall events; `screen` on `sign_in_completed`/`sign_in_failed`.
- `IOS RunSmart app/Features/Auth/SignInView.swift` - `onAppear`, tap, and `scenePhase == .background` wiring.
- `IOS RunSmart app/Services/PlanGenerationStore.swift` - terminal analytics events now matched to an observed start.
- `IOS RunSmart appTests/RunSmartReadinessTests.swift` - 7 new tests.
- `IOS RunSmart app.xcodeproj/project.pbxproj` - 1.1.0 (24) -> 1.1.1 (25).

### Evidence
- Full suite: **313 passed / 0 failed / 0 skipped**, iPhone 17 / iOS 26.5, `-derivedDataPath /private/tmp/rs-dd-wp47`. Count read from the xcresult bundle (`xcrun xcresulttool get test-results summary --path /private/tmp/rs-wp47.xcresult`), not pipe output. 306 baseline + 7 new.
- Non-vacuous check: both double-fire tests were re-run against a temporarily reverted `PlanGenerationStore` and **failed** (exit 65), then passed once the fix was restored.

### Root cause recorded (double-fire)
`PlanGenerationStore` is a UI-state observer that was also the analytics emitter for the generation lifecycle, so every terminal state transition emitted a funnel event. Two terminal notifications arriving back to back (`saveTrainingGoal` posts one per call and is reachable from six call sites) each flipped state and each emitted - hence six failed/succeeded pairs 19ms apart on `0efa0d1b`. Fix: terminal events consume an observed `startedAt`, so the second post of a pair is silent and an unmatched terminal status emits nothing.

### Blocked / handed to founder
- **S0 device test (~20 min, highest value in the portfolio):** reproduce ASAuthorizationError 1000 on a physical iCloud-signed device against the **live App Store build**, not a simulator or local build. Not possible from this environment. Prior attempt is documented as blocked in `docs/qa/reports/release-1.0.9-build23-siwa-device-test-2026-07-19.md`. Until it runs, "unwilling" and "unable" both remain live hypotheses.
- Archive, ASC upload, and submission of 1.1.1: not performed (constraint required explicit approval; none given).

### Not done
- No S2 (value-before-account / guest mode) work - explicitly out of packet scope.
- No Adaptive Coach Phase 2 work - explicitly excluded by the packet.
- No session replay - the plan gates it on privacy guardrails and allows shipping events without it.
- The new events are **unverified in PostHog**: they cannot fire until a build carrying them runs.


## 2026-07-19 - Ship 1.1.0 (24): Adaptive Coach flag ON, archive + ASC upload

### Task Summary
Closed all remaining automated Phase 1 gates and shipped the release build: Claude review + merge of PR #101, Deno sanitizer tests (9/9 after installing Deno 2.9.3), founder flag decision executed (ON for all users), version bump to 1.1.0 (24), full-suite re-verification, PR #102 merge, CLI archive, and successful App Store Connect upload.

### Evidence
- PR #101 merged `e097881`; docs commit `c48decc`; release PR #102 merged `c6e75c1`.
- Flag-ON tree suite: 306/306 (xcresult bundle verified). Deno: 9/9.
- `RunSmart-1.1.0-build24-20260719.xcarchive` ARCHIVE SUCCEEDED; bundle Info.plist flag = YES; ASC upload "Upload succeeded" 12:43.

### Blocked / handed to founder
- `coach_message` deploy: no `SUPABASE_ACCESS_TOKEN` / CLI login on this machine; deploy staged, needs `npx supabase login`. Must precede App Store release since flag ships ON.
- ASC portal: create 1.1.0, attach build 24, submit for review (no ASC API key locally).
- Live-AI device smoke after deploy.

### Not done
- No Plan 3 activation work this session (queued as separate Opus 4.8 session).
- 4 pre-existing untracked iCloud-duplicate QA files left untouched.

## 2026-07-19 - Adaptive Coach physical-device QA and fallback fixes

### Task Summary
Ran the Adaptive Coach Review/confirm/dismiss flow on a physical iPhone using the Debug QA flags. Device QA found and fixed a date-sensitive QA fixture and a contradictory deterministic workout downgrade. No edge function, production flag, archive, or ASC state changed.

### Findings and Fixes
- The QA card was absent on the new local week because the demo fixture had no missed workout, healthy readiness, and no load spike. Adaptive Coach demo QA now supplies deterministic low readiness only when its QA launch flag is active.
- The fallback changed `Intervals · 8 x 400m` to `Easy Run · 8 x 400m`. Easy downgrades now clear hard target pace/structure, use honest easy-effort detail, and map repetition prescriptions to `5.0 km`.

### Device Evidence
- Card rendered with low-recovery trigger and readiness 38.
- Review showed one corrected change with a rationale and safety fallback disclosure.
- Both Confirm New Week and Keep Original Plan were visible.
- Confirm succeeded, showed the updated state, and closed normally.
- Dismiss hid the card and remained persisted after process relaunch; Today loaded normally with the trigger still active.
- A transient black screen occurred only when an automated relaunch met a locked device; unlocked console relaunch had no crash or console error.

### Validation
- Adaptive Coach + Flex Week focused suites: **44 passed, 0 failed**.
- Full fixed-tree suite: **306 passed, 0 failed, 0 skipped**.
- Physical Debug build, install, and repeated launch passed.
- `git diff --check` and plist lint passed.

### Remaining Operational Gates
- GPT-authored fixes require Claude cross-vendor review before merge.
- Deno sanitizer tests remain unrun locally.
- `coach_message` remains undeployed; live AI behavior is not device-smoke-tested.
- Founder still must approve edge deployment and choose the bundled release flag.

## 2026-07-19 - Adaptive Coach Phase 1 merge and release gates

### Task Summary
Merged the FlexWeek duplicate-UUID prerequisite, rebased and verified Adaptive Coach Phase 1, completed cross-vendor review, and merged PR #99 to `main`. No edge function was deployed, no release flag was changed, and no archive or ASC upload was started.

### Validation
- Flag inspection: `RUNSMART_ADAPTIVE_COACH_ENABLED` is read from the bundled Info.plist; only the QA launch argument overrides it. It is not remotely flippable.
- Full reviewed-tree XCTest run: **303 passed, 0 failed, 0 skipped** on iPhone 17 Pro / iOS 26.5.
- `xcodebuild build-for-testing`: passed with DerivedData under `/private/tmp`.
- `git diff --check`: passed.
- `plutil -lint RunSmartInfo.plist RunSmartRunLiveActivityExtension-Info.plist`: both passed.
- Deno sanitizer tests: not run because Deno is not installed locally.
- GPT-5.6 Sol review of Claude Opus 4.8-authored code: no blocking findings. CodeRabbit and GitGuardian passed.

### GitHub
- FlexWeek prerequisite merged and pushed to `main` as `c967d9c`.
- Adaptive Coach PR #99 merged to `main` as `8eef381`.

### Open Gates
- Founder approval is required before deploying `coach_message`; it remains undeployed.
- Founder must choose release flag ON or OFF before archive. Recommendation: OFF until device QA passes.
- Device QA is not complete for Review → diff → confirm or dismiss persistence.
- Version/build bump, archive, ASC upload, and submission have not started.
- Non-blocking review debt: two Swift actor-isolation warnings in `TrainingLoadCalculator` method references.

## 2026-07-15 - 1.0.9 post-live activation documentation

### Task Summary
Created an executable documentation-only post-approval verification package. No Swift, project, plist, signing, version/build, dependency, ASC, or PostHog configuration changed.

### Evidence
- PR review caught and corrected a headline-numerator bug: D7 activation now counts any qualifying `run_completed`, while the eight-step ordered completion remains a separate diagnostic.
- Incremental review required explicit false production-device flags, bounded lifetime exclusions at `snapshot_end`, named `plan_generation_succeeded` as the E1 lifecycle terminal, and aligned task wording with the direct numerator.
- Code-verified proposed WP-43/WP-45 events/properties against `main`.
- Read-only PostHog inspection confirmed pre-live build-23 QA telemetry is mechanics-only.
- Dashboard inspection confirmed rolling operational windows differ from mature D7.
- Live HogQL validation established `windowFunnel` with a `DateTime` cast. The final corrected frozen-snapshot query executed successfully after the review fixes. The rejected `sequenceMatch` attempt became a future query rule in `tasks/lessons.md`.
- Property-query validation caught and removed a full `$set` selection; the published query selects only nested `onboarding_completed_at` to avoid enriched system/geographic fields.

### Deliverable
- `docs/qa/reports/release-1.0.9-build23-post-live-activation-verification.md`
- PR #95 from `codex/docs-1.0.9-activation-read` into `main`.

### Not Done
- Did not start E1, alter release/analytics state, or draw conclusions from QA rows.

## 2026-07-13 - Public 1.0.8 (22) live smoke evidence

### Task Summary
Installed the public App Store binary on a paired physical iPhone and recorded evidence only for HealthKit state, Today data, run entry, a short run, finish confirmation, and completion. No product code or feature was changed.

### Validation
- CoreDevice inventory confirmed `com.runsmart.lite`, version `1.0.8`, build `22`.
- Today showed Apple Health attribution, 1.8k steps, 46 active kcal, and honest missing sleep.
- Profile showed HealthKit connected; the detail screen named HealthKit, explained read/write behavior, and listed enabled data categories.
- Run entry showed GPS ready / Free Run / Start Run.
- A 1:41 short activity recorded, presented the two-path short-run finish alert, and saved as review-only with honest insufficient-analysis copy.
- Evidence: `docs/qa/reports/release-1.0.8-build22-public-smoke-2026-07-13.md`.

### Not Observed
- True fresh-account HealthKit onboarding and true first-run-user CTA state. Reinstall restored the existing signed-in account and prior history; no destructive account reset was performed.

---

## 2026-07-12 - RunSmart 1.0.8 (22) release tracking commit

### Task Summary
Committed version bump, release notes, QA closeout docs, and task-memory update after founder archived **1.0.8 (22)** from Xcode Organizer. Build is **waiting for App Store Connect / App Review**.

### Changes
- `MARKETING_VERSION` 1.0.7 → 1.0.8, `CURRENT_PROJECT_VERSION` 21 → 22 (all targets).
- Release notes + handoff + WP-40 S3/S4 device closeout reports.
- Task status: archived, awaiting review.

### Not Done
- TestFlight smoke on processed ASC build.
- WP-42 re-read on clean 1.0.8 user cohort.

---

## 2026-07-12 - WP-40 S3 device closeout + S4 post-merge re-read

### Task Summary
Closed the remaining WP-40 verification gap with founder physical-device QA on a cable-connected iPhone 13. Today Apple Health value surfacing was captured; PostHog build-21 funnel was re-read after PR #84 merge.

### Validation
- **S3 Today (PASS):** Today tab shows **Today's activity** with **Apple Health** attribution — Steps **1.8k**, Active kcal **46**, Sleep `--` (no sleep sample in HealthKit window; not blocking).
- Evidence saved: `docs/qa/reports/assets-2026-07-12-wp40-s3/wp40-s3-today-apple-health-card.png`.
- **S3 Recovery path:** Profile → Wellness Trends → Readiness should show `"Recovery data synced from Apple Health."` when Garmin is not the recovery source (optional screenshot).
- **S4 re-read:** PostHog 171597, 2026-07-11→12 — raw `healthkit_sync_completed` ×3 on build 21; ordered funnel n=1 not decision-grade; WP-42 clean cohort still 0.
- Closeout report: `docs/qa/reports/wp40-s3-s4-device-closeout-2026-07-12.md`.

### Not Done
- Optional Recovery wellness screenshot.
- S2 periodic background HealthKit re-sync (founder product decision).
- WP-42 decision-grade funnel (needs ≥10 clean native disclosure viewers).

---

## 2026-07-10 - WP-40 S1 Apple Health primary-flow activation

### Task Summary
Executed only WP-40 S1 on the existing `claude/wp40-healthkit-activation` branch. Preserved partial uncommitted WP-40 files found at session start, completed the onboarding HealthKit connection boundary, and did not expand the pre-existing S2 auto-sync edits.

### Changes
- Added a skippable Apple Health step before the Ready step in onboarding.
- Reused the existing HealthKit provider connect route and existing analytics events.
- Added connected-state policy coverage plus stable Connect/Skip accessibility identifiers.
- Kept Skip available only while HealthKit is not already connected.
- Added a focused S1 simulator QA report.

### Validation
- TDD red: focused test failed because `OnboardingHealthKitStep` did not exist.
- TDD green: `testOnboardingHealthKitStepUsesExistingProviderAndRequiresConnectedState` passed (1/1).
- iPhone 17 Debug simulator build passed.
- Onboarding replay exposed Connect and Skip; Skip reached Ready; Connect used the real HealthKit route and advanced on the already-authorized simulator.
- Preserved system Health Access sheet evidence: `docs/qa/reports/wp40-18-after-wait.png`.
- `git diff --check` passed.

### Not Done
- S2 auto-import, S3 value surfacing, and S4 production PostHog verification were not completed.
- No commit, push, or PR was requested or created.
- Physical-device HealthKit QA remains required.

---

## 2026-07-02 - WP-27 Garmin Data Trust Audit

### Task Summary
Started WP-27 after confirming PR #71 was mislabeled as WP-26 but is canonically WP-27 founder-run evidence work still blocked on live screenshots. Audited Garmin labels and source attribution across Today routes, Activity/Report, Run Report, Recovery dashboard, Wellness Trends, Morning Check-In, and Profile connected surfaces.

### Changes
- Added `RecoverySnapshot.includesGarminDeviceSourcedData` so UI attribution can distinguish Garmin-backed recovery from HealthKit/manual fallback.
- Marked Supabase Garmin recovery snapshots as Garmin device-sourced.
- Gated Recovery dashboard, Wellness Trends, and Morning Check-In Garmin attribution/derived-data footers on actual Garmin-backed data.
- Normalized cached Garmin device names through `RunSmartAttribution.garminDeviceLabel(...)` so bare model names render as `Garmin [device model]`.
- Added focused tests for bare connected-device fallback labels and recovery provenance defaults.
- Added `docs/qa/wp27-garmin-data-trust-audit.md`.
- Renamed the Gate-4 evidence recapture runbook to `docs/qa/wp27-garmin-gate4-evidence-recapture.md`.
- Replaced the misleading local WP-25 Garmin track spec with an Agentic OS pointer.
- Replaced the local Garmin Connect tile JPEG derivative with Garmin's official iOS tile PDF from the public brand page.

### Validation
- `git diff --check` passed.
- App-source search found no `Garmin Wellness` / `garminWellness` strings.
- Full `xcodebuild test` passed on `iPhone 17 Pro, OS=26.5` with `-parallel-testing-enabled NO`: 234 XCTest tests and 3 Swift Testing tests passed.
- Confirmed `testBareConnectedGarminDeviceFallbackGetsBrandPrefix` and `testRecoverySnapshotDefaultsToNonGarminUntilExplicitlyMarked` executed and passed.
- Earlier iPhone 17 full-suite attempt built and launched but stalled before test-case output; interrupted after 224.522 seconds and retried on iPhone 17 Pro.
- Known warning remains: `HealthKitSyncService.swift` uses deprecated `HKWorkout` initializer.

---

## 2026-07-02 - WP-27 Garmin Gate-4 evidence recapture

### Task Summary
Implemented what was initially mislabeled WP-26 as a founder-run Garmin Gate-4 evidence recapture package; this is canonically WP-27. Added a dedicated QA runbook with source requirements, screenshot matrix, pass/fail criteria, local Garmin Connect tile metadata, evidence manifest, stop conditions, and a reply draft for tickets `213145` / `213165`.

### Changes
- Added `docs/qa/wp27-garmin-gate4-evidence-recapture.md`.
- Updated `docs/specs/wp25-garmin-track.md` to point at canonical Agentic OS work-packet specs.
- Updated canonical task state in `tasks/todo.md`.

### Validation
- Checked current local Garmin Connect tile metadata: JPEG, 512x512, SHA-256 `4df876736f980433a7f3e634a2209d383aa72c139851affa2f5013a38071d1f2`.
- Static search found no `Garmin Wellness` or `garminWellness` strings in app source.
- No app code, build number, App Store Connect state, Garmin credentials, or Garmin ticket state changed.

### Founder-only next steps
- Install or confirm `1.0.7 (20)` on a real device.
- Recapture all six Gate-4 screenshots.
- Garmin Connect tile asset is now official/pristine in repo; founder still needs to verify screenshots use it correctly.
- Verify against the Garmin brand PDF, then decide whether to ask Marc to clarify "start all over" or send the corrected evidence package.

---

## 2026-07-02 - Superseded local Garmin track initiation

### Task Summary
Initiated a local Garmin track artifact after WP-24 was paused. This was later superseded because canonical Garmin work-packet specs live in Agentic OS executive-os/work-packets/WP-25 through WP-28, and this repo does not own WP-25 or WP-26.

### Decisions
- Treat this repo's old WP-25 artifact as a pointer only.
- Keep Garmin Gate-4 evidence recapture in WP-27, separate from founder-only WP-26 Developer Portal application work.
- Preserve WP-24 paused state and do not mix its scope into Garmin track work.

### Next Recommended Story
WP-27 founder next step: install/verify `1.0.7 (20)` on a real device, recapture all required Gate-4 screenshots, verify them against Garmin's brand PDF, and prepare the ticket reply package.

---

## 2026-06-30 - WP-20 first-run activation + Garmin attribution (PR #67)

### Task Summary
Executed Agentic OS WP-20 on branch `codex/garmin-attribution-fallback` (PR #67). Combined the existing Garmin Report/Activity `device_name` fallback with the smallest rs-onboarding-001 activation intervention for a single ASC-ready `1.0.6 (19)` build.

### Changes
- Garmin attribution fallback (already on branch): activity rows prefer `sourceDeviceName`, then connected Garmin `deviceName`, across Report/Activity/Run Report surfaces.
- Addressed CodeRabbit Garmin attribution feedback: connected-status-only fallback and automatic `Garmin` prefix for bare model names.
- Default Smart return reminders ON in `OnboardingProfile.empty` and new-user profile load fallback.
- Added `FirstRunActivationSheet` after successful plan save: Start Now routes to Run; Remind Me Tomorrow enables notifications and schedules a local 7am next-day reminder.
- Added analytics: `first_run_cta_viewed`, `first_run_cta_tapped`, `first_run_reminder_scheduled`; existing `plan_run_cta_tapped` also fires from onboarding start-now.
- Added `AppStoreReviewPrompt` after first `run_completed` (one-time, positive moment only).
- Bumped `CURRENT_PROJECT_VERSION` to `19` and `MARKETING_VERSION` to `1.0.6`.

### Validation
- `git diff --check` passed.
- Simulator `xcodebuild build` succeeded (`/tmp/RunSmartDerivedData-WP20`).
- Focused XCTests passed on iPhone 17 simulator: onboarding default reminders, disabled reminder plan, enabled reminder plan, first-run reminder schedule shape.
- After CodeRabbit fixes, focused Garmin attribution XCTests passed on iPhone 17 simulator: activity device precedence, connected fallback, bare model brand-prefix normalization, and non-Garmin preservation.
- Generic simulator build after CodeRabbit fixes hung in local Xcode build operations after existing HealthKit deprecation warnings and was interrupted.

### Founder-only next steps
- Merge PR #67 into `main`.
- Archive/export `1.0.6 (19)` and upload to App Store Connect.
- After live confirmation, recapture all 6 Garmin Gate-4 screenshots and send Garmin reply.

### Follow-up metric
Watch `plan_generated -> first_run_cta_viewed -> first_run_cta_tapped -> run_started -> run_completed` and `first_run_reminder_scheduled` in the next usable cohort.

---

## 2026-06-24 - WP-15 RunSmart plan-to-run activation diagnostic

### Task Summary
Diagnosed the reported activation cliff where PostHog showed roughly 30% `plan_generated` but 0/10 D7 `run_completed`. The app had the right core analytics events, but the first post-plan Today surface could show an upcoming generated workout as `upNext` with an Ask Coach primary action instead of a run-start action.

### Event Map
- `app_launched`: emitted during app shell analytics setup.
- `onboarding_started`, `onboarding_step_completed`, `onboarding_completed`: emitted from onboarding flow.
- `plan_generated`: emitted after training plan persistence completes.
- `plan_viewed`, `plan_workout_tapped`: emitted from Plan tab viewing/detail entry, not a direct run start signal.
- `plan_run_cta_tapped`: added as the bridge event when Today starts a planned or upcoming generated workout.
- `run_started`: emitted when the Run screen start action is tapped, before GPS recording fully proves a completed run.
- `run_completed`, `first_run_completed`: emitted from shared completed-activity processing with dedupe.
- `run_abandoned`: emitted when an in-progress run is discarded.

### Changes
- Today `upNext` generated workouts now show a Start Next Run CTA and route into the Run flow.
- Added `plan_run_cta_tapped` with source, workout type, scheduled-today, and prior-run properties.
- Added focused readiness tests for the upcoming-plan CTA behavior and the new bridge analytics event.

### Validation
- `git diff --check` passed.
- Focused `xcodebuild test` compiled the app and test bundle, then stalled in CoreSimulator test worker materialization before XCTest methods executed.
- Focused `xcodebuild test-without-building` hit the same runner stall on an explicit iPhone 17 Pro simulator.
- Compile-only simulator build passed with signing disabled.

### Follow-up
Watch the next usable cohort for `plan_generated -> plan_run_cta_tapped -> run_started -> run_completed`. Success threshold: at least 20% plan-to-run conversion among users whose generated plan is available and whose first workout is visible in Today.

---

## 2026-06-24 - WP-14 RunSmart status + Garmin reply reconciliation

### Task Summary
Reconciled RunSmart live-vs-blocked status contradiction (EXD-014). App is LIVE on App Store as v1.0.3 (build 16) since 2026-06-19; v1.0.4 (build 17) submitted 2026-06-24 awaiting Apple approval.

### Evidence Used
- `tasks/progress.md` Status line (founder submission 2026-06-24)
- `docs/research/apple-garmin-developer-trends.md` (live since 2026-06-19, v1.0.3 build 16)
- `tasks/error-sweep-2026-06-19.md` (live App Store build v1.0.3 build 16)
- Agentic OS `dashboard/status.json` groundTruth: App Store state LIVE, PostHog 12 users/7d

### Changes
- Updated `tasks/progress.md` Current Phase to LIVE + precise Gate-4 gate language (removed "resubmission"/prelaunch tokens that triggered false contradiction).

### Garmin Reply Decision
**Still blocked.** Exact blocker: v1.0.4 (build 17) not yet approved/live; Gate-4 evidence package requires that build. Do not send until Apple approves and live build matches submitted screenshots.

### Validation
- `./agentic-os morning` completed 2026-06-24: `contradictionCount` 0, `portfolioTrust` trustworthy; DASHBOARD.md and PROJECT-STATUS.md show no RunSmart live-vs-blocked contradiction.

---

## 2026-06-24 - WP-15 Garmin Wellness entry point (PR #61)

### Task Summary
Executed `15-WP-WIRE-UP-GARMIN-WELLNESS-ENTRY-POINT.md`. Garmin Wellness was implemented but only reachable via DEBUG screenshot-mode launch args; added a real Profile → Connected tile.

### Changes
- `ProfileTabView.swift`: Garmin Wellness `ConnectedServiceTile` after Garmin Connect; `isGarminConnected` status gating.
- RunSmart docs: `GARMIN-STATUS.md`, `13-GATE-4-v1.0.4-build17-VERIFICATION-FINDINGS.md`.

### Validation
- PR #61 merged to `main` (`30d9914`); CodeRabbit + GitGuardian passed.
- Debug simulator build passed; demo-mode smoke: Profile tile visible, tap opens Garmin Wellness sheet.

### Remaining
- Founder TestFlight/device tap-through with real Garmin account.

---

## 2026-06-17 - Analytics Coverage QA run-funnel fix

### Task Summary
Root-caused the missing `run_started` / `run_completed` / `first_run_completed`
coverage from supplied live PostHog evidence for project 171597. The app had
typed run events, but `run_completed` only fired from the Run tab GPS UI
finish button. Garmin and HealthKit completed activities already flowed through
`processCompletedActivity(_:)`, so imports and service-side completion work
could update training history without emitting the activation event.

### Changes
- Added `Analytics.trackCompletedRunIfNeeded` with per-run dedupe and one-time
  `first_run_completed` behavior.
- Moved completion analytics to `processCompletedActivity(_:)` in both
  Supabase-backed and local production services.
- Removed the earlier UI-only `run_completed` call from `RunTabView.finishRun()`
  to avoid double-counting GPS runs.
- Documented custom `app_launched` as the canonical launch event; PostHog iOS
  lifecycle events remain diagnostic only.
- Added focused XCTest coverage for completed-run analytics dedupe and
  first-run emission.

### Validation
- `git diff --check` passed.
- Focused XCTest passed for
  `RunSmartReadinessTests/testCompletedRunAnalyticsFiresOnceAndMarksFirstRunOnce`.
- Release generic iOS build passed with signing disabled.
- Existing warning remains: `HealthKitSyncService.swift` uses a deprecated
  `HKWorkout` initializer.
- Live physical-device PostHog confirmation was not run in this session.

### Follow-up
Run a real-device QA pass against PostHog project 171597: sign up, complete
onboarding, generate a plan, start and complete a run, then verify
`app_launched`, `sign_in_completed`, identify, `run_started`, `run_completed`,
and one-time `first_run_completed` in live events.

## 2026-06-14 - Build 14 simulator smoke and App Store handoff check

### Task Summary
Checked RunSmart 1.0.2 build 14 before App Store resubmission, including the
Apple review-critical account deletion/register-again path. The app repo was
clean on `main` at `11bf497`; source version/build remained `1.0.2 (14)`.

### Validation
- Fresh install reset: uninstalled `com.runsmart.lite` from the iPhone 17 Pro
  simulator before installing the current build.
- The first XcodeBuildMCP build/run attempt timed out, but a direct simulator
  `xcodebuild` with a fresh DerivedData path completed with `** BUILD SUCCEEDED **`.
- Simulator install and launch succeeded for `com.runsmart.lite`.
- Fresh sign-in UI showed the RunSmart sign-in screen, Sign in with Apple, and
  visible HealthKit disclosure: "HealthKit reads approved data and can save
  completed GPS runs".
- Tapping Sign in with Apple failed locally with
  `com.apple.AuthenticationServices.AuthorizationError error 1000`; therefore
  live onboarding, delete account, and register-again smoke were not reachable.
- Static scan found no active name/email onboarding text-field call sites.
- Static inspection confirmed SIWA requests `.fullName` and `.email`; account
  deletion calls the `delete_account` Edge Function, clears local session/user
  data, and resets onboarding aha moments.
- Existing build 14 App Store archive/export inspection passed: bundle id
  `com.runsmart.lite`, display name `RunSmart`, version `1.0.2`, build `14`,
  encryption flag `false`, dSYM present, Apple Distribution signing, SIWA,
  associated domains, HealthKit, and `get-task-allow=false`.
- `git diff --check` passed after task-memory cleanup.
- No untracked Swift source exists under active app or test roots.

### Result
Not ready to archive/upload/resubmit yet. The remaining blocker is a real
Apple-auth-capable smoke pass: Sign in with Apple, complete onboarding, delete
account from the app, then Sign in with Apple/register again and confirm
onboarding replays without name/email collection.

## 2026-06-12 - PR #46 backend + build 14 resubmission readiness

### Task Summary
Finished the open code-review blocker follow-up for PR #46 on
`cursor/e7-wearable-depth-trends`: applied the missing production Supabase
identity/RLS/index migrations, verified Garmin gateway `authUserId` propagation
in the web repo, reran local iOS release-readiness gates, and produced a
non-upload App Store export for build 14.

### Files Changed
- `supabase/migrations/20260611120000_garmin_activity_points_rls.sql`
- `supabase/migrations/20260611121000_code_review_performance_indexes.sql`
- `supabase/migrations/20260612100000_runs_auth_user_identity_support.sql`
- `supabase/migrations/20260612101000_drop_duplicate_challenge_auth_index.sql`
- `docs/architecture/technical-risks.md`
- `docs/qa/app-store-readiness-checklist.md`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Backend
- Applied `runs_auth_user_identity_support` to add/backfill
  `runs.auth_user_id` and add the unique
  `(auth_user_id, challenge_id)` challenge enrollment index needed by iOS
  upsert conflict handling.
- Corrected the Garmin route-points RLS migration after production showed
  `garmin_activity_points` is a view, not a table. The view is now
  `security_invoker=true`, with owner RLS enforced on `garmin_activities`.
- Applied the hot-path indexes on `garmin_activities(auth_user_id, activity_id)`,
  `garmin_activities(auth_user_id, start_time desc)`, and
  `runs(auth_user_id, completed_at desc)`.
- Applied cleanup migration to drop the duplicate non-unique challenge
  enrollment auth/challenge index.
- Verified production catalog state through Supabase MCP: the intended column,
  indexes, policies, and security-invoker view option are present.
- Supabase advisors still report broader pre-existing warnings, including
  mutable function search paths, public/security-definer RPC access, multiple
  permissive policies, and older duplicate indexes. The remaining `runs`
  multiple-permissive warning comes from the existing `users_own_runs` policy
  combining with the new owner policies.

### App Store Readiness
- Version/build source state: `MARKETING_VERSION = 1.0.2`,
  `CURRENT_PROJECT_VERSION = 14`.
- Static App Review scans passed: no active untracked Swift source under app or
  test roots; HealthKit entitlement/usage strings present; no CareKit usage was
  found in app Swift/plist/entitlement/project files; no visible onboarding name
  or email text fields found.
- Release archive succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-build14-AppStore.xcarchive" archive`
- Non-upload App Store export succeeded:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-build14-AppStore.xcarchive" -exportPath "build/RunSmart-build14-AppStoreExport" -exportOptionsPlist ExportOptionsAppStore.plist -allowProvisioningUpdates`
- Exported IPA inspection confirmed `build/RunSmart-build14-AppStoreExport/RunSmart.ipa`
  has bundle id `com.runsmart.lite`, version `1.0.2`, build `14`,
  `ITSAppUsesNonExemptEncryption=false`, HealthKit entitlement, Sign in with
  Apple entitlement, associated domains entitlement, `get-task-allow=false`, and
  one dSYM in the archive.
- Xcode emitted an expired App Store Connect session warning during export, but
  the non-upload export still succeeded. Upload/submission were not performed.

### Validation
- `git diff --check` passed.
- Simulator erase/reset passed for iPhone 17 Pro Max simulator
  `66F09A08-D5EE-467D-936D-E1406E5FEE0E`.
- Focused `xcodebuild build-for-testing` passed for
  `RunSmartReadinessTests` and `WellnessTrendMapperTests` using
  `/tmp/runsmart-pr-readiness-focused-dd2`.
- Focused XCTest execution built but stalled at simulator install/launch worker
  materialization and was not counted as passed.
- Release archive/export validation passed for build 14 as described above.
- Web gateway static inspection confirmed Garmin callback/client/service paths
  carry `authUserId` through connection state and activity import.

### Remaining Risks
- `delete_account` and `coach_message` Edge Function deploys were not run from
  this machine because `supabase` CLI and `SUPABASE_ACCESS_TOKEN` are not
  available.
- Live TestFlight smoke still needs SIWA, Garmin connect, run sync, challenge,
  and delete-account coverage before App Store resubmission.
- Build output still includes existing Swift 6 actor-isolation and unused-value
  warnings; they did not block archive/export.

## 2026-06-10 - WP-6 Aha Moments iOS port (build 14)

### Task Summary
Ported four aha moments from `AHA_MOMENTS.md` into native SwiftUI: onboarding
identity + goal timeline overlays (#1/#3), post-run achievement overlay (#2),
and inline noticed card (#4). Wired Supabase `user_aha_moments` + profile insight
columns via `AhaMomentStore`. Bumped `CURRENT_PROJECT_VERSION` to 14 (marketing
1.0.2 unchanged).

### Validation
- `xcodebuild build` (generic iOS Simulator): **BUILD SUCCEEDED**
- `xcodebuild test` (iPhone 17 Pro simulator): **TEST SUCCEEDED** (includes new
  `AhaMomentsTests` — 13 cases)
- Manual simulator walkthrough + live Supabase row verification: **not run** in
  this session (requires signed-in test user)

### Files
- New: `Services/AhaMoments/*`, `Features/AhaMoments/*`, `AhaMomentsTests.swift`
- Modified: `RunSmartLiteAppShell.swift`, `PostRunSummaryView.swift`,
  `AnalyticsEvents.swift`, `project.pbxproj`

---

## 2026-06-09 - RunSmart build 12 distribution export validation

### Task Summary
Continued WP-3 for the June 08 App Review rejection recovery. Verified the
current build 12 source state, reran static App Review gates, produced a fresh
Release archive, exported a non-upload App Store IPA, inspected the upload
artifact provenance/entitlements, and captured available reviewer-device
simulator evidence without submitting to App Store Connect.

### Source State
- Branch: `codex/app-review-rejection-recovery`.
- Source commit: `064e66a`.
- Dirty tree at start: `Resources/Localizable.xcstrings` was already marked
  modified, but `git diff -- Resources/Localizable.xcstrings` showed no content
  diff.
- Version/build source state: `MARKETING_VERSION = 1.0.1` and
  `CURRENT_PROJECT_VERSION = 12`.
- Fastlane check: `fastlane/Fastfile` now logs that the committed build number
  is used; no `increment_build_number` call was found.

### Validation
- `git diff --check` passed.
- Active-source guard passed: no untracked Swift files were found under
  `IOS RunSmart app/` or `IOS RunSmart appTests/`.
- Static SIWA scan passed: no `TextField("Your name"`, `TextField("Email"`,
  or `TextField("Your email"` call site remains in app code.
- Static SIWA implementation scan confirmed `SignInWithAppleButton` requests
  `.fullName` and `.email`, then passes `credential.fullName` and
  `credential.email` into `SupabaseSession.signInWithApple` as internal seeds.
- Static CareKit scan passed across app Swift, plist/entitlement, and project
  files; no app-code CareKit references were found.
- HealthKit source strings remain visible on sign-in, onboarding Privacy,
  Profile Connected, and HealthKit detail surfaces.
- Signing-disabled simulator build passed on iPhone 17 Pro Max:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Debug -destination "platform=iOS Simulator,id=66F09A08-D5EE-467D-936D-E1406E5FEE0E" -derivedDataPath /tmp/runsmart-build12-resubmission-derived CODE_SIGNING_ALLOWED=NO build`

### Archive And Export
- Release archive succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-build12-AppStore.xcarchive" archive`
- Archive inspection confirmed display name `RunSmart`, bundle id
  `com.runsmart.lite`, version `1.0.1`, build `12`, iPhone-only
  `UIDeviceFamily = (1)`, `ITSAppUsesNonExemptEncryption=false`, and dSYM
  present.
- Important signing note: the raw archive app was signed with Apple Development
  and `get-task-allow=true`, so the raw archive app is not the upload-safe
  artifact.
- Non-upload App Store export succeeded:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-build12-AppStore.xcarchive" -exportPath "build/RunSmart-build12-AppStoreExport" -exportOptionsPlist ExportOptionsAppStore.plist -allowProvisioningUpdates`
- Export produced `build/RunSmart-build12-AppStoreExport/RunSmart.ipa`.
- IPA inspection confirmed Apple Distribution signing, display name `RunSmart`,
  bundle id `com.runsmart.lite`, version `1.0.1`, build `12`, iPhone-only
  device family, `ITSAppUsesNonExemptEncryption=false`, HealthKit entitlement,
  Sign in with Apple entitlement, associated domains entitlement, and
  `get-task-allow=false`.

### Reviewer-Device Evidence
- Captured simulator screenshots under
  `/tmp/runsmart-build12-reviewer-evidence-20260609/`.
- iPhone 17 Pro Max screenshots captured at `1320x2868`:
  sign-in HealthKit disclosure and Profile Connected HealthKit row.
- iPad Air 11-inch (M3) screenshots captured at `1640x2360`:
  sign-in HealthKit disclosure and Profile Connected HealthKit row.
- Visual inspection confirmed sign-in screenshots show HealthKit disclosure and
  Sign in with Apple, and Profile screenshots show HealthKit in Connected
  services above the fold.
- Onboarding Privacy and HealthKit detail were verified by static source
  inspection in this session; direct simulator navigation screenshots were not
  captured.

### App Review Response
Use the existing response text in `docs/qa/app-review-notes-2026-05-19.md` and
`docs/qa/app-store-readiness-checklist.md`. It stays scoped to the two actual
rejection fixes: no name/email collection after SIWA, explicit optional
HealthKit read/write disclosure, and no CareKit usage.

### Remaining Risks
- App Store Connect upload, processing, build selection, and resubmission were
  not performed.
- Fresh-account SIWA authentication was not completed manually in this session,
  so no post-auth visual proof was captured.
- HealthKit permission-sheet path and HealthKit detail sheet should still be
  clicked through manually before final resubmission.

## 2026-06-08 - RunSmart build 11 rejection recovery

### Task Summary
Handled the latest App Store rejection for RunSmart 1.0.1 build 11. Apple
rejected the app for requiring name/email after Sign in with Apple and again for
unclear HealthKit/CareKit UI identification. The fix keeps Sign in with Apple
and HealthKit enabled, removes post-auth name collection from onboarding, uses
Apple-provided account values internally when available, preserves explicit
HealthKit disclosure surfaces, and prepares build 12 as the next resubmission
build.

### Apple Review Message
- Submission ID: `63f48069-3f6c-4279-8f7f-447d9d082a10`
- Review date: 2026-06-08
- Review device: iPad Air 11-inch (M3) and iPhone 17 Pro Max
- Version reviewed: `1.0.1 (11)`
- Guideline 4 issue: the app offers Sign in with Apple but requires users to
  provide name and/or email afterward.
- Guideline 2.5.1 issue: the app uses HealthKit or CareKit APIs but does not
  clearly identify the HealthKit/CareKit functionality in the UI.

### Fix
- Removed the `Your name` onboarding field shown after Sign in with Apple.
- Captured `ASAuthorizationAppleIDCredential.fullName` and `email`, then passed
  them into `SupabaseSession` as internal profile seeds.
- Seeded a new user's onboarding profile with Apple-provided display name when
  available; otherwise RunSmart falls back internally to `RunSmart Runner`
  without asking the user for name or email.
- Strengthened visible HealthKit wording on sign-in and Profile surfaces while
  preserving onboarding Privacy and HealthKit detail disclosures.
- Disabled Fastlane build-number auto-increment for `beta` and `release` so the
  committed Xcode project build number, archive, uploaded build, and selected
  App Store Connect build stay traceable.
- Replaced the stale build-5 readiness checklist with a current 1.0.1
  resubmission checklist and reviewer response.
- Bumped the next intended resubmission build to `12`.

### Validation
- Static scan found no `TextField("Your name"` call site in app code.
- Static scan found no app-code CareKit imports or references.
- HealthKit UI strings are present on sign-in, onboarding Privacy, Profile
  Connected, and HealthKit detail surfaces.
- XcodeBuildMCP was configured for project `IOS RunSmart app.xcodeproj`, scheme
  `IOS RunSmart app`, simulator `iPhone 17 Pro Max`; its build call timed out at
  120s while the underlying `xcodebuild` continued.
- Signing-disabled simulator build passed with fresh DerivedData, then passed
  again after the build 12 bump with output showing
  `PROJECT:IOS RunSmart app-12`:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Debug -destination "platform=iOS Simulator,id=66F09A08-D5EE-467D-936D-E1406E5FEE0E" -derivedDataPath /tmp/runsmart-app-review-recovery-derived CODE_SIGNING_ALLOWED=NO build`
- Local Release archive passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-build12-local-validation.xcarchive" archive`
- Local archive inspection confirmed bundle id `com.runsmart.lite`, version
  `1.0.1`, build `12`, `ITSAppUsesNonExemptEncryption=false`, HealthKit usage
  strings, HealthKit entitlement, Sign in with Apple entitlement, and dSYM
  present.
- Local archive signing identity was `Apple Development:
  nadav.yigal@gmail.com (V2D7D57MXR)`, and entitlements showed
  `get-task-allow=true`; this is a compile/archive proof, not an App Store
  distribution artifact.

### Remaining Risks
- Build 11 provenance gap remains: current `main` had build 10 at commit
  `62823e2`, App Review rejected build 11, and no local build 11 archive was
  found during investigation.
- App Store distribution archive/export/upload/resubmission were not performed
  in this session.
- Manual visual QA is still required on iPad Air 11-inch (M3) and iPhone 17 Pro
  Max for SIWA, onboarding Privacy, Profile Connected, and HealthKit detail
  screens.
- Distribution archive inspection must verify build 12, distribution signing,
  `get-task-allow=false`, dSYM, and selected App Store Connect build.

## 2026-06-07 - RunSmart build 9 HealthKit rejection fix

### Task Summary
Handled Apple rejection for RunSmart 1.0.1 build 9. Apple rejected the app on
Guideline 2.5.1 because HealthKit/CareKit functionality was not clearly
identified in the UI. The app uses HealthKit and does not use CareKit, so the
fix keeps HealthKit enabled and makes HealthKit read/write behavior explicit in
visible UI before and during connection.

### Apple Review Message
- Submission ID: `fe1e059b-4eea-46e1-ae4e-980b1b027d84`
- Review date: 2026-06-05
- Review device: iPhone 17 Pro Max and iPad Air 11-inch (M3)
- Version reviewed: `1.0.1 (9)`
- Guideline: 2.5.1 - Performance - Software Requirements
- Issue: the app uses HealthKit or CareKit APIs but does not clearly identify
  HealthKit and CareKit functionality in the UI.

### Fix
- Made HealthKit explicit on sign-in, onboarding privacy, Profile connected
  services, and the HealthKit detail screen.
- Added detail copy stating RunSmart uses HealthKit to read approved workouts,
  routes, heart rate, HRV, sleep, steps, and active energy, and can write
  completed GPS runs to Health when allowed.
- Added analytics events for `healthkit_disclosure_viewed` and
  `healthkit_connect_tapped`.
- Wired existing `plan_generated` analytics to successful generated-plan
  persistence.
- Bumped build number to `10` for the fixed resubmission.

### Validation
- `git diff --check` passed.
- Static scan confirmed HealthKit entitlement and permission strings are present.
- Static scan found no CareKit usage.
- Analytics call-site scan confirmed onboarding, plan generation, run
  completion, HealthKit disclosure, HealthKit connect intent, and HealthKit sync
  completion events.
- Signing-disabled simulator build passed with fresh DerivedData:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-healthkit-resubmission-derived CODE_SIGNING_ALLOWED=NO build`

### Remaining Risks
- Archive/export/upload/resubmission are founder-controlled and not yet done.
- PostHog Live Events must still be verified from a configured production build.
- Visual QA should confirm the updated HealthKit wording is visible on the
  rejected review device classes before resubmission.
- Pre-existing dirty `Localizable.xcstrings` and `tasks/lessons.md` changes were
  preserved.

## 2026-06-05 - RunSmart 1.0.1 build 9 submitted

### Task Summary
Recorded the founder-confirmed App Store Connect submission after the local
release workflow completed.

### Status
- RunSmart 1.0.1 build 9 is Submitted for Review.
- Apple review outcome is pending.
- No approval, rejection, or live-store status is claimed.

### Next Recommended Action
Monitor App Store Connect. If Apple responds, handle the review outcome before
starting new release scope.

## 2026-05-28 - E7 Garmin/Wearable Depth hardening + branch commit

### Task Summary
Completed E7 follow-up on `cursor/e7-wearable-depth-trends`: committed app implementation that was previously only in working tree, hardened Striver empty states, routed trend fetch through `GarminBridge.dailyMetrics` (deduped view + base-table fallback), added sparse-history mapper test, and accessibility labels on trend surfaces.

### Hardening Changes
- Striver Today mini-stats no longer show placeholder sparklines when Garmin trend data is missing.
- Today/Wellness/Recovery trend panels show honest "Need more synced days" copy instead of fake bars.
- Removed duplicate Supabase-only series fetch; `wellnessTrendSeries` now uses `GarminBridge.shared.dailyMetrics`.
- Added `WellnessTrendMapperTests.testSeriesUsesBuildingTrendCopyForSparseHistory`.

### Files Changed
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/Garmin/GarminBridge.swift`
- `IOS RunSmart app/Services/Garmin/GarminMappers.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/StriverPersonaGate.swift` (new)
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Wellness/GarminWellnessViews.swift`
- `IOS RunSmart app/Features/Recovery/RecoveryDashboardView.swift`
- `IOS RunSmart app/PreviewSupport/RunSmartPreviewData.swift`
- `IOS RunSmart appTests/StriverPersonaGateTests.swift` (new)
- `IOS RunSmart appTests/WellnessTrendMapperTests.swift` (new)
- `IOS RunSmart app.xcodeproj/project.pbxproj` (dedupe PostHog package refs)
- `docs/qa/ios-qa-checklist.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Validation
- Generic simulator build passed (`build/DerivedData`, exit 0).
- Focused E7 tests: `StriverPersonaGateTests` (3), `WellnessTrendMapperTests` (4).

### Remaining Risks
- Physical-device Garmin sync QA not run in this session.
- Outer wrapper repo submodule pointer must track this app commit after push.

## 2026-05-28 - E7 Garmin/Wearable Depth (HRV + Readiness 7-day)

### Task Summary
Implemented the E7 wearable-depth slice end-to-end: spec, data model/service plumbing, Striver gating, Today trend wiring, Wellness/Recovery trend surfaces, preview fixtures, focused tests, and QA checklist updates.

### Files Changed
- `docs/specs/e7-garmin-wearable-depth.md` (new)
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/Garmin/GarminBridge.swift`
- `IOS RunSmart app/Services/Garmin/GarminMappers.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/StriverPersonaGate.swift` (new)
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Wellness/GarminWellnessViews.swift`
- `IOS RunSmart app/Features/Recovery/RecoveryDashboardView.swift`
- `IOS RunSmart app/PreviewSupport/RunSmartPreviewData.swift`
- `IOS RunSmart appTests/StriverPersonaGateTests.swift` (new)
- `IOS RunSmart appTests/WellnessTrendMapperTests.swift` (new)
- `docs/qa/ios-qa-checklist.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Validation
- Swift parse checks passed for all touched E7 source files.
- Focused E7 tests passed on iPhone 17 Pro simulator:
  - `StriverPersonaGateTests` (3/3)
  - `WellnessTrendMapperTests` (3/3)
- Generic simulator build passed with existing warning noise:
  - `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-e7-derived-data CODE_SIGNING_ALLOWED=NO build -quiet`

## 2026-05-26 - App Store Launch Prep: Phase 2 + Phase 3

### Task Summary
Continued App Store launch implementation plan.

**Phase 2 — Privacy gap fix + E1 timeout:**
- Fixed cross-user FlexWeek cache leak: `FlexWeekServiceSupport` `cacheResponse` and `cachedOutcome` now require `userID: UUID?` parameter; no-op if nil; cache key format is `runsmart.flexWeek.response.{uuid}.{reason}.{dates}`.
- `SupabaseRunSmartServices` updated to pass `currentUserID` at both call sites.
- Timeout bumped from 4s to 6.5s (E1 eng review decision).
- `FlexWeekCacheTests.swift` (new): 4 tests — cross-user isolation, userID in key, no write on nil userID, nil read on nil userID. All 4 green.

**Phase 3 — Design review + screenshot fix:**
- Design review of: Today tab + AI Coach, Plan tab + FlexWeek, WeeklyProgressCard, Post-run debrief.
- Critical finding: `MockRunSmartServices.generateWeeklySummary()` inherited `nil` default — WeeklyProgressCard invisible in App Store screenshots.
- Fix: Added `generateWeeklySummary()` override in `MockRunSmartServices` with rich AI-source summary (3 runs, 22.4 km, Week 4 narrative).
- Regenerated App Store screenshots via `fastlane/scripts/capture-app-store-screenshots.sh`.
- Updated `tasks/lessons.md` with mock override lesson.

### Files Changed
- `IOS RunSmart app/Services/FlexWeekServiceSupport.swift` (Phase 2 privacy fix)
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift` (Phase 2: userID at call sites + E1 timeout)
- `IOS RunSmart appTests/FlexWeekCacheTests.swift` (new — Phase 2 regression tests)
- `IOS RunSmart app/Services/RunSmartServices.swift` (Phase 3: mock generateWeeklySummary override)
- `tasks/lessons.md` (Phase 3: mock nil lesson added)

### Validation
- Phase 2: FlexWeekCacheTests 4/4 green, build clean.
- Phase 3: Build clean, screenshot script running on iPhone 17 Pro Max + iPhone 17e.

## 2026-05-26 - E5 Flex Week Stories 2 + 3

### Task Summary
Implemented `flex_week` coach_message edge intent and wired iOS `flexCurrentWeek` service so Flex Week flow calls Supabase with deterministic fallback instead of the mock sleep path.

### Files Changed
- `supabase/functions/coach_message/flex_week.ts` (new)
- `supabase/functions/coach_message/index.ts`
- `supabase/functions/coach_message/index_test.ts`
- `IOS RunSmart app/Services/FlexWeekServiceSupport.swift` (new)
- `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Features/Plan/FlexWeekFlowView.swift`
- `IOS RunSmart appTests/FlexWeekTests.swift`
- `tasks/todo.md`, `tasks/session-log.md`

### Validation
- `FlexWeekTests` clean test: 24/24 passed (iPhone 17 simulator).
- Deno edge tests: 7/7 passed; `deno check` passed on index + flex_week.

## 2026-05-24 - SwiftUI UI Patterns Root Tabs Optimization

### Task Summary
Continued the Build iOS Apps SwiftUI UI Patterns skill across the remaining RunSmart root tabs after the Today tab optimization.

### Files Changed
- `IOS RunSmart app/Features/Plan/PlanTabView.swift`
- `IOS RunSmart app/Features/Activity/ActivityTabView.swift`
- `IOS RunSmart app/Features/Profile/ProfileTabView.swift`
- `IOS RunSmart app/Features/Run/RunTabView.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Kept the pass behavior-preserving and avoided screen redesign.
- Changed scroll-heavy root tab content in Plan, Report, and Profile to `LazyVStack` so those tabs match the Today tab's container pattern.
- Changed Plan/Profile horizontal dynamic strips to `LazyHStack` where they render variable workout, month, week, or achievement collections.
- Localized key derived values in `PlanTabView` so the plan explanation, current week, and review weeks are computed once per render and reused across cards.
- Replaced repeated inline routing and refresh closures with named action methods in Plan, Report, Profile, and Run.
- Kept Run tab product behavior unchanged while moving start, route, audio cue, and metrics-refresh actions into named methods.
- Preserved existing dirty release/TestFlight work and did not touch unrelated Swift changes.

### Validation
- Swift parse validation passed:
  `xcrun swiftc -parse "IOS RunSmart app/Features/Plan/PlanTabView.swift" "IOS RunSmart app/Features/Activity/ActivityTabView.swift" "IOS RunSmart app/Features/Profile/ProfileTabView.swift" "IOS RunSmart app/Features/Run/RunTabView.swift"`
- Whitespace validation passed:
  `git diff --check -- "IOS RunSmart app/Features/Plan/PlanTabView.swift" "IOS RunSmart app/Features/Activity/ActivityTabView.swift" "IOS RunSmart app/Features/Profile/ProfileTabView.swift" "IOS RunSmart app/Features/Run/RunTabView.swift" tasks/todo.md tasks/session-log.md`
- XcodeBuildMCP simulator build passed:
  `build_sim CODE_SIGNING_ALLOWED=NO`
- Build log:
  `/Users/nadavyigal/Library/Developer/XcodeBuildMCP/workspaces/IOS-RunSmart-light-18e0783284c4/logs/build_sim_2026-05-24T08-57-57-262Z_pid15676_19753b02.log`

### Next Recommended Action
Run a short simulator UI smoke through each root tab after the existing release branch is ready for interactive QA.

## 2026-05-24 - SwiftUI UI Patterns Today Optimization

### Task Summary
Ran the Build iOS Apps SwiftUI UI Patterns skill on the RunSmart iOS app with a focused optimization pass on the Today tab.

### Files Changed
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Kept the pass behavior-preserving and avoided screen redesign.
- Changed the main Today content stack to `LazyVStack` so the scroll-heavy dashboard follows SwiftUI feed/container guidance.
- Changed the dynamic weekly workout strip to `LazyHStack` while keeping small fixed rows unchanged.
- Localized derived Today values in `body` so `TodayResolvedState` and the route/explanation snapshot are computed once per render and reused across cards.
- Replaced repeated inline router closures with named methods for Today coach, workout detail, plan adjustment, routes, reports, reschedule, and run start actions.
- Preserved existing dirty release/TestFlight work and did not touch unrelated Swift changes.

### Validation
- Swift parse validation passed:
  `xcrun swiftc -parse "IOS RunSmart app/Features/Today/TodayTabView.swift"`
- Whitespace validation passed:
  `git diff --check -- "IOS RunSmart app/Features/Today/TodayTabView.swift" tasks/todo.md`
- Generic simulator build passed with DerivedData outside synced storage:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-swiftui-ui-patterns-derived-data CODE_SIGNING_ALLOWED=NO build`
- XcodeBuildMCP simulator build was attempted first but hit the 120-second tool timeout while the underlying build continued; a direct incremental build completed successfully.
- Build warning noise remains pre-existing in AppIntents metadata extraction and the always-run metadata stripping script.

### Next Recommended Action
Use the same UI Patterns pass on `PlanTabView.swift`, then consider a small shared horizontal-section helper if the Today and Plan strips keep converging.

## 2026-05-24 - SwiftUI View Refactor Skill Pass

### Task Summary
Ran the Build iOS Apps SwiftUI View Refactor skill on the RunSmart iOS app with a focused pass on the largest secondary-flow SwiftUI surface.

### Files Changed
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Kept the refactor behavior-preserving and did not redesign any screens.
- Moved destination subtitle/symbol metadata onto `SecondaryDestination` so the root view reads as data plus layout.
- Extracted `SecondaryContentView` to keep `SecondaryFlowView` small and make the destination switch a dedicated subview concern.
- Replaced several inline async button actions with named methods in secondary-flow scaffolds.
- Preserved existing dirty release/TestFlight work and did not touch unrelated Swift changes.

### Validation
- Swift parse validation passed:
  `xcrun swiftc -parse "IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift"`
- Whitespace validation passed:
  `git diff --check -- "IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift" tasks/todo.md`
- Generic simulator build passed with DerivedData outside synced storage:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-swiftui-refactor-derived-data CODE_SIGNING_ALLOWED=NO build`
- XcodeBuildMCP simulator build was attempted first but hit the 120-second tool timeout while the underlying build continued; a direct incremental build completed successfully.
- Build warning noise remains pre-existing in HealthKit, RunSmartAPIModels, BenchmarkRouteAnalyticsService, and AppIntents metadata extraction.

### Next Recommended Action
Use the same skill on `TodayTabView.swift` or `PlanTabView.swift` next; both are large enough to benefit from a dedicated subview pass.

## 2026-05-20 - Sprint 10 TestFlight Closeout And Today QA

### Task Summary
Planned and implemented Sprint 10 through the local Agent OS flow: unblocked local build/test code signing, ran final build/build-for-testing/focused readiness validation from `/tmp/runsmart-derived-data`, fixed only release-blocking Sprint 9 regressions exposed by tests, and wrote a TestFlight closeout report with honest blockers for authenticated/manual/portal work.

### Files Changed
- `IOS RunSmart app.xcodeproj/project.pbxproj`
- `IOS RunSmart app/Services/Supabase/TrainingPlanRepository.swift`
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Features/Sharing/ProgressShareCard.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `docs/specs/sprint-10-testflight-closeout.md`
- `docs/qa/sprint-10-testflight-closeout-report.md`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Decisions Made
- Added a target build phase that runs `/usr/bin/xattr -cr` against the built app bundle before code signing so local resource metadata does not require manual cleanup.
- Kept DerivedData outside synced/FileProvider folders at `/tmp/runsmart-derived-data`.
- Changed date-only plan formatting to user-local timezone semantics because scheduled workout dates are calendar days, not UTC instants.
- Tightened low-recovery classification so low stress does not count as low recovery while high/elevated stress still does.
- Kept Sprint 10 bug fixes narrow and avoided new AI, route, onboarding, or redesign work.
- Recorded authenticated QA, physical device QA, App Store Connect portal work, and authenticated Coach smoke as blockers rather than claiming unverified access.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-derived-data build`
- Generic simulator build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-derived-data build-for-testing`
- Focused `RunSmartReadinessTests` passed on iPhone 17 Pro:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/runsmart-derived-data -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests" test`
- Codesign verification passed:
  `codesign --verify --deep --strict --verbose=2 "/tmp/runsmart-derived-data/Build/Products/Debug-iphonesimulator/IOS RunSmart app.app"`
- Whitespace validation passed:
  `git diff --check -- "IOS RunSmart app.xcodeproj/project.pbxproj" "IOS RunSmart app/Features/Run/PostRunSummaryView.swift" "IOS RunSmart app/Features/Sharing/ProgressShareCard.swift" "IOS RunSmart app/Models/RunSmartModels.swift" "IOS RunSmart app/Services/Supabase/TrainingPlanRepository.swift" "IOS RunSmart appTests/RunSmartReadinessTests.swift" docs/specs/sprint-10-testflight-closeout.md tasks/todo.md`

### Next Recommended Action
Release owner should enter demo credentials directly in App Store Connect, select the processed build, add screenshots, confirm privacy/category/age rating, then run authenticated Coach smoke plus simulator and physical-device Today QA with the active-plan demo account.

## 2026-05-19 - AI Coach Validation And QA Story 5

### Task Summary
Implemented Story 5 from the AI skills/shared contracts plan by validating the merged PR #18/#19 base on a clean branch and recording the evidence. No app behavior, backend endpoint, UI gating, generated model import, secrets, or source Agent OS files were changed.

### Files Changed
- `docs/qa/ai-coach-story-5-validation-2026-05-19.md`
- `docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Used `origin/main` as the correct branch base because PR #19 is merged by `5e49dcd` and PR #18 by `7485880`.
- Created a clean worktree/branch for Story 5 so unrelated local doc deletions in the original checkout stayed untouched.
- Treated build-for-testing plus generic simulator build as the reliable Xcode rebuild evidence.
- Attempted focused readiness XCTest execution, but recorded it as blocked because simulator launch/test execution stalled after the app and test bundle built.

### Validation
- Xcode project listing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -list`
- Story 3 docs/content and source import guards passed.
- Story 4 static symbol and Swift parse validation passed.
- Xcode build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath build/DerivedData-Story5 build-for-testing`
- Xcode generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath build/DerivedData-Story5 build`
- Focused readiness XCTest execution was attempted on iPhone 17 simulator. It built, then stalled during simulator launch/test execution and was stopped with `** BUILD INTERRUPTED **`.

### Next Recommended Action
Plan the readiness service/backend boundary and retry `RunSmartReadinessTests` from a healthy simulator before wiring readiness UI gating.

## 2026-05-19 - AI Coach Readiness DTOs Story 4

### Task Summary
Implemented Story 4 from the AI Coach contracts plan by adding the first minimal Swift DTO slice for readiness payloads. The code adds structured safety flags, readiness decisions/confidence values, readiness request/response DTOs, and focused Codable/privacy tests without wiring UI or backend behavior.

### Files Changed
- `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `docs/ai-coach/skill-contracts.md`
- `docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Kept the DTOs in the existing `RunSmartDTO` namespace.
- Added small context DTOs only for readiness payloads rather than generating or importing shared models.
- Preserved the existing live Coach response shape `safetyFlags: [String]?`; structured `SafetyFlagDTO` is for new readiness payloads.
- Did not wire Pre-run UI gating or add a backend endpoint in this story.

### Validation
- Swift parse validation passed:
  `xcrun swiftc -parse "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift" "IOS RunSmart appTests/RunSmartReadinessTests.swift"`
- Whitespace validation passed:
  `git diff --check -- "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift" "IOS RunSmart appTests/RunSmartReadinessTests.swift" docs/ai-coach/skill-contracts.md docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md tasks/todo.md tasks/session-log.md`
- Static symbol check passed:
  `rg -n "SafetyFlagDTO|ReadinessCheckRequestDTO|ReadinessCheckResponseDTO|CoachDecisionDTO|CoachConfidenceDTO|testReadinessCheck" "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift" "IOS RunSmart appTests/RunSmartReadinessTests.swift"`
- Focused red-state command was attempted before DTO implementation, but `xcodebuild ... build-for-testing` stalled after the invocation line and was stopped.
- Generic build-for-testing was attempted after implementation, but `xcodebuild ... build-for-testing` again stalled after the invocation line and was stopped.
- Draft PR #19 amended with Story 4 code/tests and updated title/body: https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/19

### Next Recommended Action
Run Story 5 validation once Xcode build infrastructure is responsive, then design the readiness service or Supabase endpoint boundary before any Pre-run UI gating.

## 2026-05-19 - AI Coach Skill Contracts Story 3

### Task Summary
Implemented Story 3 from the AI skills/shared contracts investigation by adding an iOS-native AI Coach skill contract document. The doc defines structured safety flags, shared guardrails, and request/response sketches for the next Coach contract slices without importing web/PWA skill folders or changing app behavior.

### Files Changed
- `docs/ai-coach/skill-contracts.md`
- `docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Kept Story 3 docs-only and did not add `.codex/skills/` until the iOS contract shape settles.
- Used current iOS service and screen boundaries as references: Coach, Today, Plan, Run, Route Creator, `RunSmartDTO`, `RunSmartServices`, `SupabaseRunSmartServices`, and `coach_message`.
- Chose structured `SafetyFlagDTO` as the canonical future shape while leaving the current live Coach `safetyFlags: [String]?` behavior unchanged.
- Recommended Story 4 as the first code slice: manual `SafetyFlagDTO` plus readiness request/response DTOs with fixture-based Codable tests.

### Validation
- Contract doc path/content validation passed:
  `test -f docs/ai-coach/skill-contracts.md && rg -n "SafetyFlagDTO|ReadinessCheckRequestDTO|WorkoutExplainerRequestDTO|PostRunDebriefRequestDTO|LoadAnomalyGuardRequestDTO|GoalDiscoveryRequestDTO|RouteBuilderRequestDTO|AdherenceCoachRequestDTO|Supabase|PreRunView|RunSmartDTO" docs/ai-coach/skill-contracts.md`
- Source import guard passed:
  `test ! -d .codex && test ! -d .cursor && test ! -d .claude && test ! -f AGENTS.md && test ! -f CLAUDE.md && test ! -f CODEX.md && test ! -d docs/ai-skills`
- Whitespace validation passed for tracked edited files:
  `git diff --check -- docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md tasks/todo.md tasks/session-log.md`
- Xcode availability check passed:
  `xcodebuild -version`
- Swift build/test validation was not run because Story 3 changed only docs/task files.
- Draft PR created: https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/19

### Next Recommended Action
Implement Story 4: add manually mirrored safety/readiness DTOs and focused Codable fixture tests before wiring any Pre-run UI behavior.

## 2026-05-19 - AI Skills And Shared Contracts Import Investigation

### Task Summary
Investigated the requested original RunSmart web/PWA AI coaching skills and shared TypeScript contracts, then implemented the first safe slice as a docs-only iOS mapping report and five-story implementation plan. No source Agent OS files, workflows, product docs, root instructions, task boards, bulk TypeScript contracts, generated Swift, or secrets were imported.

### Files Changed
- `docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Kept the first slice documentation-first because the iOS app already has live Coach context DTOs, plan generation DTOs, run report DTOs, route models, and backend Coach guardrails.
- Recommended against copying source `.codex`, `.cursor`, or `.claude` skill directories because their integration points reference web `v0` paths and would become stale in the native app.
- Recommended against running the source TypeScript-to-Swift generator because it targets a different output path, uses regex parsing, maps all numbers to `Double`, and does not handle this app's date, id, enum, optionality, or Codable needs.
- Identified structured `SafetyFlag` and readiness request/response DTOs as the best future first code slice after an iOS-native skill contract doc.

### Validation
- Confirmed the investigation report exists:
  `test -f docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md`
- Confirmed no source `.codex`, `.cursor`, `.claude`, root instruction, or source task-board files were copied into the app repo.
- Xcode availability check passed:
  `xcodebuild -version`
- Xcode project listing was attempted with `xcodebuild -project "IOS RunSmart app.xcodeproj" -list`, but it did not return past the invocation line within the observed window and was stopped.
- Confirmed no Swift files were changed in this slice.
- Swift build/test validation was not run because this was a docs/task-board-only change.

### Next Recommended Action
Implement Story 3 from the report: create an iOS-native AI coach skill contract doc with `SafetyFlag`, readiness, workout explainer, post-run debrief, and plan/load guard payload sketches.

## 2026-05-19 - App Store Readiness Pass

### Task Summary
Ran an Agent OS App Store readiness pass for RunSmart. The app now passes local simulator build, build-for-testing, iOS archive validation, App Store Connect IPA export, and App Store Connect upload after cleaning the folder-synced app tree. The exported/uploaded IPA is distribution-signed with `get-task-allow = false`; Apple accepted the package and reported it was processing.

### Files Changed
- `RunSmartInfo.plist`
- `IOS RunSmart app/Features/Secondary/DIAGNOSTIC_REPORT.md`
- `IOS RunSmart app/Resources/Localizable.xcstrings`
- `ExportOptionsAppStore.plist`
- `ExportOptionsAppStoreUpload.plist`
- `fastlane/metadata/en-US/*.txt`
- `docs/qa/app-review-notes-2026-05-19.md`
- `docs/qa/app-store-readiness-report-2026-05-19.md`
- `docs/qa/app-store-readiness-checklist.md`
- `docs/qa/testflight-checklist.md`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Decisions Made
- Used the outer Agent OS workflows as fallback because the canonical app repo does not contain `.agent-os/workflows/`.
- Treated archive contents as the source of truth for release readiness, not only source-tree inspection.
- Kept the scope to release readiness and minimal metadata/bundle cleanup; no app screens or product logic were redesigned.
- Set `CFBundleDisplayName` and `CFBundleName` to `RunSmart` so the archive no longer exposes the project name as the app name.
- Added `ITSAppUsesNonExemptEncryption = false` for App Store Connect export metadata.
- Removed the diagnostic markdown file that had been present in the archived app bundle.
- Removed untracked ResumeBuilder/ATS/Tailor/V2/paywall source from the Xcode folder-synced app tree instead of leaving it to compile implicitly.
- Removed stale ResumeBuilder/ATS/Tailor/PDF/credits localized strings from the shipped string catalog.
- Removed stray unreferenced app icon PNGs that caused asset warnings.
- Added a reusable App Store Connect export options plist.
- Added a reusable App Store Connect upload options plist.
- Added Fastlane metadata files and App Review notes, while leaving demo credentials out of repo memory.
- Recorded the release-owner report that outdoor GPS recording worked and battery use was acceptable on May 19, 2026.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Release archive passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-AppStoreReady-2026-05-19-v2.xcarchive" archive`
- Clean release archive passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-AppStoreReady-2026-05-19-clean.xcarchive" archive`
- App Store Connect IPA export passed:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-AppStoreReady-2026-05-19-clean.xcarchive" -exportPath "build/AppStoreExportClean" -exportOptionsPlist ExportOptionsAppStore.plist -allowProvisioningUpdates`
- App Store Connect upload passed:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-AppStoreReady-2026-05-19-clean.xcarchive" -exportPath "build/AppStoreUploadClean" -exportOptionsPlist ExportOptionsAppStoreUpload.plist -allowProvisioningUpdates`
- Archive Info.plist now shows display name `RunSmart`, bundle id `com.runsmart.lite`, version `1.0`, build `5`, and `ITSAppUsesNonExemptEncryption = false`.
- Archive contains a dSYM.
- Archive no longer contains `DIAGNOSTIC_REPORT.md`.
- Exported IPA exists at `build/AppStoreExportClean/RunSmart.ipa`.
- Exported IPA has distribution signing, active beta reports, included symbols, and `get-task-allow = false`.
- Upload log reports `Uploaded package is processing`, `Upload succeeded`, and `UPLOAD SUCCEEDED with no errors`.
- Exported IPA inspection found no bundled diagnostic or legacy ResumeBuilder/ATS/Tailor files.
- Exported localized resources contain no ResumeBuilder/Resume/ATS/Tailor/jobs/credits/PDF legacy strings.
- No untracked source files remain inside `IOS RunSmart app/`.
- Metadata text length checks passed for subtitle, keywords, promotional text, and description.
- `plutil -lint` passed for `ExportOptionsAppStore.plist`, `RunSmartInfo.plist`, `PrivacyInfo.xcprivacy`, and exported distribution plists.
- Public root, privacy, support, and terms URLs return HTTP 200 after canonical redirect.
- Deployed `coach_message` returns HTTP 401 without auth, confirming it is deployed and protected from anonymous access.

### Remaining Blockers
- Uploaded build processing must complete in App Store Connect, then build 5 must be selected for TestFlight/App Store.
- App Store screenshots are not present in the repo and still need to be captured/uploaded.
- Demo credentials must be entered directly in App Store Connect, not stored in repo memory.
- App Store Connect privacy questionnaire, age rating, category, and reviewer fields still need portal confirmation.
- Authenticated deployed Coach smoke was not re-run in this pass; the latest authenticated remote smoke remains from Sprint 8 deployment completion.
- Exact physical-device battery percentages were not stored in repo memory.

## 2026-05-18 - Local RunSmart Web Env Import

### Task Summary
Copied local RunSmart web environment keys into ignored local env files for the iOS/Supabase Coach work. Secret values were not printed or added to tracked docs.

### Files Changed
- Outer workspace `.gitignore`
- App repo `.gitignore`
- Ignored local-only env files: outer `env.local`, outer `local.env`, app `local.env`

### Decisions Made
- The user-named web project path exists at `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-`, but no real env file was present there; it only had `.env.local.example`.
- Used the available local web env source at `/Users/nadavyigal/Documents/RunSmart/v0/.env.local`.
- Added `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `OPENAI_MODEL`, `SUPABASE_PROJECT_REF`, and `SUPABASE_FUNCTIONS_URL` aliases alongside the copied web keys so the Supabase Edge Function can be configured locally.
- Added env file patterns to `.gitignore` before writing secrets.

### Validation
- Confirmed required live Coach keys exist in app `local.env`: `OPENAI_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`.
- Confirmed outer `env.local` / `local.env` and app `env.local` / `local.env` are ignored by git.
- `supabase` CLI is not installed, so secrets were not pushed with `supabase secrets set`.

## 2026-05-18 - Live AI Coach Backend Endpoint Sprint 8

### Task Summary
Implemented the first live AI Coach vertical slice: a Supabase Edge Function named `coach_message`, a companion migration for Coach ownership/idempotency metadata, sanitized iOS Coach DTOs, and an iOS live-first send path that preserves deterministic fallback.

### Files Changed
- `supabase/functions/coach_message/index.ts`
- `supabase/config.toml`
- `supabase/migrations/20260518130000_live_ai_coach_endpoint.sql`
- `supabase/migrations/20260518133000_tighten_coach_rls_policies.sql`
- `scripts/deploy-coach-message.sh`
- `docs/specs/live-ai-coach-endpoint.md`
- `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift`
- `IOS RunSmart app/Services/Live/LiveRunSmartServices.swift`
- `IOS RunSmart app/Services/Supabase/RunSmartSupabaseClient.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Decisions Made
- Used Supabase Edge Function `coach_message` instead of legacy web API routes because the repo has no RunSmart backend route tree and existing `/api/v1/chat` code is ResumeBuilder-specific.
- iOS calls `https://dxqglotcyirxzyqaxqln.supabase.co/functions/v1/coach_message` through `SupabaseManager.functionsBaseURL`, not `BackendConfig.apiBaseURL`.
- The backend authenticates the user JWT, rejects coordinate-like context payloads, persists user and assistant messages, calls OpenAI server-side, and persists deterministic backend fallback if OpenAI is unavailable.
- iOS sends one `clientMessageId` per turn; backend stores the assistant as `<clientMessageId>:assistant` to avoid duplicate rows across retries.
- iOS no longer directly inserts the live user row before the backend returns. If live backend fails, iOS uses `TrainingContextCoachResponder` and persists fallback through the existing Supabase path.
- Local deterministic fallback now handles pain/dizziness/chest pain/fainting/severe symptoms with stop-and-consult guidance.
- Remote schema migration was applied through Supabase MCP because CLI deploy/auth was not available locally.
- Existing older broad Coach RLS policies were removed; authenticated users now rely on owner-scoped conversation/message policies, with service-role access preserved for the Edge Function.
- `supabase/config.toml` sets `coach_message.verify_jwt = false` because the function performs its own JWT validation and returns stable JSON errors for local and deployed requests.
- Added `scripts/deploy-coach-message.sh` to avoid common deployment mistakes: it reads ignored `local.env`, requires `SUPABASE_ACCESS_TOKEN`, sets only `OPENAI_API_KEY`/`OPENAI_MODEL`, and deploys `coach_message` with `--use-api` so Docker is not required.
- Added documentation for request/response shape, required secrets, deployment commands, fallback behavior, and known limitations.

### Validation
- `npx -y deno check supabase/functions/coach_message/index.ts` passed.
- Supabase MCP migration `live_ai_coach_endpoint` applied successfully.
- Supabase MCP migration `tighten_coach_rls_policies` applied successfully.
- Post-migration schema check confirmed `conversations.auth_user_id`, `conversation_messages.client_message_id`, `conversation_messages.source`, existing `metadata`, and existing `created_at`.
- Post-RLS check confirmed only owner-scoped authenticated policies plus service-role policies remain on Coach conversations/messages.
- OpenAI Responses API smoke test returned HTTP 200 and text with configured model `gpt-4.1-mini`.
- Local Deno smoke test for `coach_message` started and returned JSON `401` for a POST missing a bearer token.
- `npx -y supabase@latest --version` returned `2.99.0`.
- `npx -y supabase@latest link --project-ref "$SUPABASE_PROJECT_REF"` failed because `SUPABASE_ACCESS_TOKEN` is absent and the CLI is not logged in.
- Searched local env files under `Documents` for `SUPABASE_ACCESS_TOKEN`/`sbp_`; no Supabase personal access token was found.
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed and compiled the new live Coach DTO/client/fallback tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Build still emits pre-existing AppIntents metadata warning noise.

### Deployment Steps
- `export SUPABASE_ACCESS_TOKEN=...` or run `npx -y supabase@latest login`
- Add `SUPABASE_ACCESS_TOKEN=...` to ignored `local.env` or export it in the shell.
- `scripts/deploy-coach-message.sh`

### Remaining Blockers
- Run signed-in manual QA: Today Coach live response, thread reload persistence, backend-broken iOS fallback, Report-context question, no duplicate messages, and no raw route coordinates in stored messages/metadata.

## 2026-05-18 - Live AI Coach Deployment Completion

### Task Summary
Completed the deployed Supabase side of Sprint 8 after `SUPABASE_ACCESS_TOKEN` was added to ignored local env. The `coach_message` Edge Function is now deployed, configured with server-side OpenAI secrets, and remotely smoke-tested.

### Files Changed
- `.gitignore`
- `scripts/deploy-coach-message.sh`
- `supabase/functions/coach_message/index.ts`
- `supabase/migrations/20260518140000_conversation_messages_auth_user_id.sql`
- `supabase/migrations/20260518141000_conversation_messages_public_owner_policy.sql`
- `supabase/migrations/20260518142000_conversation_messages_claim_subject_policy.sql`
- `supabase/migrations/20260518143000_coach_messages_read_view.sql`
- `supabase/migrations/20260518144000_coach_messages_security_definer_view.sql`
- `supabase/migrations/20260518145000_coach_messages_rpc.sql`
- `supabase/migrations/20260518150000_drop_unused_coach_messages_view.sql`
- `supabase/migrations/20260518151000_harden_coach_messages_rpc_grants.sql`
- `IOS RunSmart app/Services/Supabase/RunSmartSupabaseClient.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `docs/specs/live-ai-coach-endpoint.md`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Decisions Made
- Kept deployment through Supabase CLI `--use-api` so Docker is not required.
- Taught `scripts/deploy-coach-message.sh` to read ignored wrapper/app env files and accept the user-provided `UPABASE_ACCESS_TOKEN` typo by mapping it to `SUPABASE_ACCESS_TOKEN`.
- Added `conversation_messages.auth_user_id` and used it in backend/iOS fallback inserts so message ownership is explicit.
- Moved iOS Coach history reads to `coach_messages_for_conversation`, an authenticated owner-filtered RPC, because direct REST reads from `conversation_messages` returned no rows in deployed smoke tests even after RLS checks passed in SQL.
- Dropped the unused `coach_messages` view and revoked anonymous execution from the Coach history RPC.

### Validation
- `scripts/deploy-coach-message.sh` linked project `dxqglotcyirxzyqaxqln`, set `OPENAI_API_KEY` / `OPENAI_MODEL`, and deployed `coach_message`.
- Remote authenticated smoke test called deployed `POST /functions/v1/coach_message` and returned HTTP 200 with `source = live_ai`, `fallback = false`, and assistant content.
- SQL verification confirmed the smoke request persisted one user message and one assistant message with sources `client` and `live_ai`, both owned by the authenticated user.
- RPC smoke test confirmed `coach_messages_for_conversation` returns the two persisted rows for the signed-in user after grant hardening.
- Cleanup SQL removed smoke users, conversations, and messages; post-check showed 0 remaining smoke users and 0 orphan Coach rows.
- Supabase function logs show recent deployed `POST /functions/v1/coach_message` requests returning HTTP 200.
- `npx -y deno check supabase/functions/coach_message/index.ts` passed.
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Focused Coach XCTest attempt compiled the app/test bundle, then failed during simulator install with CoreSimulator 405 / NSMach -308. This matches the existing simulator-infrastructure lesson and is not a Coach compile failure.
- Supabase advisors still report broader pre-existing project warnings. The new Coach RPC is intentionally executable by authenticated users as a `security definer` function, anonymous execute is revoked, and the SQL body filters by `auth.uid()`.

### Remaining Blockers
- Manual in-app QA remains: Today Coach live response, thread reload persistence, backend-broken iOS fallback, Report-context question, no duplicate messages, and no raw route coordinates in stored message metadata.

## 2026-05-18 - Real Run Completion State Fix Sprint 7

### Task Summary
Implemented Sprint 7 by unifying real RunSmart GPS completion around one saved activity/report path, clearing Run tab post-run state after user action, refreshing dependent tabs after completion, and making suggested-next-run failure copy safe for TestFlight users.

### Root Cause
- The completed-run UX was split between Run tab's inline `finishedRun` summary and router-driven post-run sheets, allowing stale `.postRunSummary(nil)` state to surface "Run not saved" after a valid run.
- Completed activity processing refreshed plan-dependent UI only on some paths, so Today/Plan could remain stale after unmatched or partially processed runs.
- Report row opening could fall back to skeleton report details even when a cached/generated report existed.
- Suggested-workout save failures exposed debug/Xcode-console copy in user-facing UI.

### Files Changed
- `docs/specs/sprint-7-real-run-completion-state-fix.md`
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `IOS RunSmart app/Features/Run/RunTabView.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Run/PostRunLearningCard.swift`
- `IOS RunSmart app/Features/Activity/ActivityTabView.swift`
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Profile/ProfileTabView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Supabase/TrainingPlanRepository.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Kept the real GPS finish path single-surface: dismiss stale post-run router sheets before showing inline summary, and clear `finishedRun`, `postActivityOutcome`, and router run context after Keep Activity / Done or Delete.
- Added `runSmartReportsDidChange` and posted/listened for report refreshes alongside run and plan refreshes so Today, Report, Profile, and report detail screens reload after completion.
- Cached/generated reports now use the stable `reportRunID(for:)` id; Report tab resolves a saved/generated report before falling back to a skeleton.
- Today now prefers an uncompleted same-day workout and falls through to the next actionable workout when today's session is already completed.
- Kept planned-workout matching on the existing `bestWorkoutMatch` gate and added coverage for a 7.05 km / 40:23 same-day easy run.
- Hardened suggested-workout date parsing for ISO/formatted dates plus `today`, `tomorrow`, and `next weekday` labels.
- Replaced debug failure copy with: "Your run report is saved. Could not add the suggested workout to your plan; try again later."

### Validation
- Generic simulator build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Static copy scan found no remaining user-visible `Xcode console`, `Check the console`, or debug suggested-workout save copy.
- Build still emits pre-existing warning noise around AppIcon unassigned children, AppIntents metadata extraction, and resume-era actor isolation/deprecation warnings.

### Remaining Beta Blockers
- Physical-device manual QA remains required: record a real GPS run for at least 5 minutes, finish, Keep Activity / Done, verify Run exits idle, Report/Profile agree, Today no longer recommends the same workout, Plan reflects completion or extra-run state, Garmin duplicate handling stays single-activity, and suggested-next-run save behavior is safe.
- Archive/upload and App Store Connect validation were not run.

---

## 2026-05-17 - Return Loop + Share Cards + TestFlight Readiness Sprint 6B

### Task Summary
Implemented Sprint 6B by adding local smart return reminders, private progress share cards, claim cleanup, and a stronger TestFlight/physical-device checklist. The sprint stayed local-only: no remote push, social feed, leaderboard, public sharing backend, live in-run AI, or Hebrew localization.

### Files Changed
- `IOS RunSmart app/Core/Push/PushService.swift`
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseSession.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Features/Sharing/ProgressShareCard.swift` (created)
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Routes/BenchmarkComparisonCard.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart app/Features/Profile/ProfileTabView.swift`
- `IOS RunSmart app/Features/Auth/SignInView.swift`
- `IOS RunSmart app/Features/Onboarding/OnboardingView.swift`
- `IOS RunSmart app/Resources/Localizable.xcstrings`
- `docs/qa/testflight-checklist.md`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Added `RunSmartReminderPlan` and `PushService` scheduling for workout due, missed-workout recovery, rest day recovery, and weekly recap local notifications.
- Reminder scheduling respects `notificationsEnabled`; disabling reminders from Profile cancels RunSmart pending reminder requests.
- Notification taps route to Today, Plan, or Report through the existing app router.
- Supabase completed-workout processing cancels the matching workout reminder after a planned workout is completed.
- Reminder copy is intentionally calm and avoids shaming language.
- Added reusable `ProgressSharePayload`, `ProgressShareCard`, and `ProgressShareButton`; share output is text-based and private by default.
- Run report, post-run summary, benchmark comparison, and first available Profile achievement can now share progress without raw coordinates or route maps.
- Cleaned visible sign-in/onboarding/profile copy away from live in-run AI, real-time automatic plan adaptation, and overbroad Garmin/HealthKit claims.
- Left Hebrew localization as a later task because no launch-market decision was found in the approved sprint scope.
- No event analytics wrapper was found, so Sprint 6B did not add notification or share analytics events.

### Validation
- Generic simulator build-for-testing passed and compiled the new Sprint 6B tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Static copy scan checked unsupported live AI, real-time plan adaptation, medical/diagnosis wording, notification/reminder copy, Garmin/HealthKit, and location permission copy.
- Manual QA remains required for permission accepted/denied, tomorrow workout reminder, completed-workout cancellation, missed workout reminder, rest day reminder, report share, benchmark share, share cancel, sign-in copy, onboarding copy, location permission, HealthKit permission, and Garmin flow.

### Remaining Beta Blockers
- Physical-device outdoor/background GPS run and battery delta are still required before external TestFlight expansion.
- Notification permission accept/deny and notification tap routing need device/simulator manual QA.
- HealthKit and Garmin permission/connection copy needs hands-on review with real permission sheets and connected account states.
- Share sheet cancellation and benchmark/report/milestone share flows need manual UI verification.
- Archive validation and App Store Connect upload were not run.

### Next Recommended Sprint
Sprint 6C: Physical Device Beta Gate — run the unlocked-device outdoor/background/battery pass, verify permissions and local notifications on device, validate share flows, and prepare archive/upload evidence.

---

## 2026-05-17 - Routes + Benchmark Coaching Sprint 6A

### Task Summary
Implemented Sprint 6A by adding coached route recommendation for Today and safer benchmark comparison states. Today now recommends the best available saved, generated, or benchmark route for the current workout intent and distance, explains why it fits, and can carry the selected route into the Run pre-start flow.

### Files Changed
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/RouteSuggestionRanker.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Run/RunTabView.swift`
- `IOS RunSmart app/Features/Run/PreRunView.swift`
- `IOS RunSmart app/Features/Routes/BenchmarkComparisonCard.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart appTests/RouteRankingTests.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Added `RouteRecommendation` with route, reason, fit score, warning, and unavailable state.
- Ranked route suggestions by workout distance, route distance fit, workout intent, route type, and whether usable map points exist.
- Today route copy stays conservative: routes without points are allowed but clearly labeled as missing saved map points.
- `Use This Route` now selects the route and opens the Run tab; PreRun shows the selected route without claiming live navigation.
- Benchmark comparison now renders explicit weak GPS, no route data, and no benchmark states instead of silently hiding the card or showing misleading deltas.
- Existing first-run, matched comparison, personal-best, and monthly-average comparison behavior remains in the benchmark card.
- Existing `BenchmarkRouteAnalyticsService` is a comparison computation helper, not an event-tracking wrapper, so Sprint 6A did not add route analytics events.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed and compiled the new Sprint 6A tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Manual QA remains required for saved route, benchmark route, generated route if available, no route, no GPS permission, route without points, first benchmark run, second run on same route, imported matching Garmin run, and weak GPS.

### Next Recommended Sprint
Sprint 6B: Route Intent Persistence + Post-Run Route Review — persist the selected route intent onto the run, compare it with the recorded/imported GPS afterward, and show a compact post-run route review that can update saved-route and benchmark confidence without live AI or social features.

---

## 2026-05-17 - Beginner 5K Habit Track + Cue Preview Sprint 5

### Task Summary
Implemented Sprint 5 by adding a compact Beginner5KHabitCard for First 5K users on Today and a collapsible PreRunCueTimeline in PreRunView. Both features are purely derived from existing loaded data with no new service methods.

### Files Changed
- `IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift` (created)
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Run/PreRunView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Used Approach A (pure derived model) — no new service protocol methods.
- Detection: `profile.goal == "First 5K"` is primary; `experience == "Getting started"` with no advanced goal ("10K PR", "Half Marathon", "Marathon", "Get Faster") is secondary fallback.
- State resolution order: weekComplete → missedRecently → restDay → onTrack.
- `.recovery` and `.strength` WorkoutKind treated as non-running (so a recovery-only day = restDay for the habit card).
- Missed workout copy avoids shame keywords (fail, miss, skip, shame, bad) — verified by test.
- Rest day message focuses on recovery adaptation, not absence.
- `DateFormatter` extracted to static let to avoid allocation in hot path.
- PreRunCueTimeline uses `StructuredWorkoutFactory.makeSteps` which already exists; collapsed by default to keep small iPhone layout clean.
- Free run shows "Pacing intent" panel rather than claiming AI coaching.
- Goal string vocabulary updated: added `"Get Faster"` (GoalWizardView) alongside `"10K PR"` (OnboardingView) to the advanced goals exclusion list.
- No analytics wrapper found; Sprint 5 did not add analytics events.

### Validation
- Generic simulator build passed.
- Generic simulator build-for-testing passed and compiled 6 new Sprint 5 tests.
- Manual QA required before TestFlight.

### Next Recommended Sprint
Sprint 6: Plan Adjustment Review Queue — persist one suggested adjustment from completed or imported runs, show apply/dismiss on Today and Plan, and route mutations through existing amend/reschedule flows without automatic plan adaptation.

---

## 2026-05-17 - First Sync Review Sprint 4

### Task Summary
Implemented Sprint 4 by adding a first-sync review for Garmin and HealthKit. After the first successful sync, the connected-service detail surface can show what was imported, what was skipped as duplicate, whether route data is available, what Coach can now use, and one safe next action.

### Files Changed
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Live/LiveRunSmartServices.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Decisions Made
- Added `FirstSyncReview` models for provider, imported count, skipped duplicate count, route availability count, route-less count, recent imported activities, Coach capabilities, next action, seen state, and honest summary copy.
- Stored first-sync review state in the local production store per provider, with service APIs to fetch and mark the review seen.
- Garmin and HealthKit sync paths now create the review only after a successful connected sync and without rewriting import, duplicate, or route-processing logic.
- The connected-service detail scaffold shows the review once, supports dismiss, and routes next actions to existing Today, Report, or Plan tabs when available.
- Empty, duplicate-only, route-less, mixed-route, and normal imports are explained with conservative claims. HealthKit/Garmin route availability is based only on imported run route points.
- No analytics wrapper was found, so `first_sync_review_viewed`, `first_sync_provider_connected`, `first_sync_import_count`, and `first_sync_next_action_tapped` were not added.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed and compiled the new `FirstSyncReview` tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- The first build-for-testing attempt failed because a test double did not conform to newly added `DeviceSyncing` methods; fixed by adding default protocol extension fallbacks, then reran successfully.
- Focused simulator test execution was not run because recent repo validation repeatedly hit simulator install/launch infrastructure failures; build-for-testing was used for compile/link coverage.
- Manual QA remains required for Garmin first sync, HealthKit first sync, permission denied, no data, duplicate-only import, route-less import, and normal import with activities.

### Next Recommended Action
Sprint 5 should implement a Plan Adjustment Review Queue: persist one suggested adjustment from completed or imported runs, show apply/dismiss on Today and Plan, and route mutations through existing amend/reschedule/regenerate flows without automatic plan adaptation.

## 2026-05-17 - Plan Explanation Surfaces Sprint 3

### Task Summary
Implemented Sprint 3 by adding a lightweight heuristic `PlanExplanation` model and compact explanation cards on Today and Plan. The cards explain why today's workout is recommended and whether the plan is on track or needs a small review, using existing plan, workout, run/import, missed-workout, and recovery data only.

### Files Changed
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Plan/PlanTabView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Added `PlanExplanationTrigger` values for normal, completed run, missed workout, extra run, low recovery, imported activity, and manual edit, plus source values for heuristic, AI, and fallback.
- Kept Sprint 3 heuristic-only; no new plan engine, live AI, route recommendation, notifications, or adaptation workflow was added.
- Today now loads active plan, recent runs, and recovery alongside existing recommendation data so the "Why this workout?" card can handle no plan, rest day, missed workout, imported activity, recent run, and low recovery states.
- Plan now shows a compact "Plan is on track" or "Plan adjusted because..." card above the weekly schedule.
- The card shows at most one recommended action and routes only to existing surfaces: reschedule, amend workout, plan adjustment, goal wizard, or Coach.
- No analytics wrapper was found, so `plan_explanation_viewed`, `plan_adjustment_suggested`, `plan_adjustment_applied`, and `plan_adjustment_dismissed` were not added.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed and compiled the new `PlanExplanation` tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Focused simulator test execution was not run because recent repo validation repeatedly hit simulator install/launch infrastructure failures; build-for-testing was used for compile/link coverage.
- Build still reports pre-existing AppIcon unassigned-child warnings and older resume-era actor-isolation warning noise.

### Next Recommended Action
Sprint 4 should add a small plan-adjustment review queue: persist one suggested adjustment after missed/recent/imported activity, let the runner apply or dismiss it, and keep the actual plan mutation behind existing move/amend/regenerate actions.

## 2026-05-17 - Post-Run Coach Learning Card Sprint 2

### Task Summary
Implemented Sprint 2 by adding a compact post-run learning card that explains what happened, what Coach learned, plan impact, one next action, and source. The card uses existing run/report/outcome data only; no live Coach backend AI, plan adaptation execution, route recommendation, notifications, Hebrew, share cards, or live-run AI was added.

### Files Changed
- `IOS RunSmart app/Features/Run/PostRunLearningCard.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Added `PostRunLearningCardModel` as the presentation model/factory so copy and plan-impact decisions are testable without UI.
- Plan impact resolves to changed, unchanged, unavailable, or needs review from existing `PostActivityOutcome`, active plan, short-run, and report suggestion data.
- Source resolves to AI, fallback, report, or heuristic from existing report metadata; no new analytics or backend source field was invented.
- The CTA uses the existing `saveSuggestedWorkout` path when a structured next workout exists; otherwise it renders as clearly unavailable.
- GPS post-run summary, Garmin/import report flow, and saved report detail flow reuse the same card.

### Validation
- Generic simulator build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Focused Sprint 2 XCTest attempt built the app and test bundle but failed during simulator install/launch with `com.apple.CoreSimulator.SimError Code=405` and `NSMachErrorDomain Code=-308`; not counted as a test pass.
- No analytics wrapper was found, so Sprint 2 did not add `post_run_*` events.

### Next Recommended Action
Sprint 3 should make the learning card actionable across plan surfaces: add a small "review suggested adjustment" queue/state for post-run recommendations without auto-changing the plan.

## 2026-05-17 - Coach Persistence Sprint 1

### Task Summary
Implemented Sprint 1 Coach Persistence + Safe Response using the existing deterministic `TrainingContextCoachResponder` fallback. No live AI backend endpoint, Edge Function, or Coach UI redesign was added.

### Files Changed
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Supabase/RunSmartSupabaseClient.swift`
- `IOS RunSmart app/Features/Coach/CoachFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Decisions Made
- Supabase services now override `send(message:context:)` while the default protocol fallback remains unchanged for fake/non-Supabase services.
- The send path reuses the latest current-user row in `conversations`, or creates a new row with `profile_id = currentUserID.uuidString`.
- The user and assistant messages are inserted together into `conversation_messages` with roles `user` and `assistant`, preserving the existing `recentMessages()` reload path.
- Assistant content still comes from `TrainingContextCoachResponder.response(...)`; Sprint 1 does not call or name a backend AI endpoint.
- `docs/runsmart-ios-supabase-backend-plan.md` lists `POST coach_message` as a planned contract, not a confirmed implementation. Existing `/api/v1/chat` code belongs to the resume/optimization chat stack and was not reused for RunSmart Coach.
- Coach send controls are disabled while a turn is in flight to avoid rapid duplicate persisted turns.
- No training context payload, raw GPS data, latitude, or longitude is persisted with chat messages.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Sprint 1 rerun after duplicate-send guard passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Sprint 1 rerun after duplicate-send guard passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Focused Coach persistence XCTest compiled the app and test bundle, then stalled during simulator launch and was interrupted; not counted as a test pass.
- Test-only JSON key-set compile errors were fixed.
- A parallel Xcode build database lock produced one false verification failure; sequential reruns passed.

### Next Recommended Action
Run signed-in Supabase manual QA for Coach: send a message, close/reopen Coach, confirm user and assistant messages reload in order, then sign out/sign in and confirm ownership isolation. Sprint 1B can add live AI behind an authenticated, confirmed backend contract.

## 2026-05-16 - Training Context Story

### Task Summary
Implemented Story: Unified Training Context + AI Coach Context Integration.

### Files Changed
- `docs/specs/training-context-coach.md`
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Core/RunSmartServiceProviding.swift`
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `IOS RunSmart app/Features/Coach/CoachFlowView.swift`
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Plan/PlanTabView.swift`
- `IOS RunSmart app/Features/Profile/ProfileTabView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Decisions Made
- Added a native summarized `TrainingContextSnapshot` instead of a backend-coupled payload.
- Added typed `CoachEntryPoint` routing while preserving the string `openCoach(context:)` compatibility helper.
- Kept `send(message:)` as a compatibility API and routed Coach UI through `send(message:context:)`.
- Used deterministic context-aware fallback responses; no live AI endpoint, Supabase schema, permissions, or TestFlight changes were added.
- Kept raw GPS route coordinates out of Coach context by summarizing routes and runs only.

### Validation
- Focused training context tests passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testTrainingContextIncludesSummariesAndLimitsPrivateRouteData" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testTrainingContextReportsMissingDataLimitations" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testCoachFallbackResponseUsesEntryPointSpecificContext" test`
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- First focused test attempt failed during compile because Swift does not allow an awaited call in the right side of `??`; fixed by using an explicit branch.
- Existing warning noise remains: AppIcon unassigned children and older resume-era actor-isolation warnings.

### Next Recommended Action
Complete the still-open physical-device outdoor/background/battery QA before external TestFlight. A future backend story can replace the deterministic Coach fallback with an authenticated AI Coach endpoint using `TrainingContextSnapshot` as the native source contract.

## 2026-05-16 - Commit PR And Rebuild

### Task Summary
Committed the unified training context story, opened the GitHub PR, merged the base branch into `routes`, and resolved Agent OS status-file conflicts.

### Files Changed
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Decisions Made
- Kept the story commit scoped to the Coach/training context files.
- Merged `origin/runsmart-lite-build` into `routes` because the PR initially reported conflicts against the default branch.
- Resolved conflicts by preserving the completed Coach story, base run-save/Garmin fix status, and the still-open physical-device QA blocker.

### Validation
- PR #13 opened from `routes` to `runsmart-lite-build`.
- PR rebuild passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Installed and launched the rebuilt simulator app on the booted iPhone 17 Pro:
  `xcrun simctl install booted ".../IOS RunSmart app.app" && xcrun simctl launch booted com.runsmart.lite`

### Next Recommended Action
Review the PR and complete the physical-device outdoor/background/battery QA before external TestFlight.

## 2026-05-15 - Physical Device Debug Install

### Task Summary
Attempted the next physical-device validation lane before external TestFlight. Re-verified connected iPhone discovery, built and installed the Debug app on the device, then stopped short of claiming outdoor/background/battery readiness because the device was locked and no manual run evidence was available.

### Files Changed
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Decisions Made
- Treated build/install as passed device evidence, but kept manual outdoor/background/battery QA open.
- Did not change app feature code.
- Did not claim TestFlight readiness or archive/upload readiness.
- Preserved route/benchmark/Garmin limitations as documented beta risks until a real saved/finished run is validated.

### Validation
- `xcrun xctrace list devices` showed `<REDACTED_DEVICE_NAME> (26.4.2) (<REDACTED_UDID>)`.
- `xcrun devicectl list devices` showed `<REDACTED_DEVICE_NAME>`, identifier `<REDACTED_COREDEVICE_ID>`, state `available (paired)`, model `iPhone 13 (iPhone14,5)`.
- `xcodebuild -list -project "IOS RunSmart app.xcodeproj"` succeeded and listed scheme `IOS RunSmart app`.
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS,id=<REDACTED_UDID>" build` succeeded.
- Build evidence: `** BUILD SUCCEEDED **`, signing identity `Apple Development: <REDACTED_EMAIL> (<REDACTED_TEAM_ID>)`, provisioning profile `iOS Team Provisioning Profile: com.runsmart.lite`, bundle id `com.runsmart.lite`.
- Device detail check confirmed physical iPhone 13, iOS 26.4.2, developer mode enabled, paired over local network.
- `xcrun devicectl device install app --device <REDACTED_COREDEVICE_ID> ".../IOS RunSmart app.app"` succeeded for bundle id `com.runsmart.lite`.
- `xcrun devicectl device process launch --device <REDACTED_COREDEVICE_ID> com.runsmart.lite` failed because the iPhone was locked: `Unable to launch com.runsmart.lite because the device was not, or could not be, unlocked`.
- Static inspection confirmed the app has location usage strings and `UIBackgroundModes = location`; `RunRecorder` requests when-in-use location, disables automatic pauses, allows background location updates, and shows the background location indicator.

### Next Recommended Action
Unlock the connected iPhone, record starting battery percentage, launch RunSmart, complete a real outdoor run with at least 5 minutes locked/backgrounded, then record ending battery percentage, duration, distance, GPS behavior, and any permission issues before starting archive/upload readiness.

## 2026-05-15 - Agent OS Source Of Truth

### Task Summary
Consolidated Agent OS status around a single app-repo source of truth and ran only the next validation lane for physical-device readiness.

### Files Changed
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`
- `../tasks/todo.md`
- `../tasks/session-log.md`
- `../tasks/lessons.md`
- `../AGENTS.md`
- `../CODEX.md`
- `../CLAUDE.md`

### Files Removed
- `tasks/todo 2.md`
- `tasks/todo 3.md`

### Decisions Made
- Canonical task memory now lives only in the app repo: `IOS RunSmart app/tasks/todo.md`, `tasks/lessons.md`, and `tasks/session-log.md`.
- Outer wrapper `tasks/*.md` files are pointer stubs, not status sources.
- Did not change feature code.
- Treated the next validation task as the physical-device validation lane. The automatable device build passed; the real outdoor background/battery run still requires manual use on the connected iPhone.

### Validation
- `xcrun xctrace list devices` showed `<REDACTED_DEVICE_NAME> (26.4.2) (<REDACTED_UDID>)`.
- `xcrun devicectl list devices` showed `<REDACTED_DEVICE_NAME>`, identifier `<REDACTED_COREDEVICE_ID>`, state `connected`, model `iPhone 13 (iPhone14,5)`.
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS,id=<REDACTED_UDID>" build` succeeded.
- Physical-device build evidence: `** BUILD SUCCEEDED **`, signing identity `Apple Development: <REDACTED_EMAIL> (<REDACTED_TEAM_ID>)`, provisioning profile `iOS Team Provisioning Profile: com.runsmart.lite`, bundle id `com.runsmart.lite`.
- Build still emits pre-existing AppIcon warning noise and older resume-era actor-isolation warnings.

### Next Recommended Action
On the connected iPhone, run an outdoor recording session, background the app during the run, then record whether GPS/background continuation worked and the before/after battery percentage before external TestFlight.

## 2026-05-15 - Open Task Triage

### Task Summary
Used the Agent OS to triage the remaining open task notes after Story 10.

### Files Changed
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Decisions Made
- Treated the historical `RunSmartTab` ambiguity and `GlassCard` redeclaration notes as compile-blocker checks because the current task file already marked route Stories 1-10 complete.
- Did not change app source because the active RunSmart simulator build no longer reproduces either compile blocker.
- Left the physical-device battery/background run check open because it cannot be truthfully completed in the simulator.

### Validation
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build` succeeded.
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" test` was attempted, but XCTest launch stalled and ended with `NSMachErrorDomain Code=-308` after interruption.
- The build still emits pre-existing AppIcon unassigned-child warnings and older resume-era actor-isolation warning noise.

### Next Recommended Action
Run the physical-device outdoor recording check for background continuation and battery delta before external TestFlight.

## 2026-05-15 - Run Save And Garmin Merge Fix

### Task Summary
Investigated and fixed the critical TestFlight run persistence/Garmin import issue on `fix/run-save-garmin-merge-investigation`.

### Files Changed
- `IOS RunSmart app/Services/Garmin/GarminMappers.swift`
- `IOS RunSmart app/Services/Garmin/GarminImportProcessor.swift`
- `IOS RunSmart app/Services/ActivityConsolidationService.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/lessons.md`

### Decisions Made
- Kept route benchmark epic work paused; only touched activity save/import/report behavior.
- Treated Garmin import display and persistence as the same normalization problem: only valid running activities with provider IDs, valid start time, duration, and distance can map to `RecordedRun`.
- Added fragment filtering for short Garmin activities that overlap or sit directly beside a longer Garmin run from the same period, while preserving separate short real runs outside that window.
- Relaxed same-workout merge tolerances so RunSmart GPS and Garmin versions of the same morning run can consolidate even when starts differ by up to 30 minutes.
- Added deterministic run-report fallback notes when backend AI report generation is unavailable, and kept local-first save behavior instead of pretending remote sync succeeded.
- Changed suggested-workout save failure copy so it does not imply the activity/report failed to save.

### Validation
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Focused regression tests passed:
  Garmin mapper validation, Garmin fragment filtering, short-real-run preservation, and RunSmart/Garmin merge.
- Nearby Garmin/import/consolidation tests passed.
- Full iPhone 17 simulator test pass succeeded:
  `xcodebuild -quiet -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,id=A24FA1E8-AD0C-46DB-85B7-651A24B1BB38" test`

### Remaining Manual QA
- Record a short outdoor GPS run on a physical device.
- Pause, resume, finish, and confirm the summary metrics and Done behavior.
- Sync Garmin and confirm one canonical activity appears in Report/Recent Runs.
- Confirm suspected Garmin fragments do not appear as separate runs.
- Confirm any suggested-workout save failure names the plan-save problem and leaves the report visible.

## 2026-05-12

### Task Summary
Installed a lightweight Agent OS for RunSmart iOS using router files, workflows, standards, templates, task memory, and iOS QA/TestFlight docs.

### Files Changed
- Agent routers: `AGENTS.md`, `CLAUDE.md`, `CODEX.md`
- Task memory: `tasks/todo.md`, `tasks/lessons.md`, `tasks/session-log.md`
- Product docs: `docs/product/*`
- Architecture docs: `docs/architecture/*`
- Specs/decisions/QA docs: `docs/specs/*`, `docs/decisions/*`, `docs/qa/*`
- Agent OS: `.agent-os/**/*`

### Decisions Made
- Use a thin router-based OS.
- Store detailed process in workflow files.
- Treat current RunSmart state as unclear because the tracked source still contains resume-builder naming.
- Require verification before any task is marked done.

### Next Recommended Action
Run the first planning prompt from the final report to produce an approved RunSmart iOS product brief and feature spec before changing app code.

## 2026-05-12

### Task Summary
Implemented Story 1 for RunSmart iOS improvement by creating a current-to-future information architecture mapping.

### Files Changed
- `docs/specs/runsmart-ios-ia-mapping.md`
- `tasks/todo.md`
- `tasks/lessons.md`
- `tasks/session-log.md`

### Decisions Made
- Keep Story 1 documentation-only because the safe first implementation step is to map current and known app areas before editing SwiftUI navigation.
- Use five primary tabs in the recommended shell: Today, Plan, Run, Report, Profile.
- Keep Coach contextual for now instead of making it a sixth tab.
- Preserve existing features unless a later approved product decision moves, renames, or removes them.

### Next Recommended Action
Implement Story 2 only after approving the IA mapping: confirm the authoritative project/product identity, then create the smallest Today shell story.

### Validation
- IA mapping coverage check passed.
- `xcodebuild -list -project "ResumeBuilder IOS APP.xcodeproj"` succeeded.
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "generic/platform=iOS Simulator" build` succeeded.
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test` failed in the existing test target due to `ResumeOptimizationServiceSwiftTestingTests.swift` using outdated `optimize` argument labels.
- Simulator smoke test skipped because no runtime UI changed.

## 2026-05-12

### Task Summary
Fixed the existing test target and implemented Story 2 as the smallest Today command-center shell step.

### Files Changed
- `ResumeBuilder IOS APPTests/ImproveViewModelTests.swift`
- `ResumeBuilder IOS APPTests/ResumeOptimizationServiceSwiftTestingTests.swift`
- `ResumeBuilder IOS APP/Core/DesignSystem/Components/ResumlyTabBar.swift`
- `tasks/todo.md`
- `tasks/lessons.md`
- `tasks/session-log.md`

### Decisions Made
- Updated test fixtures to provide `jobDescriptionId`, matching the current scan-first optimization flow.
- Kept the first tab backed by the existing Score flow to preserve current functionality.
- Changed only the first tab shell label/icon from Score/gauge to Today/sun.
- Did not implement Garmin, HealthKit, signing, paid services, or a full redesign.

### Validation
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test` succeeded.
- Installed and launched the simulator build on iPhone 17.
- Captured visual evidence at `build/qa/story2-today-tab-after-wait.png`.

### Next Recommended Action
Implement the next small UI story by introducing a true Today content wrapper that preserves the current Score flow as a card or section, after confirming the product identity cleanup path.

## 2026-05-13

### Task Summary
Implemented Story 3 for the RunSmart iOS improvement by adding a real Today command-center wrapper as the first tab content.

### Files Changed
- `ResumeBuilder IOS APP/App/MainTabViewV2.swift`
- `ResumeBuilder IOS APP/Features/V2/Today/TodayView.swift`
- `docs/specs/runsmart-ios-ia-mapping.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Replaced the raw first-tab `ScoreView` with `TodayView`.
- Kept the current score/check flow reachable from a Today card.
- Reused the existing `ScoreViewModel` instance so the preserved flow keeps its selected file/result state.
- Kept Plan, Run, Coach, HealthKit, Garmin, signing, and paid-services work out of scope.

### Validation
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test` succeeded.
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "generic/platform=iOS Simulator" build` succeeded.
- Installed and launched the simulator build on iPhone 17.
- Captured visual evidence at `build/qa/story3-today-wrapper.png`.

### Next Recommended Action
Implement Story 4 by separating Plan from Report at the shell level with placeholder/preserved-content routing, or first approve the product identity cleanup path if naming should be fixed before more UI migration.

## 2026-05-13

### Task Summary
Implemented Story 4 for the RunSmart iOS improvement by separating Plan and Report into distinct top-level tab surfaces.

### Files Changed
- `ResumeBuilder IOS APP/App/MainTabViewV2.swift`
- `ResumeBuilder IOS APP/Core/DesignSystem/Components/ResumlyTabBar.swift`
- `ResumeBuilder IOS APP/Features/V2/Plan/PlanView.swift`
- `ResumeBuilder IOS APP/Features/V2/Report/ReportView.swift`
- `docs/specs/runsmart-ios-ia-mapping.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Replaced the second tab content with a lightweight `PlanView`.
- Replaced the fourth tab content with a lightweight `ReportView`.
- Kept the existing Tailor/Improve flow reachable from Plan.
- Kept the existing Track/applications flow reachable from Report.
- Left Run, Coach, HealthKit, Garmin, signing, and paid-services work out of scope.

### Validation
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "generic/platform=iOS Simulator" build` succeeded.
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test` succeeded.

### Next Recommended Action
Implement Story 5 by adding a Run entry point without changing GPS/background-location behavior, or approve a product identity cleanup story before expanding the shell further.

## 2026-05-13

### Task Summary
Implemented Story 5 for the RunSmart iOS improvement by adding a dedicated Run tab surface without changing GPS behavior.

### Files Changed
- `ResumeBuilder IOS APP/App/MainTabViewV2.swift`
- `ResumeBuilder IOS APP/Core/DesignSystem/Components/ResumlyTabBar.swift`
- `ResumeBuilder IOS APP/Features/V2/Run/RunView.swift`
- `docs/specs/runsmart-ios-ia-mapping.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Replaced the middle tab label/icon with Run/runner.
- Added disabled GPS start and manual log placeholders to avoid permission or tracking changes.
- Kept the existing Design/redesign flow reachable from the Run surface while product ownership remains unresolved.
- Left Coach, HealthKit, Garmin, signing, paid services, location permissions, and background GPS behavior out of scope.

### Validation
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "generic/platform=iOS Simulator" build` succeeded.
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test` succeeded.

### Next Recommended Action
Implement Story 6 by placing Coach contextually from the existing shell surfaces without adding a sixth tab, or approve product identity cleanup before expanding more screens.

## 2026-05-13

### Task Summary
Removed visible ResumeBuilder-era flows from the RunSmart Stories 1-5 shell after user correction.

### Files Changed
- `ResumeBuilder IOS APP/App/MainTabViewV2.swift`
- `ResumeBuilder IOS APP/Features/V2/Today/TodayView.swift`
- `ResumeBuilder IOS APP/Features/V2/Plan/PlanView.swift`
- `ResumeBuilder IOS APP/Features/V2/Run/RunView.swift`
- `ResumeBuilder IOS APP/Features/V2/Report/ReportView.swift`
- `ResumeBuilder IOS APP/Features/V2/Profile/ProfileViewV2.swift`
- `.agent-os/project-progress.md`
- `docs/specs/runsmart-ios-ia-mapping.md`
- `tasks/lessons.md`
- `tasks/session-log.md`

### Decisions Made
- Removed Score/ATS, Tailor/Improve, Design/redesign, applications/job tracking, resume upload, credits, and resume copy from the visible RunSmart shell.
- Kept Today, Plan, Run, Report, and Profile as RunSmart-only placeholder surfaces until approved running data models are connected.
- Recorded a new Agent OS lesson: do not expose ResumeBuilder-era flows in the RunSmart shell unless explicitly requested.
- Verified that `IOS RunSmart app.xcodeproj` currently cannot be read by `xcodebuild` because it is missing `project.pbxproj`.

### Validation
- `rg` check found no visible ResumeBuilder-era references in the active RunSmart shell files.
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "generic/platform=iOS Simulator" build` succeeded.
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test` succeeded.

### Next Recommended Action
Repair or replace the broken `IOS RunSmart app.xcodeproj` so the buildable Xcode project name matches RunSmart, then continue with Story 6.

## 2026-05-14

### Task Summary
Implemented route feature Story 5: MVP route matching for saved and benchmark routes.

### Files Changed
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/RouteMatchingService.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `IOS RunSmart app/Core/DesignSystem/Components/RunSmartTabBar.swift`
- `IOS RunSmart app/Core/DesignSystem/Components/GlassCard.swift`
- `IOS RunSmart app/Features/V2/Profile/ProfileViewV2.swift`
- `IOS RunSmart appTests/DBProfileReferenceTests 2.swift`
- `tasks/todo.md`
- `tasks/lessons.md`

### Decisions Made
- Added deterministic MVP matching using distance delta, start/end proximity, sampled shape similarity, and reversed-route detection.
- Stored high-confidence matches on `RecordedRun.routeMatchResult.routeID`; possible/no-match states keep candidate details without attaching a route.
- Wired matching through `processCompletedActivity` so in-app GPS runs and Garmin imports share the same route path.
- Updated local run persistence to replace existing provider/id runs so route match metadata can be saved after import.
- Fixed small pre-existing compile blockers in untracked migration files that prevented Story 5 tests from building.

### Validation
- Focused Story 5 route tests passed on iPhone 17 simulator:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingReturnsHighConfidenceForSameRoute" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingMarksNearbyNoisyRouteAsPossibleWithoutAttaching" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingReturnsNoMatchForUnrelatedRoute" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingHandlesReversedRouteAsMatch" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingIgnoresManualRouteLessRuns" test`

### Next Recommended Action
Implement Story 6 by calculating benchmark comparison data from runs with high-confidence benchmark route matches.

## 2026-05-14

### Task Summary
Implemented route feature Story 6: Benchmark Comparison Data.

### Files Changed
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/BenchmarkRouteAnalyticsService.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Kept Story 6 data-only; no benchmark comparison UI was added.
- Added comparison models for current/previous/PB performance, all-time averages, monthly averages, and recent trend.
- Calculated comparisons only when the run has a high-confidence attached match to a saved route that is benchmark-enabled.
- Used the caller-provided calendar for monthly aggregation so local month boundaries are respected.
- Exposed `benchmarkComparison(for:)` through the RunSmart service boundary for Story 7.

### Validation
- Focused Story 6 benchmark comparison tests passed on iPhone 17 simulator:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonReturnsFirstRunNotEnoughHistory" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonUsesPreviousPBAndAveragesAcrossGarminAndRunSmartRuns" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonMonthlyAverageRespectsLocalCalendarMonthBoundary" test`
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Build still reports pre-existing asset catalog warnings for unassigned AppIcon children.

### Next Recommended Action
Implement Story 7 by adding a benchmark comparison card to post-run and run report detail surfaces using `benchmarkComparison(for:)`.

## 2026-05-14

### Task Summary
Implemented route feature Story 7: Benchmark Comparison Card In Run Reports.

### Files Changed
- `IOS RunSmart app/Features/Routes/BenchmarkComparisonCard.swift`
- `IOS RunSmart app/Services/BenchmarkComparisonPresentation.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Kept analytics in Story 6 services and added a UI-only card/loader for Story 7.
- Rendered route name, match confidence, previous/PB/monthly/trend tiles, and deterministic coach insights.
- Added the card to post-run summaries, Garmin run reports, and saved run report detail screens.
- Resolved saved report details back to `RecordedRun` through `recentRuns()` and report run IDs; reports without a matching benchmark run quietly omit the card.
- Added focused tests around first-run and improved-run presentation copy.

### Validation
- Focused Story 7 presentation tests passed on iPhone 17 simulator:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonPresentationShowsFirstRunHistoryPrompt" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonPresentationShowsImprovementAgainstPreviousAndMonth" test`
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Build still reports pre-existing warning noise from older resume-era view models and AppIntents metadata extraction, but no Story 7 compile/test failures.

### Next Recommended Action
Implement Story 8: Route Discovery Ranking MVP.

## 2026-05-14

### Task Summary
Implemented route feature Story 9: Garmin Import Processing Into Route Flow.

### Files Changed
- `IOS RunSmart app/Services/Garmin/GarminImportProcessor.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Added a testable Garmin import processor to normalize recent Garmin activities into newest-first `RecordedRun` values.
- Fetch route points before route matching when Garmin map data is available.
- Keep route-less Garmin imports processable when map data is missing.
- Skip hidden Garmin activities before selecting the newest import.
- Deduplicate duplicate Garmin rows by provider activity id before route point loading.
- Route Supabase Garmin sync through `processCompletedActivity` so matching, report generation, workout completion, and benchmark report cards use the same path as recorded runs.
- Persist canonical completed runs even when route matching returns nil, so missing-map imports do not disappear from local history.

## 2026-05-24

### Task Summary
Implemented the App Store readiness closeout plan for local pre-archive readiness: deterministic DEBUG-only screenshot mode, full iPhone screenshot asset generation, App Store Connect portal value documentation, and validation gates.

### Files Changed
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `fastlane/Fastfile`
- `fastlane/scripts/capture-app-store-screenshots.sh`
- `fastlane/screenshots/en-US/`
- `docs/qa/app-store-connect-closeout-2026-05-24.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Kept screenshot mode behind `#if DEBUG` and `-RUNSMART_SCREENSHOT_MODE` so Release/App Store archive behavior remains production-backed.
- Reused the existing `-INITIAL_TAB` launch argument and made matching case-insensitive because `RunSmartTab` raw values are title-cased.
- Used `MockRunSmartServices`/preview data for screenshots to avoid live user data, credentials, Supabase calls, onboarding, HealthKit, Garmin, or location prompts.
- Wired `fastlane screenshots` to a local simulator capture script that validates exact required image dimensions.
- Moved the old sign-in screenshot to a supplemental `99_signin` filename so the first five upload-sorted screenshots are product screens.

### Validation
- `git diff --check` passed.
- `bash -n fastlane/scripts/capture-app-store-screenshots.sh` passed.
- No untracked Swift files were found under the app or test targets.
- `bash fastlane/scripts/capture-app-store-screenshots.sh` passed after fixing the tab argument casing and increasing the capture settle delay.
- `sips` confirmed all five 6.9-inch product screenshots are `1320 x 2868` and all five 6.1-inch product screenshots are `1170 x 2532`.
- Visual inspection confirmed screenshots are tab-specific, nonblank, free of auth/onboarding overlays, and use deterministic sample data.
- Focused `RunSmartReadinessTests` passed with signing disabled on an iPhone 17 Pro simulator.
- Built app metadata confirmed bundle id `com.runsmart.lite`, display name `RunSmart`, version `1.0`, build `5`, iPhone-only device family, encryption export flag `false`, HealthKit/location permission strings, release URLs, and Garmin gateway URL.

### Remaining Portal-Only Work
- After the merged archive is uploaded and processed in App Store Connect, select the processed build, confirm privacy questionnaire/category/age rating/screenshots/reviewer notes, and enter demo credentials directly in the portal.

### Validation
- Focused Story 9 tests passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorHydratesRoutePointsAndOrdersNewestFirst" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorKeepsRouteLessRunWhenMapDataIsMissing" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorSkipsHiddenRunsBeforeSelectingNewest" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorDedupesDuplicateProviderActivities" test`
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Build still reports pre-existing warning noise from older resume-era view models and AppIntents metadata extraction, but no Story 9 compile/test failures.

### Next Recommended Action
Implement Story 10: TestFlight Polish And Privacy Review.

## 2026-05-14

### Task Summary
Implemented route feature Story 10: TestFlight Polish And Privacy Review. Physical-device background/battery QA remains before external beta.

### Files Changed
- `RunSmartInfo.plist`
- `IOS RunSmart app/Features/Routes/SaveRouteSheet.swift`
- `IOS RunSmart app/Features/Routes/RouteDetailView.swift`
- `IOS RunSmart app/Features/Run/RunTabView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `docs/qa/testflight-checklist.md`
- `docs/qa/ios-qa-checklist.md`
- `docs/qa/route-benchmark-testflight-notes.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Clarified location permission strings around outdoor runs, benchmark-route progress, and background use while a run is active.
- Added route-save privacy copy that explains saved routes contain GPS points and Garmin activities are not deleted.
- Added saved-route deletion from route details with RunSmart-only deletion copy.
- Added weak-GPS messaging so poor accuracy does not overpromise route matching.
- Added Garmin missing-map copy and a loading state for route point fetches.
- Added TestFlight release notes and manual QA checks for routes, benchmark limitations, battery, and background behavior.

### Validation
- `plutil -lint RunSmartInfo.plist "IOS RunSmart app/PrivacyInfo.xcprivacy"` passed.
- Static copy check found the updated location, weak GPS, Garmin missing-map, privacy, and TestFlight notes strings.
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Full iPhone 17 test pass succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" test`
- Build/test still emit pre-existing warning noise from older resume-era view models and AppIntents metadata extraction, but no Story 10 failures.

### Next Recommended Action
Run a physical-device TestFlight pass for background GPS/battery, then archive/upload when signing and App Store Connect are ready.
## 2026-05-23

### Task Summary
Implemented the RunSmart iOS TestFlight Readiness Audit plan through the safe local fixes and validation that can be completed without release-owner credentials or physical-device access.

### Files Changed
- `IOS RunSmart app/Services/RouteSuggestionRanker.swift`
- `IOS RunSmart app/Features/Routes/RouteCreatorView.swift`
- `IOS RunSmart appTests/RouteRankingTests.swift`
- `IOS RunSmart app/Services/Supabase/AppLinks.swift`
- `IOS RunSmart app/Features/Auth/SignInView.swift`
- `IOS RunSmart app/Services/HealthKit/HealthKitSyncService.swift`
- `docs/qa/testflight-readiness-audit-2026-05-23.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Treated route surface selection as a release-readiness bug because Road/Trail controls were visible but not wired into ranking.
- Kept surface ranking conservative because current route data does not persist an explicit surface field.
- Replaced placeholder external URLs with live RunSmart URLs and added a Terms URL for sign-in legal copy.
- Made Terms and Privacy tappable on the sign-in screen without changing the overall auth flow.
- Cleaned up HealthKit optional read-type insertion warnings without changing HealthKit behavior.

### Validation
- Swift parse validation passed for route ranking implementation and tests.
- Generic simulator build-for-testing passed with `/tmp/runsmart-audit-derived-data`.
- iPhone 17 Pro simulator install and launch passed for `com.runsmart.lite`.
- Launch smoke reached the RunSmart sign-in screen with Sign in with Apple visible.
- Focused `RouteRankingTests` simulator execution stalled during simulator launch/test execution and was stopped; record as blocked, not passed.
- XcodeBuildMCP UI snapshot failed with no translation object returned for the simulator.
- Public marketing, support, privacy, terms, and account deletion URLs responded successfully.

### Next Recommended Action
Retry focused XCTest execution from a healthy simulator, then complete authenticated Today/Coach/route/post-run smoke and physical-device GPS/background/HealthKit QA before TestFlight submission.
## 2026-06-03

### Task Summary
Continued RunSmart iOS 1.0.1 work from the latest implementation branch at `origin/version-2` in an isolated worktree/branch, then made one small reviewable cleanup plus simulator QA harness hardening.

### Files Changed
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `IOS RunSmart app/Services/VoiceCoachService.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Created/used isolated branch `codex/1.0.1-version2-continue` from `origin/version-2` (`4c4d1ce`) instead of the frozen v1.0 review branch.
- Treated `origin/version-2` as the current implementation branch because it contains the Sprint 11 1.0.1 UX/voice work; noted but did not merge the separate divergent `origin/claude/distracted-proskuriakova-f558f2` security/spec branch.
- Kept the code change small: replaced deprecated AVAudioSession `.allowBluetooth` with `.allowBluetoothHFP` for voice coach playback.
- Added DEBUG-only environment-variable fallbacks for screenshot mode (`RUNSMART_SCREENSHOT_MODE=1`) and initial tab (`RUNSMART_INITIAL_TAB`) because simulator launch arguments produced launch/background-only captures in this environment.

### Validation
- `git fetch --all --prune` succeeded against `https://github.com/nadavyigal/IOS-runsmart-light-app-.git`.
- Branch evidence: `git branch --show-current` returned `codex/1.0.1-version2-continue`; branch was created from `origin/version-2`.
- Generic simulator build passed with signing disabled:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-101-version2-derived CODE_SIGNING_ALLOWED=NO build`
- Post-cleanup generic simulator build passed again after the screenshot harness update:
  `/tmp/runsmart-101-version2-build-after-screenshot-env.log`
- Test target build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/runsmart-101-version2-derived CODE_SIGNING_ALLOWED=NO build-for-testing`
- Full `xcodebuild test` built and installed, then stalled silently after launch; it was terminated and not counted as passed.
- Simulator screenshots captured on iPhone 17 Pro:
  `/tmp/runsmart-101-version2-screenshots-env/Today.png`
  `/tmp/runsmart-101-version2-screenshots-env/Plan.png`
  `/tmp/runsmart-101-version2-screenshots-env/Run.png`
  `/tmp/runsmart-101-version2-screenshots-env/Report.png`
  `/tmp/runsmart-101-version2-screenshots-env/Profile.png`
- Visual inspection confirmed the redesigned tabs render. Known visual issue observed: the Today week carousel/card is clipped on the right edge in the current upstream implementation.
- Artifact guard check found no local release/archive/upload/submit activity. Versus `origin/main`, `origin/version-2` already carries the intentional future 1.0.1/build 7 project-version bump; signing, bundle id, and entitlements were not changed in this continuation.

### Remaining Risks
- No physical-device voice cue/audio playback QA was performed.
- No live web endpoint or `VOICE_COACH_ENABLED` flag verification was performed.
- No dedicated `VoiceCoachService` XCTest exists yet.
- Bridge files requested in the work packet (`PROJECT-BRIDGES/runsmart-web.md`, `PROJECT-BRIDGES/runsmart-ios.md`) were not present in the local workspace.

### Next Recommended Action
B5 voice coach QA hardening: verify the deployed `/api/coach/voice-cue` flag/contract, run physical-device audio/mute testing, and add a narrow test seam for request construction or disabled-state handling.

## 2026-06-14

### Task Summary
Investigated user smoke-test failures for delete account, register/sign in again, and Garmin connect from Xcode logs plus production Supabase logs. Source fixes are complete locally; production deployment and live smoke are still required before App Store resubmission.

### Files Changed
- `IOS RunSmart app/Services/Garmin/GarminBridge.swift`
- `supabase/functions/delete_account/index.ts`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/v0/app/api/devices/garmin/connect/route.ts`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/v0/app/api/devices/garmin/callback/route.ts`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/v0/app/api/devices/garmin/oauth-state.ts`
- `docs/qa/app-store-readiness-checklist.md`
- `tasks/todo.md`
- `tasks/progress.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Findings
- Supabase Edge Function logs showed `delete_account` returning 500 during the deletion smoke.
- Supabase Postgres logs showed `cannot delete from view "garmin_activity_points"` at the matching failure time.
- Xcode logs showed Garmin connect ending as `canceled`, and source inspection found the iOS native callback was not completing the gateway callback exchange with Garmin `code`/`state`.
- RunSmart web Garmin connect source prioritized the environment redirect over the native request redirect and allowed only `http`/`https`, preventing the app's registered `runsmart://` callback from being used.

### Decisions Made
- Removed direct deletion from `garmin_activity_points` in `delete_account`; production treats it as a view and the underlying `garmin_activities` delete covers the data.
- Made iOS Garmin OAuth POST the callback `code` and `state` to the gateway callback endpoint before polling for the connection.
- Updated the web Garmin gateway to let the native request redirect win, allow `runsmart://`, and carry native auth/profile identity through signed OAuth state for callback persistence.

### Validation
- iOS simulator build passed with signing disabled:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-bugfix-dd CODE_SIGNING_ALLOWED=NO build`
- RunSmart web type-check passed:
  `npm run type-check` from `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/v0`.
- `git diff --check` passed in both the iOS app repo and RunSmart web repo.
- Deno validation was not run because `deno` is not installed in this environment.

### Remaining Risks
- Supabase Edge Function deployment was not performed because Supabase CLI/token deploy access is unavailable in this environment.
- RunSmart web/Vercel deployment was not performed because deploy permission is unavailable in this environment.
- Live delete-account, register/sign-in-again, and Garmin-connect smoke still must be rerun after production deployment.

### Next Recommended Action
Deploy the patched Supabase `delete_account` Edge Function and RunSmart web Garmin gateway, then rerun live SIWA/register, Garmin connect, delete account, and register/sign in again smoke before archiving or resubmitting build 14.

## 2026-06-15

### Task Summary
Reran RunSmart 1.0.2 build 14 release smoke after the deployment handoff. Current source is archive-compile ready, but full authenticated iOS smoke remains blocked in this environment by simulator Sign in with Apple error 1000.

### Files Changed
- `docs/qa/app-store-readiness-checklist.md`
- `tasks/todo.md`
- `tasks/progress.md`
- `tasks/session-log.md`

### Findings
- Current app repo is `main` at `c543ffe`, clean before documentation updates.
- Version/build remain `1.0.2 (14)` and bundle id remains `com.runsmart.lite`.
- Fresh simulator sign-in screen shows Sign in with Apple and visible HealthKit disclosure.
- The local simulator still returns `ASAuthorizationError 1000` when tapping Sign in with Apple, so the Garmin connect, delete account, and re-register paths could not be completed locally.
- Supabase logs show patched `delete_account` version 2 no longer returns 500; auth deletion and later Apple signup/login occurred after the patched deployment. The function returned 207 due to non-critical cleanup warnings.
- Vercel production runtime logs are still permission-limited in this environment, so Garmin callback traffic was not independently confirmed.

### Validation
- Debug simulator build passed with signing disabled:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Debug -destination "platform=iOS Simulator,id=FCC9843B-C0F3-4F7F-A04D-EF2C4875888B" -derivedDataPath /tmp/runsmart-release-smoke-20260615-dd CODE_SIGNING_ALLOWED=NO build`
- Simulator install and launch passed for `com.runsmart.lite` after uninstalling the existing simulator app.
- UI snapshot confirmed `RunSmart`, `Sign in with Apple`, and `HealthKit reads approved data and can save completed GPS runs`.
- Release iphoneos build passed with signing disabled and Xcode store validation:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -derivedDataPath /tmp/runsmart-release-smoke-20260615-release-dd CODE_SIGNING_ALLOWED=NO build`
- Release build produced one HealthKit deprecation warning for `HKWorkout` init, not a failure.
- `plutil -lint RunSmartInfo.plist "IOS RunSmart app/PrivacyInfo.xcprivacy"` passed.
- `git diff --check` passed.
- Static scan found SIWA `.fullName`/`.email`, visible HealthKit copy, no name/email onboarding text-field match, and no CareKit match.
- Built simulator app metadata confirmed bundle id `com.runsmart.lite`, version `1.0.2`, build `14`, `ITSAppUsesNonExemptEncryption=false`, full Supabase URL, and Garmin gateway URL.

### Next Recommended Action
Run the final live smoke on an Apple-auth-capable physical device or TestFlight build: SIWA -> Garmin connect -> delete account -> SIWA re-register. If that passes, archive/upload/select build 14 and resubmit.

### Device Install And Archive Recovery
Investigated the physical-device Xcode install failure reported on 2026-06-15. The failing Debug app bundle had expected metadata/signing, and direct CoreDevice install plus direct launch succeeded for `com.runsmart.lite`, so the original Xcode error is consistent with a wireless Xcode/CoreDevice install-worker connection issue rather than a broken app package.

### Additional Validation
- Direct physical-device install passed with `devicectl device install app`.
- Direct physical-device launch passed with `devicectl device process launch`.
- Debug generic iphoneos build passed with signing disabled:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Debug -destination "generic/platform=iOS" build CODE_SIGNING_ALLOWED=NO`
- Fresh Release archive passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-build14-AppStore-20260615.xcarchive" archive -allowProvisioningUpdates`
- Non-upload App Store export passed:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-build14-AppStore-20260615.xcarchive" -exportPath "build/RunSmart-build14-AppStoreExport-20260615" -exportOptionsPlist ExportOptionsAppStore.plist -allowProvisioningUpdates`
- Exported IPA inspection passed: bundle id `com.runsmart.lite`, version `1.0.2`, build `14`, `ITSAppUsesNonExemptEncryption=false`, Apple Distribution signing, HealthKit, Sign in with Apple, associated domains, `get-task-allow=false`, and dSYM symbols.

### Remaining Risk
The authenticated SIWA -> Garmin connect -> delete account -> SIWA re-register smoke was not completed by automation in this session because simulator Sign in with Apple still fails locally with `ASAuthorizationError 1000`. Run that live flow on the physical device or TestFlight build before uploading/resubmitting.

## 2026-06-16

### Task Summary
Added DEBUG-only Demo Mode for simulator recording after Apple Account verification failed inside Simulator. Demo Mode opens RunSmart directly into local demo content and avoids Apple Account, Sign in with Apple, Supabase auth, Garmin auth, HealthKit prompts, production analytics, and destructive backend actions.

### Files Changed
- `IOS RunSmart app/App/RunSmartDemoMode.swift`
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `IOS RunSmart app/Core/RunSmartServiceProviding.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart app/PreviewSupport/RunSmartPreviewData.swift`
- `IOS RunSmart app/Services/Analytics/AnalyticsService.swift`
- `IOS RunSmart app/Services/RunSmartAnalytics.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseSession.swift`
- `docs/specs/demo-mode-simulator-recording.md`
- `docs/qa/demo-mode-simulator-recording-checklist.md`
- `tasks/todo.md`

### Validation
- `git diff --check` passed.
- Debug simulator build passed through XcodeBuildMCP.
- Installed and launched the Debug app with `DEMO_MODE=true` and `RUNSMART_INITIAL_TAB=Today`; launch succeeded.
- UI snapshots confirmed Today bypassed auth and showed demo content for Alex Morgan, Profile showed Garmin/HealthKit connected states, and Account showed Demo Mode warning plus disabled sign-out/delete controls.
- Release simulator compile was attempted with signing disabled but interrupted after prolonged whole-module Swift compilation; no demo-code error appeared before interruption. The pre-existing HealthKit `HKWorkout` deprecation warning appeared.

### Remaining Risk
Demo Mode is recording-only evidence. It must not be used as App Review account-cycle proof; live SIWA/delete-account smoke still requires an Apple-auth-capable physical device or TestFlight build.

## 2026-06-22

### Task Summary
Implemented PR #55 HRV dual-source attribution plan for Garmin readiness. RunSmart now preserves HRV source through HealthKit snapshot persistence, Garmin mapping, recovery snapshots, wellness trends, and Today/Recovery UI attribution.

### Files Changed
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/HealthKit/HealthKitSyncService.swift`
- `IOS RunSmart app/Services/Garmin/GarminMappers.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Features/Recovery/RecoveryDashboardView.swift`
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/PreviewSupport/RunSmartPreviewData.swift`
- `IOS RunSmart appTests/HRVSourceTests.swift`
- `tasks/progress.md`
- `tasks/session-log.md`

### Findings
- HealthKit HRV was previously stored as an averaged scalar, with no source metadata preserved.
- Garmin direct wellness HRV now takes precedence over local HealthKit HRV when both are available.
- HealthKit HRV samples are classified from `HKQuantitySample.sourceRevision.source.bundleIdentifier` as Garmin, Apple Health, or unknown.
- Old persisted HealthKit snapshots still decode because missing `hrvSource` defaults to unknown.
- Recovery and Today HRV trend rows can now show source attribution without changing unrelated Body Battery branding.

### Validation
- `xcodebuild build-for-testing -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-hrv-source-dd CODE_SIGNING_ALLOWED=NO -quiet` passed.
- `xcodebuild test-without-building -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,id=66F09A08-D5EE-467D-936D-E1406E5FEE0E" -only-testing:"IOS RunSmart appTests/HRVSourceTests" -derivedDataPath /tmp/runsmart-hrv-source-dd CODE_SIGNING_ALLOWED=NO -quiet` passed.
- `xcodebuild build -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-hrv-source-dd CODE_SIGNING_ALLOWED=NO -quiet` passed.
- `git diff --check` passed.

### Remaining Risk
Real Garmin Connect HealthKit metadata still needs a physical-device or TestFlight proof pass before App Store resubmission. This session did not archive, upload, push, or open the PR.
## 2026-06-25

### Task Summary
Ran a Product Design audit of the RunSmart iOS app, saved 13 simulator screenshots plus audit notes, then implemented the highest-impact UX fixes.

### Files Changed
- `audits/product-design-2026-06-25/audit-notes.md`
- `audits/product-design-2026-06-25/screenshots/*.jpg`
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `IOS RunSmart app/DesignSystem/RunSmartDesignSystem.swift`
- `IOS RunSmart app/Features/Plan/FlexWeekReasonPicker.swift`
- `IOS RunSmart app/Features/Profile/ProfileTabView.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Run/RunTabView.swift`
- `IOS RunSmart app/Features/Wellness/GarminWellnessViews.swift`
- `tasks/todo.md`
- `tasks/progress.md`
- `tasks/session-log.md`

### Changes
- Added tab-bar hiding during active run and post-run review states.
- Added confirmation before finishing/saving a run, with short-run-specific copy.
- Added short-activity review messaging so 0.00 km/test runs are not presented as full training wins.
- Made disabled neon buttons visually disabled and added Flex Week disabled CTA guidance.
- Clarified Profile Garmin Wellness as an action row instead of a status-dot row.
- Allowed Garmin Wellness health interpretation text to wrap instead of truncating.

### Validation
- `git diff --check` passed.
- XcodeBuildMCP Debug simulator build passed with signing disabled.
- Demo-mode smoke passed for Run: active run hides tab bar, Finish prompts before save, short-run summary shows review copy.
- Demo-mode smoke passed for Profile/Garmin Wellness/Flex Week runtime snapshots.

### Remaining Risk
- Physical-device, Dynamic Type, VoiceOver, real outdoor GPS, HealthKit, and Garmin production data checks were not run in this session.

## 2026-06-26 - Build 18 ASC/Garmin pre-flight

### Task Summary
Executed the Codex-safe portions of `docs/superpowers/plans/2026-06-26-build18-asc-submission-and-garmin-resend.md`. Confirmed the build-18 Garmin brand fixes are merged locally, revalidated a Release archive, exported a non-upload App Store IPA, and updated Garmin handoff docs. Apple ID-gated upload/submission, live build-18 confirmation, screenshot recapture, and Garmin send remain outside this session.

### Findings
- iOS repo is on `main...origin/main`; the only dirty iOS item at start was the untracked build-18 plan file.
- PR #66 merge commit `5fdea72` is in iOS history.
- Xcode project declares `MARKETING_VERSION = 1.0.4` and `CURRENT_PROJECT_VERSION = 18`.
- Web repo history includes PR #103 merge `83408f6`; `GARMIN-STATUS.md` already records production deployment confirmation.
- Source inspection found `GarminLogoMark` wired in `SecondaryFlowView` and `device_name`/`deviceName` paths present in iOS and web code.
- Apple public lookup confirms live marketing version `1.0.4` with current version date `2026-06-24`, but does not expose build number; it cannot prove build 18 is live.

### Validation
- Release archive passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-build18-AppStore-20260626-codex.xcarchive" -allowProvisioningUpdates -quiet archive`
- Non-upload App Store export passed:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-build18-AppStore-20260626-codex.xcarchive" -exportPath "build/RunSmart-build18-AppStoreExport-20260626-codex" -exportOptionsPlist ExportOptionsAppStore.plist -allowProvisioningUpdates -quiet`
- Exported IPA metadata: display name `RunSmart`, bundle id `com.runsmart.lite`, version `1.0.4`, build `18`, `ITSAppUsesNonExemptEncryption=false`.
- Exported IPA entitlements: Sign in with Apple, associated domains, HealthKit, `beta-reports-active=true`, and `get-task-allow=false`.
- dSYM present: `build/RunSmart-build18-AppStore-20260626-codex.xcarchive/dSYMs/IOS RunSmart app.app.dSYM`.
- Known warning remains: deprecated `HKWorkout` initializer in `HealthKitSyncService.swift`.
- `xcodebuild -validate-for-store` was not run because this installed Xcode rejects `-validate-for-store` as an invalid CLI option.

### Remaining
- Founder: upload/submit build 18 to App Store Connect, wait for Apple approval, and confirm build 18 genuinely live.
- After live confirmation: recapture and verify all 6 Gate-4 screenshots against the build-18 Garmin wordmark/device attribution fixes.
- Founder: review/send the Garmin reply with the new zip attached. The 01-03 logo remains the documented Garmin corporate wordmark fallback, not a guaranteed Connect-tile pass.

## 2026-06-29 - Build 18 ASC train recovery after upload rejection

### Task Summary
Responded to the founder's Xcode Organizer upload failure for build 18. App Store Connect rejected `1.0.4 (18)` because `CFBundleShortVersionString = 1.0.4` is no longer open for new build submissions after the previously approved `1.0.4` release. Moved build 18 to the next marketing train, `1.0.5 (18)`, and reran local archive/export validation.

### Findings
- GitHub PR #66 is merged to `main`: `5fdea72129716cf6ba497c5adbc07f13508e85d4`, base `main`, merged 2026-06-26.
- Local iOS `main` is tracking `origin/main` at `5fdea72`.
- Web PR #103 is merged to the companion repo: `83408f60d0c989c7a7e416c5af0cbcb2c84538d5`; `GARMIN-STATUS.md` already records production deployment confirmation.
- Public Apple lookup still reports live RunSmart marketing version `1.0.4` with current version release date `2026-06-24T21:05:29Z`; it does not expose build number and `1.0.5 (18)` is not live yet.

### Changes
- Updated `IOS RunSmart app.xcodeproj/project.pbxproj`: `MARKETING_VERSION = 1.0.5` for app and test targets; kept `CURRENT_PROJECT_VERSION = 18`.
- Updated task memory and Garmin handoff docs to use `1.0.5 (18)` for the next founder upload/submission path.

### Validation
- Release archive passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-v1.0.5-build18-AppStore-20260629-codex.xcarchive" -allowProvisioningUpdates -quiet archive`
- Non-upload App Store export passed:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-v1.0.5-build18-AppStore-20260629-codex.xcarchive" -exportPath "build/RunSmart-v1.0.5-build18-AppStoreExport-20260629-codex" -exportOptionsPlist ExportOptionsAppStore.plist -allowProvisioningUpdates -quiet`
- Exported IPA metadata: display name `RunSmart`, bundle id `com.runsmart.lite`, version `1.0.5`, build `18`, `ITSAppUsesNonExemptEncryption=false`.
- Exported IPA entitlements: Sign in with Apple, associated domains, HealthKit, `beta-reports-active=true`, and `get-task-allow=false`.
- dSYM present: `build/RunSmart-v1.0.5-build18-AppStore-20260629-codex.xcarchive/dSYMs/IOS RunSmart app.app.dSYM`.
- Known warning remains: deprecated `HKWorkout` initializer in `HealthKitSyncService.swift`.

### Remaining
- Founder: archive/upload/submit `1.0.5 (18)` to App Store Connect, wait for approval, and confirm `1.0.5 (18)` genuinely live.
- After live confirmation: recapture and verify all 6 Gate-4 screenshots against the build-18 Garmin wordmark/device attribution fixes.
- Founder: review/send the Garmin reply with the new zip attached. The 01-03 logo remains the documented Garmin corporate wordmark fallback, not a guaranteed Connect-tile pass.

## 2026-06-30 - Garmin Report/Activity device attribution fallback

### Task Summary
Patched the remaining Garmin submission risk found in live `1.0.5 (18)` screenshots: Report rows and Run Report detail could still show bare `Garmin` when an individual activity row lacked `device_name`, even though the connection status knew the user's model.

### Changes
- Added a shared `RunSmartAttribution` helper that keeps activity-level Garmin `sourceDeviceName` first and uses the connected Garmin `deviceName` as fallback.
- Wired the main Report/Activity list to fetch connected device statuses and pass the Garmin device name into `ActivityRow`.
- Applied the same fallback to report skeletons, report summaries, cached/generated report details, and deterministic fallback reports.
- Added focused readiness tests covering activity-device precedence, connected-device fallback, and non-Garmin preservation.

### Validation
- `git diff --check` passed.
- Focused attribution XCTest compiled past source validation with only existing warnings, then hung in the local simulator install/launch worker and was interrupted after 109 seconds.
- `xcodebuild build-for-testing` on a fresh DerivedData path also emitted only existing warnings, then hung in Xcode build operations and was interrupted.

### Remaining
- Run a clean Xcode build/test or archive on a healthy Xcode/simulator session.
- Ship a new fixed build through App Store Connect; do not send Garmin screenshots from live `1.0.5 (18)` because Report/Run Report evidence still showed bare `Garmin`.
- After the fixed build is live, recapture all 6 Gate-4 screenshots and verify screens 04-06 visibly show `Garmin Forerunner 965` or the user's actual connected Garmin model.

## 2026-07-05 - WP-15 activation diagnostic + WP-34 credential-guard recovery

### Task Summary
D7 App Store readout showed 0/12 users with `run_completed` within 7 days despite some reaching `plan_generated`; 94.7% onboarding drop. Audited funnel instrumentation and post-plan UX. Searched exhaustively for lost WP-34 Garmin credential-guard branch.

### WP-15 Findings
- Event names on current code paths align with PostHog dashboards (`run_completed` canonical; not `run_logged`). `onboarding_completed` fires in `OnboardingView` on "Start RunSmart" tap — before aha moments and before async profile/plan work completes (funnel timing nuance).
- Post-plan affordances exist on main: `FirstRunActivationSheet`, Today `upNext` "Start Next Run" (PR #62), `plan_run_cta_tapped` bridge event, WP-20 reminder path.
- **Root cause (plan → run):** `saveTrainingGoal` kicks off `regenerateTrainingPlan` in a detached `Task` and returns `true` immediately. `presentFirstRunActivationIfNeeded` queried `nextWorkouts` before `persistGeneratedPlan`, so `activePlan` had no workouts → first-run sheet silently skipped → no `first_run_cta_viewed` / weak path to `run_started`.
- **Onboarding 94.7% drop (separate):** Sign-in wall + 5 onboarding steps + 2 aha screens before main app; not Garmin-related. Permission denial events not instrumented.
- GPS/Health blockers possible at run start but secondary for cohort that reached `plan_generated`.

### WP-15 Changes
- `RunSmartLiteAppShell.swift`: `firstRunnableWorkoutAfterPlanGeneration()` polls `nextWorkouts` up to 45s before presenting `FirstRunActivationSheet`.

### WP-34 Recovery
- `baa19aa` / `codex/wp24-garmin-credential-guard` not found: reflog, all branches, `git fsck --unreachable`, stash, `git fetch` + `ls-remote`, May-2025 bundle, gstack/other clones.
- Logged incident in `tasks/ERRORS.md`. No re-implementation (founder decision: re-scope WP-34 or park).

### Validation
- One-file Swift change; isolated `xcodebuild` attempted but blocked by concurrent DerivedData lock / long compile — not claimed as green build this session.

### Metrics to watch
- `plan_generated` → `plan_run_cta_tapped` → `run_started` → `run_completed` (target >=20% plan-to-run on next cohort).

### Not done
- No broad onboarding redesign, no permission analytics, no Garmin scope, no WP-34 re-implementation, no ASC release of fix build.
## 2026-07-11 - WP-42 HealthKit raw HogQL funnel autopsy

### Result
- Queried PostHog project 171597 read-only through `2026-07-11 14:57:58 UTC` for the first WP-40 build `1.0.7 (21)` cohort.
- First production-looking disclosure was `2026-07-11 05:48:24.950 UTC`.
- The only production-looking build/disclosure person also had TestFlight and sideloaded events; person-stable union exclusion removed that person, leaving 0 clean build users and 0 clean disclosure viewers.
- Reported no readable first cohort, no funnel percentage, and no largest-loss step rather than manufacturing a 0% funnel.

### Evidence and scope
- Verified release anchor `236dde0` and Xcode version/build `1.0.7 (21)`.
- Verified UTC project timezone, canonical native app/library properties, HealthKit event taxonomy, and current test-account filter.
- Frozen exclusion/readiness HogQL returned `1 production-looking / 1 excluded / 0 clean` twice; TestFlight and sideloaded exclusions fully overlap.
- Added `docs/qa/reports/runsmart-wp40-healthkit-raw-hogql-funnel-autopsy-2026-07-11.md` with exact HogQL, exclusion audit, privacy-safe appendix, and re-read condition.
- No PostHog objects/configuration, app code, instrumentation, backend, release, HealthKit behavior, or sensitive user/health data changed.
