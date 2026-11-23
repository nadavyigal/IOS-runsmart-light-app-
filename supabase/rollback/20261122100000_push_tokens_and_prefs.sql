-- Rollback for 20261122100000_push_tokens_and_prefs.sql (C7.10, M2a, Batch B).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- flipping runtime_flags.coach_v2_push to false is the first move for a push
-- problem, and it needs no rollback at all. Use this file only when the M2a
-- functions themselves are broken.
--
-- Do not run it while M2b (20261122110000_notification_log_and_deferred.sql) or any
-- later file that reads push_tokens or notification_prefs is applied. Roll back
-- newer files first, newest first.
--
-- Data-preserving:
--   * The six functions are dropped: register_push_token, unregister_push_token,
--     my_notification_prefs, set_notification_time_zone, update_notification_prefs
--     and the internal notification_time_zone_ok.
--   * push_tokens and notification_prefs stay, with every row, RLS on and their
--     owner-select policies. A deleted user's rows still go through the
--     on delete cascade from auth.users.
--   * Re-applying the migration later finds both tables and changes no row.
--
-- What clients see after this runs: v2 apps get "function not found" when they
-- register a token or read prefs. The app keeps its token on the phone and tries
-- again on the next foreground; nothing is shown to the user. Sign-out still works
-- (the unregister call fails quietly; the stale row is taken over by the next
-- account that registers this device). 1.2.6 apps see no change.

begin;

drop function if exists public.update_notification_prefs(boolean, boolean, boolean, boolean, boolean, boolean, time, time);
drop function if exists public.set_notification_time_zone(text);
drop function if exists public.my_notification_prefs(text);
drop function if exists public.unregister_push_token(text);
drop function if exists public.register_push_token(text, text, text);
drop function if exists public.notification_time_zone_ok(text);

commit;

-- Optional, destructive, NOT part of the rollback. Deletes every device token and
-- every user's notification settings. Export first, and only with a reason.
-- drop table if exists public.notification_prefs;
-- drop table if exists public.push_tokens;
