-- Two-user test for 20261115194500_leave_coach.sql.
--
-- Proves leave_coach sets status = revoked and revoked_at; the coach's SELECT
-- then returns zero rows; a third user cannot revoke someone else's link;
-- leaving twice raises not_linked; the athlete can join another coach because
-- only active links are unique; purge_coach_data_for_deleted_account removes
-- links and, when the later tables exist, their rows.
--
-- Blank throwaway Postgres only.

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'leave_coach.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'third-d@example.com', 'authenticated', 'authenticated');

insert into coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into coach_invites (id, coach_id, code, active) values
  ('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000a', 'ABC234', true),
  ('22222222-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-00000000000c', 'RON999', true);

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

-- B joins Dana ------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

select set_config('test.coach_link_id', public.join_coach(
  'ABC234',
  '11111111-0000-4000-8000-000000000001',
  'aaaaaaaa-0000-4000-8000-00000000000a',
  'bbbbbbbb-0000-4000-8000-00000000000b'
)->>'link_id', true);

-- A third user, and the coach, cannot revoke B's link ---------------------------
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_error($q$select public.leave_coach(current_setting('test.coach_link_id')::uuid)$q$, 'P0001', 'third user leave');

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_error($q$select public.leave_coach(current_setting('test.coach_link_id')::uuid)$q$, 'P0001', 'coach cannot leave as the athlete');

reset role;
do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links
  where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'active';
  if n <> 1 then
    raise exception 'FAIL: third-user leave changed the active link (count %)', n;
  end if;
end $$;

-- Direct client update is still impossible -------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error(
  $q$update public.coach_athlete_links set status = 'revoked'$q$,
  '42501',
  'client update of links');

-- Leave sets revoked and revoked_at --------------------------------------------
select pg_temp.expect_error($q$select public.leave_coach('aaaaaaaa-0000-4000-8000-000000000001')$q$, 'P0001', 'stale link cannot revoke current link');
select public.leave_coach(current_setting('test.coach_link_id')::uuid);

reset role;
do $$
declare
  v_status text;
  v_revoked timestamptz;
begin
  select status, revoked_at into v_status, v_revoked
  from public.coach_athlete_links
  where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
  if v_status <> 'revoked' or v_revoked is null then
    raise exception 'FAIL: leave did not set revoked/revoked_at (status %, revoked %)', v_status, v_revoked;
  end if;
end $$;

-- Coach SELECT returns zero; athlete still sees the revoked row ----------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links;
  if n <> 0 then
    raise exception 'FAIL: coach still sees % link rows after revoke', n;
  end if;
end $$;

select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links;
  if n <> 1 then
    raise exception 'FAIL: athlete should still read the revoked row, saw %', n;
  end if;
end $$;

-- Leaving twice raises not_linked ----------------------------------------------
select pg_temp.expect_error(
  $q$select public.leave_coach(current_setting('test.coach_link_id')::uuid)$q$,
  'P0001',
  'leave twice');

-- Athlete can join another coach; only active links are unique -----------------
select public.join_coach(
  'RON999',
  '22222222-0000-4000-8000-000000000002',
  'cccccccc-0000-4000-8000-00000000000c',
  'bbbbbbbb-0000-4000-8000-00000000000b'
);

reset role;
do $$
declare
  n_active int;
  n_revoked int;
begin
  select count(*) into n_active from public.coach_athlete_links
  where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'active';
  select count(*) into n_revoked from public.coach_athlete_links
  where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'revoked';
  if n_active <> 1 or n_revoked <> 1 then
    raise exception 'FAIL: expected 1 active and 1 revoked, got % active % revoked', n_active, n_revoked;
  end if;
end $$;

-- New coach sees the active link; Dana still sees none -------------------------
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links;
  if n <> 1 then
    raise exception 'FAIL: new coach should see the active link, saw %', n;
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links;
  if n <> 0 then
    raise exception 'FAIL: previous coach sees a revoked link (% rows)', n;
  end if;
end $$;

-- delete_account cleanup: links, and later tables when they exist --------------
reset role;

create table public.coach_feedback (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null,
  athlete_id uuid not null,
  body text
);

create table public.coach_plan_drafts (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null,
  athlete_id uuid not null,
  body text
);

insert into public.coach_feedback (coach_id, athlete_id, body) values
  ('cccccccc-0000-4000-8000-00000000000c', 'bbbbbbbb-0000-4000-8000-00000000000b', 'kept until delete'),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-00000000000d', 'someone else');

insert into public.coach_plan_drafts (coach_id, athlete_id, body) values
  ('cccccccc-0000-4000-8000-00000000000c', 'bbbbbbbb-0000-4000-8000-00000000000b', 'draft'),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-00000000000d', 'other draft');

-- Authenticated callers cannot run the cleanup.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error(
  $q$select public.purge_coach_data_for_deleted_account('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501',
  'authenticated purge');

reset role;
select public.purge_coach_data_for_deleted_account('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_athlete_links
  where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
     or coach_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
  if n <> 0 then
    raise exception 'FAIL: purge left % links for the deleted athlete', n;
  end if;

  select count(*) into n from public.coach_feedback
  where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
     or coach_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
  if n <> 0 then
    raise exception 'FAIL: purge left % feedback rows', n;
  end if;

  select count(*) into n from public.coach_plan_drafts
  where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
     or coach_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
  if n <> 0 then
    raise exception 'FAIL: purge left % draft rows', n;
  end if;

  select count(*) into n from public.coach_feedback
  where athlete_id = 'dddddddd-0000-4000-8000-00000000000d';
  if n <> 1 then
    raise exception 'FAIL: purge removed another athlete''s feedback';
  end if;

  select count(*) into n from public.coach_plan_drafts
  where athlete_id = 'dddddddd-0000-4000-8000-00000000000d';
  if n <> 1 then
    raise exception 'FAIL: purge removed another athlete''s draft';
  end if;
end $$;

-- Deleting the coach removes their profile and any remaining links ------------
select public.purge_coach_data_for_deleted_account('aaaaaaaa-0000-4000-8000-00000000000a');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_profiles
  where user_id = 'aaaaaaaa-0000-4000-8000-00000000000a';
  if n <> 0 then
    raise exception 'FAIL: purge left the coach profile';
  end if;
  select count(*) into n from public.coach_athlete_links
  where coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a';
  if n <> 0 then
    raise exception 'FAIL: purge left links for the deleted coach';
  end if;
  select count(*) into n from public.coach_feedback
  where coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a';
  if n <> 0 then
    raise exception 'FAIL: purge left the coach''s feedback';
  end if;
end $$;

reset role;
do $$
begin
  raise notice 'leave_coach: PASS';
end $$;

rollback;
