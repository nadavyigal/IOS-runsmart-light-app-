-- Rollback for 20261127100000_coach_workout_locks.sql (C8.1a, M6a, Batch C).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- flipping runtime_flags.coach_v2 to false is the first move. With the flag off,
-- coach writes stop (v2_unavailable) and the trigger keeps every locked row
-- protected, which is what you want on a bad day.
--
-- WARNING (v1.3 section 3.7): once athletes have coach workouts, dropping the
-- trigger exposes those rows to the AI, to 1.2.6 clients and to the web sync.
-- Their planned fields can then be overwritten and the rows deleted. Run this
-- only when the M6a functions themselves are broken. To unlock rows on purpose,
-- run supabase/rollback/release_all_coach_locks.sql instead (or first).
--
-- Roll back M6b (20261201110000_coach_plan_locks.sql) before this file: M6b's
-- athlete RPC and end_coach_link lock release use these columns and the trigger.
--
-- Data-preserving:
--   * The trigger workouts_protect_coach_rows and its function are dropped.
--   * The four coach write RPCs and the internal helpers are dropped.
--   * Every workouts column added by M6a stays, with its values (source, locked,
--     coach_id, coach_revision, published_version_id, coach_edited,
--     athlete_change, athlete_changed_at, original_date), and so does the
--     partial index idx_workouts_locked_plan_date.
--   * athlete_plan_update_queue stays, with every row, RLS on and no client grant.
--   * Re-applying the migration later finds the columns and the table and
--     changes nothing in them.
--
-- What clients see after this runs: v2 coach apps get "function not found" on
-- create / edit / move / delete and keep the edits queued; athletes see their
-- coach workouts as before, but nothing stops another writer from changing them.
-- 1.2.6 apps see no change.

begin;

drop trigger if exists workouts_protect_coach_rows on public.workouts;
drop function if exists public.workouts_protect_coach_rows();

drop function if exists public.coach_create_workout(uuid, uuid, date, text, numeric, integer, integer, text, jsonb, text);
drop function if exists public.coach_update_workout(uuid, integer, text, numeric, integer, integer, text, jsonb, text);
drop function if exists public.coach_move_workout(uuid, date, integer);
drop function if exists public.coach_delete_workout(uuid, integer);

drop function if exists public.coach_workout_for_write(uuid);
drop function if exists public.coach_queue_plan_update(uuid, uuid, uuid, text, date);
drop function if exists public.coach_workout_fields_check(text, numeric, integer, integer, text, jsonb, text);
drop function if exists public.coach_workout_structure_ok(jsonb);
drop function if exists public.coach_workout_gate(uuid, text);
drop function if exists public.coach_athlete_today(uuid, text);

commit;
