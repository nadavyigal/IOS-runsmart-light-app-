# 2026-11-15: Coach Mode story 1.3, athlete joins a coach with consent

Current Phase: unchanged; Coach Mode (human coaches) epic 1, branch `feat/join-coach-consent`.
Active Story: migration `20261115091000_coach_athlete_links.sql` (table `coach_athlete_links`, RPCs `lookup_invite`, `join_coach`, `my_coach_link`). Settings → "Join a coach" (only when not linked) leads to the code field and the consent screen. A signed-out person starts from "Join a coach" on the sign-in screen; Continue sends them to sign in and the code is kept. Share joins the coach named on the consent screen. Not now does not. Not applied to production. The web repo `Running-coach-` needs the same file in `v0/supabase/migrations/`.
Next Recommended Story: 1.4 (invite link opens the app). Leave coach is 1.5. Coached-by header is 3.3.
Blockers: migration not applied to production yet.
Last Validation: 2026-11-15, SQL coach_athlete_links.sql PASS on throwaway Postgres 17.6 after applying the migration twice; CoachLinkTests 12 passed on iPhone 17 Pro simulator, including Share staying on the code that was shown.
Last Updated: 2026-11-15

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
