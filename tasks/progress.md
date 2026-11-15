## 2026-11-15 — 1.2.5 (43) App Review preparation

**Status:** App Store Connect version 1.2.5 (43) staged at Ready for Review at 12:55 Israel time.
**Current Phase:** Build 43 is Testing in Apple Watch Beta. One tester installed it and shows 18 sessions.
**Active Story:** Submit build 43 to App Review with automatic release after approval.
**Last Completed Story:** Draft verified after reload. Founder confirmed demo login. Physical-device tester pass on build 43: NOT VERIFIED. No dated step results were supplied.
**Next Recommended Story:** Get final approval and submit build 43 only after a verified physical pass, if that is still required.
**Blockers:** Physical-device tester pass on build 43 is NOT VERIFIED. Final submission approval pending.
**Last Validation:** Archive source `f43ba8d` contains benchmark fix `5c96738`; processed build 43 verified in App Store Connect. The physical pass is not part of that validation.

## 2026-11-07 — 1.2.5 (43) Apple Watch release candidate started

**Status:** PR #165 (Apple Watch workout round trip and deferred Health completion) merged into `main` on the founder's yes (merge `8f35e73`). 1.2.4 (42) is live on the App Store (Apple lookup, released 2026-11-06). Release branch `claude/2026-11-07-release-1-2-5` merges the 1.2.4 release records from PR #177 (`origin/claude/2026-11-05-release-1-2-4`), so `main` will carry them once this branch merges, and sets 1.2.5 (43) in all six build configurations.
**Current Phase:** 1.2.5 (43) uploaded on the founder's yes (2026-11-07 20:08:50); in TestFlight beta review (Waiting for Review) with Apple Watch Beta and RunSmart Internal groups. Next: external tester repeats the Watch round trip on build 43.
**Active Story:** 1.2.5 (43), first public release with the Apple Watch workout round trip.
**Last Completed Story:** PR #165 merged (review fixes `a4bab42`, `acc8e59`).
**Next Recommended Story:** The external tester repeats the paired-Watch round trip on the installed 1.2.5 (43) (`docs/qa/releases/1.2.5/testflight-notes.txt`); record build, date, source and result. Then App Store submission (needs founder yes). Do not upload build 43 again.
**Blockers:** The build 41 Watch pass does not cover `a4bab42`/`acc8e59`; build 43 needs its own paired-Watch pass before submission.
**Last Validation:** 2026-11-07, release source: full suite 863 tests, 862 passed / 0 failed / 1 skipped, `TEST SUCCEEDED`. Archive from `f43ba8d` and exported IPA: 1.2.5 (43) on app and extension, strict deep codesign pass, Apple Distribution, `get-task-allow` false, dSYMs present, backend gate passed (HTTP 200, Apple and email on). Details in `docs/qa/releases/1.2.5/README.md`.
**Last Updated:** 2026-11-11

# 2026-11-14: Coach Mode story 1.2, coach role and invite code

Current Phase: unchanged; Coach Mode (human coaches) epic 1, branch `feat/coach-role-invite`.
Active Story: migration `20261114210000_coach_role_and_invites.sql` (tables `coach_profiles`, `coach_invites`, RPC `get_or_create_my_invite()`), a Coach tab for flagged coaches only, and the invite section (code, link, Copy, Share). Not applied to production; Nadav applies after review. The web repo `Running-coach-` needs the same file in `v0/supabase/migrations/`. Flag a coach with `insert into coach_profiles (user_id, display_name) values ('<uuid>', 'Dana');`. "Coach" here is the human coach, unrelated to the AI coach (`coach_message`, `coaching_style`).
Next Recommended Story: 1.3 (athlete joins with consent, `coach_athlete_links`), then 1.4 (invite link opens the app).
Blockers: migration not applied to production yet.
Last Validation: SQL two-user test `supabase/tests/coach_invites.sql` passes on a throwaway Postgres 17.6 after applying the migration twice; `CoachModeTests` plus `EmailSignInTests` pass on the iPhone 17 Pro simulator.
Last Updated: 2026-11-14

# 2026-11-14: Workout completion save (story 0.1)

Current Phase: unchanged.
Active Story: completed runs mark the planned workout done. `actual_pace` is sent as integer seconds/km (no migration). Failed updates are queued and retried on launch and foreground, dropped after 5 attempts.
Next Recommended Story: Story 0.2 (match logic / `runs.workout_id` / backfill). Not this PR.
Blockers: none. Post-release check: `select count(*) from workouts where completed = true and completed_at > '<release date>';`
Last Validation: 2026-11-14, iPhone 17 simulator, the six workout-completion tests passed (`TEST SUCCEEDED`).
Last Updated: 2026-11-14

# 2026-11-13: Two Swift 6 errors-in-waiting fixed

Current Phase: unchanged; audit item 1 decided by the founder.
Active Story: RunSessionCheckpoint is nonisolated (encoded on the checkpoint queue); StravaUploadCoordinator resolves main-actor singletons inside init, not in default arguments.
Next Recommended Story: the 8 remaining main-actor warnings (LocalRunCueService, analytics, training load, route snapshot).
Blockers: none.
Last Validation: 2026-11-13 iPhone 17 iOS 26.5 full suite 862 passed, 1 skipped, 0 failed; app warnings 22 to 8, none Swift 6 errors.
Last Updated: 2026-11-13

# 2026-11-11: Repo audit, unused views removed

Current Phase: unchanged; repo hygiene pass on `claude/2026-11-11-ios-repo-audit`.
Active Story: delete 4 unreachable views, move 2 reports out of the Xcode project bundle, list the rest for review.
Next Recommended Story: founder review of docs/audits/2026-11-11-repo-audit.md, item 1 (two Swift 6 concurrency errors) first.
Blockers: none. PR #179 Tier 1, code-reviewer APPROVED, awaiting founder merge.
Last Validation: 2026-11-11 iPhone 17 iOS 26.5 full suite 862 passed, 1 skipped, 0 failed before and after.
Last Updated: 2026-11-11

## 2026-11-14 — Story 0.2: runs link to their workout (PR open, not merged)

**Status:** In review on `feat/run-workout-link`. **Active Story:** coach-mode 0.2. **Next:** Nadav applies `supabase/migrations/20261114130000_runs_workout_link.sql` after review (and copies it to the web repo `Running-coach-/v0/supabase/migrations/`), then merge.
Live schema check (production `dxqglotcyirxzyqaxqln`, read-only): `runs.workout_id` did not exist, so the migration adds it (uuid, nullable, FK to `workouts.id` ON DELETE SET NULL, guarded and idempotent) and a partial unique index `runs_workout_id_unique`. After a match, `completeBestMatchingWorkout` sets `runs.workout_id` by `(auth_user_id, source_provider, source_activity_id)` only while the run has none; a queued or not-yet-synced link retries from `RunWorkoutLinkOutbox`. Health, Garmin and in-app runs share that path. A per-account, once-per-install 30-day backfill logs matched/unmatched first (debug dry-run: `-runsmart.debug.runWorkoutBackfillDryRun YES`). Match thresholds unchanged.
**Review fixes (2026-11-15):** migration now has a `runs_enforce_workout_owner` trigger (a run may only link a workout its owner owns), tested in a throwaway Postgres (`supabase/tests/runs_workout_link*.sql`); the link retry queue has a one-pass gate; the backfill skips hidden runs.
**Last Validation:** full suite, iPhone 17 Pro simulator: 888 passed / 0 failed / 1 skipped (21 new tests in `RunWorkoutLinkTests`); SQL test PASS. The link write itself is not covered by a unit test (needs the migrated database).
**Last Updated:** 2026-11-14

## 2026-11-07 — Build 41 Watch round trip passed; PR165 review findings fixed

**Status:** In review. **Current Phase:** Watch release candidate. **Active Story:** PR #165 review fixes and merge of `main` (public 1.2.4). **Last Completed Story:** physical Watch round trip on 1.2.3 (41). **Next Recommended Story:** un-draft PR #165 after a green suite, then cut the 1.2.5 candidate with the Watch app. **Blockers:** none known.

**Physical Watch QA on build 41: PASS, by owner report.** The founder reported on 2026-11-07 that the external tester confirmed both checks: the planned workout appears on the Apple Watch, and the completed run saves back to the iPhone. App Store Connect, read live the same day, shows the tester's iPhone account on 1.2.3 (41) with 14 sessions, no crashes and no TestFlight feedback entries. This closes the "final candidate Watch round trip remains pending" item from 2026-11-02.

**Review findings fixed (8 open threads at head `7d2f9fd`).** Recovery ownership is now bound at the first failed Health import and never adopted by the account that later resolves the lookup; `HealthKitDeferredCompletion.process` rejects ownerless recoveries (Codex P2, CodeRabbit Major). Ownerless records from older builds stay inert rather than guessing an owner. An empty plan workout list keeps deferred completion pending. An unchanged Health route keeps its stored point IDs, so it no longer re-uploads and clears the route match on every sync. The daily wellness snapshot is saved before a failed workout read returns. The exact-ID completion path reloads the run and skips a hidden or removed one. Health-driven plan completion refreshes Apple Watch exports before the plan notification. The tester's email and name were replaced with "the external tester" in five public files; earlier commits still hold them in history.

**Last Validation:** 2026-11-07, merged result (`2c232a0`, branch plus `origin/main`): full suite on iPhone 17 Pro simulator, **863 tests: 862 passed / 0 failed / 1 skipped** (the existing opt-in map-render skip), `TEST SUCCEEDED`. All 5 new and 3 updated recovery/merge tests pass. A second-model review then found that `refreshAppleWorkoutExports` did not recheck the account after its plan fetch, now reached on every Health sync; fixed with a recheck, full suite rerun: same 862 / 0 / 1, `TEST SUCCEEDED`. Version stays 1.2.3 (41) on this branch; `origin/main` still carries 1.2.2 (40) although 1.2.4 (42) is live, so the next candidate must be 1.2.5 (43) or higher.
**Last Updated: 2026-11-07**

## 2026-11-02 — Watch beta accepted by tester; integrated candidate 1.2.3 (41)

Owner reports the external tester completed beta38 tests and all looked good; accepted as tester-reported paired-device evidence. Correct tester the external tester installed on iPhone15ProMax/iOS27.0.1. Reconciled PR165 with main3c2d679 without rewriting history; retained both records and current iPhone features. Reproduced failed→successful unassociated Health lookup losing completion. Deferred recovery persists owner/target, survives transient failure/relaunch, yields to exact Health identity and cannot rematch replacements or replay reports. Independent QA's account-switch/new-exact-ID races fixed with regressions. Final simulator suite: **841 passed /0failed /1existing opt-in map-render skip**,33Watch tests pass. Version1.2.3(41) allocated after live ASC latest40 complete. Source4f20bc0 pushed to PR165; main now mergeable. Signed archive/signatures/versions/HealthKit/privacy/dSYMs and actual-artifact backend HTTP200 pass. Owner approved signing; exported IPA distribution signatures/debugging disabled/dSYMs and actual IPA backend HTTP200 pass. Upload/processing succeeded; build UUIDc554c551-d5d0-4b50-8ffd-6da19b4ea9da attached to Apple Watch Beta. What to Test saved; automatic notification enabled; beta review submitted and live group table verifies Waiting for Review. No public submission/release; final candidate Watch round trip remains pending. See docs/qa/releases/1.2.3-watch-candidate/ and docs/plans/2026-11-02-watch-release-candidate.md. Clean temporary clone protects original worktrees: /private/tmp/runsmart-watch-release-20261102.

## 2026-10-26 — External Watch beta submitted: Waiting for Review

Owner completed signing and private TestFlight review fields, then restored the expired browser session. Existing upload succeeded (no duplicate upload); Apple processing completed for 1.2.1 (38), source `feee81c`. Verified saved review fields without retaining credentials. Added build UUID `1792958d-9264-4ad2-b09e-5f741d314128` to Apple Watch Beta, saved exact testing instructions and submitted for beta review with Automatically notify testers checked. ASC verifies one tester/one build, **Waiting for Review**. Tester remains **No Builds Available** pending Apple approval; delivery/acceptance/install are not claimed. Public1.2.0 unchanged; PR165 draft until physical Watch QA. Existing 749/749 application tests, archive/export/signature/privacy/dSYM and actual-artifact backend checks remain the validation baseline; this continuation changed distribution metadata/docs only. Evidence: `docs/qa/releases/1.2.1-watch-beta/`.

## 2026-10-26 — Approved external Watch beta 1.2.1 (38), local input gate

Owner approved external TestFlight and the named tester invitation. Checked live ASC: build37 latest, no pending newer upload. Committed 1.2.1 (38) across all configurations; app code unchanged from 749/749 test pass. Signed archive and Apple Distribution IPA verified; actual archive/IPA backend HTTP200 checks, privacy, HealthKit, matching versions and dSYMs pass. Created Apple Watch Beta external group and added only the approved tester; actual state No Builds Available. Upload preparation waits in codesign key access; owner asked to approve the protected macOS prompt. Prepared beta-review form; owner must enter contact phone and existing reviewer username/password directly because saved values are masked to automation, then Save. No successful upload/review submission/invitation delivery claim yet. Public1.2.0 unchanged; PR165 draft. Evidence/resume steps: `docs/qa/releases/1.2.1-watch-beta/README.md`.

## 2026-10-26 — PR165 reviewed sync fix and local device archive

Verified CodeRabbit's unchanged-import finding against head b27bf40 (hosted Codex clean at that old head). New change detection preserves local route/consolidation fields and normalizes raw Health timestamps to the ISO8601 store precision. Completion retries are independent; failed uploads use explicit pending/staging and fresh-payload confirmation. Added 10 regressions including real save/reload and fractional timestamp round-trip; final **749/749 tests pass** (746 XCTest + 3 Swift Testing). Signed device Release archive and strict signature/config/HealthKit/dSYM checks pass; actual archived backend HTTP200/provider check passes. Local artifacts: `/Users/nadavyigal/Developer/runsmart-apple-watch-artifacts/2026-10-26/`. Diagnostic build remains 1.2.0 (37); allocate a distinct unused build before authorized internal TestFlight upload. No install/upload, release change, Garmin/Strava activation or production mutation. Apple confirms public 1.2.0; read-only compatible phone-run telemetry is founder/device QA per owner report, not real-user activation or Watch validation. PR165 remains draft pending paired Watch matrix. Evidence: `docs/qa/reports/2026-10-26-apple-workout-candidate.md`.

## 2026-10-25 — Apple Workout draft candidate

Apple Watch track implemented in isolated `/Users/nadavyigal/Developer/runsmart-apple-watch`, branch `codex/apple-watch-workoutkit`, base `61b7cfb`. Existing release checkout untouched. WorkoutKit session-detail send uses current APIs, the phone guide, stable IDs, separate permission flow, capacity/readback checks and queued edit/cancel reconciliation. Health imports refresh late data without duplicate runs, preserve exact identity and failed-lookup state through consolidation, retry exact completion and avoid stale cached completion candidates. Health read choices are shown honestly. Final simulator suite **739 passed / 0 failed** (736 XCTest + 3 Swift Testing, including 14 new tests); actual scheduling denial UI verified. Spec and QA: `docs/specs/2026-10-25-apple-workout.md`, `docs/qa/reports/2026-10-25-apple-workout.md`. Draft PR #165: https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/165 ; **paired physical iPhone/Watch round trip remains required; not release-ready**. No version/archive/upload/submission or production configuration changes.

## 2026-11-05: 1.2.4 (42) submitted to App Review, T7 coach tones

**Status:** Founder said "yes, merge + release". PR #176 merged into `main` (a624885). Release branch `claude/2026-11-05-release-1-2-4` sets 1.2.4 (42) in all 6 configurations. 1.2.3 is skipped because build 41 is the 1.2.3 Watch beta (PR #165, uploaded 2026-11-02). Archived, IPA verified and uploaded to ASC 18:35 host time. Processed; in TestFlight RunSmart Internal; 1.2.4 ASC draft created with build 42 and What's New. Review notes updated by the founder; submitted, Waiting for Review.
**Current Phase:** 1.2.4 (42) Waiting for Review. Automatic release to all users after approval.
**Active Story:** App Review outcome for 1.2.4 (42). Release PR #177 open (version bump and evidence).
**Last Completed Story:** T7 coaching tones merged (PR #176).
**Next Recommended Story:** After approval: merge PR #177, record the live version, and listen to the three tones on a real run. Coach voice clips (open-source TTS, VoxCPM2 candidate) continue in their own session for a later version.
**Blockers:** No device listening evidence (founder chose to check in production). Founder must approve the keychain prompt during export and may need to sign in to ASC.
**Last Validation:** 2026-11-05, full `xcodebuild test` on the app source of `main` a624885 (its project file still says 1.2.2 (40)), iPhone 17 Pro simulator, iOS 26.5: TEST SUCCEEDED, 825 passed, 0 failed, 1 skipped (`RunSharePosterRenderTests.testMapPostersRenderAtExportSize`). The released 1.2.4 (42) commit `a49420e` differs from a624885 only in the 12 version lines of `project.pbxproj`; no test run is recorded on a49420e itself.
**Last Updated:** 2026-11-05

## 2026-11-05 — T7 coach tones merged (PR #176); PR #174 merged

**Status:** PR #174 (1.2.2 release source) merged into `main` on founder's yes, so `main` now matches the live 1.2.2 build. T7 merged into `main` through PR #176 on founder's yes. Founder chose to skip the pre-merge device listening test and check the tones in production. No version bump, no archive, no upload.
**Current Phase:** One tone list (Motivating, Calm, Technical), a saved choice, and that choice on offline cue wording, speech rate and pitch. The AI cue request sends `coachingStyle`.
**Active Story:** none. T7 is in `main`, waiting for the next release build.
**Last Completed Story:** T7 code plus a review fix: sign-out and demo mode now reset the spoken tone, so a previous account's tone is not kept on the phone. `.gitignore` line for `.track-status.md` left uncommitted (tooling, not T7).
**Next Recommended Story:** Optional: a Play button on the Coaching Tone preview so the runner can hear each tone without running. Founder listening test on a physical iPhone after the next archive (build number above 40). Separately approve or reject `docs/qa/2026-10-31-voice-web-change.md` before the web route is edited.
**Blockers:** No device listening evidence. `VOICE_COACH_ENABLED` in production unverified. Web route change not applied, so the server ignores `coachingStyle`. Codex review out of credits.
**Last Validation:** 2026-11-05, full `xcodebuild test` on T7 merged with `main` (incl. #174), iPhone 17 Pro simulator, iOS 26.5: TEST SUCCEEDED, 825 passed, 0 failed, 1 skipped (`RunSharePosterRenderTests.testMapPostersRenderAtExportSize`, needs `TEST_RUNNER_RUN_SHARE_RENDER_DIR`). Not checked on a device.
**Last Updated:** 2026-11-05

## 2026-11-04 — 1.2.2 is live on the App Store

**Status:** 1.2.2 is public on the App Store since 2026-10-30 15:13 UTC (Apple lookup API, id 6768297840, polled 3 times with varying URLs on 2026-11-04, all agree). The public lookup does not show the build number. PR #174 records 1.2.2 (40) as the build selected in the ASC 1.2.2 draft, so the live build is most likely 40. Not checked in App Store Connect.
**Current Phase:** 1.2.2 live. Main does not hold the release source yet: it sits on `codex/release-1-2-2`, PR #174 (draft, 2 commits ahead of main).
**Active Story:** none. This entry only records the release.
**Last Completed Story:** 1.2.2 shipped (build most likely 40, see Status): satellite run sharing (PRs #171, #172), plan recovery and plan-failure analytics (PR #173), stats-only fallback when MapKit cannot load. Apple Watch PR #165 is not in this release.
**Next Recommended Story:** merge PR #174 so main matches the live build. Its progress entry also goes at the top of this file, so keep both entries when resolving. Then confirm in App Store Connect that the live build is 40.
**Blockers:** none.
**Last Validation:** 2026-11-04: Apple lookup API, 3 of 3 polls returned version 1.2.2, release date 2026-10-30T15:13:05Z. Docs only, no tests run.
**Last Updated:** 2026-11-04

Older entries: [tasks/archive/progress-to-2026-10-29.md](archive/progress-to-2026-10-29.md).
