-- Two-user test for 20261115091000_coach_athlete_links.sql.
--
-- A and C are coaches, B and E are athletes, D is a third user with no role.
-- Proves:
--   * an athlete sees only their own link; a coach sees only links to them;
--     a third user sees nothing;
--   * a second active link for one athlete is rejected;
--   * a self-join is rejected;
--   * an inactive code is rejected and returns nothing from lookup_invite;
--   * clients cannot insert, update, or delete links;
--   * join_coach inserts status = active with consented_at set, and a second
--     join returns already_linked with the current coach's name and no new row.
-- Raises on the first failure; prints "coach_athlete_links: PASS" otherwise.
--
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (after applying Story 1.2 and this migration, twice to prove idempotence):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_athlete_links.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_athlete_links.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'third-d@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated');

insert into coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into coach_invites (id, coach_id, code, active) values
  ('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000a', 'ABC234', true),
  ('22222222-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-00000000000c', 'RON999', false);

create function pg_temp.act_as(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
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

grant execute on function pg_temp.act_as(text), pg_temp.expect_error(text, text, text)
  to authenticated, anon;

-- B joins Dana, case-insensitively ------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  looked_up int;
  result jsonb;
  n int;
begin
  select count(*) into looked_up from public.lookup_invite('abc234');
  if looked_up <> 1 then
    raise exception 'FAIL: lookup_invite(abc234) returned % rows, expected 1', looked_up;
  end if;
  if (select display_name from public.lookup_invite('abc234')) <> 'Dana' then
    raise exception 'FAIL: lookup_invite did not return Dana';
  end if;

  result := public.join_coach(
    'abc234',
    '11111111-0000-4000-8000-000000000001',
    'aaaaaaaa-0000-4000-8000-00000000000a'
  );
  if result->>'status' <> 'joined' then
    raise exception 'FAIL: join_coach status was %, expected joined', result->>'status';
  end if;
  if result->>'display_name' <> 'Dana' then
    raise exception 'FAIL: join_coach did not return Dana';
  end if;

  select count(*) into n from public.coach_athlete_links;
  if n <> 1 then raise exception 'FAIL: athlete B sees % links, expected 1', n; end if;
  if (select status from public.coach_athlete_links) <> 'active' then
    raise exception 'FAIL: link status is not active';
  end if;
  if (select consented_at from public.coach_athlete_links) is null then
    raise exception 'FAIL: consented_at was not set';
  end if;

  if (select display_name from public.my_coach_link()) <> 'Dana' then
    raise exception 'FAIL: my_coach_link did not return Dana';
  end if;
end $$;

-- B cannot write the table, and a second join does not create a row ---------------
select pg_temp.expect_error(
  $q$insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at)
     values ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now())$q$,
  '42501', 'athlete B inserting a link');
select pg_temp.expect_error(
  $q$update public.coach_athlete_links set status = 'revoked'$q$,
  '42501', 'athlete B updating a link');
select pg_temp.expect_error(
  $q$delete from public.coach_athlete_links$q$,
  '42501', 'athlete B deleting a link');

do $$
declare
  result jsonb;
  n int;
begin
  result := public.join_coach(
    'ABC234',
    '11111111-0000-4000-8000-000000000001',
    'aaaaaaaa-0000-4000-8000-00000000000a'
  );
  if result->>'status' <> 'already_linked' or result->>'display_name' <> 'Dana' then
    raise exception 'FAIL: second join returned %', result;
  end if;
  select count(*) into n from public.coach_athlete_links;
  if n <> 1 then raise exception 'FAIL: already_linked created a row (B sees %)', n; end if;
end $$;

-- Inactive code: nothing from lookup, join rejected, still one row -----------------
do $$
declare
  n int;
begin
  select count(*) into n from public.lookup_invite('RON999');
  if n <> 0 then raise exception 'FAIL: inactive code lookup returned % rows', n; end if;
  select count(*) into n from public.lookup_invite('NOPE00');
  if n <> 0 then raise exception 'FAIL: invalid code lookup returned % rows', n; end if;
end $$;

select pg_temp.expect_error(
  $q$select public.join_coach('abc234', '11111111-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-00000000000c')$q$,
  'P0001', 'join when the consented coach does not match the code');
select pg_temp.expect_error(
  $q$select public.join_coach('RON999', '22222222-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-00000000000c')$q$,
  'P0001', 'join with an inactive code');
select pg_temp.expect_error(
  $q$select public.join_coach('NOPE00', '11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000a')$q$,
  'P0001', 'join with an invalid code');

-- Coach A sees the link to them. Third user D sees nothing. -----------------------
reset role;
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links;
  if n <> 1 then raise exception 'FAIL: coach A sees % links, expected 1', n; end if;
  if (select athlete_id from public.coach_athlete_links) <> 'bbbbbbbb-0000-4000-8000-00000000000b' then
    raise exception 'FAIL: coach A sees a link that is not theirs';
  end if;
end $$;

-- A cannot join themselves
do $$
begin
  perform public.join_coach(
    'ABC234',
    '11111111-0000-4000-8000-000000000001',
    'aaaaaaaa-0000-4000-8000-00000000000a'
  );
  raise exception 'FAIL: self-join succeeded';
exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm <> 'cannot_join_self' or sqlstate <> 'P0001' then
    raise exception 'FAIL: self-join raised % (%), expected P0001 cannot_join_self', sqlstate, sqlerrm;
  end if;
end $$;

reset role;
set local role authenticated;
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links;
  if n <> 0 then raise exception 'FAIL: third user D sees % links', n; end if;
  select count(*) into n from public.my_coach_link();
  if n <> 0 then raise exception 'FAIL: third user D has a coach link'; end if;
end $$;

-- A second athlete linked to A is visible to A and to that athlete, not to B ------
reset role;
insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at)
values ('aaaaaaaa-0000-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-00000000000e', 'active', now());

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links;
  if n <> 2 then raise exception 'FAIL: coach A sees % links, expected 2', n; end if;
end $$;

reset role;
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links;
  if n <> 1 then raise exception 'FAIL: athlete B sees % links after E joined, expected 1', n; end if;
end $$;

reset role;
set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links;
  if n <> 1 then raise exception 'FAIL: athlete E sees % links, expected 1', n; end if;
  if (select display_name from public.my_coach_link()) <> 'Dana' then
    raise exception 'FAIL: athlete E is not linked to Dana';
  end if;
end $$;

-- Coach C sees nothing (the links are Dana's). A second active row for B fails. ---
reset role;
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links;
  if n <> 0 then raise exception 'FAIL: coach C sees % links, expected 0', n; end if;
end $$;

reset role;
select pg_temp.expect_error(
  $q$insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at)
     values ('cccccccc-0000-4000-8000-00000000000c', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now())$q$,
  '23505', 'second active link for athlete B');

-- anon --------------------------------------------------------------------------
reset role;
set local role anon;
select pg_temp.expect_error('select count(*) from public.coach_athlete_links', '42501', 'anon reading links');
select pg_temp.expect_error($q$select public.lookup_invite('ABC234')$q$, '42501', 'anon lookup_invite');
select pg_temp.expect_error(
  $q$select public.join_coach('ABC234', '11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000a')$q$,
  '42501', 'anon join_coach');
select pg_temp.expect_error('select public.my_coach_link()', '42501', 'anon my_coach_link');

reset role;
do $$
begin
  raise notice 'coach_athlete_links: PASS';
end $$;

rollback;
