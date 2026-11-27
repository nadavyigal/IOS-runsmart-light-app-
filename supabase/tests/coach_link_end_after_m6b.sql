-- C8.1b (M6b) AC4: C7.11's coach_link_end suite, run again with M6a and M6b on
-- top, so the parity test and every M5b case stay green against the M6b
-- end_coach_link (lock release added). CI's matrix row applies the same files as
-- coach_link_end, then 20261122100000_push_tokens_and_prefs,
-- 20261127100000_coach_workout_locks and 20261127110000_coach_plan_locks (twice),
-- on coach_plan_locks_fixture.sql.
--
-- THROWAWAY DATABASES ONLY. coach_link_end.sql refuses a non-empty auth.users.

\ir coach_link_end.sql
