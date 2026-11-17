-- Story 1.7. Proves Plan Mode and Group Plan Settings.
--
-- A and C are coaches, B is not. Proves:
--   * a non-coach cannot call the RPCs or read coach_group_plans;
--   * a second set_plan_mode raises plan_mode_locked;
--   * an individual-mode coach cannot save group settings;
--   * a past race date and a too-close race date are rejected;
--   * a race more than 16 weeks out is saved;
--   * get_or_create_my_invite() raises plan_mode_not_set until the gate is open,
--     then returns a code;
--   * another coach cannot read my settings.
-- Raises on the first failure. Prints "coach_plan_mode: PASS" otherwise.
--
-- Refuses to run unless auth.users is empty, so it can only run on a blank
-- throwaway Postgres, never production.
--
-- Run, after applying Story 1.2 and this migration (apply the new file twice):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117130000_coach_plan_mode_group_settings.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_plan_mode.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_plan_mode.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated');

insert into coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

create function pg_temp.act_as(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

create function pg_temp.expect_error(stmt text, expected_message text, label text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL: % succeeded but should have failed (%)', label, expected_message;
exception when others then
  if sqlstate = 'P0001' and sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm <> expected_message then
    raise exception 'FAIL: % failed with % (%), expected message %', label, sqlstate, sqlerrm, expected_message;
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.expect_error(text, text, text)
  to authenticated, anon;

-- Non-coach and anon ----------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_group_plans;
  if n <> 0 then raise exception 'FAIL: non-coach B sees % coach_group_plans rows', n; end if;

  select count(*) into n from public.coach_profiles;
  if n <> 0 then raise exception 'FAIL: non-coach B sees % coach_profiles rows', n; end if;
end $$;

select pg_temp.expect_error(
  $q$select public.set_plan_mode('group')$q$,
  'not a coach', 'non-coach B set_plan_mode');
select pg_temp.expect_error(
  $q$select public.save_group_plan_settings('habit', '5k', current_date + 40, 'beginner', 3)$q$,
  'not a coach', 'non-coach B save_group_plan_settings');
select pg_temp.expect_error(
  $q$select public.get_or_create_my_invite()$q$,
  'not a coach', 'non-coach B get_or_create_my_invite');

reset role;
set local role anon;
select pg_temp.expect_error(
  $q$select public.set_plan_mode('group')$q$,
  'permission denied for function set_plan_mode', 'anon set_plan_mode');

-- Coach A: mode is a one-time choice, then group settings ----------------------
reset role;
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

select pg_temp.expect_error(
  $q$select public.get_or_create_my_invite()$q$,
  'plan_mode_not_set', 'invite before Plan Mode is chosen');

select public.set_plan_mode('group');

select pg_temp.expect_error(
  $q$select public.set_plan_mode('individual')$q$,
  'plan_mode_locked', 'second set_plan_mode');

do $$
declare
  v_mode text;
begin
  select plan_mode into v_mode from public.coach_profiles;
  if v_mode <> 'group' then
    raise exception 'FAIL: locked mode changed to %', v_mode;
  end if;
end $$;

select pg_temp.expect_error(
  $q$select public.get_or_create_my_invite()$q$,
  'plan_mode_not_set', 'group invite before settings are saved');

select pg_temp.expect_error(
  $q$select public.save_group_plan_settings('habit', '5k', current_date - 1, 'beginner', 3)$q$,
  'race_date_in_past', 'past race date');
select pg_temp.expect_error(
  $q$select public.save_group_plan_settings('habit', '5k', current_date + 21, 'beginner', 3)$q$,
  'race_too_close', '5k race 3 weeks out');
select pg_temp.expect_error(
  $q$select public.save_group_plan_settings('habit', 'marathon', current_date + 28, 'beginner', 3)$q$,
  'race_too_close', 'marathon race 4 weeks out');
select pg_temp.expect_error(
  $q$select public.save_group_plan_settings('nope', '5k', current_date + 40, 'beginner', 3)$q$,
  'invalid_group_plan', 'goal outside the generator list');

-- More than 16 weeks out is saved, not rejected.
select public.save_group_plan_settings('distance', 'half-marathon', current_date + 140, 'intermediate', 4);

do $$
declare
  n int;
  v_code text;
begin
  select count(*) into n from public.coach_group_plans;
  if n <> 1 then raise exception 'FAIL: coach A sees % group plan rows, expected 1', n; end if;

  v_code := public.get_or_create_my_invite();
  if v_code is null or char_length(v_code) <> 6 then
    raise exception 'FAIL: invite after the gate opened was %', v_code;
  end if;
end $$;

select pg_temp.expect_error(
  $q$insert into public.coach_group_plans (coach_id, goal, target_distance, race_date, level, runs_per_week)
    values ('aaaaaaaa-0000-4000-8000-00000000000a', 'habit', '5k', current_date + 40, 'beginner', 3)$q$,
  'permission denied for table coach_group_plans', 'client insert into coach_group_plans');

-- Editing later replaces the one row and does not touch anything else.
select public.save_group_plan_settings('speed', '10k', current_date + 50, 'advanced', 5);

do $$
declare
  n int;
  v_goal text;
begin
  select count(*) into n from public.coach_group_plans;
  if n <> 1 then raise exception 'FAIL: edit created an extra row (% rows)', n; end if;
  select goal into v_goal from public.coach_group_plans;
  if v_goal <> 'speed' then raise exception 'FAIL: edited goal is %', v_goal; end if;
end $$;

-- Coach C is on Individual Plans and cannot write group settings ---------------
reset role;
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');

select public.set_plan_mode('individual');

select pg_temp.expect_error(
  $q$select public.save_group_plan_settings('habit', '5k', current_date + 40, 'beginner', 3)$q$,
  'plan_mode_not_group', 'individual coach save_group_plan_settings');

do $$
declare
  n int;
  v_code text;
begin
  select count(*) into n from public.coach_group_plans;
  if n <> 0 then
    raise exception 'FAIL: coach C can see % group plan rows (A''s settings leaked)', n;
  end if;

  v_code := public.get_or_create_my_invite();
  if v_code is null or char_length(v_code) <> 6 then
    raise exception 'FAIL: individual coach invite was %', v_code;
  end if;
end $$;

reset role;

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_group_plans;
  if n <> 1 then raise exception 'FAIL: expected 1 group plan row after the test, saw %', n; end if;
end $$;

rollback;

\echo coach_plan_mode: PASS
