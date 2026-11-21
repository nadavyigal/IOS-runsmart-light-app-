-- Rollback for 20261121100000_coach_v2_gate.sql (C7.0 + C7.12, M0 + M0b, Batch A).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- flipping runtime_flags.coach_v2 to false is the first move, and it needs no
-- rollback at all. Use this file only when the M0 functions themselves are
-- broken.
--
-- Do not run it while any later v2 migration is applied. Every later v2 RPC
-- calls link_is_v2, so dropping it breaks them. Roll back newer batches first,
-- newest file first.
--
-- Data-preserving: drops the functions only. The three tables and their rows
-- stay (capability rows, Nadav's flag values, the pilot coach list). With the
-- functions gone, no client can read or write them: RLS stays on and clients
-- have no table grant except select on their own capability row.
-- Re-applying the migration later restores the functions and keeps the rows.
--
-- What breaks for clients after this runs: the v2 app calls to
-- report_client_capabilities, get_runtime_flags, coach_v2_pilot_access and
-- coach_v2_roster_status fail. The app treats a failed flag read as "v2 off", so
-- every build shows the 1.2.6 coach UI. Nothing else changes.

begin;

drop function if exists public.coach_v2_roster_status();
drop function if exists public.link_is_v2(uuid, uuid);
drop function if exists public.coach_v2_pilot_access();
drop function if exists public.get_runtime_flags();
drop function if exists public.report_client_capabilities(boolean, text, integer, text, text);

-- Optional, destructive, and NOT part of the default rollback. Export the rows
-- first if you ever need them, then remove the leading "-- " to run:
-- drop table if exists public.coach_v2_pilot_coaches;
-- drop table if exists public.runtime_flags;
-- drop table if exists public.client_capabilities;

commit;
