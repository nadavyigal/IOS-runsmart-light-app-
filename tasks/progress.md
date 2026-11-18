# 2026-11-18: Coach Mode story 2.4, athlete detail

Current Phase: Coach Mode pilot foundation, story 2.4 on `feat/coach-athlete-detail`, stacked on 2.3 (#204).
Active Story: Coach opens an athlete: two-week strip, day detail with planned vs actual, matched-by-date, revoked and no-plan states. Read-only.
Next Recommended Story: Founder merges #204 then this PR; then 3.1 coach feedback.
Blockers: Stacked on #204; retarget to main after #204 merges.
Last Validation: iPhone 17 simulator, 29 coach tests passed (detail, adherence, read service, plan setup); screens rendered from sample data.
Last Updated: 2026-11-18

# 2026-11-18: Coach Mode story 2.3, athlete list review fixes

Current Phase: Coach Mode pilot foundation, story 2.3 (PR #204) review fixes.
Active Story: Rest days no longer count as planned or missed; roster sorts by status group first, so Needs attention ordering is stable.
Next Recommended Story: Founder merges #204, then 2.4 athlete detail. Race-date Gregorian fix is merged in #205.
Blockers: Current-head review and CI are being refreshed after merging #205 into this branch.
Last Validation: iPhone 17 simulator, WorkoutAdherenceTests and CoachReadServiceTests, 14 passed / 0 failed, including two new tests.
Last Updated: 2026-11-18

# 2026-11-18: Group race date written as Gregorian (follow-up to #197)

Current Phase: Coach Mode pilot foundation, follow-up fix to story 1.7.
Active Story: Group Plan race date now serializes and parses with a Gregorian calendar, whatever calendar the coach's phone uses.
Next Recommended Story: Founder merges this and #204, then 2.4 athlete detail.
Blockers: None. No migration.
Last Validation: iPhone 17 simulator, CoachPlanSetupTests and GroupPlanJoinTests 25 passed; the new test fails on the old code.
Last Updated: 2026-11-18

# 2026-11-17: Coach Mode story 1.8, group plan on join

Current Phase: Coach Mode pilot foundation.
Active Story: When an athlete taps Share for a Group Plan coach, they confirm the group plan, their phone generates it, and only then does `join_coach` run. Individual Plans still join on Share. Migration `20261117160000_lookup_invite_group_plan.sql` replaces `lookup_invite(text)` so it also returns `plan_mode` and, for a group coach, the group settings. `join_coach` is unchanged. Not applied to production. Nadav applies it. Copy the same file to `Running-coach-/v0/supabase/migrations/`.
A race more than 16 weeks out asks the generator for 16 weeks and starts the plan on the race date minus 16 weeks (the final 16 weeks). Before that date, Today keeps the existing empty-workout state. If the plan is saved and `join_coach` then fails, Retry joins again and does not generate again. Cancel leaves that new plan in place and the athlete unlinked.
Next Recommended Story: 2.2 or 6.4, not this branch.
Blockers: migration not applied. Group confirm stays hidden until it is, because an older `lookup_invite` has no `plan_mode` and the app keeps Story 1.3's immediate join.
Last Validation: iPhone 17 Pro simulator, GroupPlanJoinTests 15 passed, plus CoachLinkTests and CoachPlanSetupTests, 47 passed / 0 failed. SQL suite is in PR checks. It was not run locally: Docker would not start.
Last Updated: 2026-11-17

# 2026-11-15: Coach Mode adherence follow-up

Current Phase: Coach Mode pilot foundation.
Active Story: Make the workout completion and run association atomic, retain only one retry with the matching run and its actuals, and rank new HealthKit runs as a batch.
Next Recommended Story: Verify a real in-app run and a third-party HealthKit run produce the expected row links before implementing the Coach adherence view.
Blockers: `20261117120000_complete_run_workout.sql` must be mirrored in the web repo and applied before the updated iOS client is released. The new client uses the owner-scoped RPC for completion writes. Stage the DB migration first, validate the exact pilot build, and keep pilot participants on that build so older clients do not replay split writes. Upgrade recovery completes persisted links to incomplete active workouts using actuals from the linked run, including links older than the normal 30-day heuristic window. Legacy split payloads without a proven run association are never replayed.
Last Validation: Throwaway Postgres 17.6 passed the original workout-link test and the new atomic completion test. iOS and physical workout checks are tracked in tasks/todo.md.

# 2026-11-15: Coach Mode story 1.3, athlete joins a coach with consent

Current Phase: unchanged; Coach Mode (human coaches) epic 1, branch `feat/join-coach-consent`.
Active Story: migration `20261115091000_coach_athlete_links.sql` (table `coach_athlete_links`, RPCs `lookup_invite` returning invite id, `join_coach(code, expected_invite_id, expected_coach_id, expected_athlete_id)`, `my_coach_link`). Settings → "Join a coach" (only when not linked) leads to the code field and the consent screen. A signed-out person uses "Join a coach" on the sign-in screen, which stays on sign-in; after sign-in and any required onboarding they get an empty code field. There is no guest code entry. Share joins only the invite and coach on the consent screen for the athlete who saw it. The server returns the persisted link ID and consent timestamp. If the code now names someone else, the app shows "This code now belongs to {name}", drops the previous consent, and waits for a new Share tap. Not now does not join. Not applied to production. Nadav applies this migration himself. Do not apply an older copy. Do not mirror it to the web repo yet.
Follow-up before any pilot: Story 1.5 MUST ship athlete "Leave coach" plus a revoke RPC before the pilot. Leaving cuts off all coach access. The consent sentence "You can leave anytime in Settings" stays. Join is not held for this.
Next Recommended Story: After the founder merges 1.3, prioritize 1.5 (Leave coach) before the pilot. 1.4 adds invite links. Coached-by header is 3.3.
Blockers: migration not applied to production yet.
Last Validation: 2026-11-15, SQL coach_athlete_links.sql PASS on throwaway Postgres 17.6 after applying the current migration twice. Includes wrong-athlete rejection and equality of the persisted link identity and consent time in both RPCs.
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

## 2026-11-18 Story 3.1 coach feedback write
- Current Phase: Coach Mode Phase 3, coach feedback (3.1) in review
- Active Story: 3.1 coach writes feedback on a run or a week, with drafts and offline queue
- Next Recommended Story: 3.2 athlete sees coach feedback, after the 3.1 PR merges and the migration is applied
- Blockers: migration 20261118100000_coach_feedback not applied; founder applies after review
- Last Validation: 34 coach unit tests pass on iPhone 17 simulator; SQL suite runs in CI only
- Last Updated: 2026-11-18

## 2026-11-18 Story 2.4 review fix (#206)
- Current Phase: Coach Mode Phase 2, athlete detail (2.4) in review
- Active Story: 2.4 fix, no-plan athletes keep their recorded runs visible as extra runs
- Next Recommended Story: 3.1 coach feedback, after #206 merges
- Blockers: none; founder merges #206
- Last Validation: 23 coach unit tests pass on iPhone 17 simulator, 0 failed
- Last Updated: 2026-11-18

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

# 2026-11-17: Coach Mode story 2.2, coach reads linked athletes

Current Phase: Coach Mode. Branch `feat/coach-read-rpcs`.
Active Story: migration `20261117164500_coach_read_rpcs.sql` (`is_active_coach_of`, `athlete_display_name`, `coach_list_athletes`, `coach_get_athlete_plan`, `coach_get_athletes_workouts`, `coach_get_athletes_runs`) and `CoachReadService`. No UI. RLS on existing tables is unchanged. Not applied to production. The web repo needs the same migration file.
Next Recommended Story: 2.3, the athlete list, after this migration is applied.
Blockers: migration not applied. Run dates are the UTC date of `runs.completed_at`.
Last Validation: `CoachReadServiceTests` 7 passed on the iPhone 17 Pro simulator. SQL suite is `supabase/tests/coach_read.sql`; local Docker did not start, so that suite is left to CI.
Last Updated: 2026-11-17
