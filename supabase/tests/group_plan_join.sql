-- Story 1.8. Proves lookup_invite returns Plan Mode and Group Plan Settings,
-- and that a coach still cannot write an athlete's plans or workouts.
-- join_coach is not changed here.
--
-- This story adds no coach write policy. The plans and workouts tables below
-- are the owner-only policies from the 2026-11-14 production listing (same
-- shape as supabase/tests/runs_workout_link_fixture.sql). They exist so a
-- blank throwaway database can prove the coach is blocked. Do not apply this
-- file to production.
--
-- Refuses to run unless auth.users is empty.
--
-- Run, after applying Story 1.2, 1.3, 1.7, and this migration twice:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117130000_coach_plan_mode_group_settings.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117160000_lookup_invite_group_plan.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117160000_lookup_invite_group_plan.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/group_plan_join.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'group_plan_join.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
  if to_regclass('public.plans') is not null or to_regclass('public.workouts') is not null then
    raise exception 'group_plan_join.sql refused: plans or workouts already exist. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null,
  auth_user_id uuid references auth.users(id) on delete cascade,
  title text not null,
  is_active boolean not null default true
);

create table public.workouts (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans(id) on delete cascade,
  auth_user_id uuid references auth.users(id) on delete cascade,
  completed boolean not null default false
);

alter table public.plans enable row level security;
alter table public.workouts enable row level security;

grant select, insert, update, delete on public.plans, public.workouts to authenticated;

create policy plans_owner_access on public.plans
  for all to authenticated
  using ((auth_user_id = (select auth.uid())) or (profile_id = (select auth.uid())))
  with check ((auth_user_id = (select auth.uid())) and (profile_id = (select auth.uid())));

create policy workouts_owner_access on public.workouts
  for all to authenticated
  using ((auth_user_id = (select auth.uid())) or exists (
    select 1 from public.plans p where p.id = workouts.plan_id
      and ((p.auth_user_id = (select auth.uid())) or (p.profile_id = (select auth.uid())))))
  with check ((auth_user_id = (select auth.uid())) and exists (
    select 1 from public.plans p where p.id = workouts.plan_id
      and ((p.auth_user_id = (select auth.uid())) or (p.profile_id = (select auth.uid())))));

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated');

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

-- Dana's group settings -------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.set_plan_mode('group');
select public.save_group_plan_settings(
  'distance',
  'half-marathon',
  current_date + 140,
  'beginner',
  3
);

-- Two athletes read the same settings. Neither is linked by lookup. ----------
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  v_mode text;
  v_goal text;
  v_distance text;
  v_race date;
  v_level text;
  v_runs int;
  v_name text;
begin
  select plan_mode, goal, target_distance, race_date, level, runs_per_week, display_name
    into v_mode, v_goal, v_distance, v_race, v_level, v_runs, v_name
  from public.lookup_invite('abc234');

  if v_name is distinct from 'Dana' then
    raise exception 'FAIL: lookup_invite did not return Dana';
  end if;
  if v_mode is distinct from 'group'
     or v_goal is distinct from 'distance'
     or v_distance is distinct from 'half-marathon'
     or v_race is distinct from current_date + 140
     or v_level is distinct from 'beginner'
     or v_runs is distinct from 3 then
    raise exception 'FAIL: athlete B lookup was % % % % % %',
      v_mode, v_goal, v_distance, v_race, v_level, v_runs;
  end if;
end $$;

select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');

do $$
declare
  v_goal text;
  v_distance text;
  v_race date;
begin
  select goal, target_distance, race_date
    into v_goal, v_distance, v_race
  from public.lookup_invite('ABC234');

  if v_goal is distinct from 'distance'
     or v_distance is distinct from 'half-marathon'
     or v_race is distinct from current_date + 140 then
    raise exception 'FAIL: athlete E did not see Dana''s group settings';
  end if;
end $$;

-- Individual Plans coach: mode is returned, settings are not. -----------------
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select public.set_plan_mode('individual');

select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  v_mode text;
  v_goal text;
  v_distance text;
  v_race date;
  v_level text;
  v_runs int;
begin
  select plan_mode, goal, target_distance, race_date, level, runs_per_week
    into v_mode, v_goal, v_distance, v_race, v_level, v_runs
  from public.lookup_invite('ron999');

  if v_mode is distinct from 'individual' then
    raise exception 'FAIL: individual lookup plan_mode was %', v_mode;
  end if;
  if v_goal is not null or v_distance is not null or v_race is not null
     or v_level is not null or v_runs is not null then
    raise exception 'FAIL: individual lookup returned group settings';
  end if;
end $$;

-- Athlete B's plan. Dana cannot read or write it. ----------------------------
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  n int;
begin
  insert into public.plans (id, profile_id, auth_user_id, title)
  values (
    'bbbbbbbb-0000-4000-8000-0000000000b1',
    'bbbbbbbb-0000-4000-8000-00000000000b',
    'bbbbbbbb-0000-4000-8000-00000000000b',
    '10K'
  );

  insert into public.workouts (plan_id, auth_user_id)
  values (
    'bbbbbbbb-0000-4000-8000-0000000000b1',
    'bbbbbbbb-0000-4000-8000-00000000000b'
  );

  select count(*) into n from public.plans;
  if n <> 1 then raise exception 'FAIL: athlete B sees % plans, expected 1', n; end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

do $$
declare
  n int;
begin
  select count(*) into n from public.plans;
  if n <> 0 then raise exception 'FAIL: coach Dana sees % athlete plans', n; end if;
  select count(*) into n from public.workouts;
  if n <> 0 then raise exception 'FAIL: coach Dana sees % athlete workouts', n; end if;

  update public.plans set title = 'stolen';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: coach Dana updated % plan rows', n; end if;

  update public.workouts set completed = true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: coach Dana updated % workout rows', n; end if;

  delete from public.workouts;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: coach Dana deleted % workouts', n; end if;

  delete from public.plans;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: coach Dana deleted % plans', n; end if;
end $$;

select pg_temp.expect_error(
  $q$insert into public.plans (profile_id, auth_user_id, title)
     values ('bbbbbbbb-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b', 'stolen')$q$,
  '42501', 'coach insert into athlete plan');

select pg_temp.expect_error(
  $q$insert into public.workouts (plan_id, auth_user_id)
     values ('bbbbbbbb-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', 'coach insert into athlete workout');

select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  n int;
  v_title text;
begin
  select count(*), max(title) into n, v_title from public.plans;
  if n <> 1 or v_title is distinct from '10K' then
    raise exception 'FAIL: athlete plan changed after the coach write attempts (% %)', n, v_title;
  end if;
  select count(*) into n from public.workouts;
  if n <> 1 then raise exception 'FAIL: athlete workout count is %', n; end if;
end $$;

-- anon still cannot look up an invite ---------------------------------------
reset role;
set local role anon;
select pg_temp.expect_error(
  $q$select public.lookup_invite('ABC234')$q$,
  '42501',
  'anon lookup_invite');

reset role;
do $$
begin
  raise notice 'group_plan_join: PASS';
end $$;

rollback;
