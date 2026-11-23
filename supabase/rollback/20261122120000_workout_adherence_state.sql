-- Rollback for 20261122120000_workout_adherence_state.sql (C7.6, Batch B).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- turning the evening summary off is runtime_flags.coach_v2_push = false, or
-- unscheduling the coach_evening_summary_hourly cron. Neither needs a rollback.
-- Use this file only when the functions themselves are broken.
--
-- Before running it: unschedule coach_evening_summary_hourly
-- (docs/coach-v2-batch-b-runbook.md section 7), or every hourly call fails.
--
-- Data-preserving: the file created functions only, so there is no data to keep.
-- It drops coach_evening_summary_counts, workout_adherence_state and
-- workout_adherence_boundary. Held summaries (deferred_pushes rows of kind
-- coachEveningSummary) and summary log rows stay; re-applying the migration and
-- the cron sends the held ones at the next run.
--
-- What clients see after this runs: nothing. No client calls these functions.
-- Coaches get no evening summary until the file is re-applied.

begin;

drop function if exists public.coach_evening_summary_counts(uuid, date, text, timestamptz);
drop function if exists public.workout_adherence_state(text, numeric, integer, date, numeric, integer, date);
drop function if exists public.workout_adherence_boundary(timestamptz, text);

commit;
