-- Two-user test for 20261114210000_coach_role_and_invites.sql.
--
-- A and C are flagged coaches, B is not. Proves:
--   * B (non-coach) sees zero rows of coach_profiles and coach_invites, and
--     get_or_create_my_invite() raises "not a coach" for B and for anon;
--   * a coach sees only their own profile and invite, never another coach's;
--   * the RPC returns a 6-character code from the unambiguous alphabet and is
--     stable across calls (one active invite per coach);
--   * clients cannot insert/update/delete on either table (no self-serve coach);
--   * codes are unique case-insensitively, and a coach has one active invite max.
-- Raises an exception on the first failure; prints "coach_invites: PASS" otherwise.
--
-- Everything runs in one transaction and is rolled back, but it inserts auth.users
-- rows while it runs. It refuses to run if auth.users already has rows, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (after applying the migration, ideally twice to prove it is idempotent):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_invites.sql
-- Use a superuser-capable role (postgres) so the fixture inserts bypass RLS.

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_invites.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

-- Fixture (as table owner, bypassing RLS) --------------------------------------
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated');

-- This is the exact snippet from the migration header that Nadav runs.
insert into coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

-- Coach C already has an invite (created as owner); A and B have none.
insert into coach_invites (coach_id, code) values
  ('cccccccc-0000-4000-8000-00000000000c', 'ABC234');

-- Helper: impersonate a user the way PostgREST does -----------------------------
create function pg_temp.act_as(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

-- Helper: assert a statement fails with the given SQLSTATE ----------------------
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

grant execute on function pg_temp.act_as(text), pg_temp.expect_error(text, text, text)
  to authenticated, anon;

-- B, the non-coach: nothing visible, RPC refused ---------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  n int;
  v_code text;
begin
  select count(*) into n from public.coach_profiles;
  if n <> 0 then raise exception 'FAIL: non-coach B sees % coach_profiles rows', n; end if;

  select count(*) into n from public.coach_invites;
  if n <> 0 then raise exception 'FAIL: non-coach B sees % coach_invites rows', n; end if;

  begin
    v_code := public.get_or_create_my_invite();
    raise exception 'FAIL: non-coach B got an invite code from the RPC: %', v_code;
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'not a coach' or sqlstate <> '42501' then
      raise exception 'FAIL: RPC for non-coach raised % (%), expected 42501 "not a coach"', sqlstate, sqlerrm;
    end if;
  end;

  select count(*) into n from public.coach_invites;
  if n <> 0 then raise exception 'FAIL: the refused RPC call left rows visible to B (%)', n; end if;
end $$;

-- B cannot flag themselves as a coach or write invites
select pg_temp.expect_error(
  $q$insert into public.coach_profiles (user_id, display_name) values ('bbbbbbbb-0000-4000-8000-00000000000b', 'Self')$q$,
  '42501', 'non-coach B self-inserting a coach_profiles row');
select pg_temp.expect_error(
  $q$insert into public.coach_invites (coach_id, code) values ('bbbbbbbb-0000-4000-8000-00000000000b', 'ZZZ999')$q$,
  '42501', 'B inserting a coach_invites row');

-- A, a coach: own rows only; RPC creates and then reuses one code -----------------
reset role;
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

do $$
declare
  n int;
  first_code text;
  second_code text;
begin
  select count(*) into n from public.coach_profiles;
  if n <> 1 then raise exception 'FAIL: coach A sees % coach_profiles rows, expected 1 (own)', n; end if;
  if (select display_name from public.coach_profiles) <> 'Dana' then
    raise exception 'FAIL: coach A sees someone else''s coach_profiles row';
  end if;

  select count(*) into n from public.coach_invites;
  if n <> 0 then raise exception 'FAIL: coach A sees % invites before creating one (C''s leaked?)', n; end if;

  first_code := public.get_or_create_my_invite();
  if first_code !~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'FAIL: invite code % is not 6 chars from the unambiguous alphabet', first_code;
  end if;

  second_code := public.get_or_create_my_invite();
  if second_code <> first_code then
    raise exception 'FAIL: RPC returned a different code on the second call (% vs %)', first_code, second_code;
  end if;

  select count(*) into n from public.coach_invites;
  if n <> 1 then raise exception 'FAIL: coach A sees % invites, expected exactly 1 (own)', n; end if;
  if (select code from public.coach_invites) <> first_code then
    raise exception 'FAIL: the invite A can read is not the one the RPC returned';
  end if;
  if (select active from public.coach_invites) is not true then
    raise exception 'FAIL: created invite is not active';
  end if;
end $$;

-- A cannot write either table directly
select pg_temp.expect_error(
  $q$insert into public.coach_invites (coach_id, code) values ('aaaaaaaa-0000-4000-8000-00000000000a', 'QQQ222')$q$,
  '42501', 'coach A inserting an invite');
select pg_temp.expect_error(
  $q$update public.coach_invites set code = 'HACKED'$q$,
  '42501', 'coach A updating an invite');
select pg_temp.expect_error(
  $q$delete from public.coach_invites$q$,
  '42501', 'coach A deleting an invite');
select pg_temp.expect_error(
  $q$update public.coach_profiles set display_name = 'Mallory'$q$,
  '42501', 'coach A updating coach_profiles');
select pg_temp.expect_error(
  $q$delete from public.coach_profiles$q$,
  '42501', 'coach A deleting coach_profiles');
select pg_temp.expect_error(
  $q$insert into public.coach_profiles (user_id, display_name) values ('bbbbbbbb-0000-4000-8000-00000000000b', 'Mallory')$q$,
  '42501', 'coach A inserting a coach_profiles row');

-- C, the other coach: sees only C's own invite, which the RPC returns unchanged ----
reset role;
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_profiles;
  if n <> 1 then raise exception 'FAIL: coach C sees % coach_profiles rows, expected 1', n; end if;
  select count(*) into n from public.coach_invites;
  if n <> 1 then raise exception 'FAIL: coach C sees % invites, expected 1', n; end if;
  if public.get_or_create_my_invite() <> 'ABC234' then
    raise exception 'FAIL: RPC did not return C''s existing active code';
  end if;
end $$;

-- anon: no table access, no RPC ------------------------------------------------------
reset role;
set local role anon;
select pg_temp.expect_error('select count(*) from public.coach_profiles', '42501', 'anon reading coach_profiles');
select pg_temp.expect_error('select count(*) from public.coach_invites', '42501', 'anon reading coach_invites');
select pg_temp.expect_error('select public.get_or_create_my_invite()', '42501', 'anon calling the RPC');

-- Uniqueness and cascade (as table owner) ---------------------------------------------
reset role;

-- Case-insensitive: A's code, lower-cased, cannot be reused by C
do $$
declare
  a_code text;
begin
  select code into a_code from public.coach_invites
  where coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a' and active;
  if a_code is null then raise exception 'FAIL: setup: A has no active invite'; end if;

  perform pg_temp.expect_error(
    format('insert into public.coach_invites (coach_id, code, active) values (%L, %L, false)',
           'cccccccc-0000-4000-8000-00000000000c', lower(a_code)),
    '23505', 'reusing a code in a different case');
end $$;

-- C already has an active invite, so a second active one is refused; an inactive one is fine
select pg_temp.expect_error(
  $q$insert into public.coach_invites (coach_id, code) values ('cccccccc-0000-4000-8000-00000000000c', 'XYZ789')$q$,
  '23505', 'a second active invite for one coach');
insert into public.coach_invites (coach_id, code, active)
  values ('cccccccc-0000-4000-8000-00000000000c', 'XYZ789', false);

-- Many generated codes stay valid and unique (exercises the generator, not production)
insert into auth.users (id, email, aud, role)
select ('dddddddd-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid, 'bulk' || i || '@example.com',
       'authenticated', 'authenticated'
from generate_series(1, 200) i;
insert into public.coach_profiles (user_id, display_name)
select id, 'Bulk' from auth.users where email like 'bulk%';

-- Runs as the table owner with a JWT sub per coach; the RPC is security definer
-- and reads the caller from auth.uid(), so this exercises the same code path.
do $$
declare
  u uuid;
  n int;
  distinct_codes int;
begin
  for u in select id from auth.users where email like 'bulk%' loop
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', u::text, true);
    perform public.get_or_create_my_invite();
  end loop;
  select count(*), count(distinct upper(code)) into n, distinct_codes
  from public.coach_invites where coach_id in (select id from auth.users where email like 'bulk%');
  if n <> 200 or distinct_codes <> 200 then
    raise exception 'FAIL: 200 coaches got % invites with % distinct codes', n, distinct_codes;
  end if;
end $$;

-- Deleting the auth user removes the coach row and their invites
delete from auth.users where id = 'cccccccc-0000-4000-8000-00000000000c';
do $$
begin
  if exists (select 1 from public.coach_profiles where user_id = 'cccccccc-0000-4000-8000-00000000000c')
     or exists (select 1 from public.coach_invites where coach_id = 'cccccccc-0000-4000-8000-00000000000c') then
    raise exception 'FAIL: deleting the auth user did not cascade to coach_profiles / coach_invites';
  end if;
end $$;

-- Policy and grant shape: select-only, own rows, nothing for anon -----------------------
do $$
declare
  offending text;
begin
  select string_agg(tablename || '.' || policyname || ':' || cmd, ', ') into offending
  from pg_policies
  where schemaname = 'public'
    and tablename in ('coach_profiles', 'coach_invites')
    and cmd <> 'SELECT';
  if offending is not null then
    raise exception 'FAIL: a client write policy exists: %', offending;
  end if;

  if not (select relrowsecurity from pg_class where oid = 'public.coach_profiles'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.coach_invites'::regclass) then
    raise exception 'FAIL: RLS is not enabled on both tables';
  end if;

  if (select count(*) from pg_tables
      where schemaname = 'public' and tablename like 'coach%') <> 2 then
    raise exception 'FAIL: expected exactly two coach tables in public';
  end if;
end $$;

select 'coach_invites: PASS' as result;

rollback;
