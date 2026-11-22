# RunSmart: Coach Experience v2, full plan (paste into Claude Code / Codex)

Version: **v1.3**, 2026-11-20. PM pass by John (product-manager review) on top of v1.2. v1.2 stays unchanged at `coach-experience-v2-full-plan.md`. v1.2 author: Grok Bot (read-only code audit of `nadavyigal/IOS-runsmart-light-app-` @ `4a016b4`, the head of `main` on Nov 20, plus `nadavyigal/Running-coach-` @ `main`, plus market research). Owner: Nadav Yigal.

**Precedence (read first).** Nadav's decisions win: D1–D10 (§0.1) and §2.2. After them comes this v1.3 text, then Sally's spec (`coach-experience-v2-ux-spec.md`). The v1.2 and v1.1 changelogs (§0.1, §0.2) are kept for history and evidence. Where they describe a story, migration or AC differently from §3–§5 below, **§3–§5 win**. Flag any conflict in the PR; don't resolve it silently.

**Tags.** `[ASSUMPTION]` marks an inference that is not verified in code. "**Claude checks first:**" marks a check Claude does before coding. If a check fails, stop and write the finding in the PR instead of guessing.

## 0.0 Changelog v1.3 (John)

### Nadav's decisions on v1.3 (Nov 20, 12:55 Israel). Binding, same rank as D1–D10
| # | Decision | Was | Where it lands |
|---|---|---|---|
| D11 | Broadcast push shows the **first 80 characters** of the message (cut safely, composer hint) | Q5 (my default) | C8.12 AC 2 (PR 34), §3.9, §6 bidi fixtures |
| D12 | **Label AI-assisted notes to the athlete.** Athlete copy: EN "Written with help from RunSmart AI" / HE "נכתב בעזרת RunSmart AI" | Q6 (my default was no label; Nadav chose a label) | C9.4 AC 2, 4–8 (PR 38); new migration **M16** `coach_feedback_ai_assisted` (Batch F) |
| D13 | **Keep milestones + one-tap praise** (FR-20b) | New-A (my default) | C7.16 (PR 13) |
| D14 | Coach drafts for an athlete who left are **deleted immediately** at link end (PRD FR-5) | New-B (my default) | M7 / C8.6 AC 9 |

Q5, Q6, New-A and New-B are removed from the open-question tables below.


### Top changes
1. **Fixed forward dependencies in Phase 1.** In v1.2, Phase-1 SQL referenced Phase-2 objects:
   - `end_coach_link` (M5, C7.11) cleared `locked`/`coach_published` (M6), purged drafts (M7) and dropped queued pushes (M2, applied later in Batch B).
   - C7.2 and C7.6 counted `coach_athlete_events`, which was created in M6.
   v1.3 fixes this:
   - `coach_athlete_events` moves to **M3**.
   - `end_coach_link` grows through three new `create or replace` files: M5b, then M6b (lock release), then M7 (draft purge).
   - Pushes for ended links are dropped by a check at send time, not by Phase-1 SQL.
2. **C7.9 moves to Phase 2 and keeps its ID.** In Phase 1 no workout can be locked (the columns arrive with M6a), so "{n} workouts {Coach} set will be replaced" is always 0. Phase 1 still tells the coach about goal changes, through `athlete_log_goal_change` (C7.2, M3).
3. **Splits so that each story is one reviewable PR:**
   - C8.1 becomes **C8.1a + C8.1b** (M6a + M6b, applied together).
   - C8.4 becomes **C8.4** (UI) **+ C8.16** (the digest Edge Function).
   - C7.5 becomes **C7.5** (server) **+ C7.14** (coach and athlete notification settings screens).
   - A migration that two PRs shared is now **two files**: M1a/M1b, M2a/M2b, M5a/M5b, M6a/M6b. v1.2's "same M5 file as PR 4" (one PR editing another PR's file) is dropped.
4. **New safety stories:**
   - **C7.12** server kill switch + rollback runbook. `coachV2Enabled` is set at build time, so v1.2 could only turn v2 off for TestFlight users by shipping a new build.
   - **C0.2** migration ledger + iOS/web drift report.
   - **C7.13** pilot analytics events and v2 success metrics. v1.2 had neither.
   - **C7.15** mixed-direction (Hebrew/English) text in notes, names and pushes.
5. **Every stale AC is rewritten as Given/When/Then.** v1.2 left in place ACs that its own "v1.2:" notes overrode, and Claude would have implemented both versions:
   - C7.3 AC 2 (note backfill)
   - C7.5 AC 2 ("or dropped")
   - C7.6 AC 1–2 (names and misses only)
   - C7.9 AC 1 (no count)
   - C7.10 AC 2 (permission "after sign-in")
   - C8.4 AC 4 (48-hour marker only)
   - C8.5 AC 3–4
   - C8.6 AC 1 ("(or group)")
   - C8.8 AC 1 (card string)
   - C9.3 AC 1 ("Sunday evening")
   
   Cross-cutting ACs (§1.1) now cover flag off/on, mixed versions, a link that has ended, offline/outbox, RLS, push content and analytics for every story.
6. **"The athlete never sees a draft" is now an explicit, tested invariant** (§3.10, INV-1…INV-6). C8.6, C8.7 and C8.8 and the test plan cite it.
7. **Restored MVP FR-20b** (beginner milestones and one-tap praise) as **C7.16**. v1.2 dropped it without saying so. It is pilot-PRD scope and one of the cheapest P-1 levers. Nadav confirmed (D13).
8. **Model rule:** one primary author model per PR, picked by the riskiest part of the PR (§1.1, tiers). No schema, RLS, security-definer or consent work goes to Haiku. 11 stories change (table below).

### Stories added, split, moved (old → new IDs)
| v1.2 | v1.3 | Why |
|---|---|---|
| (none) | **C0.2** Migration ledger + drift report (docs only) | Known drift between `supabase/migrations/` and `Running-coach-/v0/supabase/migrations/`. Every v2 file must be mirrored and applied in order. |
| (none) | **C7.12** Server kill switch + rollback runbook (M0b) | Switch v2 off without a build or App Review. A written rollback per batch. |
| (none) | **C7.13** Pilot analytics events + metric definitions | v1.2 had no way to measure §7.1. |
| C7.5's settings UI + Sally G13 athlete toggles | **C7.14** Notification settings screens (coach T5 + athlete) | No v1.2 story owned the athlete toggles or athlete quiet hours. |
| (none) | **C7.15** Mixed-direction text helpers | Hebrew notes and names inside English strings and pushes (MVP Q18). |
| MVP Story 5.4 / FR-20b | **C7.16** Milestones + one-tap praise | Pilot-PRD scope that v1.2 omitted. |
| C8.1 | **C8.1a** (M6a) + **C8.1b** (M6b) | The riskiest PR is split into halves that can be reviewed. Both are applied together as Batch C. |
| C8.4 (digest part) | **C8.4** (UI, M) + **C8.16** (digest function, M) | Different risk and model; the digest is server and push code. |
| C7.9 (Phase 1) | **C7.9** (Phase 2, after C8.1b) | Its count needs locked rows (M6). |
| C7.7 push ACs | moved into **C7.5** | One sender (`coach_notify` + `_shared/notify.ts`) owns prefs, quiet hours, dedupe and logging. |

**No merges.** The small stories (C7.8, C8.12) each carry their own migration. Merging them would mix unrelated security checklists.

**Story count:** 35 → **43** (Phase 0 = 1, Phase 1 = 16, Phase 2 = 18, Phase 3 = 4, Later = 4). There are **39 PRs** (C0.2 plus 38 build PRs), plus docs PR 0.

### Migration file map (v1.2 → v1.3)
Batch = the group Nadav applies together (§5). Timestamps must sort in the order listed inside each batch.

| v1.2 | v1.3 file | Story | Batch |
|---|---|---|---|
| M0 | **M0** `client_capabilities` + `link_is_v2` | C7.0 | A |
| (none) | **M0b** `runtime_flags` + `link_is_v2` v2 (kill switch) | C7.12 | A |
| M5 (consent part) | **M5a** `coach_consent_v2` | C7.8 | A |
| M1 (part A) | **M1a** `athlete_run_sharing` (RPE, notes, ack gate) | C7.3 | A |
| M3 | **M3** `coach_last_seen_and_events`, now also creating `coach_athlete_events` + `athlete_log_goal_change` | C7.2 | A |
| M4 | **M4** `coach_feedback_replies` | C7.7 | A |
| M1 (part B) | **M1b** `athlete_run_flags` | C7.4 | A |
| M5 (link-end part) | **M5b** `coach_link_end` (`end_coach_link` v1, `coach_remove_athlete`, new `leave_coach`) | C7.11 | A |
| (none) | **M13** `coach_milestones` read RPC, **only if** C7.16's check finds the existing RPCs can't answer it | C7.16 | A |
| M2 (tokens part) | **M2a** `push_tokens_and_prefs` (tokens + `notification_prefs`, moved here) | C7.10 | B |
| M2 (prefs/log/deferred) | **M2b** `notification_log_and_deferred` | C7.5 | B |
| M6 | **M6a** columns + coach write RPCs + `workouts_protect_coach_rows` + `athlete_plan_update_queue` | C8.1a | C |
| M6 | **M6b** plan trigger + athlete RPCs + `end_coach_link` v2 (lock release) + new `replace_group_training_plan` | C8.1b | C |
| M10 | **M10** `coach_self_signup` | C8.13 | C |
| M7 | **M7** `coach_plan_versions` + `end_coach_link` v3 (purge drafts at link end) | C8.6 | D |
| M8, M11, M9 | unchanged (templates, groups, broadcasts) | C8.10, C8.14, C8.12 | E |
| "RPC only" | **M14** `coach_athlete_history` | C9.1 | F |
| "RPC only" | **M15** `coach_athlete_load` | C9.2 | F |
| M12 | unchanged (`coach_weekly_summaries`) | C9.3 | F |
| (none) | **M16** `coach_feedback_ai_assisted` (D12 label) | C9.4 | F |

### AC rewrites (where)
- **Cross-cutting (§1.1):** flag-off, mixed-version (`link_is_v2`), link-ended, offline/outbox, push content, analytics and string rules. Every story inherits them, and its PR checklist ticks each one.
- **Consent and RLS:**
  - C7.3, C7.4, C7.7, C7.8: no sharing before `ack_coach_consent(2)`. Notes on runs completed before the ack are never synced, even if they are edited later.
  - Every RPC: tests for non-coach, revoked and athlete-self.
- **Athlete leaving:** C7.11 adds a parity test. After a leave **and** after a removal, every coach read RPC returns zero rows. C8.1b and C8.6 keep that test green as `end_coach_link` grows.
- **AI proposal → coach approval → athlete view:** C8.6, C8.7 and C8.8 are rewritten around INV-1…INV-6.
- **Vague wording removed:** "handled gracefully" (C8.5 AC 3), "Validation messages are clear" (C8.2 AC 3) and "Works with 0, 1 and 30 athletes" (C7.1 AC 4) are replaced with named states and exact copy from the spec.

### Model-size changes
| Story | v1.2 | v1.3 | Reason |
|---|---|---|---|
| C7.0 | Sonnet (flag) + Opus (M0) | **Opus (high)** | `link_is_v2` is called by every v2 RPC. One author per PR. |
| C7.1 | Sonnet (medium) | **Sonnet (high)** | The largest state matrix in Phase 1 (§A.5). |
| C7.2 | Opus migration + Sonnet UI, S | **Opus (high), M** | Now owns `coach_athlete_events` and a security-definer write RPC. |
| C7.8 | Haiku (low) copy + Sonnet | **Opus (high)** | It's the consent gate that every sharing RPC depends on. The copy is fixed by the spec, so Haiku adds nothing. |
| C7.9 | Sonnet (medium) | **Sonnet (high)** | The count race (`count_changed`) plus every plan-writer caller. |
| C7.11 | Opus + Sonnet + Haiku | **Opus (high)** | Refactors `leave_coach`, which is live for 1.2.6 clients. |
| C8.4 | Sonnet UI + Opus digest, L | **Sonnet (medium), M** | The digest moved to C8.16, which is Opus (high). |
| C8.10, C9.1 | Sonnet (medium) | **Sonnet (high)** + a required Opus/Codex-high RLS review | An owner-only table, or a read-only security-definer RPC (tier 2). |
| C8.12 | Sonnet (medium) | **Opus (high)** | Cross-user reads: athletes read coach rows, and the coach reads read receipts. |
| C8.13 | Sonnet + Opus review | **Opus (high)** | `become_coach` is a security-definer write to a table whose writes are revoked. Self-serve coach creation grants a privilege. |

### Open questions: defaults (detail and reasons in §7.3)
| # | Question | Default | Needs Nadav? |
|---|---|---|---|
| Q1 | Pilot size | 2 coaches × 8–20 athletes (PRD v7). Design and test for 30. | No (the PRD answers it) |
| Q2 | Plan Mode lock | Keep the lock until C8.14 | No |
| Q3 | One-level reply vs chat | One level for v2. Measure replies per note. | No |
| Q4 | Load-jump threshold, HRV | Acute:chronic ≥ 1.5 with a chronic-load floor. No HRV or readiness. | No (Phase 3; revisit at TF-5) |
| New-C | Kill switch keeps locks enforced | Yes; releasing locks is a separate runbook script | No |
| New-D | C8.13 "Free for now." copy | Remove it | No |
| New-E | Coach run-finished burst rule | After 3 in 10 minutes, collapse the rest into one push | No |

---

## 0.1 Changelog v1.2 (UX review + Nadav decisions). Kept for history; the D1–D10 decisions below are binding

**Companion file, required.** Paste `coach-experience-v2-ux-spec.md` (Sally's UX spec) into Claude **together with this plan**. The stories below cite its sections for exact copy, states, layout, accessibility and RTL. Where this plan says "UX AC: §X", those acceptance criteria are part of the story. If the spec and this plan conflict, this plan's decisions (§2.2) win; flag the conflict in the PR.

### Nadav's decisions (Nov 20, 11:09 Israel), all of Sally's recommended defaults accepted
| # | Decision | Sally gap | Where it lands |
|---|---|---|---|
| D1 | The athlete can **skip** or **move** a coach-set workout after a confirm ("{Coach} set this workout. Change it anyway? {Coach} will see the change."). The workout **stays locked against the AI**, and the coach sees "Changed by {Athlete}". Content edits (distance, steps, pace) stay coach-only. | G2 | New story **C8.15**. M6 adds `athlete_change`, `athlete_changed_at` and an `athlete_change_coach_workout` RPC, and the trigger allows only those fields through the athlete path. A `coach_athlete_events` row feeds C7.2 and C7.6. |
| D2 | **Goal change:** blocked only when the coach published a whole plan (P5 copy plus a "Reply to {Coach}'s latest note" link). Otherwise the athlete gets a warning with a **count of coach workouts that will be replaced**, and then the plan is replaced. | G3 | C7.9 adds the count. M6's plan trigger raises only for `coach_published` plans; replacing a plan that has some locked workouts goes through a new athlete RPC `athlete_replace_training_plan`, which logs a `goal_change` event. C8.5 is updated to match. |
| D3 | A single coach edit goes **live immediately**. The athlete gets **one bundled push about 10 minutes after the coach stops editing** ("{Coach} updated your plan · {n} changes"), plus a change-list card. Draft and publish are only for whole plans. | G1 | New table `athlete_plan_update_queue` (M6). Edge Function `athlete_plan_update_digest` runs on a 2-minute cron. C8.4 and C8.11 enqueue changes, and C8.8 shows the card. |
| D4 | **Pilot version rule:** v2 tools turn on only when **both** the coach and the athlete run a v2 build. Pilot athletes join TestFlight. Otherwise the coach sees "{Athlete} needs the latest RunSmart". | G4 | C7.0 grows to M and gets migration **M0** (`client_capabilities`, `report_client_capabilities`, `link_is_v2`). Every v2 coach write and every athlete sharing RPC checks `link_is_v2`. Structured workouts always also carry a text summary. |
| D5 | **No group-wide AI drafts** in v2; drafts are per-athlete only. Groups get shared workouts through templates and assign. New group joiners get the group's RunSmart plan from the current week. | G8 | M7 drops `group_id` from `coach_plan_versions`. C8.6 scope is per-athlete. Sally's G10 adds an "Edit plan" action (a draft cloned from the live plan) to C8.7. |
| D6 | **Notifications:** coach "run finished" is ON by default, max 1 per athlete per 30 min. Pain flags **don't** break quiet hours. Each publish notifies the athlete **once**. The 20:00 coach push shows counts: misses, open flags, plan changes. | G6, G13 | C7.5: deferred pushes collapse into one at quiet end. C7.6: the counts message, skipped only when every count is zero. Athlete prefs and quiet hours are added (M2). C8.8: one push per publish. |
| D7 | **Backfill:** past notes are **never** shared. RPE from the last 14 days syncs **only after the athlete taps OK** on the new consent. **Nothing is shared before the acknowledgement.** | G5 | M5 adds `consent_acknowledged_at`. Sharing RPCs return nothing until `consent_version >= 2 and consent_acknowledged_at is not null`. C7.3 drops the note backfill. |
| D8 | The **coach can remove an athlete**, with the same effects as the athlete leaving, plus one neutral in-app line for the athlete ("You're no longer coached by {Coach}. Your plan stays and RunSmart keeps adapting it."), and no push. | G16 | New story **C7.11**. M5 adds `coach_remove_athlete` and refactors `leave_coach` around a shared `end_coach_link(link, ended_by)` function. |
| D9 | The **consent copy states that the coach can see when athletes read group messages** (read counts). | G12 | C7.8 copy (P8/P9). C8.12 shows "Read by {n} of {m}". |
| D10 | **Base coach mode ON in the App Store build (1.2.6 build 46) is intentional** (Nadav, Nov 20, 10:47 Israel). v2 stays behind `coachV2Enabled` (Debug/TestFlight only). | (Codex finding / old Q0) | §1 Flags rule stands as written; App Store regression = 1.2.6 coach behavior, no v2 UI. |

### Other Sally gaps resolved with her defaults (no Nadav input needed)
- **G6:** C7.2 also counts goal changes and athlete changes.
- **G7:** permanent tags "From {Coach}" (created), "Edited by {Coach}" (edited RunSmart workout) and "Changed by {Athlete}". The 48-hour "Updated" pill is an extra, not a replacement. The card uses the MVP string.
- **G9:** multi-assign with a pace shows a warning. Effort-word targets ("easy", "comfortably hard", "hard") are allowed in `workout_structure` (a small `effort` field).
- **G10:** "Edit plan" clones the live published version into a draft.
- **G11:** per-rep results are out of v2. "Rep times on structured runs" is the first Phase-3 candidate, not yet a story.
- **G12:** the broadcast push carries the first 80 characters (see open question), delete is allowed within 15 minutes, "Messages from {Coach}" lives in My coach, "Send to {n} athletes?" confirm, and athletes get an opt-out toggle.
- **G13:** athlete toggles for coach notes, plan updates and broadcasts, with athlete quiet hours. Pre-permission screens: T6 for the coach, P10 for the athlete. Never re-prompt after a denial; show "Open Settings" instead.
- **G14:** one training-week start per athlete, using the region rule as today. Summaries run at the end of the coach's week (Saturday evening for IL), not "Sunday evening".
- **G15:** a workout counts as "missed" only after a 20:00 athlete-local cutoff; before that it is "Not done yet".
- **G17:** the leave/remove sheet gets new lines: "{Coach} won't see your effort, notes or flags" and "Your replies stay". Drafts for an ended link are purged after 30 days.
- **G18:** dual roles are allowed (coach and coached). Monogram fallback when there's no avatar. No moderation in the pilot.
- **G19/G20:** 5-second client-side undo for move, delete and mark-handled. Mark-handled goes through the outbox. Multi-assign and draft edits need a connection, with explicit copy.
- **G21:** a pain flag causes no AI plan changes. The RunSmart chat answers with the safety line. The athlete can always skip (D1).
- **G24:** keep the MVP "{Coach} will review this run" → "Shared with {Coach}" line, as one status line only.
- **G25:** C7.1 degrades gracefully without C7.4, and push dependencies are stated in the AC.
- **C7.10 per Sally:** a token per device; signing out on one device doesn't unregister the others; tapping a push whose target is gone opens the nearest valid screen with a one-line notice.

### Structural changes in v1.2
- Stories: **+C7.11** (coach removes athlete) and **+C8.15** (athlete skip/move coach workout).
  - C7.0 goes from S to **M** (capability tracking plus migration M0).
  - C7.9 goes from S to M.
  - C8.4 goes from M to **L**, because of the bundled-push queue.
  - C8.6 shrinks to M (per-athlete only).
  - **Total: 35** (Phase 1 = 12, Phase 2 = 15, Phase 3 = 4, Later = 4).
- Schema: new **M0** (`client_capabilities`). M2 gains athlete prefs. M5 gains `consent_acknowledged_at` and coach-remove. M6 gains athlete-change fields, the athlete RPCs, `coach_athlete_events` and `athlete_plan_update_queue`, and its trigger rules are rewritten. M7 drops `group_id`.
- Sally gates: C8.15 is covered by spec §C.5. C7.11 needs only a light copy review.
- §5 PR order, §6 tests and §7 open questions are updated. Q0, Q3, Q6, Q7 and Q8 are answered and moved out.

---

## 0.2 Changelog v1.1 (Codex review + self-review). History and evidence

Codex flagged four code locations. Each one breaks an assumption in v1. A wider self-review found more. Every finding below cites the evidence and says what changed in this plan.

### Codex findings
| # | Evidence | What it shows | What changed in the plan |
|---|---|---|---|
| 1 | [`CoachModeService.swift` L3–L18](https://github.com/nadavyigal/IOS-runsmart-light-app-/blob/4a016b4/IOS%20RunSmart%20app/Services/Coach/CoachModeService.swift#L3-L18) | **Coach Mode is ON in every Release build, including the App Store.** Commit "Turn Coach Mode on for App Store builds and bump to 1.2.6 (46)" (Nov 19, 22:07 Israel). `coachModeEnabled` returns `true` for any non-Debug build. The Coach tab is gated only by a `coach_profiles` row, and athletes see "Join a coach". 1.2.6 (46) was submitted to App Review (PR #228, Nov 20, 07:18 Israel). v1 assumed "OFF in App Store, ON in TestFlight/Debug". **That is false on `main`.** | The flag rule in §1 is rewritten. A new story, **C7.0**, adds a separate `coachV2Enabled` gate: ON in Debug and TestFlight (sandbox receipt, the logic from the removed Nov 19 09:02 commit), OFF in the App Store. All v2 UI sits behind it. Every v2 migration must be **backward compatible with 1.2.6 clients already in the wild**, because they write `workouts`/`runs` directly and know nothing about locks. ⚠️ **Decision for Nadav:** this contradicts his standing rule ("coach mode OFF in Release"). Either he chose to ship base coach mode to the store (that is what the commit says), or this needs reverting. This plan assumes the store ships base coach mode and keeps v2 hidden. |
| 2 | [`SupabaseRunSmartServices.swift` L683–L695](https://github.com/nadavyigal/IOS-runsmart-light-app-/blob/4a016b4/IOS%20RunSmart%20app/Services/Supabase/SupabaseRunSmartServices.swift#L683-L695) | `updateRunRPE` writes only to the local store (`store.updateRunRPE`), and nothing goes to Supabase. Its doc comment says: "Title and notes stay on this device… `runs.notes` holds a system source note". `DBRunInsert` (same file, ~L2725) has no RPE or user-notes field. **RPE and run notes are device-only, so a coach RPC has nothing to read.** | M1 and C7.3 are rewritten. Add `runs.rpe` and a **new** `runs.athlete_note` column; `runs.notes` is not reused because it holds the source note. The app syncs both from `updateRunRPE`/`updateRunDetails`. Only runs with a server row can be shared: `runsmart_ios` runs, plus imported runs once they sync. C7.3 grows from M to **L**, still Opus (high). This is a privacy change ("notes stay on this device"), so the C7.8 consent copy must say it, and C7.8 now blocks C7.3. |
| 3 | [`20261117163000_replace_group_training_plan.sql` L24–L53](https://github.com/nadavyigal/IOS-runsmart-light-app-/blob/4a016b4/supabase/migrations/20261117163000_replace_group_training_plan.sql#L24-L53) | Plan replacement is **plan-level**: it sets every active plan's `is_active=false` and inserts a new plan plus workouts. It is `security invoker` and relies on owner RLS. The old plan's workouts are orphaned on an inactive plan, which the app and coach RPCs don't read. **A coach-locked workout on the old plan would silently disappear.** It also shows that `workouts` already has `workout_structure`, `intensity`, `training_phase`, `week`, `day` and `auth_user_id`. | A row-level `locked` flag alone is not enough. **M6** adds DB triggers on `plans` and `workouts`: a plan containing locked or coach-published workouts cannot be deactivated except through a coach RPC; locked rows can't be deleted; planned fields of locked rows can't be changed by non-coach writers. There is also a new `create or replace` of `replace_group_training_plan`, as a **new** migration file, because the applied file is never edited. v1's `structure jsonb` column is dropped; the plan **reuses `workouts.workout_structure`**. |
| 4 | [`TrainingPlanRepository.swift` L489](https://github.com/nadavyigal/IOS-runsmart-light-app-/blob/4a016b4/IOS%20RunSmart%20app/Services/Supabase/TrainingPlanRepository.swift#L489) | `persistGeneratedPlan` is the athlete-side plan writer. For solo users it does a direct `plans.update(is_active=false)` and then inserts a plan and workouts. Group joins use the RPC above. The same repository also writes `workouts` directly: `amendWorkout`, `pushWorkoutTomorrow`, `removeWorkout`, and the flex-week apply path (~L872–L990). **Any regeneration, goal change, or AI flex-week edit from the athlete's phone would overwrite or orphan coach workouts**, and 1.2.6 clients will keep doing this. | The lock is enforced **in the database** (M6 triggers), not only in `CoachAssistant`. C8.5 is extended: hide the athlete edit, move, delete and flex actions on locked rows, and handle the new `workout_locked` / `plan_locked_by_coach` errors. C7.9 (goal-change warning) stays a warning in Phase 1. After C8.1 a coached athlete with a coach-published plan **can't regenerate**: the server blocks it, and the UI says "Ask {Coach} to change your plan". |

### Extra findings (self-review)
| # | Evidence | Finding | Change |
|---|---|---|---|
| 5 | `IOS RunSmart app/Core/Push/PushService.swift` (only `UNCalendarNotificationTrigger` local notifications); [`RunSmart.entitlements`](https://github.com/nadavyigal/IOS-runsmart-light-app-/blob/main/RunSmart.entitlements) has **no `aps-environment`**; code search finds no `registerForRemoteNotifications` | **There is no remote push at all.** No APNs entitlement, no device-token registration, no token table. v1's "VERIFY push token storage" resolves to "none exists". | New story **C7.10 Remote push foundation** (L, Opus high): entitlement, token registration, `push_tokens` table, APNs sender in `_shared`. **Nadav must create an APNs Auth Key (.p8) in Apple Developer and set the Edge Function secrets.** C7.5, C7.6 and C7.7's push part depend on it. It moves to the front of the Phase 1 order. |
| 6 | [`Running-coach-/v0/lib/sync/plan-workout-sync.ts` ~L95–L220](https://github.com/nadavyigal/Running-coach-/blob/main/v0/lib/sync/plan-workout-sync.ts) | The web app upserts `workouts` from its local store with `onConflict: 'plan_id,local_id'` and **full planned fields** (type, distance, pace, `workout_structure`, `scheduled_date`). It would overwrite coach edits on any web-originated row. | Covered by the M6 trigger, which keeps the planned fields of locked rows from non-coach writers and does not raise, so web sync batches don't fail. The web repo needs no code change, but the migration **must be mirrored** to `v0/supabase/migrations/`. |
| 7 | `20261114120000_close_cross_user_rls_leaks.sql` (comment: owner-only `workouts_owner_access`, `plans_owner_access` kept) | The athlete has **full owner write access** to `workouts` and `plans` through RLS. With columns alone, an athlete client (or a 1.2.6 client) could set `locked=false`. | The M6 trigger also protects `source`, `locked`, `coach_id`, `coach_revision` and `published_version_id`. Only writes inside coach RPCs, which set `set_config('runsmart.coach_write','on', true)` and are verified with `is_active_coach_of`, can change them. SQL tests cover a direct-PATCH bypass attempt. |
| 8 | `20261114210000_coach_role_and_invites.sql` L30–L34, L55–L63 | `coach_profiles` = `(user_id pk, display_name not null, created_at)`. There is a select-own policy only, and writes are revoked from API roles. | VERIFY resolved. M10 `become_coach` must be `security definer`, and adds `bio`/`avatar_path` columns. |
| 9 | `supabase/functions/coach_message/flex_week.ts` (exports `generateFlexWeek`, `validateFlexWeekResponse`; returns proposals only, no DB writes) | The AI **proposes**, and the **client applies** the changes through `TrainingPlanRepository`. Edge Functions present: `_shared`, `coach_message`, `delete_account`, `strava_oauth`. None writes `workouts`. | C8.5: filter locked IDs **both** server-side in `flex_week.ts` (drop changes to locked IDs) **and** client-side before applying. The DB trigger is the backstop. `delete_account` must also purge the new tables (check whether it calls `purge_coach_data_for_deleted_account`). |
| 10 | `IOS RunSmart app/Services/StructuredWorkoutFactory.swift` (live-run guide stages parsed from the workout's text/targets, e.g. "8 x 400m with 90 s recovery") | The VERIFY on step guidance is resolved: **a live-run guide already exists**, but it **parses text**, not `workout_structure`. | C8.3: the factory reads `workout_structure` first and falls back to text parsing. The coach also gets live guidance on the run screen for free. The format is aligned with what the generator already writes to `workout_structure`. **VERIFY** that shape before defining v1's JSON; the plan no longer invents a new schema. Size stays L. |
| 11 | `IOS RunSmart app/Features/Goals/GoalWizardView.swift` (~L259 `services.saveTrainingGoal(request)` → `persistGeneratedPlan`) | This is one goal-change entry point. Others (the Plan "Build my plan" CTA, settings) are not confirmed. | C7.9 lists `GoalWizardView` and asks the agent to grep every `saveTrainingGoal`/`persistGeneratedPlan` caller. It stays partly VERIFY. |
| 12 | Migration ordering | All coach migrations through `20261118180000` plus `20261117163000` are already applied in prod (per the Nov 19 status). Editing an applied file does nothing on prod and diverges from it. | Rule added: **never edit an applied migration**; changes are new `create or replace` files that sort after the newest file on `main` at PR time. Each PR lists its apply order. Batches A, B and C are in §5. |
| 13 | Flag scope / external testers | Moot. Base coach mode now reaches everyone with a store or TestFlight build. | Covered by C7.0 (`coachV2Enabled`). Phase 1 athlete-side changes (consent sheet, reply, pain flag) are **only visible to linked athletes**, and stay behind `coachV2Enabled` until TF-1 passes. |
| 14 | RLS gap in v1's M1 | v1 left a choice between extending `coach_get_athletes_runs` and adding a separate RPC. | Decided: extend `coach_get_athletes_runs` with `rpe` and `has_note`, using a new `create or replace`. Full note text goes through `coach_get_run_notes(p_run_ids)`, which honors a per-run "hide note from coach". |

**Story count change:** Phase 1 goes from 9 to **11** (adds C7.0 and C7.10). Phase 2 stays at 14, with C8.1, C8.3 and C8.5 expanded. Phase 3 stays at 4 and Later at 4. Total **33**.

---

## 1. Prompt for the agent (read this first)

**Role.** You are the senior iOS + Supabase engineer on RunSmart (SwiftUI app, Supabase backend, Edge Functions in Deno). You own planning quality and implementation of Coach Experience v2.

**Goal.** Coach mode today is a read-only, athlete-first add-on (21 stories, merged). v2 turns it into a real coaching tool on iPhone. The coach can see at a glance who needs attention, gets told when something happens, sees how athletes felt, builds and edits workouts, and publishes plans that the AI can draft but never overwrites.

**How to use this doc.**
0. **Two files go together:** this plan and `coach-experience-v2-ux-spec.md` (Sally's UX spec). Read both. The spec holds the exact copy, states, accessibility and RTL rules that the stories reference as "UX AC: §…".
1. **Review and refine first. Do not code yet.** Read every file and migration cited below on `main` and check each claim. This plan was written from a code read, not a build. Push back where it is wrong: wrong table or column names, a better schema, stories in the wrong order, stories that are too big, missing risks. Pay special attention to the items marked **VERIFY**.
2. Write the refined plan (C0.1) to `docs/coach-experience-v2-plan.md`, with a "Changes from the input plan" section at the top. Open it as a **draft PR** (docs only) and stop. Nadav reads it and says go.
3. Then implement **story by story**, one small draft PR per story (or per row in §5), in the order in §5. Each PR's description lists: story ID, acceptance criteria with a ✅/❌ for each, tests added, migration files (if any), and "Nadav must apply: yes/no".
4. Keep `tasks/coach-mode-status.md` updated, adding a v2 table in the same format.
5. **v1.3:** follow §1.1 (cross-cutting rules, model tiers, DoD) in every PR. Keep `docs/migration-ledger.md` (C0.2) and `docs/coach-v2-rollback.md` (C7.12) current.

**Rules (non-negotiable).**
- **Draft PRs only. Never merge.** Never push to `main`.
- **Production Supabase migrations: write the files only.** Never apply them to production or run anything against the production project. Nadav applies them himself. Every migration file starts with the header used in the repo today ("Do not apply this to production from the app PR. Nadav applies … Mirror it to `Running-coach-/v0/supabase/migrations/`"). Migrations must be idempotent, like the existing ones.
- **Flags.** On `main`, `RunSmartFeatures.coachModeEnabled` is **ON in all Release builds (App Store too)** and Debug-opt-in (`IOS RunSmart app/Services/Coach/CoachModeService.swift`, since the 1.2.6 (46) commit). Don't change it without Nadav. **All v2 work goes behind a new `RunSmartFeatures.coachV2Enabled` (C7.0): ON in Debug and TestFlight, OFF in App Store builds.** Solo users and App Store builds must behave exactly as today.
- **Backward compatibility.** 1.2.6 clients write `plans`, `workouts` and `runs` directly. Every migration must keep them working, and must protect coach data from them through DB triggers, not only app code.
- **Never edit an applied migration.** Write a new file that sorts after the newest one on `main`.
- No commercial map SDKs or tiles beyond what the app already uses.
- No payments, no web app, no push to the watch, no outreach to coaches.
- **Reviews by an agent other than the author.** Claude Code is the primary author. Codex currently has no credits, so treat it as optional: when it has credits, it reviews or authors; otherwise the reviewer is a Cursor agent or a separate Claude session that did not write the PR.
- Tests are required. Swift unit tests in `IOS RunSmart appTests/`, SQL tests in `supabase/tests/*.sql` (same style as `coach_feedback.sql`, `coach_read.sql`), and Deno tests for Edge Functions (same style as `supabase/functions/coach_message/*_test.ts`). Local DB work uses `supabase start` only.
- Hebrew/RTL: new strings go through the same localization path the app uses today. Codes and links stay LTR, as `CoachInviteSection` already does.

### 1.1 Cross-cutting rules v1.3 (every story inherits these; tick each in the PR checklist)

**Model tiers (one primary author per PR, picked by the riskiest part of the PR).**
| Tier | What the PR contains | Author | Reviewer |
|---|---|---|---|
| 1 | New tables with cross-user access, triggers, security-definer **write** functions, consent or privacy gates, Edge Functions that send pushes or call the AI | **Claude Opus (high)** | Codex high (when it has credits), or a Cursor agent / fresh Claude session using the RLS checklist. Grok Bot runs a read-only audit before Nadav applies the migration. |
| 2 | Owner-only tables, read-only security-definer RPCs | **Claude Sonnet (high)** | Opus (high) or Codex high, using the RLS checklist |
| 3 | SwiftUI screens and wiring with no migration | **Claude Sonnet (medium)** | A different agent |
| 4 | Docs only | Sonnet (medium) | A different agent |

Haiku authors no PR in v2. Every string is fixed by the spec, so there is no copy-only PR.

**Migrations.**
- One new file per PR. Its timestamp sorts after the newest file on `main` **and** after every v2 file listed as "written" in `docs/migration-ledger.md` (C0.2). If two open drafts collide, the one approved later renames its file before approval. Renaming is allowed only while the file is unapplied.
- Mirror the identical file into `Running-coach-/v0/supabase/migrations/` in a **separate draft PR in the web repo**. Claude prepares it and never merges it. Update the ledger row in both PRs.
- Every file keeps the repo's header ("Do not apply this to production from the app PR. Nadav applies …"). Files are idempotent: `if not exists`, `create or replace`, `drop trigger if exists`.
- Every security-definer function sets `set search_path = ''`, runs `revoke all on function … from public`, and grants execute only to `authenticated`.
- When a function created by an earlier v2 migration is replaced (`end_coach_link`, `link_is_v2`, `coach_get_athletes_runs`, `leave_coach`), the new file carries its **full** previous behavior. The earlier stories' SQL tests stay in the suite and must stay green.
- Every migration ships a data-preserving rollback file in `supabase/rollback/` (never in `migrations/`) and a row in `docs/coach-v2-rollback.md` (C7.12). Agents never run a rollback.
- Backfills are idempotent and `raise notice` the row counts.

**Flag-off AC (every v2 story with UI).** **Given** `coachV2Enabled = false` **When** the user goes through the story's screens **Then** no v2 string, sheet, permission prompt or v2 RPC call happens (assert it with the service mock), and the existing `CoachModeTests` pass unchanged.

**Mixed-version AC (every v2 coach write or athlete-sharing RPC).**
- **Given** `link_is_v2(coach, athlete) = false` (either side has no `client_capabilities` row, or `coach_v2 = false`, or the kill switch is on) **When** the RPC is called **Then** write RPCs raise `v2_unavailable` and read RPCs return zero rows.
- **And** the coach UI shows "{Athlete} needs the latest RunSmart" with the v2 actions disabled.
- **And** the athlete UI hides v2 sharing lines ("Shared with {Coach}", "{Coach} will see this").

**Link-ended AC.** **Given** the link was revoked or removed **When** any queued (outbox) action for it flushes **Then** the server rejects it with `link_inactive`, the client drops it and shows the spec's link-gone copy once, and nothing reaches the other side.

**Offline/outbox AC (every outboxed action).** **Given** no connection **When** the user does an outboxed action **Then**:
- it shows "Waiting to sync" (coach) or "Waiting to send" (athlete);
- it survives the app being killed and relaunched;
- it is idempotent by client id on flush (two flushes → one row);
- on `v2_unavailable` it stays queued and retries on the next foreground. No athlete data is dropped while the kill switch is on.

**Push AC.**
- Pushes carry no health words, no note, flag or reply text, and no RPE. The only exception is the broadcast body: its first 80 characters (D11).
- Names inside templates are direction-isolated (C7.15).
- Every send writes `coach_notification_log` and goes through `_shared/notify.ts` (C7.5), which applies prefs, quiet hours, dedupe, collapse, the kill switch and a link re-check at send time.

**Analytics AC.** Each story emits exactly the events listed for it in §3.8, through the typed `CoachV2Analytics` (C7.13). No free text, no names, no note or flag content.

**Strings.** Sentence case. Strings go through the app's localization path, with `{Coach}`/`{Athlete}` as placeholders, never concatenated. Exact copy comes from the spec section the story cites.

**Definition of Done (every story; adds to the repo's standard DoD).**
- [ ] Every AC passes, including the named empty, error, offline, link-ended and flag-off cases, plus the §1.1 cross-cutting ACs that apply.
- [ ] New tables have RLS on. A SQL test shows that a non-linked user, a revoked link and the wrong athlete get zero rows or an error.
- [ ] The migration is mirrored to the web tree (draft PR). Rows are updated in the ledger and the rollback runbook.
- [ ] No dependency on a later story. Out-of-scope items weren't built quietly.
- [ ] The PR description lists: story ID, each AC ✅/❌, tests added, migration file(s) with their batch, and "Nadav must apply: yes/no".
- [ ] Reviewed by an agent other than the author, at the story's tier.

---

## 2. Context

### 2.1 Current coach mode (audit of `main`, 2026-11-19)
| Area | Today | Where |
|---|---|---|
| Flag | `coachModeEnabled` = **true in every Release build (App Store + TestFlight)**, Debug needs `-enable-coach-mode`. The Coach tab needs a `coach_profiles` row. 1.2.6 (46) is in App Review | `Services/Coach/CoachModeService.swift` L3–L18 @4a016b4 |
| Becoming a coach | No in-app sign-up. A `coach_profiles` row is inserted by SQL | `tasks/coach-pilot-testing.md`, `20261114210000_coach_role_and_invites.sql` |
| Plan Mode | Group or Individual, locked after save ("Set for the pilot") | `Features/CoachMode/PlanModePickerView.swift`, `Services/Coach/GroupPlanRules.swift`, `20261117130000_coach_plan_mode_group_settings.sql` |
| Group plan | goal, distance, race date, level, runs/week, max 16 weeks. The AI generator builds it. New joiners get it, existing athletes keep theirs | `GroupPlanSettingsView.swift`, `Services/Coach/GroupPlanJoin.swift`, `CoachPlanSetupModel.swift`, `SupabaseCoachPlanRepository.swift` |
| Invite | One active code and link (`get_or_create_my_invite`, `lookup_invite`, `join_coach`), `/join/{CODE}` | `CoachTabView.swift` (`CoachInviteSection`), `JoinCoachView.swift`, `Services/Coach/CoachLinkService.swift` |
| Roster | Groups: Needs attention / On track / No plan yet; "X of Y this week", last run; 80% rule | `Features/CoachMode/CoachAthleteList.swift`, `Services/Coach/WorkoutAdherence.swift` |
| Athlete detail | This week + last week only; day = planned vs actual (distance, duration, pace, avg HR), Missed, Extra run, Matched by date. **Read-only** | `CoachAthleteDetail.swift`, `Services/Coach/CoachAthleteDays.swift`, `CoachReadService.swift` |
| Read RPCs | `coach_list_athletes`, `coach_get_athlete_plan`, `coach_get_athletes_workouts`, `coach_get_athletes_runs` (returns id, athlete_id, workout_id, completed_at, type, distance_km, duration_seconds, pace, average_heart_rate, source; **no RPE, no notes, no splits**), helper `is_active_coach_of` | `20261117164500_coach_read_rpcs.sql` |
| Map | Start/end privacy trim, "Map hidden" / "No map", `coach_get_run_route`, `set_run_route_hidden` | `CoachRunMap.swift`, `CoachRouteUpload.swift`, `CoachRunRouteService.swift`, `20261118140000_coach_run_route.sql`, `20261117100000_coach_route_upload.sql` |
| Feedback | `coach_feedback` (run XOR week, 1–2000 chars, revision, RPC-only writes, offline outbox, edit) | `CoachFeedbackComposer.swift`, `Services/Coach/CoachFeedbackService.swift`, `20261118100000_coach_feedback.sql` |
| Athlete side | `my_coach_feedback`, `mark_feedback_read`, badge, Today cards; note is **read-only, no reply** | `AthleteFeedbackViews.swift`, `AthleteFeedbackService.swift`, `20261118120000_athlete_feedback_read.sql` |
| Presence | "Coached by X" on Today/Plan (`get_my_coach`) | `CoachPresenceViews.swift`, `CoachPresence.swift`, `20261118160000_get_my_coach.sql` |
| Welcome note | Template + per-athlete override | `CoachWelcomeEditor.swift`, `CoachWelcomeService.swift`, `20261118180000_coach_welcome_note.sql` |
| AI as assistant | String swaps to "RunSmart"; `CoachContext.lockedWorkoutIDs` **always empty ("until Story 4.1")**; "That's {Coach}'s workout" copy exists | `Services/Coach/CoachAssistant.swift`, `supabase/functions/coach_message/*` |
| Leave | `leave_coach`, account-deletion cleanup (`purge_coach_data_for_deleted_account`) | `20261115194500_leave_coach.sql`, `MyCoachView.swift` |
| Push | **Local notifications only** (`UNCalendarNotificationTrigger`): `workoutDue`, `missedWorkoutRecovery`, `restDayRecovery`, `weeklyRecap`. **No remote push**: no `aps-environment` in `RunSmart.entitlements`, no token registration, no token table | `Core/Push/PushService.swift`, `RunSmart.entitlements` |
| RPE + notes | Athlete picks 1–10 in `RPESelector`. **Stored on the device only**: `updateRunRPE` → `store.updateRunRPE`. Title and notes are also device-only. `runs.notes` holds a system source note. `DBRunInsert` has no RPE field | `Features/Run/RPESelector.swift`, `Services/Supabase/SupabaseRunSmartServices.swift` L683–L695, ~L2725 |
| Plan and workout writers | **iOS:** `TrainingPlanRepository.persistGeneratedPlan` (L489: deactivates plans, inserts plan and workouts), `replace_group_training_plan` RPC for group joins, `amendWorkout`, `pushWorkoutTomorrow`, `removeWorkout`, flex-week apply, `complete_run_workout` RPC. **Web:** `Running-coach-/v0/lib/sync/plan-workout-sync.ts` upserts on `(plan_id, local_id)`. **Edge Functions:** none write (`flex_week.ts` only proposes). **RLS:** owner-full `workouts_owner_access` / `plans_owner_access` | `Services/Supabase/TrainingPlanRepository.swift`, `20261117163000_replace_group_training_plan.sql`, `20261114120000_close_cross_user_rls_leaks.sql` |
| Live-run guide | `StructuredWorkoutFactory` builds guide stages by **parsing workout text** ("8 x 400m with 90 s recovery") | `Services/StructuredWorkoutFactory.swift` |
| Load | `TrainingLoadCalculator` exists, athlete-side only | `Services/TrainingLoadCalculator.swift`, `Features/TrainingLoad/*` |
| Goal-change warning | Agreed, **not found in code** | – |

Schema facts from `20261117164500_coach_read_rpcs.sql`:
- `plans(id uuid, profile_id, auth_user_id, title, start_date, end_date, is_active, target_distance, target_time)`
- `workouts(id uuid, plan_id, auth_user_id, week, day, scheduled_date date, type, distance, duration, pace int, notes, workout_structure jsonb, intensity, training_phase, completed, completed_at, actual_*, local_id)`. `local_id` is used by web sync, and `workout_structure` already exists.
- `coach_profiles(user_id pk, display_name, created_at)`: select-own only, writes revoked
- `runs(id bigint, auth_user_id, workout_id, completed_at, type, distance, duration, pace, heart_rate, source_provider)`
- `profiles.name` is the display name. There is no `plans.race_date`.
- These tables are shared with the web repo `Running-coach-`, so every change must be mirrored there.

### 2.2 Decisions (Nadav, Nov 19–20)
1. **Coaches build workouts themselves**, from scratch, and can edit, move or delete upcoming workouts. **The AI may propose a draft plan.** The coach edits it and explicitly **approves/publishes** it. **The athlete sees only the coach-approved (published) plan.** Coach-made or coach-edited workouts are **locked against AI overwrite** (wire `CoachAssistant` / `lockedWorkoutIDs` and the `coach_message` Edge Function).
2. **Athlete RPE, run notes and a "pain / something off" flag are shared with the coach by default.** Update the join consent copy, and show existing linked athletes a one-time notice.
3. **No coach interviews. Build now.**
4. **Nov 20, after the UX review:** D1–D9 in §0 (athlete skip/move, goal-change rule, live single edits with a bundled push, both-sides-v2 pilot rule, per-athlete AI drafts only, notification defaults, no note backfill / ack-gated RPE, coach removes athlete, read counts in consent).

### 2.3 Constraints
- Free for now. Later pricing is $9/athlete through a coach and $15 solo. Do not build billing, but don't paint the data model into a corner (keep `coach_id` on coach-owned rows).
- iPhone first. iPad later. The web app may be dropped.
- Garmin Starter route = **upload from watch only**. No workout push to the watch.
- No commercial maps.
- Small solo-founder team: prefer boring and simple, and reuse existing RPC, outbox and test patterns.

### 2.4 Non-goals for v2
Web coach dashboard; payments/billing; pushing workouts to Garmin or Apple Watch; group social wall; coach interviews or outreach; Android.

### 2.5 Consistency with the pilot MVP PRD (v7.2), its epics and the commercial plan (v1.3)
MVP Epics 4–5 (Stories 4.1–4.4 and 5.1–5.4) were never built: `lockedWorkoutIDs` is empty "until Story 4.1". v2 replaces them as follows:
- 4.1 → C8.1a / C8.5
- 4.2 and 4.3 → C8.6 / C8.7
- 4.4 → C7.9
- 5.1 → C7.10
- 5.2 → C7.5 / C8.8 / C8.16
- 5.3 → C7.6
- 5.4 → C7.16

**Claude checks first (C0.1):** confirm that no `workouts.locked` / `edited_by` column, no `coach_plan_drafts` table and no push-token object exists on `main` or in the web tree from earlier MVP prompts. If any exists, extend it rather than creating a duplicate.

| PRD / plan item | v2 | Status |
|---|---|---|
| FR-8…FR-10: every coach edit goes into a draft, then one publish | D3: single edits go live, with one bundled push. Drafts are for whole plans only. | **Superseded by Nadav (D3).** PRD v7.2 isn't updated. Don't "fix" v2 back toward the PRD. |
| FR-9c: an athlete edit clears the lock | D1: skip/move only, and the workout stays locked against the AI | **Superseded (D1)** |
| FR-2e: goal change always allowed after a warning | D2: blocked only for coach-published plans | **Superseded (D2)** |
| FR-12b: digest content (ran, missed, new runs) | D6: counts of misses, open flags, plan changes | **Superseded (D6)** |
| FR-5: "the coach's drafts for that athlete are deleted" on leave | v1.2: drafts purged after 30 days (G17) | **Contradiction. v1.3 follows FR-5: drafts are deleted at link end (M7).** |
| FR-20b: milestones + one-tap praise (pilot weeks 1–2) | Missing in v1.2 | **Gap. v1.3 adds C7.16 (Nadav confirmed, D13).** |
| §5 non-goal: "RPE, run notes … v2, needs separate consent" | P8/P9 copy plus the `ack_coach_consent(2)` gate (D7) | Consistent: the ack is that separate consent. |
| FR-17: permanent "Edited by {Coach}" | G7 tags | Consistent |
| FR-18b: 72-hour "Shared with {Coach}" | G24 | Consistent |
| FR-21: simple leaving, plan keeps adapting | `end_coach_link` releases locks (M6b) | Consistent |
| English UI; Hebrew notes shown as written (Q18) | C7.15 | Consistent |
| Commercial plan v1: coach tool free; later a $9 seat or $15 solo; no payment links in the app | §2.3, L3 | Consistent. The C8.13 explainer's "Free for now." is removed (Sally L3: v2 copy avoids "free"; athlete pricing may change). |
| Locked: "the athlete sees only the coach-approved version" | Applies to coach plans: drafts are never visible (INV-1…6), and published rows are locked | Consistent. [ASSUMPTION] A linked athlete with **no** coach-published plan keeps their own RunSmart plan, which keeps adapting (MVP behavior). The AI never touches locked rows. Nadav flags it if he meant something else. |

---

## 3. Architecture and data model

> **v1.3 note.** Migration IDs follow the v1.3 file map (§0.0): M1a/M1b, M2a/M2b, M5a/M5b, M6a/M6b, and new M0b, M13, M14, M15, M16. The bullets below are updated inline. Where a bullet and a story disagree, the story's AC wins.

> Every migration below is a **draft file only; Nadav applies**. Name files `YYYYMMDDHHMMSS_<name>.sql` after the latest existing one, add a `supabase/tests/<name>.sql`, and mirror to `Running-coach-/v0/supabase/migrations/`. All writes go through `security definer` RPCs with `set search_path = ''`, with no client insert/update/delete policies on new tables, in the same pattern as `coach_feedback`. All coach reads gate on `public.is_active_coach_of(athlete)`.

### 3.1 Phase 1 schema
- **M0 `client_capabilities`** (C7.0, D4): `client_capabilities(user_id pk, coach_v2 boolean not null default false, app_version text, build int, platform text, updated_at)`, own-row, written via RPC `report_client_capabilities(p_coach_v2, p_version, p_build)` on sign-in and app foreground. Helper `link_is_v2(p_coach uuid, p_athlete uuid) returns boolean` (true when both rows have `coach_v2 = true`). **Every v2 coach write RPC and every athlete-sharing RPC checks `link_is_v2`**, and the coach roster returns `athlete_is_v2` so the UI can show "{Athlete} needs the latest RunSmart". It is a security definer function that reads only the boolean. 1.2.6 clients never write a row, so they are treated as not v2.
- **M1a `athlete_run_sharing` (C7.3) + M1b `athlete_run_flags` (C7.4)**. These are two files, one per PR.
  - M1a holds the `runs` columns, `coach_get_athletes_runs`, `coach_get_run_notes` and the ack gate.
  - M1b holds `athlete_run_flags`, its RPCs (plus `athlete_remove_flag(p_id)`, allowed only before the flag is resolved) and the flag reads.
  - RPE and notes are device-only today (`SupabaseRunSmartServices.swift` L683–L695). Add nullable `runs.rpe smallint check (rpe between 1 and 10)` and `runs.athlete_note text check (char_length(athlete_note) <= 1000)`. **Do not reuse `runs.notes`**, which holds the system source note. Add `runs.note_hidden_from_coach boolean not null default false`.
  - 1.2.6 clients upsert `runs` without these keys. PostgREST upsert only sets the columns it receives, so old clients won't null them. Add a SQL test that an upsert without the keys keeps the existing values.
  - `create or replace` `coach_get_athletes_runs` (new file) to also return `rpe smallint, has_note boolean`. Add `coach_get_run_notes(p_run_ids bigint[])` returning `(run_id, athlete_note)`, skipping hidden notes. Both are gated by `is_active_coach_of`.
  - New table `athlete_run_flags(id uuid pk, athlete_id uuid, run_id bigint null, kind text check in ('pain','off'), note text check (char_length ≤ 500), created_at, resolved_at, resolved_by uuid)`. RPCs `athlete_flag_run(p_run_id, p_kind, p_note, p_id)` (idempotent by `p_id`) and `coach_resolve_flag(p_flag_id)`. Owner select only, with no client write policy.
  - **Ack gate (D7):** `coach_get_athletes_runs`' new columns, `coach_get_run_notes` and the flag reads return nothing for a link until `consent_version >= 2 and consent_acknowledged_at is not null` (M5) **and** `link_is_v2` holds. The client does not sync RPE or notes for a link before the ack. **Past notes are never synced.** RPE from the last 14 days syncs once, right after the ack.
  - Extend `purge_coach_data_for_deleted_account`, and check that the `delete_account` Edge Function reaches it.
- **M2a `push_tokens_and_prefs` (C7.10) + M2b `notification_log_and_deferred` (C7.5)**.
  - M2a holds `push_tokens` and `notification_prefs`. The prefs table moved here in v1.3, so the settings screens (C7.14) and every sender read one table.
  - M2b holds `coach_notification_log` and `deferred_pushes`.
  - **There is no remote push today.** New `push_tokens(id uuid pk, user_id uuid, token text unique, environment text check in ('sandbox','production'), bundle_id text, created_at, last_seen_at, disabled_at)`. Own-row insert, update and delete go through RPCs `register_push_token(p_token, p_env)` and `unregister_push_token(p_token)`.
  - `notification_prefs(user_id pk, coach_run_finished bool default true, coach_evening_summary bool default true, coach_pain_flag bool default true, athlete_coach_note bool default true, athlete_plan_updates bool default true, athlete_broadcasts bool default true, quiet_start time default '21:30', quiet_end time default '07:00', time_zone text not null, updated_at)`, own-row.
  - `coach_notification_log(id, recipient_id, athlete_id, kind, ref_id, sent_at)`, server-only, used for dedupe and rate-limiting. Throttle rules (D6): run-finished ≤1 per athlete per coach per 30 min. Anything that falls inside quiet hours (pain included) goes to `deferred_pushes(recipient_id, kind, payload, created_at)` and is **collapsed into one push at quiet end**. Each publish notifies the athlete once.
- **M3 `coach_last_seen`** (C7.2): `coach_athlete_seen(coach_id, athlete_id, seen_at, pk(coach_id, athlete_id))`. RPC `coach_mark_athlete_seen(p_athlete)`. Extend `coach_list_athletes` (or add `coach_roster_summary`) to return `new_runs int`, `new_flags int`, `new_replies int` and `new_events int` since `seen_at`.
  - **v1.3:** M3 also **creates `coach_athlete_events`** (moved from M6), with the full kind list `('athlete_skip','athlete_move','goal_change','left','removed')` defined once here.
  - It adds `athlete_log_goal_change()` (security definer; the caller needs an active link; writes `goal_change`) and `coach_get_athlete_events(p_athlete, p_since)`.
  - This gives Phase 1 a real source for "Changed goal" (C7.2, C7.6) and for the `left`/`removed` events (M5b).
- **M4 `coach_feedback_replies`** (C7.7)
  - `coach_feedback_replies(id uuid pk, feedback_id uuid fk coach_feedback, author_id uuid, text 1..1000, created_at, read_at)`. One level only: replies to replies are not allowed.
  - RPCs `athlete_reply_to_feedback(p_feedback_id, p_text, p_id)` (author must be the feedback's athlete; allowed only while the link is active) and `coach_mark_reply_read`.
  - Extend `my_coach_feedback` and the coach feedback read to include replies.
  - Delete cleanup goes into the purge function.
- **M5a `coach_consent_v2` (C7.8) + M5b `coach_link_end` (C7.11)**. These are two files.
  - M5a holds the consent columns, `ack_coach_consent` and a new `create or replace` of `join_coach` with the same signature.
  - M5b holds `ended_by`, `ended_notice_seen_at`, `end_coach_link`, the new `leave_coach`, `coach_remove_athlete` and the notice RPCs.
  - `coach_athlete_links.consent_version int default 1` and **`consent_acknowledged_at timestamptz null`**. RPC `ack_coach_consent(p_version)` sets both. New joins on a v2 client write version 2 plus the ack at consent. The server state means TestFlight testers never see P9 twice when v2 reaches the store.
  - `coach_athlete_links.ended_by text check in ('athlete','coach') null` and `ended_notice_seen_at timestamptz null`.
  - Refactor: a new internal `end_coach_link(p_link_id, p_ended_by)` holds the effects of today's `leave_coach`. **v1.3, Phase-1 scope.** In M5b, `end_coach_link`:
    - revokes the link and logs `left`/`removed` to `coach_athlete_events` (M3);
    - leaves `leave_coach`'s signature and return shape unchanged (1.2.6 clients call it);
    - **does not reference any column or table that doesn't exist yet.**

    Later behavior arrives in new `create or replace` files:
    - lock release, in **M6b**: `locked`/`coach_published` are cleared, and the workouts stay and are unlocked (G17);
    - draft deletion, in **M7**, **at link end** (PRD FR-5) instead of after 30 days.

    Queued and deferred pushes aren't deleted by SQL. Every sender re-checks the link at send time and drops the row; M2b is applied later, in Batch B.
  - `leave_coach` is a new `create or replace` that calls it. **New RPC `coach_remove_athlete(p_athlete)`** checks `is_active_coach_of` and calls it with `'coach'`. The athlete gets one neutral in-app line, via `my_coach_link_notice()` + `mark_link_notice_seen()`, and no push.

### 3.2 Phase 2 schema
- **M6 `coach_authored_workouts` + lock triggers**, in two files applied together as Batch C:
  - **M6a (C8.1a):** the columns, the coach write RPCs, `workouts_protect_coach_rows`, `athlete_plan_update_queue`, the `link_is_v2` checks, and a `workout_structure` guard (≤16 KB, recognized shape).
  - **M6b (C8.1b):** `plans_protect_coach_plans`, `athlete_replace_training_plan`, `athlete_change_coach_workout` (with `p_request_id`), `end_coach_link` with lock release, and the new `replace_group_training_plan`.
  - `coach_delete_workout` leaves a locked coach `rest` row [ASSUMPTION; see C8.1a]. This is the most important migration in v2, because Codex findings 3 and 4 and self-review findings 6 and 7 all hinge on it.
  - On `workouts`, add `source text not null default 'ai' check in ('ai','coach')`, `locked boolean not null default false`, `coach_id uuid null`, `coach_revision int not null default 0`, `published_version_id uuid null`, **`coach_edited boolean not null default false`** (an RunSmart workout edited by the coach, tagged "Edited by {Coach}"), **`athlete_change text null check in ('skipped','moved')`**, **`athlete_changed_at timestamptz null`** and **`original_date date null`** (for "moved from"). **Reuse the existing `workout_structure` column** for intervals, with no new `structure` column. On `plans`, add `coach_published boolean not null default false` and `coach_id uuid null`.
  - Coach writes go through `security definer` RPCs only: `coach_create_workout`, `coach_update_workout(p_id, p_revision, …)`, `coach_move_workout`, `coach_delete_workout`. Each one checks `is_active_coach_of(plan owner)`, that the workout is `completed = false` and `scheduled_date >= today` (athlete tz), sets `set_config('runsmart.coach_write','on', true)`, then writes `source='coach', locked=true, coach_id`, and bumps `coach_revision`. A stale revision raises `edit_conflict`.
  - **Athlete RPC `athlete_change_coach_workout(p_id, p_action 'skip'|'move', p_new_date date null)` (D1).** It checks that the caller owns the workout, that the row is locked, future and not completed, and `link_is_v2`. It sets `set_config('runsmart.athlete_change','on', true)`, then sets `athlete_change`, `athlete_changed_at`, `original_date` (on the first move) and `scheduled_date` (move only). The row **stays `locked`**. It inserts a `coach_athlete_events` row and **notifies the coach in-app only** (C7.2 marker + C7.6 count).
  - **`coach_athlete_events`** is **created in M3** (v1.3). M6b only writes `athlete_skip`/`athlete_move`/`goal_change` rows to it. It feeds C7.2 and C7.6.
  - **`athlete_plan_update_queue(athlete_id pk, coach_id, first_change_at, last_change_at, change_count, changes jsonb, sent_at)`** (D3). Every coach write RPC upserts into it. The `athlete_plan_update_digest` function sends **one** push once `last_change_at < now() - 10 min`, respecting athlete quiet hours.
  - **Trigger `workouts_protect_coach_rows` (BEFORE UPDATE/DELETE)**, when `OLD.locked` and `runsmart.coach_write` is not on:
    - If `runsmart.athlete_change` is on, **only** `scheduled_date`, `original_date`, `athlete_change` and `athlete_changed_at` may change, and everything else is kept from `OLD`.
    - On UPDATE, **keep** `OLD`'s planned fields (`type, distance, duration, pace, notes, workout_structure, intensity, scheduled_date, plan_id`) and the lock columns. Completion fields (`completed, completed_at, actual_*`) still change. It doesn't raise, so 1.2.6 clients and the web sync never fail mid-batch.
    - On DELETE, raise `workout_locked`.
    - Lock columns (`source, locked, coach_id, coach_revision, published_version_id`) can never be set by a non-coach writer on INSERT or UPDATE. An INSERT with `locked=true` from a non-coach is forced to `false`/`ai`.
  - **Trigger `plans_protect_coach_plans` (BEFORE UPDATE OF is_active, and DELETE), reworked for D2:**
    - A plan with `coach_published = true` raises `plan_locked_by_coach` unless `runsmart.coach_write` is on. The athlete sees "Ask {Coach} to change your plan" (P5) plus "Reply to {Coach}'s latest note".
    - A plan that is **not** coach-published but has locked future workouts raises `coach_workouts_present` unless `runsmart.goal_change` is on.
    - **New athlete RPC `athlete_replace_training_plan(expected_athlete, new_plan, new_workouts, p_ack_replaced_count int)`.** It recounts the locked future workouts and raises `count_changed` if they differ from `p_ack_replaced_count`. Then it sets `runsmart.goal_change`, deactivates the plan, inserts the new one, and logs `goal_change` to `coach_athlete_events`.
    - `persistGeneratedPlan` (L489) moves to this RPC for linked athletes. 1.2.6 clients can only hit `coach_workouts_present` if a v2 coach edited their workouts, which D4 prevents (coach writes require `link_is_v2`). Ending a link clears `coach_published` and `locked` in the same transaction, so a solo plan works again. **v1.3:** that is a new `create or replace` of **`end_coach_link`** in M6b. M5b already routes `leave_coach` and `coach_remove_athlete` through it, so `leave_coach` isn't replaced again.
  - New `create or replace` of `replace_group_training_plan` (new file; the applied `20261117163000` is never edited) so it inherits the trigger behavior and returns a clear error.
  - SQL tests:
    - A direct PostgREST PATCH as the athlete can't unlock or alter a locked row.
    - A web-style upsert on `(plan_id, local_id)` keeps coach fields.
    - Completion still works.
    - Plan regeneration is blocked for coach-published plans and allowed after leaving.
    - Regeneration with a few locked workouts succeeds only through `athlete_replace_training_plan` with the right count.
    - The athlete skip/move path can change only the allowed fields, and the row stays locked.
    - Coach writes are rejected when `link_is_v2` is false.
    - Solo users are unaffected.
- **M7 `coach_plan_versions`** (C8.6, C8.7). Drafts never touch `workouts`.
  - `coach_plan_versions(id uuid pk, coach_id, athlete_id uuid not null, status text check in ('draft','published','archived'), origin text check in ('ai','coach'), base_plan_id uuid null, created_at, published_at, revision int, cloned_from_version_id uuid null)`. **Per-athlete only (D5), with no `group_id`.** "Edit plan" clones the live published version into a new draft (G10).
  - `coach_plan_version_workouts(id, version_id fk, week, day, scheduled_date, type, distance, duration, pace, notes, workout_structure jsonb, intensity, training_phase)`. It mirrors the `workouts` columns used by `persistGeneratedPlan`.
  - RPC `coach_publish_plan_version(p_version_id, p_revision)` runs in one transaction. It creates or updates the athlete's **coach-published plan** (`plans.coach_published=true`) under `runsmart.coach_write`, then writes workouts from the publish date onward with `source='coach', locked=true, published_version_id`. The first publish deactivates the athlete's AI plan through the coach path; future completed rows stay on the old plan. It **never touches completed workouts or dates before today**, archives the previous published version, and returns a diff summary.
  - The athlete keeps reading `workouts` as today, so they only ever see published rows, and athlete RLS doesn't change. The coach reads drafts via `coach_get_plan_version`. **INV-1…INV-6 (§3.10) apply.**
  - The publish RPC also deletes the athlete's pending `athlete_plan_update_queue` row, so each publish produces exactly one push (D6).
  - **v1.3:** M7 adds a new `create or replace` of `end_coach_link` that deletes that athlete's drafts at link end (PRD FR-5).
- **M8 `coach_workout_templates`** (C8.10): `coach_workout_templates(id, coach_id, name, type, distance, duration, pace, notes, workout_structure jsonb, intensity, created_at, updated_at)`, owner-only, with RPC writes. Assigning a template (C8.11) calls `coach_assign_workout(p_athlete_ids uuid[], p_date, p_template_id | inline)`. The call is all-or-nothing, and it reports skipped athletes (no active plan, or date already has a coach workout).
- **M9 `coach_broadcasts`** (C8.12): `coach_broadcasts(id, coach_id, group_id null, text 1..2000, created_at)` + `coach_broadcast_reads(broadcast_id, athlete_id, read_at)`. The athlete reads the coach's broadcasts while linked.
- **M10 `coach_self_signup`** (C8.13): RPC `become_coach(p_display_name, p_bio)` creates a `coach_profiles` row for `auth.uid()`. `coach_profiles` today = `(user_id, display_name, created_at)` with writes revoked from API roles (`20261114210000` L30–L63), so `become_coach` must be `security definer`. Add `bio text ≤ 300` and `avatar_path text null`. The UI is behind `coachV2Enabled`.
- **M11 `coach_groups`** (C8.14): `coach_groups(id, coach_id, name, plan_mode, group_settings jsonb, created_at)`. Add `coach_invites.group_id` and `coach_athlete_links.group_id`. Backfill one default group per coach from the current plan-mode/group-settings rows (`20261117130000_…`). Drop the "locked for pilot" rule at the RPC level. Switching mode applies to new joiners only.

### 3.3 Phase 3 schema
- **M12 `coach_weekly_summaries`** (C9.3): `coach_weekly_summaries(id, coach_id, week_start, payload jsonb, created_at)`, owner-only. This caches AI output to control cost.
- History and load (C9.1, C9.2) **need no new table**. They are two read-RPC files, **M14** (history) and **M15** (load). Use a new RPC `coach_get_athlete_history(p_athlete, p_weeks int ≤ 12)` that returns weekly aggregates (distance, duration, runs, avg RPE, and a load proxy) computed in SQL. **VERIFY** that `TrainingLoadCalculator` uses the same formula, or port it to SQL with tests that match the Swift output.

### 3.4 Edge Functions (Deno, `supabase/functions/`)
- **`coach_notify`** is triggered by a Database Webhook on `runs` insert and `athlete_run_flags` insert. It finds active coaches via `coach_athlete_links`, respects `notification_prefs` and quiet hours in the coach's `time_zone`, dedupes through `coach_notification_log` (max 1 run-finished push per athlete per coach per 30 min), and sends APNs. **Nothing breaks quiet hours, pain flags included (D6).** Deferred pushes collapse into one at quiet end.
  - **v1.3:** `coach_notify` also handles inserts on `coach_feedback_replies` (coach: "{Athlete} replied to your note") and `coach_feedback` (athlete: "{Coach} left you a note").
  - It adds the burst collapse (more than 3 run-finished pushes to one coach within 10 minutes become one).
  - Shared logic lives in `_shared/notify.ts`: prefs, quiet hours in the recipient's tz, dedupe, collapse, `coach_notification_log`, `_shared/flags.ts` and a link re-check at send time. Every sender uses it.
- **`athlete_plan_update_digest`** (D3, C8.4) runs on a 2-minute cron and sends the one bundled "{Coach} updated your plan · {n} changes" push 10 minutes after the coach's last change.
- **`coach_evening_summary`** runs on an hourly cron. For each coach whose local time is 20:00, it sends one push with **counts** (D6): "Today: {n} missed · {k} flags open · {m} changed their plan". It is skipped only when all three are zero; names appear in-app. "Missed" uses the 20:00 athlete-local cutoff (G15), and "changed their plan" counts `coach_athlete_events` from today. Reuse the adherence rule from `WorkoutAdherence` (port the 80% rule to SQL in one shared function).
- **`coach_plan_draft`** (C8.6) generates a draft plan version for **one athlete** (D5). Reuse the generator and prompt infrastructure in `coach_message` (`coach_prompts.ts`, `flex_week.ts`). Output is validated against the existing `workout_structure` shape and written only to `coach_plan_versions`/`…_workouts` with `status='draft', origin='ai'`.
- **`coach_message`** (existing): accept `coachContext.lockedWorkoutIds` (already sent by `CoachAssistant.swift`) and **refuse to modify locked workouts**. Return the "That's {Coach}'s workout" path. `flex_week.ts` only **proposes** changes, which the client applies through `TrainingPlanRepository`. So drop proposals touching locked IDs in `validateFlexWeekResponse` **and** filter them client-side before applying. The M6 trigger is the backstop. Add tests.
- **`_shared/flags.ts`** (C7.12) and **`_shared/text.ts`** (C7.15) are used by every function.
- **`_shared/apns.ts`** (C7.10): an APNs HTTP/2 sender with a JWT signed from the `.p8` key (secrets `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`). It picks sandbox or production by the token's `environment`, and disables a token on a 410 response.
- **`coach_weekly_summary`** (C9.3) runs on cron at the **end of the coach's training week** (Saturday evening for IL, per G14), or on demand. It summarizes each athlete's week (adherence, RPE trend, flags, replies) into `coach_weekly_summaries` and can draft week notes (never sent automatically).
- Deploy scripts follow `scripts/deploy-coach-message.sh`. **Deploying to production is Nadav's call.**

### 3.5 Push types (new remote categories next to `PushService`'s local ones; tap routing in the app delegate)
`coachRunFinished` → coach athlete day detail; `coachEveningSummary` → coach Today; `coachPainFlag` → athlete detail; `athleteCoachNote` → run with pinned note (today it's only a badge); `athleteCoachReply` (coach receives) → feedback thread; `athletePlanPublished` → Plan tab (once per publish); `athletePlanUpdated` (bundled single edits, D3) → the change-list card; `athleteBroadcast` → Today. If the target is gone, open the nearest valid screen with a one-line notice.

### 3.6 Privacy / RLS notes
- The coach never gets raw `select` on athlete tables. Everything goes through `is_active_coach_of`-gated RPCs. Leaving revokes all access immediately, including any queued pushes, which `coach_notify` re-checks at send time.
- The default-on sharing needs a clear consent copy listing **RPE, run notes, pain/off flag**. Existing links see a one-time notice with a link to Leave coach. Per-run "Hide note from {Coach}" mirrors "Hide map" (in C7.3). The consent copy also says the coach sees **when athletes read group messages** (D9). **Nothing is shared before `ack_coach_consent(2)`, and past notes are never shared (D7).**
- Push payloads contain no health detail ("Dana finished a run", not "pain: knee").
- Account deletion: extend `purge_coach_data_for_deleted_account` with every new table.

### 3.7 Kill switch and rollback (C7.12, M0b)
- **Table.** `runtime_flags(key text primary key, enabled boolean not null, updated_at timestamptz, note text)`.
  - No client write policy. Nadav flips a flag with one SQL `update`; the runbook has the exact line.
  - Clients read through `get_runtime_flags()` (security definer), which returns only allow-listed keys.
  - Seed rows, all `enabled = true`: `coach_v2`, `coach_v2_push`, `coach_v2_ai`.
- **Server effect of `coach_v2 = false`.** A new `create or replace` of `link_is_v2` returns false, so:
  - every v2 coach write RPC raises `v2_unavailable`;
  - every sharing read returns zero rows;
  - `athlete_change_coach_workout` raises.
  
  **Existing locks stay enforced by the triggers** (data-safe). Unlocking is a separate Nadav-only script, `supabase/rollback/release_all_coach_locks.sql`.
- **Edge Functions** read the flags at start through `_shared/flags.ts`:
  - `coach_v2_push = false`: nothing is sent; queue and deferred rows are kept, not lost.
  - `coach_v2_ai = false`: `coach_plan_draft` and `coach_weekly_summary` return "Drafting is paused. You can build the plan yourself from the calendar." [ASSUMPTION copy; Sally light review]
- **Client.** Reads the flags on launch and foreground (15-minute cache) [ASSUMPTION].
  - With `coach_v2 = false` it renders the flag-off (1.2.6) UI exactly, and outbox items stay queued.
  - Coaches see one line on the roster: "Some coach tools are paused for now." [ASSUMPTION copy]
  - Athletes see nothing new.
- **Rollback runbook** `docs/coach-v2-rollback.md`, one row per migration batch:
  1. Which flag to flip first.
  2. What stays safe with the flag off.
  3. The rollback file. It drops triggers, then functions, then policies, then new tables, and **keeps new columns on existing tables**.
  4. When **not** to roll back. Example: once athletes have coach-published plans, dropping the M6 triggers exposes those plans to the AI and to 1.2.6 writers, so flip `coach_v2` instead.

### 3.8 Analytics events (C7.13; each story adds its own)
**Claude checks first:** which analytics path the iOS app uses today: the PostHog SDK, the `analytics_events` table (whose RLS MVP Story 1.1 hardened), or both. Use that path. No new vendor, no new table.

**Property rules:**
- Allowed: internal uuids, enums, counts and durations.
- Never: names, note, flag or reply text, or RPE values tied to a person.

**Server-side facts** come from existing tables and are not duplicated as events: `coach_notification_log` (pushes sent, by kind), `coach_athlete_events`, `coach_feedback`, `coach_feedback_replies`, `athlete_run_flags`, `coach_plan_versions`.

| Story | Events (client) |
|---|---|
| C7.1 | `coach_today_viewed(athlete_count, need_count)`, `coach_today_row_opened(reason)` |
| C7.3 | `run_rpe_set(shared)`, `run_note_saved(shared)`, `run_note_hidden_toggled(hidden)`, `rpe_backfill_done(count)` |
| C7.4 | `flag_created(kind, has_run)`, `flag_removed`, `flag_resolved(minutes_open)` |
| C7.7 | `coach_note_reply_sent` |
| C7.8 | `consent_v2_shown(surface)`, `consent_v2_acked(surface)`, `consent_v2_leave_tapped(surface)` |
| C7.10 | `push_permission_prompted(role)`, `push_permission_result(role, granted)`, `push_opened(kind)` |
| C7.11 | `coach_removed_athlete`, `athlete_left_coach` |
| C7.14 | `notification_pref_changed(kind, enabled)` |
| C7.16 | `milestone_shown(kind)`, `praise_sent(kind)` |
| C8.2/C8.3/C8.4/C8.11 | `coach_workout_saved(action, source_before, has_steps)`, `coach_assign_done(added, skipped)` |
| C8.15 | `athlete_changed_coach_workout(action)` |
| C7.9/C8.5 | `goal_change_warned(k)`, `goal_change_confirmed(k)`, `goal_change_blocked` |
| C8.6/C8.7 | `plan_draft_requested`, `plan_draft_result(ok, seconds)`, `plan_published(weeks, workouts, edits_in_draft)`, `plan_draft_discarded` |
| C8.12 | `broadcast_sent(recipients)` |
| C9.3/C9.4 | `weekly_summary_opened`, `ai_note_draft_sent(edited)`, `ai_label_shown` (athlete side) |

### 3.9 Text direction (C7.15)
- **Free text** (notes, replies, flag notes, run notes, broadcasts, bio, template names) renders in its natural paragraph direction.
- **Placeholders.** `{Coach}`/`{Athlete}` in templates are wrapped in FSI…PDI (U+2068…U+2069) on both the client (`BidiText.isolate`) and the server (`_shared/text.ts isolate()`).
- **Server truncation** (`truncateGraphemes`) never splits a grapheme cluster.
- **Length limits.** Client counters use the same unit as the server `check` (code points via `char_length`), so a message the client accepts is never rejected by the server.
- **Numbers, paces and codes** stay as LTR runs inside RTL text.

### 3.10 Draft invariants ("the athlete never sees a draft"; tested in C8.6, C8.7, C8.8 and §6)
- **INV-1.** No athlete-readable path to `coach_plan_versions` or `coach_plan_version_workouts`:
  - RLS is on, with no athlete policy;
  - a SQL test enumerates every function granted to `authenticated` that reads those tables and asserts that each checks coach ownership.
- **INV-2.** Draft generation (`coach_plan_draft`) and draft edits never write `plans` or `workouts`. Tests assert the athlete's row counts and `updated_at` values are unchanged.
- **INV-3.** Publish is one transaction. A failure mid-publish leaves the athlete's plan byte-identical (kill-mid-publish test).
- **INV-4.** Nothing references a draft before the publish commits: no push, no `athlete_plan_update_queue` row, no analytics event with draft content, no `coach_message` AI context for the athlete, no Today card.
- **INV-5.** The athlete's client reads plan data only from `plans` and `workouts`. A code search in the PR shows no versions-table reference in athlete code paths.
- **INV-6.** The coach's "{Athlete} sees:" preview is computed on the coach's phone and never stored where the athlete can read it.

---

## 4. Epics and stories

Legend:
- **Model:** the primary author, using the tier rules in §1.1. Codex is optional because it has no credits now.
- **UX gate:** Sally's spec is ready. The gate is a check that the PR matches the spec, plus Sally's sign-off on screenshots.
- **Mig:** the migration file (Nadav applies it), with its batch letter.
- **Deps:** earlier stories only.

Every story inherits §1.1 (the cross-cutting ACs and the DoD). "UX AC: §X" means the acceptance criteria in that section of the spec are part of the story.

### Phase 0: Ground truth (docs only)

**C0.1 Refined plan (docs PR 0)**: Sonnet (medium) | Mig: none | S | Deps: none
- Story: As Nadav, I approve a plan that Claude has checked against the code before any build PR.
- AC:
  1. **Given** this plan and the spec **When** Claude reads every cited file and migration on `main` **Then** `docs/coach-experience-v2-plan.md` lists each VERIFY and "Claude checks first" item with its result (confirmed / wrong, with a file:line).
  2. **Given** a claim is wrong **Then** the doc proposes the change under "Changes from the input plan" and doesn't change any story's scope by itself.
  3. **Given** the PR **Then** it is a draft, it touches only `docs/`, and Claude stops until Nadav says go.

**C0.2 Migration ledger + iOS/web drift report (new)**: Sonnet (medium) | Mig: none | S | Deps: none (can run in parallel with C0.1)
- Story: As Nadav, I want one table of every coach migration in both repos with its apply status, so I apply v2 batches in the right order and the web tree doesn't drift further.
- Claude checks first: list both trees at `main`: iOS `supabase/migrations/` and web `Running-coach-/v0/supabase/migrations/`.
- AC:
  1. **Given** both trees **When** the report is generated **Then** `docs/migration-ledger.md` lists every file from `20261114120000` onward with: filename; present in iOS (y/n); present in web (y/n); byte-identical (y/n); applied in prod (agents write "unknown"; Nadav fills it in).
  2. **Given** a file that exists in one tree only, or contents that differ **Then** it's listed under "Drift" with a one-line description. **No file is added or changed to fix the drift in this PR.**
  3. **Given** v1.3 **Then** a "v2 batches" section has one row per file in the §0.0 map (M0…M16), with status "not written" and the batch letter. Every later migration PR updates its row (DoD).
  4. **Given** the diff **Then** only `docs/` changes.

### Phase 1: "Know who needs me" (Now, pilot)

**C7.0 `coachV2Enabled` gate + client capability (D4)**: **Opus (high)** | Codex medium (opt) | Mig: **M0** (A) | M | Deps: C0.1
- Story: As Nadav, I can ship v2 to TestFlight while the App Store build keeps 1.2.6 coach mode, and the server knows which clients are v2, so nobody on an old build gets half a feature.
- Claude checks first: the `isTestFlight(receiptName:)` logic in the Nov 19 09:02 commit; where the sign-in and foreground hooks live.
- AC:
  1. **Given** a Debug build with `-enable-coach-v2` / Debug without it / a TestFlight build (sandbox receipt) / an App Store build **When** `RunSmartFeatures.coachV2Enabled` is read **Then** it returns true / false / true / false. A unit test covers each case.
  2. **Given** any build **Then** `coachModeEnabled` behaves exactly as on `main`, and the existing `CoachModeTests` pass.
  3. **Given** a signed-in user **When** the app signs in or comes to the foreground **Then** it calls `report_client_capabilities(coachV2Enabled, version, build)` at most once per foreground. Offline, it retries on the next foreground and doesn't crash.
  4. **Given** coach C and athlete A **When** `link_is_v2(C, A)` is called **Then** it is true only when both rows have `coach_v2 = true` and the link is active. SQL tests cover the four combinations, a missing row (1.2.6) and a revoked link.
  5. **Given** user U calls `report_client_capabilities` **Then** only U's row changes. SQL tests: U can't write another user's row; `anon` is denied.
  6. **Given** a v2 coach and an athlete with `athlete_is_v2 = false` **When** the roster loads **Then** the row shows "{Athlete} needs the latest RunSmart", and v2 actions for that athlete are disabled with that line as the reason.
- Files: `Services/Coach/CoachModeService.swift`, `CoachModeTests.swift`, the sign-in/foreground hook, M0, `supabase/tests/client_capabilities.sql`. UX AC: spec Part 2 › C7.0, G4.

**C7.12 Server kill switch + rollback runbook (new)**: **Opus (high)** | Mig: **M0b** (A) | M | Deps: C7.0
- Story: As Nadav, I can switch v2 coach features off for everyone with one SQL statement, without a build, and I have a written rollback per batch, so a bad pilot day doesn't need App Review.
- AC:
  1. **Given** `runtime_flags.coach_v2 = false` **When** `link_is_v2` is called for any pair **Then** it returns false. `supabase/tests/kill_switch.sql` asserts this, and **every later v2 RPC adds a case to this file** (DoD).
  2. **Given** `coach_v2 = false` **When** a v2 client comes to the foreground **Then** within that foreground it renders the flag-off UI, and queued outbox items stay queued. **When** the flag is back on **Then** the v2 UI returns on the next foreground and the queue flushes.
  3. **Given** an authenticated client **When** it tries to insert or update `runtime_flags` **Then** it's denied. **When** it calls `get_runtime_flags()` **Then** only allow-listed keys come back. `anon` is denied.
  4. **Given** `_shared/flags.ts` **When** a flag is off **Then** the calling function exits early, returns 200 and logs `skipped_kill_switch` (Deno test).
  5. **Given** this PR **Then** `docs/coach-v2-rollback.md` exists with the flag SQL lines and a section per batch, plus `supabase/rollback/` files for M0 and M0b. Later migration PRs add theirs (DoD).
- Files: M0b, `_shared/flags.ts`, a client flag reader next to `CoachModeService`, the docs.

**C7.10 Remote push foundation**: **Opus (high)** | Codex high (opt) | Mig: **M2a** (B) | L | Deps: C7.0, C7.12
- Story: As the app, I can send a server push to one user's devices, and permission is asked in context, so coach events reach people.
- **Nadav setup (blocks device tests only):** create the APNs Auth Key (.p8), enable Push on the App ID, regenerate profiles, set `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`. Agents never handle the key.
- Claude checks first: the App/SceneDelegate name; any existing permission flow in `PushService`; the bundle ids for Debug and Release.
- AC:
  1. **Given** the build **Then** `RunSmart.entitlements` has `aps-environment` (development for Debug, production for Release).
  2. **Given** a coach on v2 **When** they first open Coach Today **Then** T6 shows once. "Turn on" → system prompt → on grant, register and call `register_push_token(token, env)`. "Not now" → no system prompt; they can enable later from T5 (C7.14).
  3. **Given** a linked v2 athlete **When** they tap OK on P8 or P9 **Then** P10 shows, with the same behavior.
  4. **Given** a fresh sign-in **Then** no permission prompt appears (this replaces v1.2 AC 2). **Given** permission was denied **Then** the app never calls the system prompt again.
  5. **Given** one user on two devices **Then** there are two `push_tokens` rows. **When** they sign out on device 1 **Then** only device 1's token is unregistered. SQL: a user can't read, change or delete another user's token.
  6. **Given** `_shared/apns.ts` **When** APNs returns 410 **Then** the token gets `disabled_at`. 400/403 are logged and not retried; 5xx is retried once [ASSUMPTION]. Deno tests mock APNs.
  7. **Given** the dev-only `push_selftest` **When** a user calls it for themselves **Then** a push arrives (manual TestFlight check). It isn't in any production deploy script.
  8. **Given** a tapped push whose target is gone (link ended, workout deleted, flag resolved) **Then** the app opens the nearest valid screen with a one-line notice. A router unit test covers each §3.5 kind.
  9. **Given** the first read of `notification_prefs` **Then** a row is created with the D6 defaults and the device `time_zone`. The time zone updates on foreground when it changes. SQL: own row only.
- Files: `RunSmart.entitlements`, App/SceneDelegate, new `Core/Push/RemotePushRegistrar.swift`, `supabase/functions/_shared/apns.ts`, M2a. UX AC: spec §A.6, §C.5 (P10), Part 2 › C7.10.

**C7.8 Consent v2 + one-time notice for existing athletes**: **Opus (high)** | Mig: **M5a** (A) | S | Deps: C7.0 | Sally: light copy review
- Story: As an athlete, I'm told exactly what my coach will now see, and nothing new is shared until I tap OK, so the privacy change is my choice.
- Claude checks first: `join_coach`'s signature. It is replaced with the same signature so 1.2.6 clients keep working; their joins stay at `consent_version = 1` with no ack.
- AC:
  1. **Given** a v2 athlete joining a v2 coach **When** the consent screen shows **Then** the copy is spec **P8** plus the D9 line "{Coach} can see when you read group messages", with equal-weight buttons.
  2. **When** they tap Share **Then** the link is created with `consent_version = 2` and `consent_acknowledged_at = now()` in the same call.
  3. **Given** an existing link with `consent_version < 2` on a v2 client, and `link_is_v2` true **When** Today opens **Then** **P9** shows. OK → `ack_coach_consent(2)`. "Leave {Coach}" → the existing leave sheet (A13), not an instant leave.
  4. **Given** the ack fails (offline or server error) **Then** P9 shows again on the next open, and the sharing RPCs still return nothing.
  5. **Given** an athlete who acked on TestFlight **When** a later build with v2 reaches them **Then** P9 doesn't show again (server state).
  6. **Given** `ack_coach_consent` called by anyone other than the link's athlete **Then** an error. Called twice → idempotent; the first ack time is kept.
  7. **Given** the coach isn't v2 **Then** the join uses the MVP A3 copy (version 1) and P9 isn't shown yet. It shows once the coach is v2.
  8. **Given** the leave sheet **Then** it adds "{Coach} won't see your effort, notes or flags" and "Your replies stay" (G17).
- Files: `JoinCoachView.swift`, `CoachConsentCopy` (in `CoachLinkService.swift`), `CoachPresenceViews.swift`, `MyCoachView.swift` (leave sheet), M5a. UX AC: spec §C.5 P8/P9, Part 2 › C7.8.

**C7.15 Mixed-direction text (new)**: Sonnet (medium) | Mig: none | S | Deps: C7.0
- Story: As a coach who writes in Hebrew inside the English pilot, my notes, my name and my athletes' replies render correctly in the app and in pushes.
- Claude checks first: how MVP Story 3.1 did "correct mixed-direction rendering". Reuse it if it exists.
- AC:
  1. **Given** free text that starts with Hebrew / English **When** it's displayed **Then** it renders right-to-left / left-to-right per paragraph, leading-aligned. Snapshot or unit fixtures cover: pure Hebrew, pure English, "6×800 ב-4:00", English with a Hebrew name, and emoji.
  2. **Given** a template with `{Coach}`/`{Athlete}` filled with a Hebrew name **Then** the name is wrapped in FSI…PDI and the surrounding punctuation stays in place (unit test on `BidiText.isolate`).
  3. **Given** server-composed push text **Then** `_shared/text.ts` `isolate()` and `truncateGraphemes(s, n)` are used. Truncation never splits a grapheme or surrogate pair and appends "…". Deno tests use Hebrew + emoji at the cut point.
  4. **Given** a reply, note or bio limit **Then** the client counter counts the same unit as the server `char_length` check. A test with emoji proves that a text the client accepts isn't rejected by the server.
  5. **Given** new v2 view files **Then** they use no hard-coded left/right alignment (a grep in the PR shows 0 hits).
- Files: new `Core/Text/BidiText.swift`, `supabase/functions/_shared/text.ts`, tests.

**C7.13 Pilot analytics events + metric definitions (new)**: Sonnet (medium) | Mig: none [ASSUMPTION; Claude checks first] | S | Deps: C7.0
- Story: As Nadav, I can see whether v2 helps coaches and athletes (§7.1) without reading anyone's notes.
- Claude checks first: the app's existing analytics path (§3.8).
- AC:
  1. **Given** this PR **Then** a typed `CoachV2Analytics` exists with every §3.8 event as a case with fixed, typed properties, and no free-form string parameters.
  2. **Given** any event **Then** a unit test asserts its properties are only ids, enums, counts or durations, with no value longer than 64 characters.
  3. **Given** `coachV2Enabled = false` **Then** no v2 event is sent.
  4. **Given** offline **Then** events use the existing path's queueing; no new queue is added.
  5. **Given** this PR **Then** `docs/coach-v2-metrics.md` defines each §7.1 metric as a query or insight over these events plus the server tables in §3.8. Metrics without a target say "watch".
  6. **Given** later stories **Then** each adds its own events (DoD). This PR wires none to screens that don't exist yet.

**C7.1 Coach Today with 7-day dots**: **Sonnet (high)** | Codex medium (opt) | **UX gate: Sally (spec §A ready)** | Mig: none | M | Deps: C7.0, C7.13
- Story: As a coach, I open the Coach tab and see in one screen who ran, who missed and who needs me today.
- UX AC: spec **§A.3–§A.10** (T1, T2 shell, states, copy, accessibility, RTL). They are part of this story.
- AC:
  1. **Given** a v2 coach with linked athletes **When** the Coach tab opens **Then** T1 renders above the existing roster: the header and summary line (§A.6), then the groups in §A.3 order, each with a "({n})" count.
  2. **Given** an athlete's last 7 days **Then** each day shows the grammar-table glyph and label: done ●; partial ◐ (<80% of planned distance or duration); missed ⊘ (only after the 20:00 athlete-local cutoff); rest –; planned ○; extra +. Color is never the only signal. Unit tests cover week, time-zone and DST boundaries, reusing the `CoachAthleteDetailTests` fixtures. The week start follows the region rule (G14).
  3. **Given** it's before 20:00 athlete-local **Then** today's undone workout reads "Not done yet", and yesterday's misses appear under "Missed yesterday".
  4. **Given** the runs RPC fails and the workouts RPC succeeds **Then** days render as "unknown" (dotted) with the §A.4 banner, never as missed.
  5. **Given** several reasons on one row **Then** one chip shows the most urgent reason, sorted per §A.3 item 6. **Given** new data arrives while the screen is visible **Then** rows don't re-sort, and the "New updates · Refresh" pill appears.
  6. **Given** each state in §A.5 (0 athletes; no plans; caught up; offline with cache; error with no cache; error with cache; partial data; revoked mid-session) **Then** the exact copy from §A.5 shows.
  7. **Given** 30 athletes **Then** any group with more than 8 rows collapses to "Show all {n}", and the list is lazy (a preview with 30 fixtures).
  8. **Given** VoiceOver **Then** each row is one element with the §A.8 summary sentence, the dots strip is adjustable, and the custom actions exist. Group headers have the header trait. **Given** XXL or AX3+ **Then** the §A.8 layout rules apply.
  9. **Given** C7.4 / C7.2 / C7.16 aren't merged yet **Then** the pain group, "new" markers and milestone tags are absent: no empty headers, and no crash.
  10. **Given** a row tap **Then** `CoachAthleteDetailView` opens on the reason's day or run. Data comes from the existing `coach_get_athletes_workouts` / `coach_get_athletes_runs` with a 7-day window; there is no new RPC.
  11. Flag-off: the Coach tab is the 1.2.6 roster with identical strings.
- Files: `CoachTabView.swift`, `CoachAthleteList.swift`, new `CoachTodayView.swift`, `WorkoutAdherence.swift`, `CoachAthleteDays.swift`. Analytics: §3.8 C7.1.

**C7.3 Sync RPE + run notes and share with the coach**: **Opus (high)** | Codex high (opt) | Mig: **M1a** (A) | L | Deps: C7.8, C7.15
- Background: RPE and notes are device-only today (`SupabaseRunSmartServices.swift` L683–L695). `runs.notes` holds a system source note, so it is not reused.
- AC:
  1. **Given** a linked athlete with `link_is_v2` and `consent_acknowledged_at` set **When** they set RPE or save a run note on a run that has a server row **Then** `runs.rpe` / `runs.athlete_note` are written, using the existing offline retry pattern. **When** they edit the note after the coach has read it **Then** the coach sees the latest version, with no history.
  2. **Given** no ack yet, or `link_is_v2` false, or a solo athlete, or the flag is off **When** the athlete sets RPE or a note **Then** nothing about it reaches the server (assert with the service mock). The "notes stay on this device" promise holds.
  3. **Given** the athlete taps OK on P9 (or P8 at join) **When** the ack succeeds **Then** a one-time job syncs **RPE only** for runs completed in the last 14 days that have a server row. It retries failures and runs once per link (persisted flag). **Notes on runs completed before the ack are never synced, even if edited later** (D7).
  4. **Given** the coach's day detail **Then** it shows "Effort 7/10" and the note in quotes with "— {Athlete}" under Actual. With no note, nothing shows. With a hidden note, nothing shows and there's no "hidden" indicator.
  5. **Given** the athlete turns on "Hide note from {Coach}" (P7, next to "Hide map") **Then** `note_hidden_from_coach = true`, and `coach_get_run_notes` skips that run at once (SQL). Turning it off restores it.
  6. **Given** a 1.2.6-style upsert without the new keys **Then** the stored `rpe` and `athlete_note` are kept (SQL).
  7. **Given** `coach_get_run_notes` called with run ids that belong to another coach's athlete, or to a revoked or removed link **Then** those ids are dropped silently (SQL).
  8. **Given** a run with no server row **Then** P7's "Shared with {Coach}" line is hidden.
  9. **Given** the run screen **Then** there is only one status line: the MVP 72-hour line when present (G24).
  10. **Given** account deletion **Then** `purge_coach_data_for_deleted_account` covers the new columns. Claude checks first: `delete_account` reaches it.
- Files: `SupabaseRunSmartServices.swift` (`updateRunRPE`, `updateRunDetails`, `DBRunInsert`), the local run store, `CoachReadService.swift`, `CoachAthleteDetail.swift`, the run detail view, M1a. UX AC: spec §C.5 P7, Part 2 › C7.3.

**C7.2 "New since last visit" markers + coach events**: **Opus (high)** | Mig: **M3** (A) | **M** (was S) | Deps: C7.1
- Story: As a coach, I see what's new for each athlete since I last opened them, including goal changes, so nothing slips by.
- Claude checks first: grep every caller of `saveTrainingGoal` / `persistGeneratedPlan` (`GoalWizardView` ~L259; the Plan "Build my plan" CTA is still VERIFY) and list them in the PR.
- AC:
  1. **Given** the coach opens an athlete's detail **Then** `coach_mark_athlete_seen(athlete)` is called (outbox when offline). **Given** a second coach device **Then** the marker clears there after a refresh.
  2. **Given** runs, open flags (once C7.4 ships), replies (once C7.7 ships) or `coach_athlete_events` rows newer than `seen_at` **Then** the row shows the dot **and** "{n} new". The dot never appears alone.
  3. **Given** a linked v2 athlete saves a new plan through any listed caller **When** the save succeeds **Then** the client calls `athlete_log_goal_change()` once (outbox), and the coach's row shows "Changed goal" (§A.3).
  4. **Given** `athlete_log_goal_change` with no active link **Then** no row is written and it returns false, with no user-visible error.
  5. SQL:
     - a non-coach can't read or write seen rows or events;
     - a revoked link returns nothing;
     - an athlete can only log for their own active link;
     - `kind` is limited to `('athlete_skip','athlete_move','goal_change','left','removed')`, defined once here.
  6. **Given** a 1.2.6 athlete **Then** no goal events are logged. This known limit is documented in the PR, and D4 covers it.
- Files: M3, `CoachReadService.swift`, `CoachAthleteList.swift` / `CoachTodayView.swift`, the goal-save callers. Tests: `supabase/tests/coach_last_seen.sql`, Swift.

**C7.7 Athlete replies to a coach note (one level)**: **Opus (high)** | Mig: **M4** (A) | M | Deps: C7.8, C7.15 (its pushes are sent by C7.5)
- Claude checks first: whether the welcome note is a `coach_feedback` row. If it is, replies are allowed on it [ASSUMPTION].
- AC:
  1. **Given** a v2 athlete with an active v2 link and a coach note on a run or week **When** they tap Reply and send ≤1000 characters **Then** a reply appears under the note as "You · {time}" with "Sent" or "Waiting to send". It goes through the outbox and is idempotent by client id.
  2. **Given** 1001 characters **Then** the counter shows the error "Keep replies under 1000 characters" and Send is disabled.
  3. **Given** an existing reply **Then** the athlete can add more replies, but can't edit or delete them.
  4. **Given** the coach **Then** replies show under the note in the day detail and week note, and count as "new" (C7.2).
  5. **Given** a reply-to-reply attempted through the RPC **Then** it's rejected; replies have no parent reply.
  6. **Given** the link has ended **Then** Reply is hidden, and notes and replies stay readable to the athlete. The coach's RPCs return nothing for that athlete's replies (SQL).
  7. **Given** the link ended before the outbox flushed **Then** the athlete sees "You're no longer linked to {Coach}, so this reply wasn't sent."
  8. **Given** a broadcast (C8.12) **Then** there's no Reply.
- Files: `AthleteFeedbackViews.swift` (drop "Read-only: no reply" behind the flag), `AthleteFeedbackService.swift`, `CoachFeedbackService.swift`, `CoachFeedbackComposer.swift`, M4. UX AC: spec §C.5 P6, Part 2 › C7.7.

**C7.4 "Pain / something off" flag**: **Opus (high)** | Mig: **M1b** (A) | M | Deps: C7.3, C7.1
- AC:
  1. **Given** a linked athlete with ack and `link_is_v2` **When** they save a run (or open its detail) **Then** they see the "Something off?" row (P7): chips "Pain" / "Something else" (`kind = 'off'`), an optional note ≤500, and "Send to {Coach}".
  2. **Given** Today **Then** a "Something off?" entry under the coached-by line creates a flag with `run_id = null` (spec C.6 P7 fallback, §A.7 item 5).
  3. **When** the flag is sent **Then** the athlete sees "Sent to {Coach}" plus the safety line "If the pain is sharp or doesn't go away, check with a doctor or physio." There is never a response-time promise.
  4. **Given** offline **Then** the flag is outboxed and idempotent by `p_id`.
  5. **Given** an unresolved flag **When** the athlete taps "Remove flag" **Then** `athlete_remove_flag(p_id)` deletes it. That is only allowed before it's resolved (SQL).
  6. **Given** the coach **Then** a "Pain" or "Something off" chip (glyph + text) shows in the Today group, the roster and the day detail, with multiple flags listed separately.
  7. **When** the coach taps "Mark handled" **Then** the outbox holds the call for 5 s behind the "Marked handled · Undo" toast. After that, the athlete sees "{Coach} saw this", and the coach sees "Handled by you · {date}".
  8. **Given** any flag **Then** no plan, AI or flex-week code path reads `athlete_run_flags` (a code search is listed in the PR). Claude checks first: whether the RunSmart chat exists. If it does, asking it about the flag gets the G21 line.
  9. **Given** no ack / not v2 / solo / flag off **Then** the row is hidden, and "{Coach} will see this" never shows.
  10. SQL:
      - only the athlete's active coach can resolve;
      - the athlete can't resolve;
      - reads are gated by ack + `link_is_v2`;
      - a revoked link returns nothing;
      - deleting the run keeps the flag, and the coach sees "Run deleted";
      - account deletion purges flags.
- Files: run summary view, new `AthleteRunFlagService.swift`, `CoachTodayView.swift`, `CoachAthleteDetail.swift`, M1b. UX AC: spec §A.7, §A.10, §C.5 P7, Part 2 › C7.4.

**C7.11 Coach removes an athlete (D8)**: **Opus (high)** | Mig: **M5b** (A) | M | Deps: C7.8 (M5a), C7.2 (M3) | Sally: light copy review
- Story: As a coach, I can end coaching for one athlete.
- AC:
  1. **Given** the athlete detail menu **When** the coach taps "Remove {Athlete}" and confirms on the sheet that lists the effects **Then** `coach_remove_athlete(athlete)` runs. It does **not** require `link_is_v2`: a coach can remove an athlete who is on any build.
  2. **Given** a removal or a leave **Then** both go through `end_coach_link(link, ended_by)`. It sets status revoked, `revoked_at` and `ended_by`, and logs a `left` or `removed` event.
  3. **Parity test:** after a leave and after a removal, every coach read RPC that exists at that point returns zero rows for that athlete. Later stories add their RPCs to this test.
  4. **Given** a 1.2.6 client calls `leave_coach` the old way **Then** the signature and return shape are unchanged (SQL test).
  5. **Given** a removal **Then** no push is sent. On the athlete's next v2 open, they see once "You're no longer coached by {Coach}. Your plan stays and RunSmart keeps adapting it." (`my_coach_link_notice()` + `mark_link_notice_seen()`). An athlete who left on their own sees no notice. A 1.2.6 athlete sees the MVP behavior.
  6. **Given** a non-coach, or another coach, calls remove **Then** an error. A repeated remove is an idempotent no-op.
  7. **Given** a queued coach action for that athlete **Then** it's rejected with `link_inactive` (§1.1).
  8. **Out of scope here (added later as new `create or replace` files):** lock release (M6b) and draft deletion (M7).
- Files: M5b, `CoachAthleteDetail.swift`, `MyCoachView.swift`, `CoachLinkService.swift`. UX AC: spec G16, Part 2 › C8.13 stop-coaching note.

**C7.16 Beginner milestones + one-tap praise (new; MVP FR-20b)**: Sonnet (medium); if M13 is needed, Sonnet (high) + RLS review | Mig: **M13** only if needed (A) | M | Deps: C7.1, C7.2 (its push is sent by C7.5)
- Story: As a coach of beginners, I see first runs and first weeks and react in one tap, so every athlete feels noticed even with 20 of them.
- Claude checks first: whether `coach_feedback` has a `kind` that fits a reaction; whether the existing read RPCs can answer "first run ever" and "longest run so far". If not, M13 adds read-only `coach_get_athlete_milestones(p_athlete_ids uuid[])`.
- AC:
  1. **Given** an athlete's first completed run, first full planned week (every non-rest workout done), longest run so far, or 3+ days without a planned workout done **Then** a tag shows on their Coach Today row: "First run", "First full week", "Longest run", "Quiet 3 days".
  2. **Given** "Quiet 3 days" **Then** it's coach-only, never shown to the athlete, and never triggers an automatic message (PRD Q8).
  3. **When** the coach taps 👏 / 🔥 / "Great job" on a milestone **Then** it's saved as coach feedback on that run or week (outbox, idempotent), counts for SM-3/SM-7, and the athlete sees it as a coach note. The push is "{Coach} left you a note", with no content (C7.5).
  4. **Given** a reacted milestone **Then** the tag shows "Reacted", and a double tap doesn't create a second reaction.
  5. **Given** milestones **Then** they come from completed workouts (Epic 0), not raw runs, and they are in-app only. The 20:00 push content stays fixed by D6 [ASSUMPTION].
- Files: `CoachTodayView.swift`, `CoachFeedbackService.swift`, M13 if needed.

**C7.5 Coach and athlete push sender: run finished, flags, notes, replies + quiet hours**: **Opus (high)** | Codex high (opt) | Mig: **M2b** (B) | L | Deps: C7.10, C7.4, C7.7, C7.12
- Story: As a coach, I'm told when an athlete finishes a run or flags something. As an athlete, I'm told when my coach writes to me. Nobody gets spammed or woken up.
- AC:
  1. **Given** a `runs` insert (in-app, Garmin or HealthKit import) for an athlete with an active v2 link **Then** within 2 minutes the coach gets "{Athlete} finished a {x} km run", once per `runs.id`. Imports with `completed_at` older than 24 h send no push but still count as "new".
  2. **Given** a second run-finished push for the same athlete within 30 minutes **Then** it isn't sent (D6).
  3. **Given** more than 3 run-finished pushes to one coach within 10 minutes **Then** the 4th and later collapse into one "{n} more athletes finished runs" at the end of that window [ASSUMPTION: a fatigue rule compatible with D6].
  4. **Given** an `athlete_run_flags` insert **Then** the coach gets "{Athlete} flagged something after a run", with no health words.
  5. **Given** a `coach_feedback_replies` insert **Then** the coach gets "{Athlete} replied to your note".
  6. **Given** a `coach_feedback` insert (note or praise) **Then** the athlete gets "{Coach} left you a note". Welcome notes created at join aren't pushed (Claude checks first how they're inserted).
  7. **Given** the recipient is in quiet hours (in their own `time_zone`) **Then** nothing is sent and a `deferred_pushes` row is written. At quiet end, **one** collapsed push goes out: coach "While you were away: {r} runs · {f} flags · {p} replies"; athlete "{Coach} left you {n} notes". Pain is included and doesn't break quiet hours (D6).
  8. **Given** the pref for that kind is off **Then** nothing is sent and nothing is deferred.
  9. **Given** the link ended, or `link_is_v2` turned false, between the event and the send **Then** nothing is sent, and the deferred rows for that link are dropped at send time.
  10. **Given** `coach_v2_push = false` **Then** nothing is sent, and deferred rows are kept.
  11. **Given** a tap **Then** it routes per §3.5.
  12. **Given** every send **Then** a `coach_notification_log` row is written; it is the source for the metrics.
  13. Deno tests cover: quiet hours across midnight, a time-zone change, DST, dedupe, collapse, a link revoked at send, the kill switch, prefs off. SQL: log and deferred tables are server-only.
- **Nadav:** Database Webhooks on inserts into `runs`, `athlete_run_flags`, `coach_feedback` and `coach_feedback_replies`; deploying `coach_notify`.
- Files: `supabase/functions/coach_notify/*`, new `_shared/notify.ts` (every later sender reuses it), M2b, tap routing.

**C7.14 Notification settings screens, coach and athlete (new; split from C7.5 + G13)**: Sonnet (medium) | Mig: none (uses M2a) | M | Deps: C7.10 (pushes only take effect once C7.5 ships)
- AC:
  1. **Given** a v2 coach **When** they open Coach tab → ⋯ → "Notifications" (T5) **Then** they see the §A.6 copy: three toggles, quiet hours "From"/"To", and the footer.
  2. **Given** a linked v2 athlete **When** they open My coach → "Notifications" **Then** they see toggles "Notes from {Coach}", "Plan updates", "Messages from {Coach}", plus quiet hours and the same footer [ASSUMPTION copy; Sally light review].
  3. **When** a toggle or time changes **Then** `notification_prefs` updates (own row). While saving, the toggles are disabled with an inline spinner. On failure the toggle reverts and "Couldn't save. Try again" shows.
  4. **Given** OS permission is denied **Then** one line and "Open Settings" show at the top, and the toggles stay editable. **Given** the user was never prompted **Then** "Turn on notifications" runs the T6/P10 flow, not the raw system prompt.
  5. **Given** quiet "From" equals "To" **Then** "Quiet hours need different start and end times" shows and Save is blocked [ASSUMPTION].
  6. **Given** VoiceOver or XXL type **Then** each toggle has a full label and the layout doesn't truncate.
  7. **Given** a solo athlete **Then** there's no athlete coach-notifications screen.
- Files: new `CoachNotificationSettingsView.swift`, new `AthleteCoachNotificationSettingsView.swift`, `MyCoachView.swift`. UX AC: spec §A.5 (T5), §A.6, G13.

**C7.6 Evening summary with counts**: **Opus (high)** | Mig: none (uses M2a/M2b, M3) | M | Deps: C7.5, C7.2
- AC:
  1. **Given** a coach whose local time reaches 20:00 **Then** one push: "Today: {n} missed · {k} flags open · {m} changed their plan".
     - n = athletes with a non-rest planned workout today that isn't ≥80% done by 20:00 athlete-local.
     - k = open flags.
     - m = distinct athletes with a `coach_athlete_events` row today: `goal_change` in Phase 1, plus `athlete_skip`/`athlete_move` after M6b.
     Names appear only in the app.
  2. **Given** n = k = m = 0 **Then** no push.
  3. **Given** 20:00 falls in the coach's quiet hours **Then** the push is deferred, and prefixed "Yesterday:" when it's delivered after the coach's local midnight.
  4. **Given** the toggle is off **Then** nothing is sent. **Given** the cron runs twice, or the time zone changes **Then** there's still at most one per coach per local day (log).
  5. **Given** a tap **Then** T2 opens filtered to "Missed today" with "Show all". If it's empty by then, the §A.5 copy shows.
  6. **Given** the shared SQL `workout_adherence_state(...)` **Then** it matches the Swift `WorkoutAdherence` on shared fixtures (partial 80%, rest, extra, time zone).
  7. **Given** athletes whose link is revoked or not v2, or the kill switch is on **Then** they're excluded from the counts.
- **Nadav:** create the hourly cron. Files: `supabase/functions/coach_evening_summary/*`, the SQL function, routing.

### Phase 2: "Coach builds the plan" (Next)

**C8.1a Coach-authored workout columns, coach write RPCs and the workouts lock trigger**: **Opus (high)** | Codex high (opt) is the preferred reviewer | Mig: **M6a** (C) | L | Deps: Phase 1 merged; Batch A applied
- Story: As a coach, the workouts I set are stored as mine, and the database protects them from every other writer.
- Claude checks first:
  - every `workouts`/`plans` writer in both repos (the §2.1 row), including any added since `4a016b4`;
  - whether `workouts` effectively allows one row per `(plan_id, scheduled_date)` (spec B.6 assumes one workout per day);
  - the body of `complete_run_workout`.
- AC:
  1. **Given** M6a **Then** the `workouts` columns in §3.2 exist with constant defaults, and existing rows read `source='ai', locked=false`. The migration reports row counts. There are no per-row updates.
  2. **Given** an active v2 link and a future, not-completed workout **When** `coach_create_workout` / `coach_update_workout(p_id, p_revision, …)` / `coach_move_workout` / `coach_delete_workout` runs **Then** the row gets `source='coach'`, `locked=true` and `coach_id`, `coach_revision` goes up by one, and `athlete_plan_update_queue` is upserted. Errors:
     - stale revision → `edit_conflict`;
     - a past or completed row → `workout_not_editable`;
     - a non-coach, a revoked link, `link_is_v2` false or the kill switch on → an error, and each case is added to `kill_switch.sql`.
  3. **Given** `coach_delete_workout` **Then** the day becomes a locked `type='rest'` coach row ("Rest (from {Coach})", spec B.6), not an empty day, so the AI can't refill it [ASSUMPTION].
  4. **Given** `workout_structure` in a coach RPC **Then** it must be a JSON object ≤16 KB with a recognized top-level shape, or it is rejected with `invalid_structure`. Detailed step validation is on the client (C8.3) [ASSUMPTION].
  5. Trigger `workouts_protect_coach_rows`, SQL tests:
     - a direct PostgREST PATCH as the athlete can't unlock or change a locked row (planned fields are kept, no raise);
     - completion fields still change;
     - DELETE raises `workout_locked`;
     - a non-coach INSERT with `locked=true` is forced to `false`/`ai`;
     - a web-style upsert on `(plan_id, local_id)` keeps the coach fields;
     - `complete_run_workout` completes a locked workout;
     - the kill switch on → the trigger still protects.
  6. **Given** solo users and unlocked rows **Then** `amendWorkout`, `pushWorkoutTomorrow`, `removeWorkout` and the flex-week apply behave exactly as before (regression tests).
  7. **Given** this PR **Then** `docs/coach-v2-writers.md` lists every writer and how it behaves under the trigger. The rollback file drops the trigger and RPCs and keeps the columns. The web mirror PR and the ledger are updated.
- Review: Codex high when it has credits, otherwise a Cursor agent with the RLS checklist, **plus a Grok Bot read-only audit before Nadav applies Batch C**.

**C8.1b Plan trigger, athlete RPCs and lock release on link end**: **Opus (high)** | Mig: **M6b** (C) | L | Deps: C8.1a
- AC:
  1. Trigger `plans_protect_coach_plans`:
     - **Given** `coach_published = true` **When** a non-coach deactivates or deletes the plan **Then** `plan_locked_by_coach`.
     - **Given** a plan that isn't coach-published but has locked future workouts **Then** `coach_workouts_present`, unless `runsmart.goal_change` is on.
  2. `athlete_replace_training_plan(expected_athlete, new_plan, new_workouts, p_ack_replaced_count)`:
     - **Given** the caller owns the plan **When** the locked future count equals `p_ack_replaced_count` **Then** in one transaction it deactivates the old plan, inserts the new one, and logs `goal_change`.
     - **When** the count differs **Then** `count_changed`, and nothing changes.
     - **Given** another user calls it **Then** an error.
  3. `athlete_change_coach_workout(p_id, p_action, p_new_date, p_request_id)` (D1):
     - **Given** the owner, a locked future not-completed row and `link_is_v2` **Then** only `scheduled_date`, `original_date` (on the first move), `athlete_change` and `athlete_changed_at` change. The row **stays locked**, and an `athlete_skip`/`athlete_move` event is logged. A repeated `p_request_id` is a no-op.
     - **Given** a past or completed row, a date in the past, or a date that already has a coach workout **Then** an error (`workout_not_editable` / `date_taken`) [ASSUMPTION].
  4. A new `create or replace` of `end_coach_link` also clears `locked`/`coach_published` on the athlete's future rows. The workouts stay and are unlocked (G17). C7.11's parity test is still green, and a new test shows a solo plan regenerates after leaving.
  5. A new `create or replace` of `replace_group_training_plan` (a new file; `20261117163000` is never edited) returns a clear error when it's blocked.
  6. **Given** a 1.2.6-style direct `plans.update(is_active=false)` on an unlocked plan **Then** it still works. On a plan with locked rows it fails, and that is only possible after a v2 coach write, which D4 limits to v2 pairs.
  7. Rollback file, web mirror PR, ledger.

**C8.5 AI and athlete side respect coach locks**: **Opus (high)** | Codex high (opt) | Mig: none | L | Deps: C8.1b
- AC:
  1. **Given** a linked athlete **Then** `CoachContext.lockedWorkoutIDs` holds the `locked = true` ids. **Given** a solo athlete **Then** the encoded bytes are unchanged (existing test).
  2. **Given** a flex-week proposal touching a locked id **Then** `validateFlexWeekResponse` drops that change (Deno test), and the client also filters it before applying through `TrainingPlanRepository`.
  3. **Given** the athlete asks RunSmart to change a locked workout **Then** the reply is "That's {Coach}'s workout.", plus "Read {Coach}'s note" only when a note exists.
  4. **Given** a coach rest/deleted day **Then** neither the AI nor flex-week adds a workout on it (test).
  5. **Given** a locked row **Then** amend, push to tomorrow, remove and swap are hidden. Skip/move appear only through C8.15 (until it merges, they're hidden too).
  6. **Given** any path returns `workout_locked` **Then** the athlete sees "{Coach} set this workout, so it can't be changed here." [ASSUMPTION copy; Sally light review], never a raw error.
  7. **Given** a coach-published plan **When** the athlete changes goal or taps Build my plan, or the server returns `plan_locked_by_coach` **Then** the P5 block shows "Ask {Coach} to change your plan", with "Reply to {Coach}'s latest note" only when a note exists.
  8. **Given** an open pain flag **When** the athlete asks the chat about the next workout **Then** it gives the G21 line.
  9. **Given** a 1.2.6 build against the Batch C schema (manual check) **Then** what the user sees on move, delete and regenerate of a locked row is written into `docs/coach-v2-writers.md`.
- Files: `Services/Coach/CoachAssistant.swift`, `supabase/functions/coach_message/*` (incl. `flex_week.ts`), `TrainingPlanRepository.swift`, the plan/workout views. UX AC: spec §C.5 P3–P5, §C.10.

**C8.15 Athlete skips or moves a coach-set workout (D1)**: Sonnet (medium) | Mig: none (uses M6b) | M | Deps: C8.5
- AC:
  1. **Given** a locked future workout on a v2 link **Then** the athlete sees "Skip this one" and "Move to another day". **Given** the link isn't v2 **Then** both are hidden.
  2. **When** either is tapped **Then** the confirm reads "{Coach} set this workout. Change it anyway? {Coach} will see the change."
  3. **On confirm** **Then** `athlete_change_coach_workout` runs through the outbox with the 5 s undo toast. The athlete sees "Changed by you", the coach sees "Changed by {Athlete}", and a move also shows "moved from {day}".
  4. **Given** the change **Then** the workout stays locked against the AI: flex-week and chat still answer "That's {Coach}'s workout".
  5. **Given** the athlete **Then** distance, steps and pace can't be edited.
  6. **Given** the coach **Then** an in-app "new" marker (C7.2) and the `m` count in the 20:00 push (C7.6), with no instant push.
  7. **Given** a move to a date in the past, or to a date that already has a coach workout **Then** the picker doesn't offer it. **Given** the server returns `date_taken` **Then** "That day already has a workout from {Coach}." [ASSUMPTION copy]
- Tests: Swift for the confirm, tags and outbox. UX AC: spec §C.5, G2.

**C7.9 Goal change on a plan with coach workouts (counted warning, D2)**: **Sonnet (high)** | Mig: none (uses M6b) | M | Deps: C8.1b, C8.5
- AC:
  1. **Given** a linked v2 athlete on an AI plan with k > 0 locked future workouts **When** they change goal, race, date or runs per week, or tap Build my plan **Then** the P5 warning shows: "{Coach} set your plan. Changing your goal replaces {k} workouts {Coach} set, and {Coach} will see the change." with Change anyway / Cancel.
  2. **On Change anyway** **Then** `athlete_replace_training_plan(…, k)` runs. On success the new plan shows, and the coach sees "Changed goal" from the RPC's event. The client doesn't also call `athlete_log_goal_change`, so there's no double event (test).
  3. **Given** `count_changed` (the coach edited meanwhile) **Then** k is re-fetched and the warning shows again with the new number.
  4. **Given** k = 0 on an Individual plan **Then** there's no warning; the save still goes through the RPC and logs the event. **Given** a Group Plan athlete **Then** the group wording from §C.5 applies. A runs-per-week-only change keeps them on the group plan and shows no warning (PRD FR-2e).
  5. **Given** a coach-published plan **Then** the C8.5 block shows, not this warning.
  6. **Given** offline **Then** "Changing your plan needs a connection." shows and nothing changes [ASSUMPTION].
  7. **Given** every caller listed in C7.2's PR **Then** each one goes through this path for linked athletes.
- Files: `Features/Goals/GoalWizardView.swift`, the plan CTA, `TrainingPlanRepository.persistGeneratedPlan`. UX AC: spec §C.5 P5, §C.10 C7.9.

**C8.13 Coach self sign-up + profile**: **Opus (high)** | Mig: **M10** (C) | M | Deps: C7.0
- AC:
  1. **Given** a v2 user in Settings **When** they tap "I'm a coach" **Then** one explainer screen shows: "Coach with RunSmart: invite athletes, see their runs, build their plans." (**no "Free for now."**). Next comes a form with the display name prefilled from `profiles.name` and a bio ≤300 with a counter.
  2. **When** they submit **Then** `become_coach` creates their `coach_profiles` row, and the Coach tab appears without SQL. A repeated call updates the row instead of duplicating it. It can't create a row for another user (SQL).
  3. **Given** the profile **Then** it's editable, and athletes see the name and bio on the consent screen and in My coach. The avatar is a monogram unless `avatar_path` upload ships in this PR.
  4. **Given** a coached athlete **Then** they can also become a coach (dual role, G18).
  5. **Given** the pilot SQL path **Then** it still works, and `tasks/coach-pilot-testing.md` is updated.
  6. **Out of scope:** stop coaching or delete the coach profile (G16 covers only removing an athlete).

**C8.16 Bundled athlete plan-update push (new; split from C8.4, D3)**: **Opus (high)** | Mig: none (queue in M6a) | M | Deps: C8.1a, C7.5
- AC:
  1. **Given** coach changes to one athlete (create, update, move, delete, assign) **When** `last_change_at < now() − 10 min` and the batch isn't sent **Then** one push "{Coach} updated your plan · {n} changes" goes out, respecting the athlete's "Plan updates" pref and quiet hours, and the row is marked sent. Changes after that start a new batch.
  2. **Given** the publish RPC (C8.7) removed the pending row **Then** nothing is sent for those changes (D6: one push per publish).
  3. **Given** the link ended **Then** nothing is sent and the row is dropped. **Given** the kill switch is on **Then** nothing is sent and the row is kept.
  4. **Given** two overlapping cron runs **Then** the push is sent once, via compare-and-set on `sent_at` (test).
  5. Deno tests cover the window, prefs, quiet hours, publish suppression and the kill switch.
- **Nadav:** create the 2-minute cron and deploy `athlete_plan_update_digest`.

**C8.2 Coach creates a simple workout**: Sonnet (medium) | **UX gate: Sally (spec §B ready)** | Mig: none | M | Deps: C8.1a, C8.5, C8.16
- UX AC: spec **§B.4, §B.8–§B.11** (fields, defaults, exact validation strings).
- AC:
  1. **Given** the athlete detail → an empty future day → "Add workout" **Then** B2 opens with the §B.4 fields and defaults. Occupied days offer "Edit" (C8.4) instead [ASSUMPTION].
  2. **Given** invalid input **Then** the exact §B.4 message shows and Save stays disabled. Rest hides the target and pace fields.
  3. **On Save** **Then** `coach_create_workout` runs through the outbox. The chip shows "Waiting to sync" until it flushes. Offline, the toast reads "Saved on this phone. It'll reach {Athlete} when you're online."
  4. **Given** the save commits **Then** the athlete sees the workout labelled "From {Coach}" after a refresh. `notes` also gets the text summary, so 1.2.6 and text-parsing paths can read it.
  5. **Given** today's workout **Then** "{Athlete} may already be out running. Changes show on their next refresh." shows.
  6. **Given** the link ended on sync **Then** the banner "{Athlete} is no longer linked. This change wasn't saved." shows with "Discard".
  7. **Given** an athlete who isn't v2 **Then** "Add workout" is disabled with "{Athlete} needs the latest RunSmart".
- Files: new `CoachWorkoutEditorView.swift`, `CoachWorkoutService.swift`, the athlete Plan/Today rows.

**C8.4 Coach edits, moves and deletes upcoming workouts (UI)**: **Sonnet (medium)** | Mig: none | **M** (was L) | Deps: C8.2
- UX AC: spec **§B.6**, Part 2 › C8.4.
- AC:
  1. **Given** any future, not-completed workout (AI or coach) **When** the coach saves an edit **Then** it becomes `source=coach, locked=true`. An edited RunSmart workout shows the inline line "Saving makes this your workout. RunSmart won't change it.", and the athlete sees the permanent "Edited by {Coach}" tag.
  2. **When** the coach moves a workout with the B5 date picker onto an occupied day **Then** B6 offers "Swap days" / "Replace it" / Cancel. Past or completed occupants aren't offered.
  3. **When** the coach deletes (B7 confirm) **Then** the athlete sees "Rest (from {Coach})". For a group-plan athlete the confirm adds "Only {Athlete}'s plan changes."
  4. **Given** move, delete or swap **Then** the "… · Undo" toast holds the RPC for 5 s. An undo within 5 s sends nothing and enqueues nothing.
  5. **Given** `edit_conflict` **Then** B11 offers "This workout changed on another phone." with "Load latest" / "Keep mine".
  6. **Given** the athlete completed the workout meanwhile **Then** "{Athlete} already ran this workout, so it can't be changed." shows.
  7. **Given** a change **Then** the athlete sees a 48 h "Updated" pill next to the permanent tag, and gets one bundled push (C8.16).

**C8.3 Structured intervals (steps and repeats)**: **Opus (high)** | **UX gate: Sally** | Mig: none (uses `workouts.workout_structure`) | L | Deps: C8.2
- Claude checks first:
  - the `workout_structure` shape the AI generator writes, and what the web repo writes. Extend that shape; don't invent a new one.
  - whether `StructuredWorkoutFactory` handles nested repeats and treadmill (time-only) runs.
- UX AC: spec **§B.5**, Part 2 › C8.3.
- AC:
  1. **Given** type Intervals **Then** B3 opens with the starter structure, and the coach can add Warm-up, Run, Recover (Jog/Walk/Stand), Cool-down and Repeat (2–30, not nested), with the §B.5 validation strings.
  2. **Given** steps **Then** the preview shows "About {x} km · {y} min", following the §B.5 estimate rule when a pace is missing, and an "{Athlete} sees:" line (INV-6).
  3. **On Save** **Then** both `workout_structure` and the text summary are written. Effort-word targets are allowed (G9). The add menu has a "Run–walk (8 × 1 min run, 1 min walk)" starter.
  4. **Given** the athlete on v2 **Then** the steps show in the workout detail, and the live-run guide follows them. A test shows a coach 6×800 m produces the same guide stages as the equivalent text plan. **Given** an unknown legacy structure **Then** the text summary shows read-only with "Rebuild as steps".
  5. **Given** VoiceOver **Then** steps read as sentences, with "Move up" / "Move down" custom actions.
  6. `Codable` round-trip tests, plus a server rejection test for malformed JSON (from M6a).

**C8.6 AI drafts a plan for one athlete**: **Opus (high)** | **UX gate: Sally (spec §C.4 D1–D3 ready)** | Mig: **M7** (D) | M | Deps: C8.1b, C8.3
- UX AC: spec §C.1, §C.4 D1–D2, §C.6, §C.10 C8.6. Per-athlete only (D5).
- AC:
  1. **Given** a v2 coach on a v2 athlete **When** they tap "Draft a plan with AI" **Then** D1 opens prefilled (goal, race date, runs per week, level, start). Inline errors cover the 16-week cap and the per-distance minimums from `GroupPlanRules`.
  2. **When** they tap Draft plan **Then** `coach_plan_draft` writes one `draft` version with `origin='ai'` and nothing else (**INV-2**: the athlete's `plans`/`workouts` counts and `updated_at` are unchanged in the test). The output is validated against the `workout_structure` shape.
  3. **Given** the AI fails or times out **Then** "Couldn't draft. Try again." shows, with no partial rows. On the third failure in a row, the "build it yourself" line is added.
  4. **Given** the cap (N per coach per day, configurable) **Then** D1 shows "{k} of {N} AI drafts left today". At 0, the §C.6 cap copy shows. **Given** `coach_v2_ai = false` **Then** the paused copy (§3.7) shows.
  5. **Given** an open draft for that athlete **Then** "Open it / Start over" shows. There is one open draft per athlete.
  6. **Given** the coach leaves the screen **Then** drafting continues, and an in-app "{Athlete}'s draft is ready · Review" banner appears. No push.
  7. **Given** offline **Then** "Drafting needs a connection." shows and the button is disabled.
  8. **INV-1/INV-4 tests:** the athlete can't read the draft through any RPC. The athlete's `coach_message` AI context doesn't include it. No queue row, push or Today card exists for it.
  9. **Given** the link ends **Then** M7's new `create or replace` of `end_coach_link` deletes that athlete's drafts **at link end** (PRD FR-5). C7.11's parity test is extended to the drafts tables.

**C8.7 Coach reviews, edits, publishes; the athlete sees only the published plan**: **Opus (high)** | **UX gate: Sally (spec §C.4 D3–D5 ready)** | Mig: uses M7 | L | Deps: C8.6, C8.4
- UX AC: spec §C.4, §C.6, §C.7, §C.10 C8.7.
- AC:
  1. **Given** a draft **Then** D3 shows the persistent "Draft · {Athlete} can't see this" strip, week cards and day rows using the C8.2/C8.3 editor. Edited items show "Your change". Offline, it's read-only with "Editing a draft needs a connection."
  2. **When** the coach taps "Review and publish" **Then** D4 shows every §C.4 line, including "Including {j} you set before", "{m} workouts {Athlete} changed will be replaced", and the next-7-days diff.
  3. **When** they tap "Publish to {Athlete}" **Then** `coach_publish_plan_version` runs in **one transaction** (**INV-3**, kill-mid-publish test). It:
     - creates or updates the coach-published plan;
     - writes workouts from the start date with `locked=true` and `published_version_id`;
     - never touches completed or past rows;
     - archives the previous version;
     - deletes the athlete's pending `athlete_plan_update_queue` row;
     - sends **exactly one** `athletePlanPublished` push.
  4. **Given** a stale revision / a link that has ended / offline **Then** the §C.4 copy shows, and nothing changes for the athlete.
  5. **Given** the athlete's plan changed since drafting **Then** the stale-plan banner shows.
  6. **Given** "Edit plan" **Then** a draft is cloned from the live version, so earlier single edits survive a re-publish (G10). "Redraft with AI" and "Discard draft" use the §C.4 confirms.
  7. **Given** D5 **Then** a read-only versions list shows. There's no revert in v2.
  8. **Given** the athlete **Before** publish **Then** they see nothing new (INV-1, INV-4, INV-5 tests). **After** publish, every published workout is locked.

**C8.8 Athlete side of published plans + change-list card**: Sonnet (medium) | Mig: none | M | Deps: C8.7, C8.16
- UX AC: spec §C.2, §C.5 P1–P4, §C.6 P2/P3.
- AC:
  1. **Given** a coach-published plan **Then** Plan shows "{Coach}'s plan: {title}" with "Race {d Mon} · Week {n} of {w}". A group athlete with an individual publish sees "{Coach}'s plan for you: {goal}".
  2. **Given** a publish or a bundled-edit push **Then** Today shows "{Coach} updated your plan · {n} changes this week" (the MVP string, G7). It opens the change list with "Got it". Several publishes before the athlete opens the app give **one** card, compared with what they last saw.
  3. **Given** workout detail **Then** it shows the permanent tags "From {Coach}" / "Edited by {Coach}" / "Changed by you", the lock with "Set by {Coach}", the note verbatim with "— {Coach}", and the steps.
  4. **Given** the athlete's client **Then** plan data is read only from `plans`/`workouts` (**INV-5**, code search in the PR).
  5. **Given** a flag-off or 1.2.6 build **Then** published workouts appear as ordinary workouts with the text summary (documented).

**C8.9 Coach 4-week calendar**: Sonnet (medium) | UX spec §B.3 | Mig: none | M | Deps: C8.4
- AC:
  1. **Given** an athlete **Then** B1 shows this week plus the next 3 (fixed). Chips show the source and lock glyphs and completion. Past days are dimmed and read-only, and weeks after the plan end say "Plan ends {date}". The week start follows the region rule.
  2. **Given** XL type or the "List" toggle **Then** the B1a agenda shows.
  3. **When** the coach long-press-drags a future chip **Then** `coach_move_workout` runs. Occupied → B6. A drop on a past day snaps back with "Can't move to a past day". "Move to…" is a non-drag path (menu and VoiceOver action).
  4. **Given** athlete skips or moves **Then** "Changed by {Athlete}" and "moved from {day}" show. Pending sync shows the clock glyph.

**C8.10 Workout templates library**: **Sonnet (high)** + required Opus/Codex-high RLS review | Mig: **M8** (E) | M | Deps: C8.3
- AC:
  1. **When** the coach taps "Save as template" in the editor **Then** a template is stored (owner-only).
  2. **Given** B8 **Then** search, edit and delete work, with the empty state "No templates yet" and the no-results copy.
  3. **When** a template is edited **Then** the footer says changes apply only from now on, and already-assigned workouts don't change (test).
  4. **Given** offline **Then** templates are read-only with "Templates can be edited when you're online".
  5. SQL: owner-only read and write; another coach gets zero rows; account deletion purges.

**C8.11 Assign to several athletes or a group**: **Opus (high)** | Mig: uses M8 | M | Deps: C8.10 (group chips need C8.14)
- AC:
  1. **Given** B9 **Then** the steps are workout → date → athletes. Each athlete shows eligibility **before** submit: no plan / already has your workout that day / already ran that day / needs the latest RunSmart / "Replaces: {workout}" / "Replaces: Rest".
  2. **Given** more than 1 athlete and a pace target **Then** the one-pace warning shows (G9).
  3. **When** the coach taps "Add for {n}" **Then** one `coach_assign_workout` call is all-or-nothing for the eligible set. Ineligible athletes are reported, not failed. B10 shows "Added for {n}. Skipped {k}." with reasons.
  4. **Given** the result **Then** every added workout is locked, and each athlete gets one bundled push (C8.16).
  5. **Given** offline **Then** "Adding to several athletes needs a connection." shows.
  6. SQL: only the coach's own active v2 athletes; partial-eligibility reporting; the kill switch.

**C8.14 Unlock Plan Mode + multiple groups**: **Opus (high)** | Mig: **M11** (E) | L | Deps: C8.11 (optional)
- AC:
  1. **Given** M11 **Then** each coach gets one default group from their current plan mode and group settings, and their existing invite code maps to it (backfill test: current pilot coaches work unchanged).
  2. **Given** a coach **Then** they can create groups (name, mode, settings), each with its own invite code. Consent shows "Join {Coach}'s {Group} group".
  3. **Given** the roster **Then** it filters by group, with an empty state.
  4. **When** a group's mode or settings change **Then** the confirm says "This applies to athletes who join from now on. Current athletes keep their plans.", and only new joiners are affected. Mid-plan joiners get the group's RunSmart plan from the current week (D5).
  5. **When** an athlete moves between groups **Then** their plan doesn't change [ASSUMPTION]. **When** a coach deletes a group that still has athletes **Then** it's blocked with "Move or remove its athletes first" [ASSUMPTION].
  6. **Given** C8.14 **Then** the "Set for the pilot" lock is removed at the RPC level.

**C8.12 Broadcast message to a group**: **Opus (high)** | Mig: **M9** (E) | S–M | Deps: C8.14, C7.8 (D9 line), C7.5
- AC:
  1. **Given** a coach **When** they write ≤2000 characters to all athletes or one group **Then** "Send to {n} athletes?" confirms it. Only active v2 recipients are counted; the result adds "{x} need the latest RunSmart".
  2. **Given** an athlete **Then** the message shows on Today and in "Messages from {Coach}" (My coach), read-only with no Reply. The push follows **D11**: the first 80 characters, `truncateGraphemes` + `isolate`; with "New message from {Coach}" only as the fallback for an empty body. It respects the "Messages from {Coach}" pref and quiet hours.
  3. **Given** reads **Then** the coach sees "Read by {n} of {m}". Reads are recorded only for athletes with `consent_version ≥ 2` (D9 consent) (SQL).
  4. **Given** the coach deletes within 15 minutes **Then** the message disappears for athletes. After 15 minutes, delete is not offered.
  5. **Given** the link has ended **Then** the athlete no longer sees new broadcasts, and the coach no longer counts them (SQL).

### Phase 3: "AI assistant for the coach + trends" (Next+)

**C9.1 8–12 week history**: **Sonnet (high)** + required RLS review | Mig: **M14** (F, read RPC) | M | Deps: C7.3
- AC:
  1. **Given** athlete detail → "Trends" **Then** weekly distance, runs, adherence % and average RPE show for 8 or 12 weeks (segmented), from `coach_get_athlete_history(p_athlete, p_weeks ≤ 12)`.
  2. **Given** fewer than 2 weeks of data **Then** "Trends appear after 2 weeks of runs." shows. A week with no RPE shows "No effort logged", not 0.
  3. **Given** VoiceOver **Then** each chart has an audio-graph summary. Claude checks first: which chart kit exists; otherwise use SwiftUI Charts.
  4. SQL: gated by `is_active_coach_of` + ack + `link_is_v2`; a revoked link returns nothing; added to the parity and kill-switch tests.

**C9.2 Training load for coaches**: **Opus (high)** | Mig: **M15** (F, read RPC) | M | Deps: C9.1
- AC:
  1. **Given** the same fixtures **Then** acute and chronic load from SQL match `TrainingLoadCalculator` (parity test).
  2. **Given** acute:chronic ≥ 1.5 and a chronic load above the floor **Then** the coach-only Today chip "Load jump" shows. Tapping it explains "This week's load is {x}× the 4-week average." with no medical words. The threshold is Q4's default [ASSUMPTION], with the floor tuned at TF-5.
  3. **Given** the athlete **Then** this is never shown to them.

**C9.3 AI weekly coach summary**: **Opus (high)** | Mig: **M12** (F) | L | Deps: C7.3, C7.4, C9.1
- AC:
  1. **Given** the end of the coach's training week (Saturday evening for IL, G14), or "Refresh" (once a day) **Then** "Your week" shows 1–2 lines per athlete (adherence, RPE trend, flags, replies, athlete changes) plus a "needs you" list, labelled "Summary by RunSmart". It's cached in `coach_weekly_summaries`.
  2. **Given** the prompt **Then** it receives aggregates only. A snapshot test of the request shows no notes, no flag text and no names beyond first names [ASSUMPTION], and no number the aggregates don't contain.
  3. **Given** the push **Then** it reads "Your week with {n} athletes is ready", with no health details.
  4. **Given** a failure **Then** "Couldn't make this week's summary. Try again" shows. **Given** `coach_v2_ai = false` **Then** the paused copy shows.

**C9.4 AI-drafted notes from the summary, with the athlete label (D12)**: **Sonnet (high)** + required Opus/Codex-high RLS review (it changes a security-definer write RPC and the athlete read RPC) | Mig: **M16** (F) | M | Deps: C9.3
- M16 `coach_feedback_ai_assisted` (new file; never edit `20261118100000_coach_feedback.sql` or `20261118120000_athlete_feedback_read.sql`):
  - `alter table coach_feedback add column ai_assisted boolean not null default false`.
  - `create or replace` the coach send RPC so it accepts `p_ai_assisted boolean default false`. **Claude checks first** that the existing call signature used by 1.2.6 clients still resolves (no ambiguous overload); old clients keep sending notes with `ai_assisted = false`.
  - `create or replace` `my_coach_feedback` (and the coach's own feedback read) to return `ai_assisted`.
  - The flag is set only at insert. The edit RPC can't clear or set it.
- AC:
  1. **Given** a summary line **When** the coach taps "Draft note" **Then** `CoachFeedbackComposer` opens prefilled and editable. **It is never sent automatically**, and there's no send-from-list shortcut.
  2. **Given** the composer opened from "Draft note" **Then** the coach sees "Drafted with RunSmart" and, above Send, the preview line "Your athlete will see: Written with help from RunSmart AI". There is no toggle to hide the label.
  3. **When** the coach sends **Then** the `ai_note_draft_sent(edited)` event fires.
  4. **Given** a note sent from a composer opened via "Draft note" **When** it's saved **Then** `ai_assisted = true`, **whether or not the coach edited the text**. **Given** any other note (typed from scratch, welcome note, one-tap praise from C7.16, broadcast) **Then** `ai_assisted = false`.
  5. **Given** an athlete opens a note with `ai_assisted = true` **Then** a small secondary line under the note reads EN "Written with help from RunSmart AI" / HE "נכתב בעזרת RunSmart AI" (copy via the localization file, RTL-safe per §3.9). The note still shows the coach as the author, and the label is the same on Today and in "Messages from {Coach}" (My coach). **Given** `ai_assisted = false` **Then** no label and no empty space.
  6. **Given** the coach later edits an AI-assisted note **Then** the label stays (SQL test: the edit RPC leaves `ai_assisted` unchanged).
  7. **Given** the push for an AI-assisted note **Then** it is the normal "{Coach} left you a note"; the label shows in-app only.
  8. **Given** `coach_v2_ai = false` (kill switch) **Then** "Draft note" is hidden, and notes already sent keep their label.
  9. **Given** an athlete on a pre-v2 build (no `ai_assisted` field) **Then** the note still renders as before (decoding treats a missing field as false). [ASSUMPTION: pilot athletes are on TestFlight v2, so they see the label.]

### Later (not in v2 scope; keep the design open)
- **L1 iPad layout**: Sonnet, M. Split view with the roster and the detail, and a wider calendar.
- **L2 Push workouts to the watch**: blocked until the Garmin Training API is approved (the Starter route is upload-only). Apple WorkoutKit is a possible alternative for Apple Watch. L, Opus.
- **L3 Payments ($9 per athlete through a coach, $15 solo; commercial plan v1)**: L, Opus. Needs the pricing decisions and an Apple IAP / guideline review. The v2 data model keeps `coach_id` on coach-owned rows.
- **L4 Group wall / community**: L, needs a moderation design.
- First Phase-3 candidate (not counted): **rep times on structured runs** (G11). `runs` has no splits today.

**Story count (v1.3):** Phase 0 = 1 (C0.2; C0.1 is docs PR 0), Phase 1 = **16**, Phase 2 = **18**, Phase 3 = 4, Later = 4. **Total 43.**

**Sally (UX) gates:** C7.1 (§A), C8.2 + C8.3 (§B), C8.6 + C8.7 (§C). Light copy reviews: C7.8, C7.11, C7.14 (athlete toggles), C7.12 (paused line), C8.5 (lock error line), C8.15 (date-taken line). Everything else builds on the existing design system (`ContentCard`, `NeonButtonStyle`, sentence case, no all-caps).

---

## 5. PR sequence (v1.3)

Each numbered line is one draft PR. "∥" means it can run in parallel with the previous PR. "→" means it must wait for the previous PR. The author is Claude Code at the story's tier (§1.1), and the reviewer is a different agent. Every dependency in §4 points to an earlier line; the check is in the table at the end.

**Phase 0**
0. C0.1 refined plan (docs). **Nadav approves before PR 1.** ∥ 0b. C0.2 migration ledger + drift report (docs).

**Phase 1**
1. C7.0 gate + capabilities (M0)
2. C7.12 kill switch + rollback runbook (M0b)
3. C7.10 push foundation (M2a). **Nadav's APNs setup starts on day 1, in parallel.** ∥ 4. C7.8 consent v2 (M5a) ∥ 5. C7.15 mixed-direction text ∥ 6. C7.13 analytics
7. C7.1 Coach Today ∥ 8. C7.3 RPE + notes (M1a; needs 4, 5)
9. C7.2 markers + events (M3; needs 7) ∥ 10. C7.7 replies (M4; needs 4, 5)
11. C7.4 pain flag (M1b; needs 7, 8) ∥ 12. C7.11 remove athlete (M5b; needs 4, 9)
13. C7.16 milestones + praise (M13 if needed; needs 7, 9)
- **Batch A (Nadav applies, in this timestamp order):** M0, M0b, M5a, M1a, M3, M4, M1b, M5b, (M13). Apply after PRs 1, 2, 4, 8, 9, 10, 11, 12 (13) are approved. **Before applying: the Grok Bot read-only audit, and a 1.2.6 regression on local Supabase** (§6).
14. C7.5 push sender (M2b; needs 3, 10, 11) → 15. C7.14 settings screens (needs 3) ∥ 16. C7.6 evening summary (needs 14, 9)
- **Batch B:** M2a, M2b. Together with it, Nadav does the webhooks (inserts on `runs`, `athlete_run_flags`, `coach_feedback`, `coach_feedback_replies`), the hourly cron, the `coach_notify` / `coach_evening_summary` deploys and the APNs secrets.
- **TF-1** (two phones, TestFlight, `coachV2Enabled` on) after PR 16, plus the **kill-switch drill** (§6). The App Store build stays on 1.2.6 behavior.

**Phase 2**
17. C8.1a columns + coach RPCs + workouts trigger (M6a) → 18. C8.1b plan trigger + athlete RPCs + lock release (M6b)
19. C8.13 self sign-up (M10; needs only C7.0, so it can run in parallel with 17–18)
- **Batch C:** M6a + M6b together (+ M10). Apply after the Grok Bot audit and the 1.2.6 regression against this schema, at a quiet time (no athlete runs expected), with the rollback file ready. It changes behavior for live 1.2.6 clients, but only for coached athletes who have locked rows.
20. C8.5 lock respect (needs 18). **It must merge before any coach-write UI reaches testers.**
21. C8.15 athlete skip/move (needs 20) ∥ 22. C7.9 counted goal change (needs 18, 20) ∥ 23. C8.16 digest function (needs 17, 14)
24. C8.2 simple editor (needs 17, 20, 23) → 25. C8.4 edit/move/delete UI → 26. C8.3 intervals
- **Nadav:** deploy `athlete_plan_update_digest` + the 2-minute cron before TF-2.
- **TF-2:**
  - the coach builds and edits workouts, and the AI doesn't overwrite them;
  - the athlete skips or moves one, and the coach sees it;
  - one bundled push arrives about 10 minutes after the edits;
  - a goal change shows the count.
27. C8.6 AI draft (M7) → 28. C8.7 review/publish → 29. C8.8 athlete published view
- **Batch D:** M7, before PR 27 is tested on TestFlight. **TF-3:** draft → publish end to end, with the INV checks (§6).
30. C8.9 calendar ∥ 31. C8.10 templates (M8) → 32. C8.11 assign
33. C8.14 groups (M11) → 34. C8.12 broadcast (M9)
- **Batch E:** M8, M11, M9. **TF-4:** templates, assigning to 3 athletes (1 ineligible, reported), group invite codes, broadcast read counts.

**Phase 3**
35. C9.1 history (M14) → 36. C9.2 load (M15) ∥ 37. C9.3 weekly summary (M12) → 38. C9.4 AI-drafted notes + athlete label (M16)
- **Batch F:** M14, M15, M12, M16. **TF-5:** a real week with the pilot coach, checking the summary's accuracy against the athlete detail.

**Dependency check (each story's deps vs. its PR line)**
| PR | Story | Deps → their PR lines | OK |
|---|---|---|---|
| 1 | C7.0 | C0.1 → 0 | ✅ |
| 2 | C7.12 | C7.0 → 1 | ✅ |
| 3 | C7.10 | C7.0, C7.12 → 1, 2 | ✅ |
| 4 | C7.8 | C7.0 → 1 | ✅ |
| 5, 6 | C7.15, C7.13 | C7.0 → 1 | ✅ |
| 7 | C7.1 | C7.0, C7.13 → 1, 6 | ✅ |
| 8 | C7.3 | C7.8, C7.15 → 4, 5 | ✅ |
| 9 | C7.2 | C7.1 → 7 | ✅ |
| 10 | C7.7 | C7.8, C7.15 → 4, 5 | ✅ |
| 11 | C7.4 | C7.3, C7.1 → 8, 7 | ✅ |
| 12 | C7.11 | C7.8, C7.2 → 4, 9 | ✅ |
| 13 | C7.16 | C7.1, C7.2 → 7, 9 | ✅ |
| 14 | C7.5 | C7.10, C7.4, C7.7, C7.12 → 3, 11, 10, 2 | ✅ |
| 15 | C7.14 | C7.10 → 3 | ✅ |
| 16 | C7.6 | C7.5, C7.2 → 14, 9 | ✅ |
| 17 | C8.1a | Phase 1, Batch A | ✅ |
| 18 | C8.1b | C8.1a → 17 | ✅ |
| 19 | C8.13 | C7.0 → 1 | ✅ |
| 20 | C8.5 | C8.1b → 18 | ✅ |
| 21 | C8.15 | C8.5 → 20 | ✅ |
| 22 | C7.9 | C8.1b, C8.5 → 18, 20 | ✅ |
| 23 | C8.16 | C8.1a, C7.5 → 17, 14 | ✅ |
| 24 | C8.2 | C8.1a, C8.5, C8.16 → 17, 20, 23 | ✅ |
| 25 | C8.4 | C8.2 → 24 | ✅ |
| 26 | C8.3 | C8.2 → 24 | ✅ |
| 27 | C8.6 | C8.1b, C8.3 → 18, 26 | ✅ |
| 28 | C8.7 | C8.6, C8.4 → 27, 25 | ✅ |
| 29 | C8.8 | C8.7, C8.16 → 28, 23 | ✅ |
| 30 | C8.9 | C8.4 → 25 | ✅ |
| 31 | C8.10 | C8.3 → 26 | ✅ |
| 32 | C8.11 | C8.10 → 31 (group chips once 33 lands; until then the roster) | ✅ |
| 33 | C8.14 | C8.11 (optional) → 32 | ✅ |
| 34 | C8.12 | C8.14, C7.8, C7.5 → 33, 4, 14 | ✅ |
| 35–38 | C9.1–C9.4 | C7.3, C7.4, C9.x → 8, 11, 35–37 | ✅ |

**What v1.2 had wrong in §5:**
- PR 9b "same M5 file as PR 4": one PR edited another PR's migration.
- M5's `end_coach_link` referenced M6/M7/M2 objects.
- C7.6 needed M6 events in Phase 1.
- C7.7's push part had no prefs table until C7.5.
- C7.9's count had no locked rows to count.
- C8.12's "one group" ran in parallel with C8.14, which creates groups.
- "C7.1 (after Sally's mock)": the spec is already written.

**Review pairing:** tier 1 → Codex high or a Cursor agent with the RLS/security checklist, plus a Grok Bot audit before apply; tier 2 → Opus or Codex high with the RLS checklist; tier 3/4 → a different agent for UI/state bugs and tests. No author reviews their own PR.

---

## 6. Test plan

**Every PR:** `xcodebuild test` on the simulator (all `IOS RunSmart appTests`); `supabase start` + `supabase db reset` locally, then run `supabase/tests/*.sql`; `deno test` for touched functions. CI must be green. Use Release-config checks for the flag: no coach UI with the flag off, and existing tests like `CoachModeTests` must keep passing.

**Phase 1:**
- Simulator: dots/sorting fixtures, outbox offline/online, consent sheet once, goal-warning gate.
- Local Supabase: consent gating for every new RPC (coach / non-coach / revoked / athlete self), flag and reply idempotency, purge-on-delete, quiet-hour and dedupe logic (Deno).
- Regression on a **1.2.6-equivalent build** (the `main` before v2) against the Batch A/B schema: run upload, RPE edit, plan regeneration and group join all still work.
- **Two-phone TestFlight (TF-1):**
  1. Athlete runs → coach push within 2 min.
  2. Athlete adds RPE + note + pain → coach sees chip and note, then marks handled.
  3. Coach note → athlete push → athlete replies → coach push + "new" marker.
  4. Miss a workout → 20:00 summary.
  5. Quiet hours respected.
  6. Leave coach → the coach stops getting anything. Coach removes an athlete → the athlete sees one neutral line and no push (C7.11).
  7. App Store build: **base coach mode as in 1.2.6, no v2 UI** (v1.1 wrongly said "no coach UI").
  8. Mixed versions: a v2 coach and a 1.2.6 athlete → the coach sees "{Athlete} needs the latest RunSmart", no sharing, no coach writes (D4).
  9. Consent: before tapping OK on P9 nothing is shared. After OK, RPE from the last 14 days appears and old notes don't (D7).
  10. A pain flag at 23:00 → no push until quiet end, then one collapsed push (D6).

**Phase 2:**
- Local: **trigger bypass tests** (direct PATCH, web upsert, old-client regeneration), lock and revision SQL tests, publish atomicity (kill mid-publish → no partial state), athlete can't read drafts, `coach_message` / flex-week ignores locked rows.
- **TF-2/TF-3:**
  1. Coach creates an interval workout → athlete sees steps.
  2. Athlete asks the AI to change it → lock reply.
  3. Coach edits/moves/deletes it, and the athlete updates.
  4. AI draft → coach edits 3 workouts → publish → the athlete sees only the published plan, completed runs are untouched, and **exactly one** publish push arrives.
  5. Goal change: with an AI plan plus 2 coach workouts → a warning with "2", then the plan is replaced and the coach sees "changed their plan". With a coach-published plan → blocked, with the reply link (D2).
  6. "Edit plan" clones the live version, and re-publishing keeps the coach's earlier single edits.
- **TF-4:** template → assign to 3 athletes (1 ineligible, reported), group invite codes, broadcast read counts.

**Phase 3:**
- Swift↔SQL load parity tests.
- Summary prompt gets aggregates only (a snapshot of the request).
- **TF-5:** a real week with the pilot coach; check summary accuracy against the athlete detail.

**v1.3 additions to the test plan**
- **Flag matrix (every UI PR):** run the story's screens with `coachV2Enabled` off and on, and with `link_is_v2` false and true. Assert with the service mock that the flag-off and mixed-version paths make no v2 RPC calls.
- **1.2.6 regression before every batch:** check out `main` at the 1.2.6 (46) commit, point it at local Supabase with the batch applied, and check:
  - run upload, RPE edit (stays local), plan regeneration, group join, leave coach;
  - after Batch C: move, delete and regenerate of a locked row, documenting what the user sees (C8.5 AC 9).
- **Web tree:** apply the mirrored files on a second local Supabase from the web tree and run the web `plan-workout-sync` upsert against a locked row (C8.1a AC 5). Compare `supabase db diff` output between the two trees after each batch. Any difference goes into the ledger's "Drift" section, not into a fix.
- **Kill-switch drill (before TF-1 sign-off, and again after Batch C):**
  1. Flip `coach_v2` off. The coach can't write. The athlete's sharing lines disappear on the next foreground. Pushes stop. Locked rows stay locked. The outbox keeps a pain flag queued.
  2. Flip it back on. The queued flag arrives.
  3. Time the whole drill and write it in the runbook.
- **Draft invariants (TF-3, SQL and Deno):** INV-1…INV-6 in §3.10, including a kill-mid-publish test (abort the transaction after half the workouts are written) and an AI-context snapshot for the athlete that shows no draft content.
- **Link end parity:** after leave and after removal, every coach read RPC returns zero rows for that athlete. The test grows with each story (C7.11, C8.1b, C8.6, C9.1).
- **Bidi fixtures:** Hebrew coach names and notes in push templates, cuts at 80 characters with emoji, and counters vs the server `char_length` (C7.15).
- **Analytics:** a unit test per event asserts the properties have no free text (C7.13). At TF-1, check that the events arrive in the analytics tool and the §7.1 queries return numbers.
- **Notification fatigue (TF-1):** with 20 fixture athletes finishing within 10 minutes, the coach gets at most 4 pushes (3 + 1 collapsed). A pain flag at 23:00 gives one collapsed push at quiet end (D6).

---

## 7. Success metrics, risks and open questions

### 7.1 v2 pilot success metrics (definitions in `docs/coach-v2-metrics.md`, C7.13)
These build on PRD v7.2 SM-1…SM-9. Baselines don't exist yet, so v2 sets **no new targets**: "watch" means review at each TF gate and at the end of the pilot. PRD targets still apply where cited.
- **SM-V1 Coach daily use:** days per week each coach opens Coach Today (`coach_today_viewed`). Validates C7.1. PRD SM-2 (≥2 a week) is the floor.
- **SM-V2 Time to handle a pain flag:** median `flag_resolved.minutes_open`, per coach. Watch.
- **SM-V3 Consent outcome:** for P9, acked vs "Leave {Coach}" tapped, per coach. Counter-metric for PRD SM-C1 (opt-out).
- **SM-V4 Coach involvement:** coach-built or coach-edited workouts plus feedback per active athlete per week. Extends PRD SM-3 (≥1 per active athlete per week).
- **SM-V5 Replies:** replies per coach note. Answers Q3.
- **SM-V6 Draft usefulness:** % of AI drafts published, and edits per published draft. Watch.
- **Counter-metrics:**
  - **SM-VC1 Notification fatigue:** share of coaches or athletes who turn off any coach push kind (`notification_pref_changed`), plus pushes per coach per day (`coach_notification_log`). If more than one pilot coach turns off "run finished", revisit the D6 default with Nadav.
  - **SM-VC2 Athlete overrides:** `athlete_changed_coach_workout` plus `goal_change_confirmed` per coach workout (PRD SM-C2).
  - **PRD SM-8 (leakage) stays the headline risk metric.**

### 7.2 Top risks and mitigations
| # | Risk | Why it matters | Mitigation in v1.3 |
|---|---|---|---|
| R1 | **M6 triggers on live tables** (1.2.6 clients and the web sync write `workouts`/`plans` directly) | A trigger bug hits real App Store users. A silent revert confuses athletes, and a raise can break web sync batches. | M6 is split into M6a/M6b and applied together after an audit, at a quiet time. The trigger keeps fields instead of raising. There are bypass, web-upsert and 1.2.6 regression tests, a writer doc, a rollback file, and the kill switch keeps locks enforced. D4 means only v2 pairs ever get locked rows. |
| R2 | **The athlete sees a draft or a half-published plan** (locked decision) | It breaks coach trust, and P-1. | INV-1…INV-6 (§3.10): separate tables, no athlete path, a one-transaction publish, a kill-mid-publish test, and an AI-context snapshot. |
| R3 | **The privacy change** (RPE, notes and flags shared by default) | Notes were promised to stay on the phone. | The ack gate on the server (M5a + M1a). No note backfill, ever. Hide-note. Pushes and analytics carry no content. The C7.8 copy has a light review. |
| R4 | **Push is on the critical path** (no APNs today; Nadav's Apple setup) | TF-1 slips. | APNs setup on day 1. Phase 1's in-app value (C7.1–C7.4, C7.7, C7.11) doesn't need push. Batch B is separate from Batch A. |
| R5 | **Mixed versions and TestFlight friction** (D4: both sides on v2) | Beginner athletes may not install TestFlight, so the coach sees "needs the latest RunSmart" for many athletes. | The roster shows who's blocked. **Nadav action:** send TestFlight invites with one-line steps before TF-1. Measure the share of v2 athletes per coach at TF-1. [ASSUMPTION: external TestFlight review is needed for the first build] |
| R6 | **Notification fatigue** (run finished ON for up to 20 athletes) | The coach mutes everything, including pain. | The 30-minute per-athlete dedupe (D6), the burst collapse (C7.5 AC 3), collapsed quiet-end pushes, counts-only summaries and SM-VC1. |
| R7 | **Migration drift between the iOS and web trees** | A missing or different file in one tree breaks the web app or the next batch. | C0.2 ledger, a web mirror PR per migration, the `db diff` check per batch, and "don't fix drift in v2 PRs". |
| R8 | **Scope** (43 stories, a solo founder) | Phase 2 stalls before the pilot sees value. | Phase 1 is a complete pilot release on its own (TF-1). Order: C8.1a/b → C8.5 → C8.2/C8.4 before intervals and AI drafts. Each TF gate is a stop/go point for Nadav. |
| R9 | **AI cost and quality** | Draft and summary costs grow with coaches; a bad draft wastes coach time. | Daily caps, cached summaries, the `coach_v2_ai` kill switch, aggregates-only prompts, SM-V6. |
| R10 | **Time zones and week start** | False "missed" items and wrong summary days. | One shared adherence function (Swift = SQL parity), the 20:00 athlete-local cutoff, the region week start, DST tests. |

### 7.3 Open questions: defaults
| # | Question (v1.2 §7) | Recommended default | Reason (one line) | Needs Nadav? |
|---|---|---|---|---|
| Q1 | Pilot size | 2 coaches × 8–20 athletes; test at 30 | PRD v7 already says so; 30 gives headroom for "more coaches may join". | No |
| Q2 | Plan Mode lock | Keep the lock until C8.14 | Unlocking without groups (M11) has no safe model, and the pilot doesn't need it. | No |
| Q3 | One-level reply vs full chat | One level for v2. Revisit if SM-V5 shows long back-and-forth | Coaches already use WhatsApp, and chat adds moderation and notification load. | No |
| Q4 | Load-jump threshold; readiness/HRV | ACWR ≥ 1.5 with a chronic-load floor [ASSUMPTION; tune at TF-5]. No HRV/readiness | 1.5 is the common rule of thumb; the floor stops false jumps for beginners; consent says HRV isn't shared. | No (Phase 3) |

### 7.4 New gaps (v1.3) and who decides
| # | Gap | Default | Needs Nadav? |
|---|---|---|---|
| C | The kill switch can't unlock rows by itself | Locks stay enforced; releasing them is a separate runbook script | No |
| D | C8.13 explainer says "Free for now." | Remove it | No |
| E | Coach run-finished bursts | Collapse after 3 in 10 minutes | No |
| F | Pilot athletes need TestFlight for v2 (D4) | Nadav sends the invites before TF-1 | Action, not a decision |

**Decided Nov 20 (moved out in v1.3):** Q5 → D11, Q6 → D12, gap A → D13, gap B → D14.

**Answered earlier (moved out in v1.2):** old Q0, Q3, Q6, Q7, Q8, and Sally's Q1–Q8 became D1–D10.

### 7.5 Assumptions index (v1.3)
- §2.5: an athlete with no coach-published plan keeps an adapting RunSmart plan.
- §3.7: the client flag cache is 15 minutes; the copy for the paused line and the drafting-paused line.
- C7.10: the 5xx retry-once policy.
- C7.4: a run-less flag entry on Today.
- C7.7: replies allowed on the welcome note if it's a `coach_feedback` row.
- C7.13: no migration is needed for analytics.
- C7.14: the athlete toggle copy; the equal-times validation.
- C7.16: milestones are in-app only; M13 only if needed.
- C7.5: the burst-collapse rule.
- C8.1a: delete becomes a locked rest row; `workout_structure` server guard ≤16 KB; one workout per day.
- C8.1b / C8.15: `date_taken` when a coach workout already exists that day.
- C8.2: occupied days offer Edit, not Add.
- C8.5: the `workout_locked` copy.
- C7.9: goal change needs a connection.
- C8.14: moving between groups doesn't change the plan; deleting a group with athletes is blocked.
- C9.2: the threshold of 1.5 plus a floor.
- C9.3: first names only in the prompt.
- R5: external TestFlight review.
