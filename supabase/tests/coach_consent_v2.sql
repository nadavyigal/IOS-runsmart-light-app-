-- Test for 20261121110000_coach_consent_v2.sql (story C7.8, M5a).
--
-- Users: A (Dana) and C (Ron) are coaches. B, E, F, G, H are athletes. D has no role.
--   A: TestFlight, v2, unlisted. C: App Store, v2, unlisted at first.
--   B: TestFlight, v2, linked to A before this migration (consent v1).
--   E: App Store, v2, linked to C before this migration (consent v1).
--   F: TestFlight, v2, joins A through the v2 path.
--   G: a 1.2.6 client (no capability row), joins A through join_coach.
--   H: TestFlight, v2, had a link to A that was revoked.
-- Proves:
--   * Shape: both columns exist, existing links read consent_version = 1 with no
--     ack, a v2 consent without an ack time is rejected, every new function is
--     security definer with search_path = '', clients cannot call
--     coach_v2_sharing_allowed, anon is denied everywhere.
--   * 1.2.6 compatibility: join_coach keeps its signature, still returns the
--     Story 1.3 payload, and writes consent_version = 1 with no ack.
--   * AC2: join_coach_v2(..., 2) creates the link with consent_version = 2 and
--     consent_acknowledged_at = consented_at, in the same call. Bad versions fail.
--     already_linked leaves the existing link's consent alone.
--   * AC3 + AC7 (server half): my_coach_consent_status says needs_v2_ack only for
--     a v1 link on a v2 pair; not for an App Store athlete whose coach is
--     unlisted, until the coach is listed. coach_invite_consent_version is 2 only
--     when the P8 copy applies.
--   * AC4: a failed ack (pair not v2) raises v2_unavailable and changes nothing,
--     so needs_v2_ack stays true and sharing stays off.
--   * AC5: an athlete who acked on TestFlight and later reports an App Store
--     build is never asked again (server state).
--   * AC6: ack by the coach, an unlinked user, a revoked athlete or anon fails.
--     A second ack is idempotent and keeps the first ack time.
--   * D7: coach_v2_sharing_allowed is false before the ack and true after.
--   * my_coach_consent_status returns the caller's own active link only.
-- The kill-switch case for these RPCs lives in kill_switch.sql (C7.12 DoD).
-- Raises on the first failure; prints "coach_consent_v2: PASS" otherwise.
--
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (after Stories 1.2 and 1.3 and the gate, then this migration twice):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121110000_coach_consent_v2.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121110000_coach_consent_v2.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_consent_v2.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_consent_v2.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'third-d@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated'),
  ('ffffffff-0000-4000-8000-00000000000f', 'athlete-f@example.com', 'authenticated', 'authenticated'),
  ('99999999-0000-4000-8000-000000000009', 'athlete-g@example.com', 'authenticated', 'authenticated'),
  ('88888888-0000-4000-8000-000000000008', 'athlete-h@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_invites (id, coach_id, code, active) values
  ('a1111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000a', 'DANA22', true),
  ('c3333333-0000-4000-8000-000000000003', 'cccccccc-0000-4000-8000-00000000000c', 'RONN33', true);

-- Links that existed before M5a get the column default (consent v1, no ack).
insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at, revoked_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now(), null),
  ('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e', 'active', now(), null),
  ('aaaaaaaa-0000-4000-8000-00000000000a', '88888888-0000-4000-8000-000000000008', 'revoked', now(), now());

insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight'),
  ('cccccccc-0000-4000-8000-00000000000c', true, 'app_store'),
  ('eeeeeeee-0000-4000-8000-00000000000e', true, 'app_store'),
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
    raise exception 'FAIL: % failed with "%", expected "%"', label, sqlerrm, expected_message;
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

create function pg_temp.expect_text(actual text, expected text, label text) returns void
language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL: % was %, expected %', label, actual, expected;
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.act_as_anon(),
  pg_temp.expect_error(text, text, text, text), pg_temp.expect_count(text, int, text),
  pg_temp.expect_bool(boolean, boolean, text), pg_temp.expect_text(text, text, text)
  to authenticated, anon;

-- Shape -----------------------------------------------------------------------------
do $$
declare
  f text;
begin
  if exists (select 1 from public.coach_athlete_links
             where consent_version <> 1 or consent_acknowledged_at is not null) then
    raise exception 'FAIL: an existing link did not get consent_version = 1 with no ack';
  end if;
  foreach f in array array['join_coach', 'join_coach_v2', 'coach_invite_consent_version',
                           'ack_coach_consent', 'my_coach_consent_status', 'coach_v2_sharing_allowed'] loop
    if exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f
        and not (p.prosecdef and p.proconfig @> array['search_path=""'])
    ) or not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f
    ) then
      raise exception 'FAIL: % is missing or not security definer with search_path = ''''', f;
    end if;
  end loop;
  -- 1.2.6 clients call the 4-argument join_coach. It must be the only join_coach.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'join_coach') <> 1
     or to_regprocedure('public.join_coach(text, uuid, uuid, uuid)') is null then
    raise exception 'FAIL: join_coach(text, uuid, uuid, uuid) is not the only join_coach';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'join_coach_v2') <> 1 then
    raise exception 'FAIL: more than one join_coach_v2 signature';
  end if;
end $$;

select pg_temp.expect_error(
  $q$insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at, consent_version)
     values ('cccccccc-0000-4000-8000-00000000000c', 'dddddddd-0000-4000-8000-00000000000d', 'active', now(), 2)$q$,
  '23514', null, 'v2 consent without an ack time');
select pg_temp.expect_error(
  $q$update public.coach_athlete_links set consent_version = 0
     where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'$q$,
  '23514', null, 'consent_version below 1');

-- AC7 (server half): which copy the join screen shows ---------------------------------
set local role authenticated;
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_text(public.coach_invite_consent_version('DANA22')::text, '2',
  'TestFlight athlete, TestFlight v2 coach: P8');
select pg_temp.expect_text(public.coach_invite_consent_version(' dana22 ')::text, '2',
  'code is trimmed and case-insensitive');
select pg_temp.expect_text(public.coach_invite_consent_version('RONN33')::text, '1',
  'App Store coach, unlisted: A3');
select pg_temp.expect_text(public.coach_invite_consent_version('NOPE99')::text, '1',
  'unknown code: A3');
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
select pg_temp.expect_text(public.coach_invite_consent_version('DANA22')::text, '1',
  'caller with no capability row: A3');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_text(public.coach_invite_consent_version('DANA22')::text, '1',
  'own code: A3');
reset role;

-- 1.2.6 compatibility: join_coach keeps consent v1 ------------------------------------
set local role authenticated;
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
do $$
declare
  r jsonb;
begin
  r := public.join_coach('DANA22', 'a1111111-0000-4000-8000-000000000001',
    'aaaaaaaa-0000-4000-8000-00000000000a', '99999999-0000-4000-8000-000000000009');
  if r->>'status' <> 'joined' or r->>'display_name' <> 'Dana'
     or r->>'link_id' is null or r->>'consented_at' is null
     or r->>'coach_id' <> 'aaaaaaaa-0000-4000-8000-00000000000a' then
    raise exception 'FAIL: join_coach payload changed: %', r;
  end if;
  if (r->>'consent_version')::int <> 1 or r ? 'consent_acknowledged_at' and r->'consent_acknowledged_at' <> 'null'::jsonb then
    raise exception 'FAIL: join_coach wrote consent other than v1 with no ack: %', r;
  end if;
end $$;
reset role;
select pg_temp.expect_count(
  $q$select 1 from public.coach_athlete_links where athlete_id = '99999999-0000-4000-8000-000000000009'
     and status = 'active' and consent_version = 1 and consent_acknowledged_at is null$q$,
  1, '1.2.6 join stored consent v1 with no ack');
select pg_temp.expect_bool(public.coach_v2_sharing_allowed('aaaaaaaa-0000-4000-8000-00000000000a',
  '99999999-0000-4000-8000-000000000009'), false, '1.2.6 athlete shares nothing');

-- AC2: v2 join writes version 2 and the ack in the same call ----------------------------
set local role authenticated;
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_error(
  $q$select public.join_coach_v2('DANA22', 'a1111111-0000-4000-8000-000000000001',
     'aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f', 3)$q$,
  '22023', 'bad_consent_version', 'join with consent version 3');
select pg_temp.expect_error(
  $q$select public.join_coach_v2('DANA22', 'a1111111-0000-4000-8000-000000000001',
     'aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f', null)$q$,
  '22023', 'bad_consent_version', 'join with no consent version');
select pg_temp.expect_error(
  $q$select public.join_coach_v2('DANA22', 'a1111111-0000-4000-8000-000000000001',
     'aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 2)$q$,
  '42501', 'consenting athlete changed', 'join for another athlete');
select pg_temp.expect_error(
  $q$select public.join_coach_v2('DANA22', 'c3333333-0000-4000-8000-000000000003',
     'aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f', 2)$q$,
  'P0001', 'consent_mismatch', 'join with a moved invite');
do $$
declare
  r jsonb;
begin
  r := public.join_coach_v2('DANA22', 'a1111111-0000-4000-8000-000000000001',
    'aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f', 2);
  if r->>'status' <> 'joined' or (r->>'consent_version')::int <> 2
     or r->>'consent_acknowledged_at' is null then
    raise exception 'FAIL: v2 join payload: %', r;
  end if;
end $$;
reset role;
select pg_temp.expect_count(
  $q$select 1 from public.coach_athlete_links where athlete_id = 'ffffffff-0000-4000-8000-00000000000f'
     and status = 'active' and consent_version = 2 and consent_acknowledged_at = consented_at$q$,
  1, 'v2 join stored version 2 with the ack at consent');
select pg_temp.expect_bool(public.coach_v2_sharing_allowed('aaaaaaaa-0000-4000-8000-00000000000a',
  'ffffffff-0000-4000-8000-00000000000f'), true, 'v2 joiner shares at once');

-- already_linked leaves the existing link's consent alone.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
do $$
declare
  r jsonb;
begin
  r := public.join_coach_v2('RONN33', 'c3333333-0000-4000-8000-000000000003',
    'cccccccc-0000-4000-8000-00000000000c', 'bbbbbbbb-0000-4000-8000-00000000000b', 2);
  if r->>'status' <> 'already_linked' or r->>'display_name' <> 'Dana' then
    raise exception 'FAIL: already-linked v2 join: %', r;
  end if;
end $$;
reset role;
select pg_temp.expect_count(
  $q$select 1 from public.coach_athlete_links where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
     and status = 'active' and consent_version = 1 and consent_acknowledged_at is null$q$,
  1, 'already_linked kept consent v1');

-- AC3: status for the caller's own link --------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status()
     where coach_display_name = 'Dana' and link_is_v2 and needs_v2_ack and not sharing_active$q$,
  1, 'v1 link on a v2 pair needs P9');
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status()
     where link_is_v2 and not needs_v2_ack and sharing_active$q$,
  1, 'v2 joiner never sees P9');
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status()
     where not link_is_v2 and not needs_v2_ack and not sharing_active$q$,
  1, '1.2.6 athlete: no P9 while their client is not v2');
-- Own link only: a coach, a user with no role and a revoked athlete get nothing.
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count('select 1 from public.my_coach_consent_status()', 0, 'coach reads consent status');
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_count('select 1 from public.my_coach_consent_status()', 0, 'unlinked user reads consent status');
select pg_temp.act_as('88888888-0000-4000-8000-000000000008');
select pg_temp.expect_count('select 1 from public.my_coach_consent_status()', 0, 'revoked athlete reads consent status');
reset role;

-- AC7: App Store athlete, unlisted App Store coach: no P9 until the coach is v2 -----------
set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status()
     where coach_display_name = 'Ron' and not link_is_v2 and not needs_v2_ack$q$,
  1, 'unlisted App Store coach: no P9 yet');
-- AC4: the ack fails on a pair that is not v2, and nothing changes.
select pg_temp.expect_error($q$select public.ack_coach_consent(2)$q$,
  'P0001', 'v2_unavailable', 'ack while the pair is not v2');
reset role;
select pg_temp.expect_count(
  $q$select 1 from public.coach_athlete_links where athlete_id = 'eeeeeeee-0000-4000-8000-00000000000e'
     and status = 'active' and consent_version = 1 and consent_acknowledged_at is null$q$,
  1, 'failed ack changed nothing');
-- Nadav lists Ron: P9 shows now.
insert into public.coach_v2_pilot_coaches (coach_id) values ('cccccccc-0000-4000-8000-00000000000c');
set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status() where link_is_v2 and needs_v2_ack and not sharing_active$q$,
  1, 'listed coach: P9 shows');
reset role;
select pg_temp.expect_bool(public.coach_v2_sharing_allowed('cccccccc-0000-4000-8000-00000000000c',
  'eeeeeeee-0000-4000-8000-00000000000e'), false, 'nothing shared before the ack (D7)');

-- AC6: only the link's athlete can ack ------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_error($q$select public.ack_coach_consent(2)$q$,
  'P0001', 'no_active_link', 'coach acks');
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_error($q$select public.ack_coach_consent(2)$q$,
  'P0001', 'no_active_link', 'unlinked user acks');
select pg_temp.act_as('88888888-0000-4000-8000-000000000008');
select pg_temp.expect_error($q$select public.ack_coach_consent(2)$q$,
  'P0001', 'no_active_link', 'revoked athlete acks');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error($q$select public.ack_coach_consent(1)$q$,
  '22023', 'bad_consent_version', 'ack version 1');
select pg_temp.expect_error($q$select public.ack_coach_consent(3)$q$,
  '22023', 'bad_consent_version', 'ack version 3');
select pg_temp.expect_error($q$select public.ack_coach_consent(null)$q$,
  '22023', 'bad_consent_version', 'ack with no version');
-- The coach's ack attempt above did not touch B's link.
reset role;
select pg_temp.expect_count(
  $q$select 1 from public.coach_athlete_links where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
     and consent_version = 1 and consent_acknowledged_at is null$q$,
  1, 'failed acks left B on consent v1');

-- B acks: version 2, ack time set, sharing on.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
do $$
declare
  r jsonb;
begin
  r := public.ack_coach_consent(2);
  if r->>'status' <> 'acked' or (r->>'consent_version')::int <> 2 or r->>'consent_acknowledged_at' is null then
    raise exception 'FAIL: first ack: %', r;
  end if;
end $$;
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status() where link_is_v2 and not needs_v2_ack and sharing_active$q$,
  1, 'after the ack: no P9, sharing on');
reset role;
select pg_temp.expect_bool(public.coach_v2_sharing_allowed('aaaaaaaa-0000-4000-8000-00000000000a',
  'bbbbbbbb-0000-4000-8000-00000000000b'), true, 'sharing allowed after the ack');

-- A second ack keeps the first ack time. now() is fixed inside one transaction, so
-- move the stored time back first and check the second call leaves it there.
update public.coach_athlete_links set consent_acknowledged_at = '2026-11-01 08:00:00+00'
 where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'active';
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
do $$
declare
  r jsonb;
begin
  r := public.ack_coach_consent(2);
  if r->>'status' <> 'already_acked'
     or (r->>'consent_acknowledged_at')::timestamptz <> '2026-11-01 08:00:00+00'::timestamptz then
    raise exception 'FAIL: second ack moved the ack time or did not say already_acked: %', r;
  end if;
end $$;
reset role;
select pg_temp.expect_count(
  $q$select 1 from public.coach_athlete_links where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
     and consent_version = 2 and consent_acknowledged_at = '2026-11-01 08:00:00+00'$q$,
  1, 'first ack time kept');

-- AC5: acked on TestFlight, then the App Store build reaches the athlete -----------------
-- F acked at join on TestFlight. F's next report says app_store. Coach A is unlisted, so
-- the pair is off until Nadav lists A; then it is on and P9 still never shows.
set local role authenticated;
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select public.report_client_capabilities(true, '1.3.0', 60, 'app_store');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status() where not link_is_v2 and not needs_v2_ack$q$,
  1, 'App Store build, coach unlisted: pair off, no P9');
reset role;
insert into public.coach_v2_pilot_coaches (coach_id) values ('aaaaaaaa-0000-4000-8000-00000000000a');
set local role authenticated;
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status() where link_is_v2 and not needs_v2_ack and sharing_active$q$,
  1, 'App Store build, coach listed: no second P9');
reset role;

-- Clients cannot call the internal gate; anon is denied everywhere ------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error(
  $q$select public.coach_v2_sharing_allowed('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', null, 'client calls coach_v2_sharing_allowed');
-- The table stays read-only for clients: no direct write of the consent columns.
select pg_temp.expect_error(
  $q$update public.coach_athlete_links set consent_version = 2, consent_acknowledged_at = now()
     where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'$q$,
  '42501', null, 'client updates consent directly');
reset role;

set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error($q$select public.ack_coach_consent(2)$q$, '42501', null, 'anon acks');
select pg_temp.expect_error($q$select * from public.my_coach_consent_status()$q$, '42501', null, 'anon reads status');
select pg_temp.expect_error($q$select public.coach_invite_consent_version('DANA22')$q$, '42501', null,
  'anon reads invite consent version');
select pg_temp.expect_error(
  $q$select public.join_coach_v2('DANA22', 'a1111111-0000-4000-8000-000000000001',
     'aaaaaaaa-0000-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-00000000000d', 2)$q$,
  '42501', null, 'anon joins with v2');
select pg_temp.expect_error(
  $q$select public.join_coach('DANA22', 'a1111111-0000-4000-8000-000000000001',
     'aaaaaaaa-0000-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-00000000000d')$q$,
  '42501', null, 'anon joins');
reset role;

do $$ begin raise notice 'coach_consent_v2: PASS'; end $$;

rollback;
