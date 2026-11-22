-- Rollback for 20261121130000_coach_last_seen_and_events.sql (C7.2, M3, Batch A).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- flipping runtime_flags.coach_v2 to false is the first move, and it needs no
-- rollback at all. Use this file only when the M3 functions themselves are
-- broken.
--
-- Do not run it while a later Batch A file that writes or reads
-- coach_athlete_events or replaces coach_roster_summary is applied (M4, M1b,
-- M5b and later). Roll back newer files first, newest first.
--
-- Data-preserving:
--   * The four M3 functions are dropped: coach_roster_summary,
--     coach_get_athlete_events, athlete_log_goal_change, coach_mark_athlete_seen.
--   * coach_athlete_seen and coach_athlete_events stay, with every row, RLS on,
--     no client grant and no client policy. Re-applying the migration later
--     finds them and changes nothing.
--   * No existing function or column is touched: M3 replaced none.
--
-- What clients see after this runs: v2 coach apps fail the counts read and show
-- Coach Today without "new" markers; seen writes and goal-change writes fail and
-- stay in the phone's outbox (dropped after 14 days). 1.2.6 apps see no change.

begin;

drop function if exists public.coach_roster_summary();
drop function if exists public.coach_get_athlete_events(uuid, timestamptz);
drop function if exists public.athlete_log_goal_change(uuid);
drop function if exists public.coach_mark_athlete_seen(uuid, timestamptz);

commit;

-- Optional, destructive, NOT part of the rollback. Deletes every seen time and
-- every coach event, including left/removed history from M5b. Export first.
-- drop table if exists public.coach_athlete_events;
-- drop table if exists public.coach_athlete_seen;
