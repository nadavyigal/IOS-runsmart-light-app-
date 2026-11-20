# Coach Experience v2: refined plan (C0.1)

**Date:** 2026-11-20. **Status:** draft for Nadav's approval. No product code or migration is written until Nadav says go.
**Inputs (copied into the repo so every agent can read them):**
- `docs/coach-mode/v2/coach-experience-v2-full-plan-v1.3.md` (John, v1.3): stories, ACs, schema, cross-cutting rules, invariants, test plan.
- `docs/coach-mode/v2/coach-experience-v2-ux-spec.md` (Sally): exact copy, states, accessibility, RTL.

**How to read this doc.** It changes **order, release gates, parallel work and a few facts**. Everything else in v1.3 stays binding: every story's ACs, §1.1 cross-cutting rules and model tiers, §3 schema, §3.10 draft invariants, §6 test plan, and Nadav's decisions D1 to D14. Where this doc and v1.3 disagree, this doc wins (it is newer). §5 of v1.3 (the serial PR sequence) is replaced by §3 here.

---

## 0. Changes from the input plan

### 0.1 Fact fixes (checked against `origin/main` @ `4a016b4`)

| # | v1.3 says | The code says | What changes |
|---|---|---|---|
| F1 | RPE and notes live in `Services/Supabase/SupabaseRunSmartServices.swift` L683 to L695 | The app path is `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift:1701` (`updateRunRPE`) and `:1709` (`updateRunDetails`). Both call the local store and post `.runSmartRunsDidChange`. Nothing reaches Supabase. | C7.3 edits this file. The privacy claim in v1.3 holds. |
| F2 | C7.13 needs no migration [ASSUMPTION] | Confirmed. Analytics is PostHog: `Services/Analytics/AnalyticsService.swift` (`import PostHog`, `PostHogSDK.shared.capture`). | Assumption closed. |
| F3 | §2.5: check that no lock, draft or push-token object exists | No `workouts.locked`, no `edited_by`, no push-token table. But `supabase/migrations/20261115194500_leave_coach.sql:111` already deletes from `public.coach_plan_drafts` when that table exists, and `supabase/functions/delete_account/index.ts:112` names `coach_plan_drafts`. | v1.3 names the M7 table `coach_plan_versions`, so these hooks would silently miss it. **C8.6 / M7 must** update `delete_account` and `purge_coach_data_for_deleted_account` to cover `coach_plan_versions`, and add a SQL test that account deletion and leave both remove the drafts. |
| F4 | Live-run guide "parses workout text" | `Services/StructuredWorkoutFactory.swift:20-25` reads `workouts.workout_structure` JSON first (`parseJSON`), then falls back to text-derived steps per workout kind. | The athlete side can already render structured steps. C8.3 is mostly the coach's editor and server validation. Coaches can ship interval sessions in C8.2 as type "intervals" plus description. This is why C8.3 can wait (§0.2). |
| F5 | C0.2: "known drift" between iOS and web migration trees | All 17 `2026111x` coach migrations exist on web `origin/main` (`Running-coach-/v0/supabase/migrations/`). Byte identity was not checked. | C0.2 stays, as a small script plus ledger, not an investigation. |
| F6 | (not in v1.3) | `tasks/coach-mode-status.md` (last checked 2026-11-18) lists 6 v1 coach migrations **not yet applied** to production: `20261118100000` to `20261118180000`. Not re-checked since (agents never query production). | New Nadav step N2: confirm they are applied before Batch A. The ledger records it. |
| F7 | (not in v1.3) | Newest migration on `main`: `20261118180000_coach_welcome_note.sql`. | Reserved v2 timestamps (§3.4) sort after it. |
| F8 | Coach Mode ON in all Release builds; no remote push; `lockedWorkoutIDs` always empty | All confirmed (`Services/Coach/CoachModeService.swift`, `RunSmart.entitlements` has no `aps-environment`, `Services/Coach/CoachAssistant.swift`). | None. |

### 0.2 Scope and order (the main change)

**The problem.** v1.3 is careful, but it is 43 stories and 39 PRs for a pilot of 2 coaches with 8 to 20 athletes each. The first screen a coach notices is PR 7. The first TestFlight gate (TF-1) comes after PR 16 and waits on Apple push setup. At about one merged PR a working day, a coach sees v2 in about 3 to 4 weeks and full v2 lands in about 2 months (guess). The risk is that Phase 2 stalls before the pilot shows value (v1.3 names this as R8 but keeps the serial order).

**What this doc does. No story is deleted.** It folds 3 small stories into their neighbours, splits TF-1 so push stops blocking coach value, runs 3 lanes in parallel, and moves 15 stories behind a stop/go gate after TF-2.

| # | Change | Why |
|---|---|---|
| S1 | **Fold C7.12 (kill switch) into C7.0 (gate).** One migration (`M0`) creates `client_capabilities`, `runtime_flags` and `link_is_v2`, which reads both. All ACs of both stories stay. `docs/coach-v2-rollback.md` still ships in this PR. | Same SQL function, same tier (Opus high), one review. With N1 = B, v2 code ships in the App Store build, so the kill switch is essential from day 1. |
| S2 | **Fold C7.15 (mixed-direction text) into C7.3.** C7.3 is the first story that shows athlete text to the coach. Helpers and bidi fixtures keep their ACs. | A helper with no caller is hard to review. |
| S3 | **Fold C7.13 (analytics) into the stories.** C7.0 creates the typed `CoachV2Analytics` with no events. Each story adds its own events from v1.3 §3.8. `docs/coach-v2-metrics.md` ships with C0.2. | Analytics has no migration (F2). Events are reviewed with the code that fires them. |
| S4 | **Split TF-1 into TF-1a (in-app, after Batch A) and TF-1b (push, after Batch B).** | Push depends on Nadav's Apple setup (v1.3 R4). Coach Today, RPE, notes, flags, replies and removal all work without push. |
| S5 | **After TF-2, stop and decide** which of these 15 ship next: C7.6 evening summary, C8.13 coach self sign-up, C8.3 interval editor, C8.6/C8.7/C8.8 AI drafts and publish, C8.9 calendar, C8.10/C8.11 templates and assign, C8.14 groups, C8.12 broadcast, C9.1 to C9.4. Their ACs stay as in v1.3. | Decide with pilot data (SM-V1 to SM-V6), not up front. C8.13: pilot coaches are created by SQL today (`tasks/coach-pilot-testing.md`), so self sign-up matters when coach number 3 arrives. C8.3: see F4. C7.6: if coaches open Coach Today daily (SM-V1), a nightly summary adds little. |
| S6 | **Three lanes in parallel, with migration timestamps reserved now** (§3). | v1.3 is almost fully serial. Real dependencies allow 3 lanes. Reserved timestamps remove the collision risk v1.3 handles by renaming. |

**Result (guess):** 35 build PRs instead of 38. **20 PRs reach TF-2** (coach builds workouts on TestFlight). TF-1a, the first coach-visible gate, comes after 9 PRs, about 2 weeks after approval. TF-2 is about 4 to 5 weeks after approval, against about 6 in v1.3.

### 0.3 Decision N1 (decided 2026-11-20: B): how pilot athletes get v2

v1.3 puts v2 behind `coachV2Enabled`, ON only in Debug and TestFlight. With D4 (both sides need v2), **every pilot athlete must install TestFlight**. Beginner runners often won't, and the coach then sees "{Athlete} needs the latest RunSmart" for most of the roster (v1.3 R5).

| | A. TestFlight only (v1.3 as written) | **B. Dark in the App Store build, switched on per coach (chosen)** |
|---|---|---|
| How | Build flag only. | Build flag ON for Debug and TestFlight. In App Store builds, v2 is ON only when the user is a coach on the server allowlist (`coach_v2_pilot_coaches`), or an athlete linked to one. The client reads it through the 15-minute flag cache v1.3 §3.7 already defines. |
| Athlete friction | High: install TestFlight, accept the invite, keep it updated. | None: a normal App Store update. |
| Risk to solo users | None. | Low: v2 code ships but stays off for everyone not linked to an allowlisted coach. Same App Review per release as today. |
| Extra work | None. | One extra condition in C7.0, plus a flag-off test for an App Store build with an unlisted coach. |

**Decision: B** (Nadav, 2026-11-20), because the pilot only works if athletes actually run v2. TF-1a and TF-1b still run on TestFlight with Nadav's own two phones first. The allowlist gets pilot coaches only after TF-1a passes. D4 does not change: both sides still need a v2-capable build.
**What this means for C7.0:** v1.3's `runtime_flags` holds one boolean per key, so it cannot hold a coach list. M0 adds a table `coach_v2_pilot_coaches(coach_id uuid primary key references auth.users on delete cascade, added_at timestamptz not null default now())` with RLS on and no client policies, plus a security-definer RPC `coach_v2_pilot_access()` (`set search_path=''`) that returns true when `auth.uid()` is a listed coach or has an active link to one. `coachV2Enabled` = build flag (ON in Debug and TestFlight) OR, in App Store builds, `coach_v2_pilot_access()`. The table ships empty. The kill switch (`runtime_flags.coach_v2 = false`) overrides both, and `link_is_v2` also returns false for a pair whose coach is not listed when the athlete is on an App Store build. Required tests: App Store build + unlisted coach = v2 off; App Store build + listed coach = v2 on; kill switch off = v2 off in every build. Adding a coach to the list is a production data change, so Nadav does it, after TF-1a passes.

---

## 1. Releases and gates

| Release | Stories (PRs) | Migrations (batch) | Gate | Who checks |
|---|---|---|---|---|
| **R0 Ground truth** | C0.1 (this doc), C0.2 ledger + drift script + metrics doc | none | Nadav approves this doc | Nadav |
| **R1 Coach sees how athletes feel** | C7.0 (+C7.12), C7.8, C7.1, C7.3 (+C7.15), C7.2, C7.4, C7.7, C7.11, C7.16 (9 PRs) | Batch A | **TF-1a** | Nadav's two phones, then pilot coach 1 |
| **R2 Coach gets told** | C7.10, C7.14, C7.5 (3 PRs) | Batch B + webhooks, cron, deploys, APNs secrets | **TF-1b** + kill-switch drill | Nadav's two phones, then both pilot coaches |
| **R3 Coach builds workouts** | C8.1a, C8.1b, C8.5, C8.16, C8.15, C7.9, C8.2, C8.4 (8 PRs) | Batch C (M6a + M6b) | **TF-2** | Both pilot coaches |
| **R4+ Decide after TF-2** | the 15 stories in S5 | Batches D, E, F, plus M10 | TF-3, TF-4, TF-5 as in v1.3 | Nadav picks the order |

**TF-1a checks** (v1.3 §6 TF-1, without push): items 2, 6 (no-push part), 7, 8, 9; the coach reply flow from item 3 without the push; a milestone and one-tap praise (C7.16); flag matrix and 1.2.6 regression before Batch A.
**TF-1b checks:** items 1, 3 (push part), 5, 10; the notification-fatigue test (20 fixture athletes give at most 4 coach pushes); the kill-switch drill (v1.3 §6) timed and written in the runbook.
**TF-2 checks:** unchanged from v1.3 §6 TF-2 items 2, 3 and 5, plus the athlete skip/move and the single bundled push.
**Stop/go after TF-2:** Nadav reads SM-V1 to SM-V6 and SM-VC1/VC2 (v1.3 §7.1) and picks the next release from S5.

---

## 2. Story map (all 43 stories)

Tier and author model are unchanged from v1.3 unless the "Change" column says so. Mig = the migration file the PR writes (§3.4 has the reserved names).

| Story | What | Release | Lane | Mig | Deps (merged first) | Change vs v1.3 |
|---|---|---|---|---|---|---|
| C0.1 | Refined plan (this doc) | R0 | docs | none | none | Done in this PR |
| C0.2 | Migration ledger, drift script, `docs/coach-v2-metrics.md` | R0 | docs | none | none | Smaller (F5); also owns the metrics doc (S3) |
| C7.0 | `coachV2Enabled` gate + capabilities + **kill switch** + `CoachV2Analytics` shell | R1 | Gate | M0 | C0.1 | Absorbs C7.12 (S1) and the analytics shell (S3); adds the N1 = B per-coach allowlist |
| C7.12 | Kill switch + rollback runbook | R1 | (in C7.0) | (in M0) | | Folded into C7.0 |
| C7.13 | Analytics events + metric definitions | all | (in each story) | none | | Folded (S3) |
| C7.15 | Mixed-direction text helpers | R1 | (in C7.3) | none | | Folded into C7.3 (S2) |
| C7.8 | Consent v2 + one-time notice | R1 | A | M5a | C7.0 | none |
| C7.1 | Coach Today with 7-day dots | R1 | B | none | C7.0 | none |
| C7.10 | Remote push foundation (tokens, permission, routing) | R2 | C | M2a | C7.0 | Written in wave 2; applied in Batch B |
| C7.3 | Sync RPE + notes, share with coach (+ bidi helpers) | R1 | A | M1a | C7.8 | Edits `RunSmartProductionServices.swift:1701,1709` (F1) |
| C7.2 | "New since last visit" + `coach_athlete_events` | R1 | B | M3 | C7.1 | none |
| C7.4 | Pain / something-off flag | R1 | A | M1b | C7.3, C7.1 | none |
| C7.11 | Coach removes an athlete | R1 | B | M5b | C7.8, C7.2 | none |
| C7.7 | Athlete replies to a coach note | R1 | A | M4 | C7.8, C7.3 (bidi) | none |
| C7.16 | Milestones + one-tap praise (D13) | R1 | B | M13 only if needed | C7.1, C7.2 | none |
| C7.14 | Notification settings, coach + athlete | R2 | C | none | C7.10 | none |
| C7.5 | Push sender, quiet hours, dedupe, collapse | R2 | C | M2b | C7.10, C7.4, C7.7 | none |
| C7.6 | Evening summary with counts | R4+ | | none | C7.5, C7.2 | Moved behind the TF-2 decision (S5) |
| C8.1a | Coach workout columns, write RPCs, workouts lock trigger | R3 | A | M6a | Batch A applied | none |
| C8.1b | Plan trigger, athlete RPCs, lock release at link end | R3 | A | M6b | C8.1a | none |
| C8.5 | AI and athlete side respect locks | R3 | A | none | C8.1b | Must merge before any coach-write UI reaches testers (unchanged) |
| C8.16 | Bundled athlete plan-update push | R3 | C | none | C8.1a, C7.5 | none |
| C8.15 | Athlete skips or moves a coach workout (D1) | R3 | B | none | C8.5 | none |
| C7.9 | Goal change with counted warning (D2) | R3 | B | none | C8.1b, C8.5 | none |
| C8.2 | Coach creates a simple workout (incl. "intervals" + description) | R3 | B | none | C8.1a, C8.5, C8.16 | Notes F4: text intervals already render |
| C8.4 | Coach edits, moves, deletes upcoming workouts | R3 | B | none | C8.2 | none |
| C8.13 | Coach self sign-up | R4+ | | M10 | C7.0 | Moved (S5) |
| C8.3 | Structured interval editor | R4+ | | none | C8.2 | Moved (S5, F4) |
| C8.6 | AI drafts a plan for one athlete | R4+ | | M7 | C8.1b, C8.3 | Must cover `coach_plan_versions` in delete/leave purge (F3) |
| C8.7 | Review, edit, publish | R4+ | | uses M7 | C8.6, C8.4 | none |
| C8.8 | Athlete side of published plans | R4+ | | none | C8.7, C8.16 | none |
| C8.9 | Coach 4-week calendar | R4+ | | none | C8.4 | none |
| C8.10 | Templates library | R4+ | | M8 | C8.3 | none |
| C8.11 | Assign to several athletes | R4+ | | uses M8 | C8.10 | none |
| C8.14 | Unlock Plan Mode + multiple groups | R4+ | | M11 | C8.11 (optional) | none |
| C8.12 | Broadcast to a group | R4+ | | M9 | C8.14, C7.8, C7.5 | none |
| C9.1 to C9.4 | History, load, AI weekly summary, AI-drafted notes | R4+ | | M14, M15, M12, M16 | as v1.3 | none |
| L1 to L4 | Later | out of v2 | | | | none |

---

## 3. Parallel work

### 3.1 Lanes (each lane owns its files; touching another lane's files means stop and surface)

| Lane | Owns | R1 / R2 stories | R3 stories |
|---|---|---|---|
| **Gate** (one session, alone) | `CoachModeService.swift`, flag cache, `client_capabilities` / `runtime_flags` SQL | C7.0 | none |
| **A: athlete sharing + data** | Athlete run detail, `RPESelector`, consent sheet, `AthleteFeedbackViews`, `RunSmartProductionServices` run-detail paths, sharing SQL | C7.8, C7.3, C7.4, C7.7 | C8.1a, C8.1b, C8.5 |
| **B: coach screens** | `Features/CoachMode/*` (Coach Today, roster, athlete detail), coach read SQL | C7.1, C7.2, C7.11, C7.16 | C8.15, C7.9, C8.2, C8.4 |
| **C: push** | `Core/Push/*`, entitlements, app delegate routing, `supabase/functions/coach_notify`, `_shared/apns.ts`, `_shared/notify.ts` | C7.10, C7.14, C7.5 | C8.16 |

C7.4 adds a chip on Coach Today (lane B's screen): it starts only after C7.1 is merged and keeps its edit to that screen small.

### 3.2 Waves

| Wave | Gate lane | Lane A | Lane B | Lane C | Nadav |
|---|---|---|---|---|---|
| 0 (now) | | | | | Approve this doc; N2 (v1 migrations applied?); start APNs setup; TestFlight invites to both coaches. C0.2 runs in parallel. |
| 1 | **C7.0** | | | | Review C7.0 |
| 2 | | C7.8 | C7.1 | C7.10 | Review 3 drafts |
| 3 | | C7.3 (+bidi) | C7.2 | C7.14 | |
| 4 | | C7.4 (after C7.1 merged) | C7.11 (after C7.8 merged) | waits | |
| 5 | | C7.7 | C7.16 | waits | **Apply Batch A** after the Grok Bot audit and the 1.2.6 regression. **TF-1a.** |
| 6 | | C8.1a | | C7.5 | APNs secrets ready |
| 7 | | C8.1b | | | **Apply Batch B**, webhooks, cron, deploys. **TF-1b** + kill-switch drill. |
| 8 | | C8.5 | | C8.16 | **Apply Batch C** at a quiet time, rollback file ready |
| 9 | | | C8.15, then C7.9 | | Deploy the digest function + 2-minute cron |
| 10 | | | C8.2, then C8.4 | | **TF-2**, then stop/go |

A dependent story starts from `main` after its parent is merged. No stacked branches: they make review harder and Nadav merges by hand. While a lane waits, it takes the next story with no open dependency.

### 3.3 Session rules
- One worktree per story under `~/Developer/runsmart-ios-worktrees/`, branch `claude/<date>-coach-v2-<story>`, one draft PR. Never merge, never push to `main`.
- **At most 3 sessions write code at once.** Nadav's review is the bottleneck, not agent time.
- Every draft PR is reviewed first by a fresh agent at the story's tier (v1.3 §1.1). Codex has no credits, so the reviewer is a new Claude session or a Cursor agent. Nadav then reads only the PR's AC table and "Nadav must apply: yes/no".
- Every migration PR has a twin draft PR in the web repo (`Running-coach-/v0/supabase/migrations/`) with the identical file, and updates `docs/migration-ledger.md` in both.

### 3.4 Reserved migration files (sorted after `20261118180000`; the ledger owns this list)

| Batch | File | Story |
|---|---|---|
| A | `20261121100000_coach_v2_gate.sql` (M0 + M0b) | C7.0 |
| A | `20261121110000_coach_consent_v2.sql` (M5a) | C7.8 |
| A | `20261121120000_athlete_run_sharing.sql` (M1a) | C7.3 |
| A | `20261121130000_coach_last_seen_and_events.sql` (M3) | C7.2 |
| A | `20261121140000_coach_feedback_replies.sql` (M4) | C7.7 |
| A | `20261121150000_athlete_run_flags.sql` (M1b) | C7.4 |
| A | `20261121160000_coach_link_end.sql` (M5b) | C7.11 |
| A | `20261121170000_coach_milestones.sql` (M13, only if needed) | C7.16 |
| B | `20261122100000_push_tokens_and_prefs.sql` (M2a) | C7.10 |
| B | `20261122110000_notification_log_and_deferred.sql` (M2b) | C7.5 |
| C | `20261201100000_coach_workout_locks.sql` (M6a) | C8.1a |
| C | `20261201110000_coach_plan_locks.sql` (M6b) | C8.1b |

The order inside Batch A matches v1.3. A story that needs a file not listed adds a ledger row first, with a timestamp that sorts in the right place. Later batches (D, E, F, M10) get their rows when Nadav picks them after TF-2.

---

## 4. What Nadav does outside code

| # | Action | When |
|---|---|---|
| N1 | Done 2026-11-20: B, dark in the App Store build with a per-coach allowlist (§0.3). Later: insert each pilot coach into `coach_v2_pilot_coaches` after TF-1a passes. | After TF-1a |
| N2 | Confirm the 6 v1 coach migrations in `tasks/coach-mode-status.md` are applied in production (or apply them). | Before Batch A |
| N3 | APNs: create the key, enable Push Notifications on the App ID, store the secrets in Supabase. Agents never handle the `.p8` key. | Start in wave 0; needed by wave 6 |
| N4 | TestFlight invites to both pilot coaches. Athletes need no TestFlight (N1 = B). | Wave 0 |
| N5 | Apply Batches A, B, C after each audit and regression. | Waves 5, 7, 8 |
| N6 | Stop/go after TF-2. | After wave 10 |

---

## 5. Risks this doc adds or changes (v1.3 §7.2 R1 to R10 still apply)

| # | Risk | Mitigation |
|---|---|---|
| R5 (changed) | Athletes won't install TestFlight | N1 option B |
| R8 (changed) | Scope | Releases R1 to R3 are complete on their own; 15 stories wait for the TF-2 decision |
| R11 (new) | Three lanes produce more PRs than one person can review | At most 3 writing sessions; agent review first; Nadav reads only the AC table |
| R12 (new) | v1 coach migrations not applied in production | N2 before Batch A; ledger row per file |
| R13 (new) | Draft tables missed by account deletion and leave (F3) | C8.6 updates both hooks and adds a SQL test |
