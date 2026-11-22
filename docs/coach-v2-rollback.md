# Coach Experience v2: kill switch and rollback runbook

**Owner:** Nadav. Agents never run anything in this file against production.
**Created:** 2026-11-21 by story C7.0 (C7.12 folded in). Every later v2 migration PR adds its row and its batch section here.
**Source of truth for the switch:** `supabase/migrations/20261121100000_coach_v2_gate.sql`.

## 1. First move on a bad pilot day: flip the flag

Run these in the Supabase SQL editor for the production project. Each is one statement and needs no build.

Turn every v2 coach feature off:

```sql
update public.runtime_flags set enabled = false, updated_at = now(), note = 'off: <reason>' where key = 'coach_v2';
```

Turn it back on:

```sql
update public.runtime_flags set enabled = true, updated_at = now(), note = null where key = 'coach_v2';
```

Narrower switches (they leave the rest of v2 running):

```sql
-- Stop coach pushes only. Queued and deferred rows are kept and send when it is back on.
update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2_push';
-- Pause AI drafting and weekly summaries only.
update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2_ai';
```

Check the current values:

```sql
select key, enabled, updated_at, note from public.runtime_flags order by key;
```

### What happens when `coach_v2` is off

| Where | Effect | How fast |
|---|---|---|
| Server | `link_is_v2` returns false for every pair. v2 read RPCs return zero rows, v2 write RPCs raise `v2_unavailable`. | Next call, right away |
| Edge Functions | Functions that need the flag exit with 200 and log `skipped_kill_switch` (`supabase/functions/_shared/flags.ts`). Nothing is sent or deleted. | Next invocation |
| App | Shows the 1.2.6 coach UI. A pilot coach whose build would have v2 sees one line on the roster: "Some coach tools are paused for now." Queued outbox items stay queued. Solo users see nothing new. | Next foreground after the 15-minute flag cache expires |

The server side is the real gate, so data stops flowing at once even while an app still shows v2 for up to 15 minutes.

### When the switch is back on

The server answers at once. Apps keep reporting `coach_v2 = true` while the switch is off (they report what the build can do, and the server applies the switch), so every pair is v2 again right away on the server, including athletes who have not opened the app. Each app shows v2 again on its next foreground after its 15-minute cache. Outbox items flush from that point.

## 2. Pilot coach allowlist (decision N1 = B)

App Store builds turn v2 on only for coaches in `coach_v2_pilot_coaches` and for athletes with an active link to one. TestFlight and Debug builds do not need the list. The table ships empty. Add coaches only after TF-1a passes.

Find a coach's user id by email:

```sql
select u.id, u.email, cp.display_name
from auth.users u join public.coach_profiles cp on cp.user_id = u.id
where u.email = '<coach email>';
```

Add a pilot coach:

```sql
insert into public.coach_v2_pilot_coaches (coach_id) values ('<coach user id>') on conflict (coach_id) do nothing;
```

Remove a pilot coach (their App Store pairs turn off on the next server call; their apps follow within 15 minutes):

```sql
delete from public.coach_v2_pilot_coaches where coach_id = '<coach user id>';
```

List pilot coaches:

```sql
select p.coach_id, cp.display_name, p.added_at
from public.coach_v2_pilot_coaches p left join public.coach_profiles cp on cp.user_id = p.coach_id
order by p.added_at;
```

See which of a coach's athletes are v2-capable (the same data the roster line uses):

```sql
select l.athlete_id, c.coach_v2, c.channel, c.app_version, c.build, c.updated_at
from public.coach_athlete_links l left join public.client_capabilities c on c.user_id = l.athlete_id
where l.coach_id = '<coach user id>' and l.status = 'active';
```

## 3. Rollback files, one section per batch

Rules for every batch:

1. Flip the flag first (section 1). Most problems end there.
2. Roll back only the newest batch first, newest file first. Never roll back a batch while a later one is applied.
3. Rollback files live in `supabase/rollback/`, never in `supabase/migrations/`. They drop triggers, then functions, then policies, then new tables. They keep new columns on existing tables.
4. After a rollback, the migration can be applied again. It is idempotent and keeps the rows the rollback kept.

### Batch A (R1: coach sees how athletes feel)

| File | Story | Rollback file | Status |
|---|---|---|---|
| `20261121100000_coach_v2_gate.sql` (M0 + M0b) | C7.0 + C7.12 | `supabase/rollback/20261121100000_coach_v2_gate.sql` | written (draft PR) |
| `20261121110000_coach_consent_v2.sql` (M5a) | C7.8 | `supabase/rollback/20261121110000_coach_consent_v2.sql` | written (draft PR) |
| `20261121120000_athlete_run_sharing.sql` (M1a) | C7.3 | `supabase/rollback/20261121120000_athlete_run_sharing.sql` | written (draft PR) |
| `20261121130000_coach_last_seen_and_events.sql` (M3) | C7.2 | added by C7.2 | not written |
| `20261121140000_coach_feedback_replies.sql` (M4) | C7.7 | added by C7.7 | not written |
| `20261121150000_athlete_run_flags.sql` (M1b) | C7.4 | added by C7.4 | not written |
| `20261121160000_coach_link_end.sql` (M5b) | C7.11 | added by C7.11 | not written |
| `20261121170000_coach_milestones.sql` (M13, only if needed) | C7.16 | added by C7.16 | not written |

#### M0: `20261121100000_coach_v2_gate.sql`

1. **Flag to flip first:** `coach_v2` to false.
2. **Safe with the flag off:** every pair is non-v2 on the server. Capability reports keep arriving, so the server knows which clients are v2 when the flag returns. The pilot list and the flag values are untouched. No athlete data is shared through v2 while the flag is off.
3. **Rollback file:** `supabase/rollback/20261121100000_coach_v2_gate.sql`. It drops the five functions (`coach_v2_roster_status`, `link_is_v2`, `coach_v2_pilot_access`, `get_runtime_flags`, `report_client_capabilities`). It keeps the three tables and their rows: `client_capabilities`, `runtime_flags`, `coach_v2_pilot_coaches`. RLS stays on and clients keep no write access. Dropping the tables is a commented, optional step at the end of the file; export first if you ever run it.
4. **When not to roll back:** while any later v2 migration is applied. Every later v2 RPC calls `link_is_v2`, so dropping it breaks them. Flip `coach_v2` instead.
5. **After the rollback, the app:** fails its flag read, treats v2 as off, and shows the 1.2.6 coach UI in every build. Nothing else changes for users.
6. **Verified:** on a throwaway local Postgres (supabase/postgres 17.6.1.158), 2026-11-21: the rollback dropped all five functions, kept the pilot row and a flag value set to false, and a re-apply restored the functions without changing either.

#### M5a: `20261121110000_coach_consent_v2.sql`

1. **Flag to flip first:** `coach_v2` to false. With it off, `my_coach_consent_status` reports no P9 and no sharing, `ack_coach_consent` raises `v2_unavailable`, `coach_v2_sharing_allowed` is false for every pair, and the join screen shows the A3 copy (`coach_invite_consent_version` returns 1).
2. **Safe with the flag off:** every ack already given stays in `coach_athlete_links` (`consent_version`, `consent_acknowledged_at`). Athletes who have not acked see P9 again when the flag returns. Joins keep working: 1.2.6 and flag-off clients use Story 1.3's `join_coach`.
3. **Rollback file:** `supabase/rollback/20261121110000_coach_consent_v2.sql`. It restores Story 1.3's `join_coach` body (same signature, same payload), then drops `my_coach_consent_status`, `ack_coach_consent`, `coach_invite_consent_version`, `join_coach_v2` and `coach_v2_sharing_allowed`. It keeps both columns, their values and both check constraints. Dropping the columns is a commented, optional step that deletes every ack; export first if you ever run it.
4. **When not to roll back:** while M1a (`20261121120000_athlete_run_sharing.sql`) or any later file that calls `coach_v2_sharing_allowed` is applied. Roll those back first, or flip `coach_v2` instead.
5. **After the rollback, the app:** v2 builds fail the status read, so P9 never shows; the join screen falls back to the A3 copy and `join_coach`. 1.2.6 apps see no change.
6. **Verified:** on a throwaway local Postgres (supabase/postgres 17.6.1.158), 2026-11-22: with an acked link in place, the rollback dropped the five functions, kept the link's `consent_version = 2` and its ack time, and the restored `join_coach` joined a new athlete at consent v1 with the Story 1.3 payload. Re-applying the migration kept the ack unchanged, and `coach_consent_v2.sql` passed again.

#### M1a: `20261121120000_athlete_run_sharing.sql`

1. **Flag to flip first:** `coach_v2` to false. With it off, `coach_get_athletes_runs` keeps returning runs exactly as Story 2.2 did, but `rpe` is null and `has_note` is false; `coach_get_run_notes` returns zero rows; the athlete's effort and note writes raise `v2_unavailable`, so the app keeps them queued. Hiding a note still works.
2. **Safe with the flag off:** every effort and note already synced stays in `runs`, unreadable by any coach. Changes made while the flag is off wait on the athlete's phone and flush when it returns. A note hidden while the flag is off stays hidden after.
3. **Rollback file:** `supabase/rollback/20261121120000_athlete_run_sharing.sql`. It restores Story 2.2's ten-column `coach_get_athletes_runs` and Story 1.5's `purge_coach_data_for_deleted_account`, then drops `coach_get_run_notes`, `athlete_set_run_note_hidden`, `athlete_set_run_note`, `athlete_set_run_rpe`, `athlete_sharing_ack_time` and `athlete_own_run_id`. It keeps `runs.rpe`, `runs.athlete_note`, `runs.note_hidden_from_coach`, their values and both check constraints. Dropping the columns is a commented, optional step that deletes every synced effort and note; export first if you ever run it.
4. **When not to roll back:** while M1b (`20261121150000_athlete_run_flags.sql`) or any later file that relies on these columns is applied. Roll those back first, or flip `coach_v2` instead. M5a (`coach_v2_sharing_allowed`) must stay applied while M1a is.
5. **After the rollback, the app:** v2 athlete apps get "function not found" on the sharing writes and keep them queued; coach apps read runs without effort or notes. 1.2.6 apps see no change.
6. **Verified:** on a throwaway local Postgres (supabase/postgres 17.6.1.158), 2026-11-22: with a run holding `rpe = 7`, a note and the hide flag, the rollback dropped the six functions, restored the ten-column `coach_get_athletes_runs` and the Story 1.5 purge, and kept all three values. Re-applying the migration kept the values unchanged and restored the functions.

### Batch B (R2: coach gets told)

| File | Story | Rollback file | Status |
|---|---|---|---|
| `20261122100000_push_tokens_and_prefs.sql` (M2a) | C7.10 | added by C7.10 | not written |
| `20261122110000_notification_log_and_deferred.sql` (M2b) | C7.5 | added by C7.5 | not written |

First move: `coach_v2_push` to false. Senders keep their queue.

### Batch C (R3: coach builds workouts)

| File | Story | Rollback file | Status |
|---|---|---|---|
| `20261201100000_coach_workout_locks.sql` (M6a) | C8.1a | added by C8.1a | not written |
| `20261201110000_coach_plan_locks.sql` (M6b) | C8.1b | added by C8.1b | not written |

Warning carried from v1.3 §3.7: once athletes have coach-published workouts, dropping the M6 triggers exposes them to the AI and to 1.2.6 writers. Flip `coach_v2` instead. Existing locks stay enforced by the triggers with the flag off. Unlocking is a separate Nadav-only script, `supabase/rollback/release_all_coach_locks.sql`, added by C8.1a.

### Batches D, E, F and M10

Rows are added when Nadav picks those stories after TF-2.

## 4. Kill-switch drill (TF-1b)

Run once on TestFlight with Nadav's two phones before pilot coaches get push (refined plan §1, TF-1b). Time each step and write the times here.

1. Coach phone and athlete phone both on v2. Confirm a v2 screen shows on the coach phone.
2. Run the "turn off" line from section 1. Note the time.
3. Background and reopen both apps after 15 minutes. Expect the 1.2.6 coach UI and the paused line on the coach roster.
4. Run the "turn back on" line. Background and reopen after 15 minutes. Expect v2 back and any queued items sent.

| Step | Expected | Time taken | Date |
|---|---|---|---|
| Off to flag-off UI | at most 15 minutes plus one foreground | not run yet | |
| On to v2 back | at most 15 minutes plus one foreground | not run yet | |
