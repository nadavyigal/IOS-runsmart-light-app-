# Coach v2: every `workouts` / `plans` writer under the M6a and M6b lock triggers

**Story:** C8.1a (M6a, `supabase/migrations/20261127100000_coach_workout_locks.sql`) and C8.1b (M6b, `supabase/migrations/20261127110000_coach_plan_locks.sql`). **Written:** 2026-11-27.
**Checked at:** iOS `origin/main` `ae24e5e`, web `origin/main` `d0ca8c98` (read-only), production schema read-only on 2026-11-27.
**Update this file** in every story that adds a writer or changes the trigger (C8.1b, C8.5, C8.6 and later).

## How the trigger decides

`workouts_protect_coach_rows` runs BEFORE INSERT, UPDATE and DELETE on `public.workouts`, for every row.

| Writer kind | INSERT | UPDATE of an unlocked row | UPDATE of a locked row | DELETE of a locked row |
|---|---|---|---|---|
| Coach RPC (`runsmart.coach_write = on`, non-client role) | as written | as written | as written | allowed |
| M6b athlete RPC (`runsmart.athlete_change = on`, non-client role) | lock columns reset | lock and athlete-change columns kept | only `scheduled_date`, `day`, `week`, `original_date`, `athlete_change`, `athlete_changed_at` change | raises `workout_locked` |
| Everyone else: the app as `authenticated`, the web sync, owner SQL without the setting | lock columns reset to `source='ai'`, `locked=false`, `coach_id=null`, `coach_revision=0` | unchanged behavior; only the lock and athlete-change columns are kept | planned fields, date and lock columns kept; completion fields (`completed`, `completed_at`, `actual_*`) change; **no error** | raises `workout_locked` |
| Service role (`delete_account`) | as everyone else | as everyone else | as everyone else | allowed |
| FK cascade (a plan or an auth user is deleted) | n/a | n/a | n/a | allowed |
| FK SET NULL (a coach's auth user is deleted) | n/a | `coach_id` set to null | `coach_id` set to null, all else kept | n/a |

"Planned fields" are `id, plan_id, auth_user_id, local_id, type, distance, duration, pace, notes, workout_structure, intensity, training_phase, created_at` (plus `scheduled_date, day, week` outside the athlete-change path).

A client cannot become a coach writer by setting `runsmart.coach_write` itself: the trigger ignores both settings while `current_user` is `authenticated` or `anon`. The kill switch (`runtime_flags.coach_v2`) does not change the trigger. With the flag off, coach RPCs raise `v2_unavailable` and locked rows stay protected.

## How the plans trigger decides (M6b)

`plans_protect_coach_plans` runs BEFORE INSERT, UPDATE and DELETE on `public.plans`, for every row. "Locked future rows" means workouts of that plan with `locked = true` dated on or after the owner's today (their notification time zone, else the plan's `created_in_timezone`, else UTC), counted by `coach_plan_locked_future_count`. Past locked rows never block anything.

| Writer kind | INSERT | UPDATE that keeps `is_active` | UPDATE `is_active` true to false | DELETE |
|---|---|---|---|---|
| Coach path (`runsmart.coach_write = on`, non-client role): `end_coach_link` lock release, M7 publish later | as written | as written | allowed | allowed |
| `athlete_replace_training_plan` (`runsmart.goal_change = on`, non-client role) | n/a (inserts as everyone else) | as everyone else | `plan_locked_by_coach` if published; allowed with locked future rows | n/a |
| Everyone else: the app as `authenticated`, the web sync, owner SQL without a setting | `coach_published = false`, `coach_id = null` forced | `coach_published` and `coach_id` kept from OLD, no error | `plan_locked_by_coach` if published, else `coach_workouts_present` if it has locked future rows, else allowed | same as deactivation |
| Service role (`delete_account`) | as everyone else | as everyone else | as everyone else | allowed |
| FK cascade (an auth user is deleted) | n/a | n/a | n/a | allowed |
| FK SET NULL (a coach's auth user is deleted) | n/a | `coach_id` set to null, all else kept | n/a | n/a |

The same trust rule as M6a: a client that sets `runsmart.goal_change` or `runsmart.coach_write` itself is ignored (tested). The kill switch does not change the trigger.

When a coach link ends, the athlete's future locked workouts are unlocked and `coach_published` is cleared on their plans, in the same transaction. The rows stay, with `source = 'coach'` and their `coach_id` (G17). This runs from `end_coach_link` (`leave_coach`, `coach_remove_athlete`) and, for account deletion, from the `coach_links_release_locks_on_delete` trigger, because `purge_coach_data_for_deleted_account` and the auth FK cascade delete link rows without `end_coach_link`.

## Lock order (every coach write, and M6b's `end_coach_link`)

Every coach write RPC takes its locks in this order, and anything that ends a link or releases coach locks must take them in the same order, so writers can wait on each other but never deadlock:

0. The athlete's and the coach's `auth.users` rows, `FOR KEY SHARE`, in `coach_workout_gate`. The workout insert and the `athlete_plan_update_queue` upsert check foreign keys to `auth.users`, which takes `KEY SHARE` on those rows. Taken late, that deadlocks with an account delete, which holds the `auth.users` row and cascades into links, plans and workouts. Taken first, the delete waits for the coach write, or the write waits for the delete and then finds no link. `KEY SHARE` blocks only deletes and key changes of those two rows, not other coach writes or ordinary updates. The function owner `postgres` has UPDATE on `auth.users` and `rolbypassrls` (production read, 2026-11-27), so the lock works in Supabase.
1. The `coach_athlete_links` row, `FOR SHARE`, in `coach_workout_gate`. A revoke (UPDATE of `status`) waits for the coach write to commit. If the revoke committed first, the locking read finds no active row and the RPC raises `link_inactive`.
2. The `plans` row, `FOR SHARE` (`coach_create_workout`, and `coach_workout_for_write` for update / move / delete). A plan deactivation waits. If it committed first, `is_active` is re-checked under the lock: create raises `no_active_plan`, the others `workout_not_found`.
3. The `workouts` row, `FOR UPDATE` (`coach_workout_for_write`).
4. Advisory locks: key 62 (one `p_id`, create retries) and key 61 (one plan-day, one workout per day).

Update, move and delete first read the workout's athlete without a lock (`coach_workout_owner`), so they can take locks 0 and 1 before locks 2 and 3. They then check that the locked row still belongs to that athlete. `supabase/tests/coach_workout_locks_race.sh` shows each wait with real connections, including an athlete account delete during a coach create (its own row in the CI db matrix).

`supabase/rollback/release_all_coach_locks.sql` follows the same order: it locks the affected plans `FOR UPDATE` first, then updates workouts, then plans. `supabase/tests/coach_lock_release.sh` tests that (its own row in the CI db matrix).

## Writers

### iOS app (`IOS RunSmart app/Services/Supabase/TrainingPlanRepository.swift`)

| # | Writer | Table and write | Under the trigger | Follow-up |
|---|---|---|---|---|
| 1 | `persistGeneratedPlan` (L489): deactivate old plans (L552, L561, L568, L575) | `plans` UPDATE `is_active=false` | Not touched by M6a. | **M6b:** blocked with `plan_locked_by_coach` / `coach_workouts_present` only when the active plan is published or has locked future rows (tested with this exact filter). A solo user or an unlocked plan works as before (AC6). C8.5 moves linked athletes to `athlete_replace_training_plan`. |
| 2 | `persistGeneratedPlan`: new plan (L583) and its workouts (L597) | `plans` INSERT, `workouts` INSERT | Workouts arrive as `source='ai'`, unlocked. | none |
| 3 | `persistGeneratedPlan` via `replace_group_training_plan` RPC (L547) | security invoker: `plans` UPDATE + INSERT, `workouts` INSERT | Same as 1 and 2. | **M6b:** replaced (same signature, still security invoker). Raises `plan_locked_by_coach` / `coach_workouts_present` with a detail and a hint before it changes anything; otherwise unchanged (tested). |
| 4 | `saveSuggestedWorkout` (L612, insert at L660) and `createRecommendationPlan` (L673) | `workouts` INSERT, `plans` INSERT | Inserted unlocked. It can add a second workout on a day that already has a locked coach row; the trigger does not prevent that. Accepted on purpose (second-model review, 2026-11-27): raising on that insert would fail whole batches from 1.2.6 clients and the web sync. | C8.5: the AI skips days that have a locked row. |
| 5 | `amendWorkout` (L869) and `moveWorkout` (L885) | `workouts` UPDATE by id (`DBWorkoutUpdate`: date, day, type, distance, duration, pace, notes, workout_structure) | Unlocked: unchanged. Locked: nothing changes and the call still returns `true`. | C8.5: the app hides edit and move on locked rows and shows the `workout_locked` copy. |
| 6 | `pushWorkoutTomorrow` (L889) | two `moveWorkout` calls (the conflict, then the workout) | Unlocked: unchanged. A locked row in either position silently keeps its date. | C8.5 |
| 7 | `removeWorkout` (L924) | `workouts` DELETE by id | Unlocked: unchanged. Locked: raises `workout_locked`, the call returns `false`. | C8.5 shows the copy. |
| 8 | `applyFlexWeek` (L940, updates at L975, rollback at L987) | `workouts` UPDATE (`DBWorkoutFlexUpdate`: date, day, type, distance, duration, pace, intensity) | Unlocked: unchanged. Locked rows keep their plan; the apply still marks the hash applied. | C8.5: the flex week leaves locked rows out. |
| 9 | `complete_run_workout` RPC (L782) | security invoker: `workouts` UPDATE of completion fields only | Completes a locked row (tested). | none |

### Web app (`Running-coach-`, read-only)

| # | Writer | Table and write | Under the trigger | Follow-up |
|---|---|---|---|---|
| 10 | `v0/lib/sync/plan-workout-sync.ts` `upsertPlans` (~L140) | `plans` upsert on `(profile_id, local_id)`, includes `is_active` | **M6b:** coach columns are kept; an upsert that sets `is_active = false` on a published plan or one with locked future rows raises, and that batch fails. Only possible for a linked athlete whose v2 coach wrote workouts (D4). | Web follow-up if web users get coaches: send `is_active` changes for such plans through `athlete_replace_training_plan`. |
| 11 | `v0/lib/sync/plan-workout-sync.ts` `upsertWorkouts` (~L210) | `workouts` upsert on `(plan_id, local_id)` with full planned and completion fields | Locked rows keep their planned fields and lock columns; completion fields are written; no error, so a batch never fails mid-way (tested). Coach-created rows have `local_id = null`, so the web never matches them. | See note below. |

Note on 11 (pre-existing, outside C8.1a, unverified in production): the only unique indexes on `workouts (plan_id, local_id)` are partial (`where local_id is not null`). On the test fixture, a bare `on conflict (plan_id, local_id)` raises 42P10 "no unique or exclusion constraint matching". If PostgREST sends the bare form, the web workout sync already fails before any trigger runs. Worth a separate check of the web sync logs.

### Server

| # | Writer | Table and write | Under the trigger | Follow-up |
|---|---|---|---|---|
| 12 | `supabase/functions/delete_account/index.ts` (L84-L85, L123, L134) | service role DELETE on `workouts` and `plans` | Allowed (service role), then FK cascades. Account deletion is never blocked (tested). | none |

**Service-role delete rule.** The trigger lets the service role delete locked rows only so that account deletion never fails. On 2026-11-27 the only service-role writer that deletes `workouts` is `delete_account` (its per-table delete loop, `index.ts:70`); the web repo has none. **Do not add other service-role deletes of `workouts`:** they would remove coach-locked rows with no check. A new server-side writer that must touch coach rows goes through a coach or athlete RPC instead.
| 13 | FK cascades: `workouts.plan_id` and `workouts.auth_user_id` are `on delete cascade` | DELETE | Allowed (trigger depth 2). Deleting an athlete account removes their locked rows and published plans (tested in both suites). | none |
| 13b | FK action: `workouts.coach_id` is `on delete set null` (deleting a coach account) | UPDATE at trigger depth 2 | `coach_id` becomes null; the row stays a locked coach row with its planned fields (tested). Every other lock column is still kept. A client statement runs at depth 1 and can never take this path. No other FK on `workouts` is SET NULL. The partial index `idx_workouts_coach_id` (and `idx_athlete_plan_update_queue_coach_id` on the queue) keeps this from scanning the table on every auth user delete. **M6b, M7 and later triggers that update `workouts` also run at depth > 1, so they must never set `coach_id` or `published_version_id` to null.** | **M6b:** deleting a coach account deletes their links (purge or cascade), which unlocks these rows (tested: purge path and direct auth delete). A row left locked with `coach_id` null by an earlier delete is unlocked when the athlete's link ends (tested). |
| 14 | `coach_create_workout`, `coach_update_workout` (every planned field required except `p_intensity`, so leaving out `p_workout_structure` errors instead of wiping it), `coach_move_workout`, `coach_delete_workout` (M6a) | `workouts` INSERT / UPDATE as the coach | The coach path. Each checks the link, `link_is_v2`, completed / past, revision and one workout per day, then writes `source='coach'`, `locked=true`, `coach_id` and `coach_revision + 1`, and upserts `athlete_plan_update_queue`. | C8.2 / C8.3 call them. |
| 15 | Nadav's SQL editor (owner role) | anything | Protected like any writer unless the script sets `runsmart.coach_write`. `supabase/rollback/release_all_coach_locks.sql` does, on purpose. | none |
| 16 | `purge_coach_data_for_deleted_account` (deletes links), `end_coach_link` (M6b version) | `workouts` UPDATE `locked = false` and `plans` UPDATE `coach_published = false` for the athlete's future rows, through `coach_release_athlete_locks` (coach path) | The coach path, so both triggers allow it. The purge reaches it through the `coach_links_release_locks_on_delete` trigger. | M7 adds draft deletion to `end_coach_link`. |
| 17 | `athlete_change_coach_workout` (M6b, D1) | `workouts` UPDATE on the athlete-change path | Only `scheduled_date`, `day`, `week`, `original_date` (first move), `athlete_change`, `athlete_changed_at` change; the row stays locked; logs `athlete_skip` / `athlete_move`; a repeated `p_request_id` returns `duplicate`, also when a retry races the original and a link end (tested, incl. `coach_plan_locks_race.sh`). Lock order: `auth.users` rows of athlete and coach (KEY SHARE), link, plan, workout, advisory. | C8.15 calls it. |
| 18 | `athlete_replace_training_plan` (M6b, D2) | `plans` UPDATE `is_active = false` with `runsmart.goal_change`, `plans` INSERT, `workouts` INSERT | Needs the acknowledged count of locked future rows (`count_changed` otherwise); never replaces a published plan; new rows arrive as unlocked AI rows; logs `goal_change` when linked. Not gated on `link_is_v2`. Takes the `auth.users` KEY SHARE and the link first, so a concurrent coach account delete waits instead of deadlocking (race-tested). | C8.5 moves `persistGeneratedPlan` here for linked athletes. Do not also call `athlete_log_goal_change` for the same change, or the coach sees two events. |

No other writer was found: no Edge Function in either repo writes `workouts` or `plans` (`coach_message`, `coach_notify`, `coach_evening_summary` only read), and no other migration function writes them. `workout_adherence_state` and the coach read RPCs only read.

## One workout per day

Production has no unique index on `workouts (plan_id, scheduled_date)`. On 2026-11-27 none of the 356 rows shares a plan and day, so the rule holds in practice. M6a enforces it only on the coach path (`date_taken` from create and move, serialized with an advisory lock on plan + day). It does not add a unique index, because a 1.2.6 client or the web sync writing a duplicate would then fail mid-batch.
