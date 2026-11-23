-- Test for 20261122120000_workout_adherence_state.sql (story C7.6).
--
-- Proves:
--   * Shape: the three functions exist; anon and authenticated cannot execute
--     them, service_role can; coach_evening_summary_counts is security definer and
--     every function has search_path = ''.
--   * AC6: workout_adherence_boundary and workout_adherence_state give the
--     expected answer on every shared fixture (workout_adherence_fixtures.sql,
--     the same list the Swift WorkoutAdherenceParityTests reads): partial at 80%,
--     rest, extra, and the 20:00 cutoff in several zones, DST included. An
--     unknown zone is read as UTC.
--   * AC1: coach_evening_summary_counts for coach A (Asia/Jerusalem) on
--     2026-11-23 at 20:00 local:
--       missed 3: B (no run), G (partial run), K (no run by 20:00). Not I (done),
--         not M (completed, an unlinked run that day: matched by date), not J
--         (rest), not L (New York, before L's own 20:00).
--       open_flags 2: G's two open flags. Not I's resolved flag.
--       plan_changes 2: B (goal_change, twice: one athlete) and J (athlete_skip).
--         Not G's change from yesterday, not I's change after 20:00, not a
--         'left' event.
--     The next morning (a summary held through quiet hours): missed 4. K's run at
--     20:30 still does not count, and L's 20:00 has now passed with no run.
--   * AC7: E (consent v1, no ack), F (1.2.6 client, not v2) and H (revoked) add
--     nothing, though each has a missed workout, an open flag and a plan change.
--     With the coach_v2 kill switch off every count is 0. A coach with no link
--     gets 0.
--   * No name, note or flag text comes back: the result is three integers.
-- Raises on the first failure; prints "workout_adherence_state: PASS" otherwise.
--
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (CI's matrix row lists the same files):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_read_fixture.sql
--   then every prerequisite of the workout_adherence_state row in
--   .github/workflows/pr-checks.yml, in order (Batch A, M2a and M2b), then
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261122120000_workout_adherence_state.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261122120000_workout_adherence_state.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/workout_adherence_state.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'workout_adherence_state.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

create function pg_temp.u(c text) returns uuid language sql as $$
  select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(ascii(c)), 2, '0'))::uuid;
$$;
create function pg_temp.link(c text) returns uuid language sql as $$
  select ('11111111-0000-4000-8000-0000000000' || lpad(to_hex(ascii(c)), 2, '0'))::uuid;
$$;

insert into auth.users (id, email, aud, role)
select pg_temp.u(c), 'user-' || lower(c) || '@example.com', 'authenticated', 'authenticated'
from unnest(array['A', 'C', 'B', 'G', 'I', 'J', 'K', 'L', 'M', 'E', 'F', 'H']) as c;

insert into public.coach_profiles (user_id, display_name) values
  (pg_temp.u('A'), 'Dana'),
  (pg_temp.u('C'), 'Ron');

-- Every athlete of A. E: consent v1 (no ack). H: revoked.
insert into public.coach_athlete_links
  (id, coach_id, athlete_id, status, consented_at, revoked_at, consent_version, consent_acknowledged_at)
select pg_temp.link(c), pg_temp.u('A'), pg_temp.u(c),
       case when c = 'H' then 'revoked' else 'active' end,
       now() - interval '30 days',
       case when c = 'H' then now() - interval '1 day' end,
       case when c = 'E' then 1 else 2 end,
       case when c = 'E' then null else now() - interval '20 days' end
from unnest(array['B', 'G', 'I', 'J', 'K', 'L', 'M', 'E', 'F', 'H']) as c;

-- F has no capability row: a 1.2.6 client.
insert into public.client_capabilities (user_id, coach_v2, channel)
select pg_temp.u(c), true, 'testflight'
from unnest(array['A', 'C', 'B', 'G', 'I', 'J', 'K', 'L', 'M', 'E', 'H']) as c;

-- The coach's zone, and L's own zone (New York). Other athletes have no prefs row,
-- so they are read in the coach's zone.
insert into public.notification_prefs (user_id, time_zone) values
  (pg_temp.u('A'), 'Asia/Jerusalem'),
  (pg_temp.u('L'), 'America/New_York');

-- One active plan per athlete.
insert into public.plans (id, profile_id, auth_user_id, title, start_date, end_date, is_active)
select pg_temp.link(c), pg_temp.u(c), pg_temp.u(c), 'Plan', date '2026-11-01', date '2026-12-31', true
from unnest(array['B', 'G', 'I', 'J', 'K', 'L', 'M', 'E', 'F', 'H']) as c;

-- 2026-11-23: a 5 km easy run for everyone, a rest day for J. M's is marked completed.
insert into public.workouts (id, plan_id, auth_user_id, type, distance, scheduled_date, completed)
select pg_temp.u(c), pg_temp.link(c), pg_temp.u(c),
       case when c = 'J' then 'rest' else 'easy' end,
       case when c = 'J' then 0 else 5 end,
       date '2026-11-23',
       c = 'M'
from unnest(array['B', 'G', 'I', 'J', 'K', 'L', 'M', 'E', 'F', 'H']) as c;

-- Runs (distance km, duration s). Israel is UTC+2: 20:00 local is 18:00Z.
insert into public.runs (auth_user_id, workout_id, distance, duration, completed_at) values
  (pg_temp.u('G'), pg_temp.u('G'), 3, 1200, '2026-11-23T12:00:00Z'),  -- partial
  (pg_temp.u('I'), pg_temp.u('I'), 5, 1800, '2026-11-23T12:00:00Z'),  -- done
  (pg_temp.u('K'), pg_temp.u('K'), 5, 1800, '2026-11-23T18:30:00Z'),  -- after 20:00
  (pg_temp.u('M'), null, 5, 1800, '2026-11-23T10:00:00Z'),            -- matched by date
  (pg_temp.u('J'), null, 4, 1500, '2026-11-23T10:00:00Z');            -- extra on a rest day

insert into public.athlete_run_flags (id, athlete_id, link_id, kind, created_at, resolved_at) values
  (gen_random_uuid(), pg_temp.u('G'), pg_temp.link('G'), 'pain', '2026-11-23T09:00:00Z', null),
  (gen_random_uuid(), pg_temp.u('G'), pg_temp.link('G'), 'off', '2026-11-20T09:00:00Z', null),
  (gen_random_uuid(), pg_temp.u('I'), pg_temp.link('I'), 'pain', '2026-11-23T09:00:00Z', '2026-11-23T10:00:00Z'),
  (gen_random_uuid(), pg_temp.u('E'), pg_temp.link('E'), 'pain', '2026-11-23T09:00:00Z', null),
  (gen_random_uuid(), pg_temp.u('F'), pg_temp.link('F'), 'pain', '2026-11-23T09:00:00Z', null),
  (gen_random_uuid(), pg_temp.u('H'), pg_temp.link('H'), 'pain', '2026-11-22T09:00:00Z', null);

insert into public.coach_athlete_events (coach_id, athlete_id, kind, created_at) values
  (pg_temp.u('A'), pg_temp.u('B'), 'goal_change', '2026-11-23T08:00:00Z'),
  (pg_temp.u('A'), pg_temp.u('B'), 'goal_change', '2026-11-23T09:00:00Z'),
  (pg_temp.u('A'), pg_temp.u('J'), 'athlete_skip', '2026-11-23T09:00:00Z'),
  (pg_temp.u('A'), pg_temp.u('G'), 'goal_change', '2026-11-22T20:00:00Z'),  -- 22:00 on the 22nd, local
  (pg_temp.u('A'), pg_temp.u('I'), 'athlete_move', '2026-11-23T18:30:00Z'), -- after 20:00
  (pg_temp.u('A'), pg_temp.u('K'), 'left', '2026-11-23T09:00:00Z'),
  (pg_temp.u('A'), pg_temp.u('E'), 'goal_change', '2026-11-23T09:00:00Z'),
  (pg_temp.u('A'), pg_temp.u('F'), 'goal_change', '2026-11-23T09:00:00Z'),
  (pg_temp.u('A'), pg_temp.u('H'), 'goal_change', '2026-11-23T09:00:00Z');

-- Shape: server-only ------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.workout_adherence_boundary(timestamptz, text)',
    'public.workout_adherence_state(text, numeric, integer, date, numeric, integer, date)',
    'public.coach_evening_summary_counts(uuid, date, text, timestamptz)'
  ] loop
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'FAIL: anon may execute %', f;
    end if;
    if has_function_privilege('authenticated', f, 'execute') then
      raise exception 'FAIL: authenticated may execute %', f;
    end if;
    if not has_function_privilege('service_role', f, 'execute') then
      raise exception 'FAIL: service_role may not execute %', f;
    end if;
    if not exists (
      select 1 from pg_proc where oid = f::regprocedure and proconfig @> array['search_path=""']
    ) then
      raise exception 'FAIL: % has no empty search_path', f;
    end if;
  end loop;
  if not (select prosecdef from pg_proc where oid = 'public.coach_evening_summary_counts(uuid, date, text, timestamptz)'::regprocedure) then
    raise exception 'FAIL: coach_evening_summary_counts is not security definer';
  end if;
  if (select prosecdef from pg_proc where oid = 'public.workout_adherence_state(text, numeric, integer, date, numeric, integer, date)'::regprocedure) then
    raise exception 'FAIL: workout_adherence_state should not be security definer';
  end if;
end $$;

-- AC6: the shared fixtures ------------------------------------------------------------
\ir workout_adherence_fixtures.sql

do $$
declare
  f record;
  got_boundary date;
  got_state text;
  n integer := 0;
begin
  for f in select * from workout_adherence_fixtures loop
    got_boundary := public.workout_adherence_boundary(f.now, f.time_zone);
    if got_boundary is distinct from f.boundary then
      raise exception 'FAIL: fixture "%": boundary %, expected %', f.name, got_boundary, f.boundary;
    end if;
    got_state := public.workout_adherence_state(
      f.type, f.planned_distance, f.planned_duration_minutes, f.scheduled_date,
      f.run_distance_km, f.run_duration_seconds, got_boundary);
    if got_state is distinct from f.state then
      raise exception 'FAIL: fixture "%": state %, expected %', f.name, got_state, f.state;
    end if;
    n := n + 1;
  end loop;
  if n < 15 then
    raise exception 'FAIL: only % fixtures ran', n;
  end if;

  -- An unknown zone is UTC.
  if public.workout_adherence_boundary('2026-11-23T20:30:00Z', 'Not/AZone') <> date '2026-11-24'
     or public.workout_adherence_boundary('2026-11-23T19:30:00Z', 'Not/AZone') <> date '2026-11-23' then
    raise exception 'FAIL: an unknown zone is not read as UTC';
  end if;
  -- Neither a workout nor a run: nothing.
  if public.workout_adherence_state(null, null, null, null, null, null, date '2026-11-23') is not null then
    raise exception 'FAIL: no workout and no run gave a state';
  end if;
end $$;

-- AC1, AC7: the counts, as the sender ----------------------------------------------------
set local role service_role;

create function pg_temp.expect_counts(
  p_coach uuid, p_now timestamptz, p_missed integer, p_flags integer, p_changes integer, label text
) returns void language plpgsql as $$
declare
  c record;
begin
  select * into c from public.coach_evening_summary_counts(p_coach, date '2026-11-23', 'Asia/Jerusalem', p_now);
  if c.missed is distinct from p_missed or c.open_flags is distinct from p_flags
     or c.plan_changes is distinct from p_changes then
    raise exception 'FAIL: % counts were % / % / %, expected % / % / %', label,
      c.missed, c.open_flags, c.plan_changes, p_missed, p_flags, p_changes;
  end if;
end $$;

select pg_temp.expect_counts(pg_temp.u('A'), '2026-11-23T18:00:00Z', 3, 2, 2, 'A at 20:00');
-- A summary held through quiet hours, counted again the next morning.
select pg_temp.expect_counts(pg_temp.u('A'), '2026-11-24T05:00:00Z', 4, 2, 2, 'A the next morning');
-- Before anybody's cutoff: nothing missed yet.
select pg_temp.expect_counts(pg_temp.u('A'), '2026-11-23T12:00:00Z', 0, 2, 2, 'A at 14:00');
select pg_temp.expect_counts(pg_temp.u('C'), '2026-11-23T18:00:00Z', 0, 0, 0, 'C (no athletes)');

do $$
begin
  if (select count(*) from public.coach_evening_summary_counts(pg_temp.u('A'), date '2026-11-23', 'Asia/Jerusalem', '2026-11-23T18:00:00Z')) <> 1 then
    raise exception 'FAIL: counts did not return exactly one row';
  end if;
end $$;

-- G's flag resolved: one open flag left.
reset role;
update public.athlete_run_flags set resolved_at = '2026-11-23T17:00:00Z'
where athlete_id = pg_temp.u('G') and kind = 'pain';
set local role service_role;
select pg_temp.expect_counts(pg_temp.u('A'), '2026-11-23T18:00:00Z', 3, 1, 2, 'A after a flag was handled');

-- E acks consent v2: E's miss, flag and change now count.
reset role;
update public.coach_athlete_links set consent_version = 2, consent_acknowledged_at = now()
where id = pg_temp.link('E');
set local role service_role;
select pg_temp.expect_counts(pg_temp.u('A'), '2026-11-23T18:00:00Z', 4, 2, 3, 'A after E acked');

-- The kill switch: nothing counts.
reset role;
update public.runtime_flags set enabled = false where key = 'coach_v2';
set local role service_role;
select pg_temp.expect_counts(pg_temp.u('A'), '2026-11-23T18:00:00Z', 0, 0, 0, 'A with coach_v2 off');
reset role;
update public.runtime_flags set enabled = true where key = 'coach_v2';

-- A client cannot call the counts.
set local role authenticated;
do $$
begin
  perform * from public.coach_evening_summary_counts(pg_temp.u('A'), date '2026-11-23', 'Asia/Jerusalem');
  raise exception 'FAIL: authenticated called the counts';
exception when insufficient_privilege then
  null;
end $$;
reset role;

do $$ begin raise notice 'workout_adherence_state: PASS'; end $$;

rollback;
