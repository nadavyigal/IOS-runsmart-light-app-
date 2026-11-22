-- Test for 20261121130000_coach_last_seen_and_events.sql (story C7.2, M3).
--
-- Users: A (Dana) and C (Ron) are coaches. B, E, F, G, H are athletes.
--   A: TestFlight, v2.            C: TestFlight, v2, not linked to B.
--   B: TestFlight, v2, linked to A (the v2 pair).
--   E: a 1.2.6 client (no capability row), linked to A (not a v2 pair).
--   F: TestFlight, v2, no link.   G: no link, used for the account-deletion case.
--   H: TestFlight, v2, had a link to A that was revoked.
-- Proves:
--   * Shape: both tables have RLS on with no client grant or policy, the kind
--     check holds the five kinds (defined once here), every new function is
--     security definer with search_path = '', anon is denied on every function.
--   * Seen (AC1): the coach's write stores seen_at, cuts a future time to now(),
--     only moves forward, and is idempotent (one row, same value on repeat).
--   * Denied: another coach, a revoked link and anon cannot write or read seen
--     state or events (link_inactive / zero rows / 42501). A pair that is not v2
--     raises v2_unavailable and writes nothing.
--   * Goal change (AC3, AC4, AC5): the linked v2 athlete logs goal_change once per
--     client id; no active link returns false and writes nothing; a revoked
--     athlete and a coach calling it get false; a pair that is not v2 raises
--     v2_unavailable.
--   * Counts (AC2): coach_roster_summary counts runs and goal/workout events after
--     seen_at, never future runs, never left/removed, never further back than
--     7 days, and drops to zero after the coach opens the athlete. Rows only for
--     the caller's active v2 athletes.
--   * coach_get_athlete_events: own active v2 athlete only, p_since filters.
--   * Account deletion: deleting the auth user removes the user's seen and event
--     rows (on delete cascade).
-- The kill-switch case for these RPCs lives in kill_switch.sql (C7.12 DoD).
-- Raises on the first failure; prints "coach_last_seen: PASS" otherwise.
--
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (coach_read_fixture for runs and profiles, then Stories 1.2, 1.3, 1.5, 2.2,
-- the gate, then this migration twice; CI's matrix row lists the same files):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_read_fixture.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115194500_leave_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117164500_coach_read_rpcs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121130000_coach_last_seen_and_events.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121130000_coach_last_seen_and_events.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_last_seen.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_last_seen.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated'),
  ('ffffffff-0000-4000-8000-00000000000f', 'athlete-f@example.com', 'authenticated', 'authenticated'),
  ('99999999-0000-4000-8000-000000000009', 'athlete-g@example.com', 'authenticated', 'authenticated'),
  ('88888888-0000-4000-8000-000000000008', 'athlete-h@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at, revoked_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now() - interval '30 days', null),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-00000000000e', 'active', now() - interval '30 days', null),
  ('aaaaaaaa-0000-4000-8000-00000000000a', '88888888-0000-4000-8000-000000000008', 'revoked', now() - interval '30 days', now() - interval '1 day');

insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight'),
  ('cccccccc-0000-4000-8000-00000000000c', true, 'testflight'),
  ('ffffffff-0000-4000-8000-00000000000f', true, 'testflight'),
  ('88888888-0000-4000-8000-000000000008', true, 'testflight');

create function pg_temp.act_as(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
end $$;

-- expected_message null checks only the SQLSTATE.
create function pg_temp.expect_error(stmt text, expected_state text, expected_message text, label text)
returns void language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL: % succeeded but should have failed with %', label, expected_state;
exception when others then
  if sqlstate = 'P0001' and sqlerrm like 'FAIL:%' then raise; end if;
  if sqlstate <> expected_state then
    raise exception 'FAIL: % failed with % (%), expected %', label, sqlstate, sqlerrm, expected_state;
  end if;
  if expected_message is not null and sqlerrm <> expected_message then
    raise exception 'FAIL: % failed with message "%", expected "%"', label, sqlerrm, expected_message;
  end if;
end $$;

create function pg_temp.expect_count(stmt text, expected int, label text) returns void
language plpgsql as $$
declare
  n int;
begin
  execute 'select count(*) from (' || stmt || ') q' into n;
  if n <> expected then
    raise exception 'FAIL: % returned % rows, expected %', label, n, expected;
  end if;
end $$;

create function pg_temp.expect_bool(actual boolean, expected boolean, label text) returns void
language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL: % was %, expected %', label, actual, expected;
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.act_as_anon(),
  pg_temp.expect_error(text, text, text, text), pg_temp.expect_count(text, int, text),
  pg_temp.expect_bool(boolean, boolean, text) to authenticated, anon;

-- Shape -------------------------------------------------------------------------------
do $$
declare
  fn text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.coach_athlete_seen'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.coach_athlete_events'::regclass) then
    raise exception 'FAIL: RLS is off on a new table';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public'
             and tablename in ('coach_athlete_seen', 'coach_athlete_events')) then
    raise exception 'FAIL: a new table has a client policy';
  end if;
  if has_table_privilege('authenticated', 'public.coach_athlete_seen', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.coach_athlete_events', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.coach_athlete_seen', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.coach_athlete_events', 'select,insert,update,delete') then
    raise exception 'FAIL: a client role has a table grant on a new table';
  end if;
  foreach fn in array array[
    'public.coach_mark_athlete_seen(uuid, timestamptz)',
    'public.athlete_log_goal_change(uuid)',
    'public.coach_get_athlete_events(uuid, timestamptz)',
    'public.coach_roster_summary()'
  ] loop
    if not exists (
      select 1 from pg_proc
      where oid = fn::regprocedure and prosecdef
        and proconfig @> array['search_path=""']
    ) then
      raise exception 'FAIL: % is not security definer with search_path = ''''', fn;
    end if;
    if has_function_privilege('anon', fn, 'execute') then
      raise exception 'FAIL: anon can execute %', fn;
    end if;
    if not has_function_privilege('authenticated', fn, 'execute') then
      raise exception 'FAIL: authenticated cannot execute %', fn;
    end if;
  end loop;
end $$;

-- The five kinds are accepted, anything else is rejected.
insert into public.coach_athlete_events (coach_id, athlete_id, kind, created_at)
select 'aaaaaaaa-0000-4000-8000-00000000000a', '99999999-0000-4000-8000-000000000009', k, now() - interval '30 days'
from unnest(array['athlete_skip', 'athlete_move', 'goal_change', 'left', 'removed']) k;
select pg_temp.expect_error(
  $q$insert into public.coach_athlete_events (coach_id, athlete_id, kind)
     values ('aaaaaaaa-0000-4000-8000-00000000000a', '99999999-0000-4000-8000-000000000009', 'praise')$q$,
  '23514', null, 'unknown event kind');

-- Clients cannot touch the tables directly.
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_error($q$select * from public.coach_athlete_seen$q$, '42501', null, 'coach reads seen table');
select pg_temp.expect_error($q$select * from public.coach_athlete_events$q$, '42501', null, 'coach reads events table');
select pg_temp.expect_error(
  $q$insert into public.coach_athlete_seen (coach_id, athlete_id, seen_at)
     values ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', now())$q$,
  '42501', null, 'coach inserts a seen row');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error(
  $q$insert into public.coach_athlete_events (coach_id, athlete_id, kind)
     values ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'goal_change')$q$,
  '42501', null, 'athlete inserts an event row');
reset role;

-- anon is denied on every function.
set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error(
  $q$select public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b')$q$, '42501', null, 'anon marks seen');
select pg_temp.expect_error($q$select public.athlete_log_goal_change()$q$, '42501', null, 'anon logs a goal change');
select pg_temp.expect_error(
  $q$select * from public.coach_get_athlete_events('bbbbbbbb-0000-4000-8000-00000000000b')$q$, '42501', null, 'anon reads events');
select pg_temp.expect_error($q$select * from public.coach_roster_summary()$q$, '42501', null, 'anon reads the summary');
reset role;

-- Runs for B: one before seen_at, two after it, one in the future, one older than 7 days.
-- Runs for E (not a v2 pair) and H (revoked) that must never be counted for A.
insert into public.runs (auth_user_id, type, distance, duration, completed_at) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5, 1800, now() - interval '3 hours'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5, 1800, now() - interval '90 minutes'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'tempo', 6, 1900, now() - interval '30 minutes'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5, 1800, now() + interval '1 day'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'long', 12, 4200, now() - interval '10 days'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'easy', 5, 1800, now() - interval '30 minutes'),
  ('88888888-0000-4000-8000-000000000008', 'easy', 5, 1800, now() - interval '30 minutes');

-- Never opened: the last 7 days count. 4 runs inside the window, minus the future one = 3.
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary()
     where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and seen_at is null
       and new_runs = 3 and new_flags = 0 and new_replies = 0 and new_events = 0
       and latest_event_kind is null$q$,
  1, 'never-opened athlete: last 7 days of runs, future run excluded');
-- Only the v2 pair comes back: not E (1.2.6), not H (revoked).
select pg_temp.expect_count('select 1 from public.coach_roster_summary()', 1, 'summary rows for coach A');
reset role;

-- AC1: the coach opens B ----------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 where public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b', now() - interval '2 hours')
       = now() - interval '2 hours'$q$,
  1, 'seen stored at the phone time');
-- Repeat: idempotent, same value.
select pg_temp.expect_count(
  $q$select 1 where public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b', now() - interval '2 hours')
       = now() - interval '2 hours'$q$,
  1, 'repeated seen keeps the value');
-- A late flush from an older open never moves it back.
select pg_temp.expect_count(
  $q$select 1 where public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b', now() - interval '5 hours')
       = now() - interval '2 hours'$q$,
  1, 'older seen does not move it back');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary()
     where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and seen_at = now() - interval '2 hours'
       and new_runs = 2 and new_events = 0 and oldest_new_at = now() - interval '90 minutes'$q$,
  1, 'two runs after seen_at');
reset role;
do $$
begin
  if (select count(*) from public.coach_athlete_seen) <> 1 then
    raise exception 'FAIL: repeated seen writes stored more than one row';
  end if;
end $$;

-- AC3: B saves a new goal ----------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_bool(public.athlete_log_goal_change('11111111-0000-4000-8000-000000000001'), true, 'B logs a goal change');
-- The outbox flushes the same item twice: one row.
select pg_temp.expect_bool(public.athlete_log_goal_change('11111111-0000-4000-8000-000000000001'), true, 'repeated client id');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary()
     where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
       and new_runs = 2 and new_events = 1 and latest_event_kind = 'goal_change'$q$,
  1, 'coach sees the goal change as new');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_events('bbbbbbbb-0000-4000-8000-00000000000b') where kind = 'goal_change'$q$,
  1, 'coach reads the goal change event');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_events('bbbbbbbb-0000-4000-8000-00000000000b', now())$q$,
  0, 'p_since filters out older events');
reset role;
do $$
begin
  if (select count(*) from public.coach_athlete_events
      where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and kind = 'goal_change') <> 1 then
    raise exception 'FAIL: a repeated client id stored a second goal_change row';
  end if;
end $$;

-- left/removed are never counted as new, even for an active pair.
insert into public.coach_athlete_events (coach_id, athlete_id, kind)
values ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'left');
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary()
     where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and new_events = 1 and latest_event_kind = 'goal_change'$q$,
  1, 'left event not counted');
-- Opening B again (a second coach phone does the same): everything is seen.
select public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary()
     where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and seen_at = now()
       and new_runs = 0 and new_events = 0 and latest_event_kind is null and oldest_new_at is null$q$,
  1, 'all seen after opening');
-- A future time is cut to now().
select pg_temp.expect_count(
  $q$select 1 where public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b', now() + interval '1 day') = now()$q$,
  1, 'future seen cut to now');
reset role;

-- AC4: goal change without an active link, or by the wrong user ---------------------------
set local role authenticated;
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_bool(public.athlete_log_goal_change(), false, 'no link returns false');
select pg_temp.act_as('88888888-0000-4000-8000-000000000008');
select pg_temp.expect_bool(public.athlete_log_goal_change(), false, 'revoked athlete returns false');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_bool(public.athlete_log_goal_change(), false, 'coach has no link as an athlete');
-- Mixed versions: E is a 1.2.6 client, so the pair is not v2.
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_error($q$select public.athlete_log_goal_change()$q$, 'P0001', 'v2_unavailable', 'goal change on a non-v2 pair');
reset role;
do $$
begin
  if exists (select 1 from public.coach_athlete_events
             where athlete_id in ('ffffffff-0000-4000-8000-00000000000f', '88888888-0000-4000-8000-000000000008',
                                  'eeeeeeee-0000-4000-8000-00000000000e', 'aaaaaaaa-0000-4000-8000-00000000000a')) then
    raise exception 'FAIL: a goal change without an active v2 link wrote a row';
  end if;
end $$;

-- Denied: other coach, revoked link, non-v2 pair --------------------------------------------
-- An event for H (revoked) and for E (not v2), as if written before.
insert into public.coach_athlete_events (coach_id, athlete_id, kind) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', '88888888-0000-4000-8000-000000000008', 'goal_change'),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-00000000000e', 'goal_change');

set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_error(
  $q$select public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  'P0001', 'link_inactive', 'other coach marks seen');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_events('bbbbbbbb-0000-4000-8000-00000000000b')$q$, 0, 'other coach reads events');
select pg_temp.expect_count('select 1 from public.coach_roster_summary()', 0, 'other coach summary');

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_error(
  $q$select public.coach_mark_athlete_seen('88888888-0000-4000-8000-000000000008')$q$,
  'P0001', 'link_inactive', 'revoked link marks seen');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_events('88888888-0000-4000-8000-000000000008')$q$, 0, 'revoked link reads events');
select pg_temp.expect_error(
  $q$select public.coach_mark_athlete_seen('eeeeeeee-0000-4000-8000-00000000000e')$q$,
  'P0001', 'v2_unavailable', 'non-v2 pair marks seen');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_events('eeeeeeee-0000-4000-8000-00000000000e')$q$, 0, 'non-v2 pair reads events');
select pg_temp.expect_error(
  $q$select public.coach_mark_athlete_seen(null)$q$, '22023', null, 'missing athlete');

-- The athlete cannot read the coach's view of them.
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_events('bbbbbbbb-0000-4000-8000-00000000000b')$q$, 0, 'athlete reads own events as coach');
select pg_temp.expect_count('select 1 from public.coach_roster_summary()', 0, 'athlete summary');
select pg_temp.expect_error(
  $q$select public.coach_mark_athlete_seen('aaaaaaaa-0000-4000-8000-00000000000a')$q$,
  'P0001', 'link_inactive', 'athlete marks the coach seen');
reset role;
do $$
begin
  if exists (select 1 from public.coach_athlete_seen
             where coach_id <> 'aaaaaaaa-0000-4000-8000-00000000000a'
                or athlete_id <> 'bbbbbbbb-0000-4000-8000-00000000000b') then
    raise exception 'FAIL: a denied seen write stored a row';
  end if;
end $$;

-- Account deletion: the auth user's rows go with it ------------------------------------------
insert into public.coach_athlete_seen (coach_id, athlete_id, seen_at)
values ('aaaaaaaa-0000-4000-8000-00000000000a', '99999999-0000-4000-8000-000000000009', now());
delete from auth.users where id = '99999999-0000-4000-8000-000000000009';
do $$
begin
  if exists (select 1 from public.coach_athlete_seen where athlete_id = '99999999-0000-4000-8000-000000000009')
     or exists (select 1 from public.coach_athlete_events where athlete_id = '99999999-0000-4000-8000-000000000009') then
    raise exception 'FAIL: deleting the auth user left seen or event rows';
  end if;
end $$;

do $$ begin raise notice 'coach_last_seen: PASS'; end $$;

rollback;
