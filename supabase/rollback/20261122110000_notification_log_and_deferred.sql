-- Rollback for 20261122110000_notification_log_and_deferred.sql (C7.5, M2b, Batch B).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- flipping runtime_flags.coach_v2_push to false is the first move for a push
-- problem, and it needs no rollback at all. Use this file only when the M2b
-- functions themselves are broken.
--
-- Before running it: delete the four Database Webhooks and the flush cron
-- (docs/coach-v2-batch-b-runbook.md), or coach_notify fails on every call.
--
-- Data-preserving:
--   * The three functions are dropped: coach_notify_claim, coach_notify_defer and
--     coach_notify_link_state.
--   * coach_notification_log and deferred_pushes stay, with every row, RLS on, no
--     policy and no client grant. A deleted user's rows still go through the
--     on delete cascade from auth.users.
--   * Re-applying the migration later finds both tables and changes no row.
--
-- What clients see after this runs: nothing. No client reads these tables or calls
-- these functions. coach_notify sends no coach or athlete push until the file is
-- re-applied.

begin;

drop function if exists public.coach_notify_defer(uuid, uuid, uuid, text, text, integer, jsonb);
drop function if exists public.coach_notify_claim(uuid, uuid, uuid, text, text, integer, integer, integer);
drop function if exists public.coach_notify_link_state(uuid);

commit;

-- Optional, destructive, NOT part of the rollback. Deletes every push log row (the
-- push metrics) and every held push. Export first, and only with a reason.
-- drop table if exists public.deferred_pushes;
-- drop table if exists public.coach_notification_log;
