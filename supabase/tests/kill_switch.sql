-- Test for the server kill switch in 20261121100000_coach_v2_gate.sql (story
-- C7.12, folded into C7.0).
--
-- Proves:
--   * C7.12 AC1: with runtime_flags.coach_v2 = false, link_is_v2 is false for
--     every pair (TestFlight pair, App Store pair with a listed coach), and the
--     v2 roster read returns zero rows. Back on, both return. A missing coach_v2
--     row counts as off.
--   * C7.12 AC3: an authenticated client cannot read, insert, update or delete
--     runtime_flags; get_runtime_flags() returns only the allow-listed keys;
--     anon is denied.
--   * The migration seeds coach_v2, coach_v2_push and coach_v2_ai as enabled.
--
-- Every later v2 RPC adds its own case to this file (C7.12 DoD): with the flag
-- off, write RPCs raise v2_unavailable and read RPCs return zero rows.
--
-- Raises on the first failure; prints "kill_switch: PASS" otherwise.
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (after Stories 1.2 and 1.3, then the gate migration twice):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kill_switch.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'kill_switch.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now()),
  ('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e', 'active', now());

-- A-B: TestFlight pair, A unlisted. C-E: App Store pair, C listed.
insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight'),
  ('cccccccc-0000-4000-8000-00000000000c', true, 'app_store'),
  ('eeeeeeee-0000-4000-8000-00000000000e', true, 'app_store');
insert into public.coach_v2_pilot_coaches (coach_id) values ('cccccccc-0000-4000-8000-00000000000c');

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

create function pg_temp.expect_error(stmt text, expected_state text, label text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL: % succeeded but should have failed with %', label, expected_state;
exception when others then
  if sqlstate = 'P0001' and sqlerrm like 'FAIL:%' then raise; end if;
  if sqlstate <> expected_state then
    raise exception 'FAIL: % failed with % (%), expected %', label, sqlstate, sqlerrm, expected_state;
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
  pg_temp.expect_error(text, text, text), pg_temp.expect_count(text, int, text),
  pg_temp.expect_bool(boolean, boolean, text) to authenticated, anon;

-- Seed ------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from public.runtime_flags
      where key in ('coach_v2', 'coach_v2_push', 'coach_v2_ai') and enabled) <> 3 then
    raise exception 'FAIL: the three v2 flags are not seeded as enabled';
  end if;
end $$;

-- C7.12 AC1: flag on, then off, then on again ------------------------------------------
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  true, 'TestFlight pair with the flag on');
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e'),
  true, 'listed App Store pair with the flag on');

-- Nadav's runbook line.
update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2';

select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  false, 'TestFlight pair with the kill switch on');
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e'),
  false, 'listed App Store pair with the kill switch on');

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count('select 1 from public.coach_v2_roster_status()', 0, 'roster status with the kill switch on');
-- The client reads the switch: coach_v2 comes back false.
select pg_temp.expect_count(
  $q$select 1 from public.get_runtime_flags() where key = 'coach_v2' and not enabled$q$,
  1, 'client sees coach_v2 = false');
-- Capability reports still work, so the server knows which clients are v2 when the flag returns.
select public.report_client_capabilities(true, '1.2.7', 50, 'testflight');
reset role;

-- The pilot list is untouched by the switch.
do $$
begin
  if not exists (select 1 from public.coach_v2_pilot_coaches where coach_id = 'cccccccc-0000-4000-8000-00000000000c') then
    raise exception 'FAIL: the kill switch changed the pilot list';
  end if;
end $$;

update public.runtime_flags set enabled = true, updated_at = now() where key = 'coach_v2';
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  true, 'TestFlight pair after the flag is back on');
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count('select 1 from public.coach_v2_roster_status()', 1, 'roster status after the flag is back on');
reset role;

-- A missing coach_v2 row fails closed.
delete from public.runtime_flags where key = 'coach_v2';
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  false, 'missing coach_v2 row');
insert into public.runtime_flags (key, enabled) values ('coach_v2', true);

-- C7.12 AC3: clients cannot touch runtime_flags; only allow-listed keys come back ----------
insert into public.runtime_flags (key, enabled, note) values ('internal_only', true, 'never returned to clients');

set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error(
  $q$select * from public.runtime_flags$q$, '42501', 'client reads runtime_flags');
select pg_temp.expect_error(
  $q$insert into public.runtime_flags (key, enabled) values ('coach_v2_extra', true)$q$, '42501', 'client inserts a flag');
select pg_temp.expect_error(
  $q$update public.runtime_flags set enabled = false$q$, '42501', 'client updates a flag');
select pg_temp.expect_error(
  $q$delete from public.runtime_flags$q$, '42501', 'client deletes a flag');
select pg_temp.expect_count('select 1 from public.get_runtime_flags()', 3, 'allow-listed flags');
select pg_temp.expect_count(
  $q$select 1 from public.get_runtime_flags() where key not in ('coach_v2', 'coach_v2_push', 'coach_v2_ai')$q$,
  0, 'non-allow-listed flag returned');
reset role;

set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error(
  $q$select * from public.get_runtime_flags()$q$, '42501', 'anon calls get_runtime_flags');
select pg_temp.expect_error(
  $q$select * from public.runtime_flags$q$, '42501', 'anon reads runtime_flags');
reset role;

do $$
begin
  if (select enabled from public.runtime_flags where key = 'coach_v2_push') is not true then
    raise exception 'FAIL: a client changed coach_v2_push';
  end if;
end $$;

do $$ begin raise notice 'kill_switch: PASS'; end $$;

rollback;
