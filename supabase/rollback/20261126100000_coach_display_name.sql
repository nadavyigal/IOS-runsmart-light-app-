-- Rollback for 20261126100000_coach_display_name.sql (names fix, 2026-11-26).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first.
--
-- Data-preserving: the migration created one function and no tables or columns. Names
-- coaches already saved stay in coach_profiles.display_name; only the RPC goes away.
--
-- What clients see after this runs: Coach > menu > Your name fails to save with
-- "Couldn't save your name". Athletes keep seeing the last saved coach name.

begin;

drop function if exists public.set_coach_display_name(text);

commit;
