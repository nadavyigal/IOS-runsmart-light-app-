-- Test for 20261121100000_coach_v2_gate.sql: client capabilities, link_is_v2,
-- and the N1 = B pilot-coach allowlist (story C7.0).
--
-- Users: A and C are coaches. B, E, F, G are athletes. D has no role.
--   A-B active, C-E active, A-G active (G is a 1.2.6 client: no capability row),
--   A-F revoked.
-- Proves:
--   * C7.0 AC5: report_client_capabilities writes only the caller's row; a
--     client cannot insert or update any row directly or read another user's
--     row; anon is denied; bad input is rejected.
--   * C7.0 AC4: link_is_v2 is true only when both rows say coach_v2 = true and
--     the link is active (the four combinations, a missing row, a revoked link,
--     and an unlinked pair). Clients cannot call link_is_v2.
--   * N1 = B: coach_v2_pilot_access() for a listed coach, an unlisted coach, an
--     athlete linked to a listed coach, an athlete with a revoked link to a
--     listed coach, and a user with no role. App Store pairs turn on only with a
--     listed coach, a forged coach report alone turns nothing on, and removing a
--     coach from the list turns the pair off on the next call.
--   * coach_v2_roster_status() returns the caller's active athletes only.
--   * Shape: RLS on, no client write policy, search_path = '' on every function,
--     rows cascade when the auth user is deleted.
-- Raises on the first failure; prints "client_capabilities: PASS" otherwise.
--
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (after Stories 1.2 and 1.3, then this migration twice to prove idempotence):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/client_capabilities.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'client_capabilities.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'third-d@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated'),
  ('ffffffff-0000-4000-8000-00000000000f', 'athlete-f@example.com', 'authenticated', 'authenticated'),
  ('99999999-0000-4000-8000-000000000009', 'athlete-g@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at, revoked_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now(), null),
  ('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e', 'active', now(), null),
  ('aaaaaaaa-0000-4000-8000-00000000000a', '99999999-0000-4000-8000-000000000009', 'active', now(), null),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f', 'revoked', now(), now());

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

-- Owner-side fixture writer for the combination cases. The client path is
-- covered by the AC5 section through the real RPC.
create function pg_temp.cap(uid text, v2 boolean, chan text) returns void language sql as $$
  insert into public.client_capabilities (user_id, coach_v2, channel)
  values (uid::uuid, v2, chan)
  on conflict (user_id) do update set coach_v2 = excluded.coach_v2, channel = excluded.channel;
$$;

grant execute on function pg_temp.act_as(text), pg_temp.act_as_anon(),
  pg_temp.expect_error(text, text, text), pg_temp.expect_count(text, int, text),
  pg_temp.expect_bool(boolean, boolean, text) to authenticated, anon;

-- Shape --------------------------------------------------------------------------
do $$
declare
  t text;
  f text;
begin
  foreach t in array array['client_capabilities', 'runtime_flags', 'coach_v2_pilot_coaches'] loop
    if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
      raise exception 'FAIL: RLS is off on %', t;
    end if;
  end loop;
  if exists (select 1 from pg_policies where schemaname = 'public'
             and tablename = 'client_capabilities' and cmd <> 'SELECT') then
    raise exception 'FAIL: client_capabilities has a client write policy';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public'
             and tablename in ('runtime_flags', 'coach_v2_pilot_coaches')) then
    raise exception 'FAIL: runtime_flags or coach_v2_pilot_coaches has a client policy';
  end if;
  foreach f in array array['report_client_capabilities', 'get_runtime_flags', 'coach_v2_pilot_access',
                           'link_is_v2', 'coach_v2_roster_status'] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f and p.prosecdef
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'FAIL: % is not security definer with search_path = ''''', f;
    end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'report_client_capabilities') <> 1 then
    raise exception 'FAIL: more than one report_client_capabilities signature';
  end if;
  if (select confdeltype from pg_constraint where conname = 'client_capabilities_user_id_fkey') <> 'c'
     or (select confdeltype from pg_constraint where conname = 'coach_v2_pilot_coaches_coach_id_fkey') <> 'c' then
    raise exception 'FAIL: a user FK does not cascade';
  end if;
  if exists (select 1 from public.coach_v2_pilot_coaches) then
    raise exception 'FAIL: coach_v2_pilot_coaches does not ship empty';
  end if;
end $$;

-- C7.0 AC5: own row only, anon denied ------------------------------------------------
set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error(
  $q$select public.report_client_capabilities(true, '1.2.7', 50, 'testflight')$q$,
  '42501', 'anon reports capabilities');
select pg_temp.expect_error(
  $q$select * from public.client_capabilities$q$, '42501', 'anon reads client_capabilities');
select pg_temp.expect_error(
  $q$select public.coach_v2_pilot_access()$q$, '42501', 'anon calls coach_v2_pilot_access');
select pg_temp.expect_error(
  $q$select * from public.coach_v2_roster_status()$q$, '42501', 'anon calls coach_v2_roster_status');
select pg_temp.expect_error(
  $q$select public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', 'anon calls link_is_v2');
reset role;

set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.report_client_capabilities(true, ' 1.2.7 ', 50, 'testflight');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.report_client_capabilities(false, '1.2.6', 46);

-- B sees only B's row, with what B sent.
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count('select 1 from public.client_capabilities', 1, 'B reads capability rows');
do $$
declare
  r public.client_capabilities;
begin
  select * into r from public.client_capabilities;
  if r.user_id <> 'bbbbbbbb-0000-4000-8000-00000000000b' or not r.coach_v2 or r.app_version <> '1.2.7'
     or r.build <> 50 or r.channel <> 'testflight' or r.platform <> 'ios' then
    raise exception 'FAIL: B row stored wrong: %', row_to_json(r);
  end if;
end $$;

-- Report again: same row, new values. Still one row for B.
select public.report_client_capabilities(false, '1.2.8', 51, 'app_store');
do $$
declare
  r public.client_capabilities;
begin
  select * into r from public.client_capabilities;
  if r.coach_v2 or r.build <> 51 or r.channel <> 'app_store' then
    raise exception 'FAIL: B second report stored wrong: %', row_to_json(r);
  end if;
end $$;

select pg_temp.expect_error(
  $q$insert into public.client_capabilities (user_id, coach_v2) values ('aaaaaaaa-0000-4000-8000-00000000000a', true)$q$,
  '42501', 'B inserts a row for A');
select pg_temp.expect_error(
  $q$insert into public.client_capabilities (user_id, coach_v2) values ('bbbbbbbb-0000-4000-8000-00000000000b', true)$q$,
  '42501', 'B inserts own row directly');
select pg_temp.expect_error(
  $q$update public.client_capabilities set coach_v2 = true$q$, '42501', 'direct update');
select pg_temp.expect_error(
  $q$delete from public.client_capabilities$q$, '42501', 'direct delete');
select pg_temp.expect_error(
  $q$select public.report_client_capabilities(true, '1.2.7', 50, 'enterprise')$q$,
  '22023', 'unknown channel');
select pg_temp.expect_error(
  $q$select public.report_client_capabilities(true, repeat('9', 33), 50, 'testflight')$q$,
  '22023', 'version over 32 characters');
select pg_temp.expect_error(
  $q$select public.report_client_capabilities(true, '1.2.7', -1, 'testflight')$q$,
  '22023', 'negative build');

-- Clients never touch the flag or allowlist tables, and cannot call link_is_v2.
select pg_temp.expect_error(
  $q$select * from public.coach_v2_pilot_coaches$q$, '42501', 'client reads the pilot list');
select pg_temp.expect_error(
  $q$insert into public.coach_v2_pilot_coaches (coach_id) values ('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', 'client adds itself to the pilot list');
select pg_temp.expect_error(
  $q$select public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', 'authenticated calls link_is_v2');
reset role;

do $$
begin
  if (select coach_v2 from public.client_capabilities where user_id = 'aaaaaaaa-0000-4000-8000-00000000000a')
     or (select channel from public.client_capabilities where user_id = 'aaaaaaaa-0000-4000-8000-00000000000a') <> 'app_store' then
    raise exception 'FAIL: B changed A''s row, or a missing channel was not stored as app_store';
  end if;
end $$;

-- C7.0 AC4: the four combinations, a missing row, a revoked link -------------------------
-- TestFlight on both sides, coach unlisted, so only rules 1 to 3 decide.
select pg_temp.cap('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight');
select pg_temp.cap('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight');
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  true, 'coach v2 + athlete v2');
select pg_temp.cap('bbbbbbbb-0000-4000-8000-00000000000b', false, 'testflight');
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  false, 'coach v2 + athlete not v2');
select pg_temp.cap('aaaaaaaa-0000-4000-8000-00000000000a', false, 'testflight');
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  false, 'coach not v2 + athlete not v2');
select pg_temp.cap('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight');
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  false, 'coach not v2 + athlete v2');
select pg_temp.cap('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight');

-- G never reported (a 1.2.6 client).
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', '99999999-0000-4000-8000-000000000009'),
  false, 'athlete with no capability row');
-- A-F was revoked.
select pg_temp.cap('ffffffff-0000-4000-8000-00000000000f', true, 'testflight');
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f'),
  false, 'revoked link');
-- C and B were never linked.
select pg_temp.cap('cccccccc-0000-4000-8000-00000000000c', true, 'testflight');
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  false, 'unlinked pair');
-- Swapped arguments are not the same pair.
select pg_temp.expect_bool(public.link_is_v2('bbbbbbbb-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-00000000000a'),
  false, 'coach and athlete swapped');

-- N1 = B: the pilot-coach allowlist ------------------------------------------------------
-- C is unlisted. C and E are on the App Store build. C forges coach_v2 = true.
select pg_temp.cap('cccccccc-0000-4000-8000-00000000000c', true, 'app_store');
select pg_temp.cap('eeeeeeee-0000-4000-8000-00000000000e', true, 'app_store');
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e'),
  false, 'App Store pair, unlisted coach, both claim v2');
-- An honest App Store athlete of an unlisted coach reports false: a forged coach report changes nothing.
select pg_temp.cap('eeeeeeee-0000-4000-8000-00000000000e', false, 'app_store');
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e'),
  false, 'forged coach report, honest App Store athlete');
-- Unlisted coach on TestFlight with an App Store athlete: off, whatever the athlete claims.
select pg_temp.cap('cccccccc-0000-4000-8000-00000000000c', true, 'testflight');
select pg_temp.cap('eeeeeeee-0000-4000-8000-00000000000e', true, 'app_store');
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e'),
  false, 'unlisted TestFlight coach, App Store athlete');

set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_bool(public.coach_v2_pilot_access(), false, 'unlisted coach pilot access');
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_bool(public.coach_v2_pilot_access(), false, 'athlete of unlisted coach pilot access');
reset role;

-- Nadav lists C.
insert into public.coach_v2_pilot_coaches (coach_id) values ('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.cap('cccccccc-0000-4000-8000-00000000000c', true, 'app_store');
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e'),
  true, 'App Store pair, listed coach, both v2');
select pg_temp.cap('eeeeeeee-0000-4000-8000-00000000000e', false, 'app_store');
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e'),
  false, 'listed coach, athlete not v2');
select pg_temp.cap('eeeeeeee-0000-4000-8000-00000000000e', true, 'app_store');

set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_bool(public.coach_v2_pilot_access(), true, 'listed coach pilot access');
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_bool(public.coach_v2_pilot_access(), true, 'athlete linked to a listed coach');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_bool(public.coach_v2_pilot_access(), false, 'athlete of an unlisted coach');
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_bool(public.coach_v2_pilot_access(), false, 'user with no role');
reset role;

-- Revoked link to a listed coach: no pilot access, no v2.
insert into public.coach_v2_pilot_coaches (coach_id) values ('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.cap('ffffffff-0000-4000-8000-00000000000f', true, 'app_store');
set local role authenticated;
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_bool(public.coach_v2_pilot_access(), false, 'athlete with a revoked link to a listed coach');
reset role;
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f'),
  false, 'revoked link to a listed coach');
delete from public.coach_v2_pilot_coaches where coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a';

-- Nadav removes C. The pair turns off on the next call, with no new report.
delete from public.coach_v2_pilot_coaches where coach_id = 'cccccccc-0000-4000-8000-00000000000c';
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e'),
  false, 'coach removed from the list');
set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_bool(public.coach_v2_pilot_access(), false, 'athlete after the coach was removed');
reset role;

-- Roster status (C7.0 AC6 data) ----------------------------------------------------------
-- A (unlisted, TestFlight): B is v2 on TestFlight, G never reported, F is revoked.
select pg_temp.cap('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight');
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count('select 1 from public.coach_v2_roster_status()', 2, 'A roster status rows');
select pg_temp.expect_count(
  $q$select 1 from public.coach_v2_roster_status() where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and athlete_is_v2$q$,
  1, 'B is v2 on A''s roster');
select pg_temp.expect_count(
  $q$select 1 from public.coach_v2_roster_status() where athlete_id = '99999999-0000-4000-8000-000000000009' and not athlete_is_v2$q$,
  1, 'G (1.2.6) needs the latest RunSmart');
-- C (unlisted): E is on the App Store build, so E needs the latest RunSmart from C's view.
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count(
  $q$select 1 from public.coach_v2_roster_status() where athlete_id = 'eeeeeeee-0000-4000-8000-00000000000e' and not athlete_is_v2$q$,
  1, 'App Store athlete of an unlisted coach');
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_count('select 1 from public.coach_v2_roster_status()', 0, 'no-role user roster status');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count('select 1 from public.coach_v2_roster_status()', 0, 'athlete roster status');
reset role;

-- Account deletion: rows go with the auth user. -----------------------------------------
insert into public.coach_v2_pilot_coaches (coach_id) values ('cccccccc-0000-4000-8000-00000000000c');
delete from public.coach_athlete_links where coach_id = 'cccccccc-0000-4000-8000-00000000000c';
delete from public.coach_profiles where user_id = 'cccccccc-0000-4000-8000-00000000000c';
delete from auth.users where id = 'cccccccc-0000-4000-8000-00000000000c';
do $$
begin
  if exists (select 1 from public.client_capabilities where user_id = 'cccccccc-0000-4000-8000-00000000000c')
     or exists (select 1 from public.coach_v2_pilot_coaches where coach_id = 'cccccccc-0000-4000-8000-00000000000c') then
    raise exception 'FAIL: deleting the auth user left capability or pilot rows';
  end if;
end $$;

do $$ begin raise notice 'client_capabilities: PASS'; end $$;

rollback;
