# Coach v2: every `workouts` / `plans` writer under the M6a lock trigger

**Story:** C8.1a (M6a, `supabase/migrations/20261127100000_coach_workout_locks.sql`). **Written:** 2026-11-27.
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

"Planned fields" are `plan_id, auth_user_id, local_id, type, distance, duration, pace, notes, workout_structure, intensity, training_phase, created_at` (plus `scheduled_date, day, week` outside the athlete-change path).

A client cannot become a coach writer by setting `runsmart.coach_write` itself: the trigger ignores both settings while `current_user` is `authenticated` or `anon`. The kill switch (`runtime_flags.coach_v2`) does not change the trigger. With the flag off, coach RPCs raise `v2_unavailable` and locked rows stay protected.

`plans` has no trigger in M6a. Plan deactivation and plan delete are M6b's (`plans_protect_coach_plans`). Until M6b is applied, deleting a plan cascades to its workouts, locked ones included. Batch C applies M6a and M6b together.

## Writers

### iOS app (`IOS RunSmart app/Services/Supabase/TrainingPlanRepository.swift`)

| # | Writer | Table and write | Under the trigger | Follow-up |
|---|---|---|---|---|
| 1 | `persistGeneratedPlan` (L489): deactivate old plans (L552, L561, L568, L575) | `plans` UPDATE `is_active=false` | Not touched by M6a. | M6b blocks it with `plan_locked_by_coach` / `coach_workouts_present`; C8.5 moves linked athletes to `athlete_replace_training_plan`. |
| 2 | `persistGeneratedPlan`: new plan (L583) and its workouts (L597) | `plans` INSERT, `workouts` INSERT | Workouts arrive as `source='ai'`, unlocked. | none |
| 3 | `persistGeneratedPlan` via `replace_group_training_plan` RPC (L547) | security invoker: `plans` UPDATE + INSERT, `workouts` INSERT | Same as 1 and 2. | M6b replaces the RPC with a clear error. |
| 4 | `saveSuggestedWorkout` (L612, insert at L660) and `createRecommendationPlan` (L673) | `workouts` INSERT, `plans` INSERT | Inserted unlocked. It can add a second workout on a day that already has a locked coach row; the trigger does not prevent that. | C8.5: the AI skips days that have a locked row. |
| 5 | `amendWorkout` (L869) and `moveWorkout` (L885) | `workouts` UPDATE by id (`DBWorkoutUpdate`: date, day, type, distance, duration, pace, notes, workout_structure) | Unlocked: unchanged. Locked: nothing changes and the call still returns `true`. | C8.5: the app hides edit and move on locked rows and shows the `workout_locked` copy. |
| 6 | `pushWorkoutTomorrow` (L889) | two `moveWorkout` calls (the conflict, then the workout) | Unlocked: unchanged. A locked row in either position silently keeps its date. | C8.5 |
| 7 | `removeWorkout` (L924) | `workouts` DELETE by id | Unlocked: unchanged. Locked: raises `workout_locked`, the call returns `false`. | C8.5 shows the copy. |
| 8 | `applyFlexWeek` (L940, updates at L975, rollback at L987) | `workouts` UPDATE (`DBWorkoutFlexUpdate`: date, day, type, distance, duration, pace, intensity) | Unlocked: unchanged. Locked rows keep their plan; the apply still marks the hash applied. | C8.5: the flex week leaves locked rows out. |
| 9 | `complete_run_workout` RPC (L782) | security invoker: `workouts` UPDATE of completion fields only | Completes a locked row (tested). | none |

### Web app (`Running-coach-`, read-only)

| # | Writer | Table and write | Under the trigger | Follow-up |
|---|---|---|---|---|
| 10 | `v0/lib/sync/plan-workout-sync.ts` `upsertPlans` (~L140) | `plans` upsert on `(profile_id, local_id)`, includes `is_active` | Not touched by M6a. | M6b |
| 11 | `v0/lib/sync/plan-workout-sync.ts` `upsertWorkouts` (~L210) | `workouts` upsert on `(plan_id, local_id)` with full planned and completion fields | Locked rows keep their planned fields and lock columns; completion fields are written; no error, so a batch never fails mid-way (tested). Coach-created rows have `local_id = null`, so the web never matches them. | See note below. |

Note on 11 (pre-existing, outside C8.1a, unverified in production): the only unique indexes on `workouts (plan_id, local_id)` are partial (`where local_id is not null`). On the test fixture, a bare `on conflict (plan_id, local_id)` raises 42P10 "no unique or exclusion constraint matching". If PostgREST sends the bare form, the web workout sync already fails before any trigger runs. Worth a separate check of the web sync logs.

### Server

| # | Writer | Table and write | Under the trigger | Follow-up |
|---|---|---|---|---|
| 12 | `supabase/functions/delete_account/index.ts` (L84-L85, L123, L134) | service role DELETE on `workouts` and `plans` | Allowed (service role), then FK cascades. Account deletion is never blocked (tested). | none |
| 13 | FK cascades: `workouts.plan_id` and `workouts.auth_user_id` are `on delete cascade` | DELETE | Allowed (trigger depth 2). | M6b guards plan delete. |
| 14 | `coach_create_workout`, `coach_update_workout`, `coach_move_workout`, `coach_delete_workout` (M6a) | `workouts` INSERT / UPDATE as the coach | The coach path. Each checks the link, `link_is_v2`, completed / past, revision and one workout per day, then writes `source='coach'`, `locked=true`, `coach_id` and `coach_revision + 1`, and upserts `athlete_plan_update_queue`. | C8.2 / C8.3 call them. |
| 15 | Nadav's SQL editor (owner role) | anything | Protected like any writer unless the script sets `runsmart.coach_write`. `supabase/rollback/release_all_coach_locks.sql` does, on purpose. | none |
| 16 | `purge_coach_data_for_deleted_account`, `end_coach_link` (M5b) | none on `workouts` today | n/a | M6b adds the lock release to `end_coach_link`. |

No other writer was found: no Edge Function in either repo writes `workouts` or `plans` (`coach_message`, `coach_notify`, `coach_evening_summary` only read), and no other migration function writes them. `workout_adherence_state` and the coach read RPCs only read.

## One workout per day

Production has no unique index on `workouts (plan_id, scheduled_date)`. On 2026-11-27 none of the 356 rows shares a plan and day, so the rule holds in practice. M6a enforces it only on the coach path (`date_taken` from create and move, serialized with an advisory lock on plan + day). It does not add a unique index, because a 1.2.6 client or the web sync writing a duplicate would then fail mid-batch.
