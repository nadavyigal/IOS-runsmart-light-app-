-- Story 2.2. A coach reads a linked athlete only through the read RPCs.
-- A revoked link, a missing link, another coach, and a non-coach return no rows.
-- Direct reads of plans, workouts, and runs stay empty. Writes of those rows fail.
-- Route, run notes, wellness, Garmin, debriefs, and conversations stay hidden.
--
-- Blank throwaway Postgres only. Apply the fixture, Story 1.2, Story 1.3, then
-- this migration twice, then this file.

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_read.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'athlete-d@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated'),
  ('ffffffff-0000-4000-8000-00000000000f', 'athlete-f@example.com', 'authenticated', 'authenticated');

insert into public.profiles (id, auth_user_id, name) values
  ('20000000-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b', 'Yoni Cohen'),
  ('20000000-0000-4000-8000-00000000000e', 'eeeeeeee-0000-4000-8000-00000000000e', '   ');

insert into public.plans (
  id, profile_id, auth_user_id, title, start_date, end_date, is_active, target_distance, target_time
) values
  ('10000000-0000-4000-8000-0000000000b1', '20000000-0000-4000-8000-00000000000b',
   'bbbbbbbb-0000-4000-8000-00000000000b', '10K build', '2026-11-16', '2026-12-27', true, 10, 3600),
  ('10000000-0000-4000-8000-0000000000b2', 'bbbbbbbb-0000-4000-8000-00000000000b',
   null, 'Old plan', '2026-10-01', '2026-11-01', false, 5, null),
  ('10000000-0000-4000-8000-0000000000e1', '20000000-0000-4000-8000-00000000000e',
   null, 'Easy start', '2026-11-16', '2026-12-27', true, 5, null),
  ('10000000-0000-4000-8000-0000000000d1', 'dddddddd-0000-4000-8000-00000000000d',
   'dddddddd-0000-4000-8000-00000000000d', 'Unlinked', '2026-11-16', '2026-12-27', true, 8, null);

insert into public.workouts (
  id, plan_id, auth_user_id, type, distance, duration, pace, notes, completed, completed_at,
  actual_distance_km, actual_duration_minutes, actual_pace, scheduled_date
) values
  ('30000000-0000-4000-8000-0000000000b1', '10000000-0000-4000-8000-0000000000b1',
   'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5, 30, 360, 'Easy day', true,
   '2026-11-16 06:00:00+00', 5.1, 31, 365, '2026-11-16'),
  ('30000000-0000-4000-8000-0000000000b2', '10000000-0000-4000-8000-0000000000b1',
   'bbbbbbbb-0000-4000-8000-00000000000b', 'long', 12, 70, 350, 'Outside the week', false,
   null, null, null, null, '2026-11-15'),
  ('30000000-0000-4000-8000-0000000000b3', '10000000-0000-4000-8000-0000000000b2',
   'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 3, 20, 400, 'Inactive plan', false,
   null, null, null, null, '2026-11-16'),
  ('30000000-0000-4000-8000-0000000000e1', '10000000-0000-4000-8000-0000000000e1',
   null, 'easy', 4, 25, 375, 'Profile owned', false,
   null, null, null, null, '2026-11-17'),
  ('30000000-0000-4000-8000-0000000000d1', '10000000-0000-4000-8000-0000000000d1',
   'dddddddd-0000-4000-8000-00000000000d', 'easy', 6, 35, 350, 'Not linked', false,
   null, null, null, null, '2026-11-16');

insert into public.runs (
  auth_user_id, workout_id, type, distance, duration, pace, heart_rate, notes, route,
  completed_at, source_provider, source_activity_id
) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', '30000000-0000-4000-8000-0000000000b1',
   'easy', 5.1, 1860, 364.7, 142, 'PRIVATE_RUN_NOTE', '{"secret":"SECRET_ROUTE"}'::jsonb,
   '2026-11-16 00:30:00+00', 'runsmart_ios', 'run-b'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', null,
   'easy', 3, 1200, 400, 130, 'PRIVATE_OLD_NOTE', '{"secret":"SECRET_OLD_ROUTE"}'::jsonb,
   '2026-11-15 23:30:00+00', 'runsmart_ios', 'run-b-old'),
  ('dddddddd-0000-4000-8000-00000000000d', null,
   'easy', 6, 2100, 350, 150, 'PRIVATE_UNLINKED_NOTE', '{"secret":"SECRET_UNLINKED_ROUTE"}'::jsonb,
   '2026-11-16 08:00:00+00', 'health', 'run-d'),
  ('eeeeeeee-0000-4000-8000-00000000000e', null,
   'easy', 4, 1500, 375, 128, 'PRIVATE_E_NOTE', '{"secret":"SECRET_E_ROUTE"}'::jsonb,
   '2026-11-22 21:00:00+00', 'garmin', 'run-e');

insert into public.wellness_checkins (auth_user_id, notes) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'SLEEP_SECRET');
insert into public.garmin_activities (auth_user_id, summary) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'GARMIN_SECRET');
insert into public.run_debriefs (auth_user_id, debrief) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'DEBRIEF_SECRET');
insert into public.conversations (auth_user_id, content) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'CHAT_SECRET');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_invites (id, coach_id, code, active) values
  ('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000a', 'ABC234', true);

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-00000000000e', 'active', '2026-11-01 08:00:00+00'),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f', 'active', '2026-11-02 08:00:00+00');

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

-- B joins Dana. E and F are already linked. D is not. ---------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

select public.join_coach(
  'ABC234',
  '11111111-0000-4000-8000-000000000001',
  'aaaaaaaa-0000-4000-8000-00000000000a',
  'bbbbbbbb-0000-4000-8000-00000000000b'
);

-- Grants and function shape, before any row is trusted ----------------------------
reset role;

do $$
declare
  fn text;
  def text;
  cols text;
begin
  if has_function_privilege('authenticated', 'public.athlete_display_name(uuid)', 'execute') then
    raise exception 'FAIL: athlete_display_name is executable by authenticated';
  end if;
  if has_function_privilege('anon', 'public.is_active_coach_of(uuid)', 'execute')
     or has_function_privilege('anon', 'public.coach_list_athletes()', 'execute')
     or has_function_privilege('anon', 'public.coach_get_athlete_plan(uuid)', 'execute')
     or has_function_privilege('anon', 'public.coach_get_athletes_workouts(date, date, uuid[])', 'execute')
     or has_function_privilege('anon', 'public.coach_get_athletes_runs(date, date, uuid[])', 'execute') then
    raise exception 'FAIL: anon can execute a coach read function';
  end if;
  if not has_function_privilege('authenticated', 'public.is_active_coach_of(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.coach_list_athletes()', 'execute') then
    raise exception 'FAIL: authenticated cannot execute the coach read functions';
  end if;

  foreach fn in array array[
    'is_active_coach_of', 'athlete_display_name', 'coach_list_athletes',
    'coach_get_athlete_plan', 'coach_get_athletes_workouts', 'coach_get_athletes_runs'
  ] loop
    select pg_get_functiondef(p.oid) into def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = fn;
    if def is null or def !~ 'search_path' or def !~ 'SECURITY DEFINER' then
      raise exception 'FAIL: % is missing security definer or search_path', fn;
    end if;
    if def ~* 'select[[:space:]]+\*' then
      raise exception 'FAIL: % contains select *', fn;
    end if;
  end loop;

  select string_agg(arg, ',' order by ord) into cols
  from (
    select u.ord, u.arg
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral unnest(p.proargmodes, p.proargnames) with ordinality as u(mode, arg, ord)
    where n.nspname = 'public'
      and p.proname = 'coach_get_athletes_runs'
      and u.mode = 't'
  ) output_columns;
  if cols is distinct from 'id,athlete_id,workout_id,completed_at,type,distance_km,duration_seconds,pace,average_heart_rate,source' then
    raise exception 'FAIL: run RPC columns are %', cols;
  end if;
  if cols like '%route%' or cols like '%notes%' then
    raise exception 'FAIL: run RPC exposes route or notes';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename in ('plans', 'workouts', 'runs', 'profiles', 'wellness_checkins',
                        'garmin_activities', 'run_debriefs', 'conversations')
      and (coalesce(qual, '') ilike '%is_active_coach_of%'
           or coalesce(with_check, '') ilike '%is_active_coach_of%')
  ) then
    raise exception 'FAIL: a table policy calls is_active_coach_of';
  end if;
end $$;

-- Active link: Dana sees B, E, and F, and not D -----------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

do $$
declare
  n int;
  payload text;
begin
  if not public.is_active_coach_of('bbbbbbbb-0000-4000-8000-00000000000b') then
    raise exception 'FAIL: Dana is not an active coach of B';
  end if;
  if public.is_active_coach_of('dddddddd-0000-4000-8000-00000000000d') then
    raise exception 'FAIL: Dana is an active coach of unlinked D';
  end if;

  select count(*) into n from public.coach_list_athletes();
  if n <> 3 then raise exception 'FAIL: Dana lists % athletes, expected 3', n; end if;
  if (select display_name from public.coach_list_athletes()
      where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b') is distinct from 'Yoni Cohen' then
    raise exception 'FAIL: B display name did not come from profiles.name';
  end if;
  if (select display_name from public.coach_list_athletes()
      where athlete_id = 'eeeeeeee-0000-4000-8000-00000000000e') is distinct from 'Athlete'
     or (select display_name from public.coach_list_athletes()
         where athlete_id = 'ffffffff-0000-4000-8000-00000000000f') is distinct from 'Athlete' then
    raise exception 'FAIL: blank or missing profile name did not fall back to Athlete';
  end if;
  if not (select has_active_plan from public.coach_list_athletes()
          where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b')
     or not (select has_active_plan from public.coach_list_athletes()
             where athlete_id = 'eeeeeeee-0000-4000-8000-00000000000e')
     or (select has_active_plan from public.coach_list_athletes()
         where athlete_id = 'ffffffff-0000-4000-8000-00000000000f') then
    raise exception 'FAIL: has_active_plan is wrong';
  end if;
  if (select linked_at from public.coach_list_athletes()
      where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b')
     is distinct from (select consented_at from public.coach_athlete_links
                       where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'active') then
    raise exception 'FAIL: linked_at is not consented_at';
  end if;

  select count(*) into n from public.coach_get_athlete_plan('bbbbbbbb-0000-4000-8000-00000000000b');
  if n <> 1 then raise exception 'FAIL: B active plans returned %, expected 1', n; end if;
  if (select title from public.coach_get_athlete_plan('bbbbbbbb-0000-4000-8000-00000000000b')) is distinct from '10K build'
     or (select target_distance from public.coach_get_athlete_plan('bbbbbbbb-0000-4000-8000-00000000000b')) <> 10
     or (select start_date from public.coach_get_athlete_plan('bbbbbbbb-0000-4000-8000-00000000000b')) <> '2026-11-16' then
    raise exception 'FAIL: B plan summary does not match the active plan';
  end if;
  if (select title from public.coach_get_athlete_plan('eeeeeeee-0000-4000-8000-00000000000e')) is distinct from 'Easy start' then
    raise exception 'FAIL: legacy plan with a distinct profile UUID was not returned';
  end if;
  select count(*) into n from public.coach_get_athlete_plan('ffffffff-0000-4000-8000-00000000000f');
  if n <> 0 then raise exception 'FAIL: F has no plan but % rows were returned', n; end if;

  select count(*) into n from public.coach_get_athletes_workouts('2026-11-16', '2026-11-22', null);
  if n <> 2 then raise exception 'FAIL: null athlete filter returned % workouts, expected B and E', n; end if;
  if not exists (
    select 1 from public.coach_get_athletes_workouts('2026-11-16', '2026-11-22', null) w
    where w.id = '30000000-0000-4000-8000-0000000000b1'
      and w.athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
      and w.planned_distance = 5 and w.planned_duration_minutes = 30 and w.target_pace = 360
      and w.completed and w.actual_distance_km = 5.1 and w.actual_duration_minutes = 31
      and w.actual_pace = 365 and w.notes = 'Easy day'
  ) then
    raise exception 'FAIL: B in-range workout actuals were not returned';
  end if;
  select count(*) into n
  from public.coach_get_athletes_workouts(
    '2026-11-16', '2026-11-22',
    array['bbbbbbbb-0000-4000-8000-00000000000b', 'dddddddd-0000-4000-8000-00000000000d']::uuid[]
  );
  if n <> 1 then raise exception 'FAIL: unlinked id was not ignored (% workouts)', n; end if;

  select count(*) into n from public.coach_get_athletes_runs('2026-11-16', '2026-11-22', null);
  if n <> 2 then raise exception 'FAIL: null athlete filter returned % runs, expected B and E', n; end if;
  if not exists (
    select 1 from public.coach_get_athletes_runs('2026-11-16', '2026-11-22', null) r
    where r.athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
      and r.workout_id = '30000000-0000-4000-8000-0000000000b1'
      and r.distance_km = 5.1 and r.duration_seconds = 1860 and r.pace = 364.7
      and r.average_heart_rate = 142 and r.source = 'runsmart_ios'
  ) then
    raise exception 'FAIL: B in-range run summary was not returned';
  end if;
  select count(*) into n from public.coach_get_athletes_runs(
    '2026-11-15', '2026-11-15', array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[]);
  if n <> 1 then
    raise exception 'FAIL: 2026-11-15 23:30 UTC was not kept on the UTC date (% rows)', n;
  end if;

  payload := '';
  select payload || coalesce(string_agg(to_jsonb(a)::text, ''), '') into payload
  from public.coach_list_athletes() a;
  select payload || coalesce(string_agg(to_jsonb(p)::text, ''), '') into payload
  from public.coach_get_athlete_plan('bbbbbbbb-0000-4000-8000-00000000000b') p;
  select payload || coalesce(string_agg(to_jsonb(w)::text, ''), '') into payload
  from public.coach_get_athletes_workouts('2026-11-01', '2026-12-31', null) w;
  select payload || coalesce(string_agg(to_jsonb(r)::text, ''), '') into payload
  from public.coach_get_athletes_runs('2026-11-01', '2026-12-31', null) r;
  if payload like '%SECRET_ROUTE%' or payload like '%PRIVATE_RUN_NOTE%'
     or payload like '%SLEEP_SECRET%' or payload like '%GARMIN_SECRET%'
     or payload like '%DEBRIEF_SECRET%' or payload like '%CHAT_SECRET%'
     or payload like '%Inactive plan%' or payload like '%Not linked%' then
    raise exception 'FAIL: a coach RPC leaked a hidden field or an out-of-scope row';
  end if;
end $$;

-- The same coach still cannot read or write the tables directly -------------------
do $$
declare
  n int;
begin
  select count(*) into n from public.plans;
  if n <> 0 then raise exception 'FAIL: Dana sees % plans through RLS', n; end if;
  select count(*) into n from public.workouts;
  if n <> 0 then raise exception 'FAIL: Dana sees % workouts through RLS', n; end if;
  select count(*) into n from public.runs;
  if n <> 0 then raise exception 'FAIL: Dana sees % runs through RLS', n; end if;
  select count(*) into n from public.profiles;
  if n <> 0 then raise exception 'FAIL: Dana sees % profiles through RLS', n; end if;
  select count(*) into n from public.wellness_checkins;
  if n <> 0 then raise exception 'FAIL: Dana sees % wellness_checkins rows', n; end if;
  select count(*) into n from public.garmin_activities;
  if n <> 0 then raise exception 'FAIL: Dana sees % garmin_activities rows', n; end if;
  select count(*) into n from public.run_debriefs;
  if n <> 0 then raise exception 'FAIL: Dana sees % run_debriefs rows', n; end if;
  select count(*) into n from public.conversations;
  if n <> 0 then raise exception 'FAIL: Dana sees % conversations rows', n; end if;

  update public.plans set title = 'hacked'
  where id = '10000000-0000-4000-8000-0000000000b1';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: Dana updated % plans', n; end if;
  update public.workouts set notes = 'hacked'
  where id = '30000000-0000-4000-8000-0000000000b1';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: Dana updated % workouts', n; end if;
  update public.runs set notes = 'hacked'
  where source_activity_id = 'run-b';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: Dana updated % runs', n; end if;
  delete from public.runs where source_activity_id = 'run-b';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: Dana deleted % runs', n; end if;
end $$;

select pg_temp.expect_error(
  $q$insert into public.plans (profile_id, auth_user_id, title, start_date, end_date, is_active)
     values ('bbbbbbbb-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b',
             'hack', '2026-11-16', '2026-12-27', true)$q$,
  '42501', 'Dana inserting B''s plan');
select pg_temp.expect_error(
  $q$insert into public.workouts (plan_id, auth_user_id, type, distance, scheduled_date)
     values ('10000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
             'easy', 1, '2026-11-18')$q$,
  '42501', 'Dana inserting B''s workout');
select pg_temp.expect_error(
  $q$insert into public.runs (auth_user_id, type, distance, duration, completed_at, source_provider, source_activity_id)
     values ('bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 1, 60, '2026-11-18 08:00:00+00', 'runsmart_ios', 'hack')$q$,
  '42501', 'Dana inserting B''s run');

-- Revoked link: B disappears. E remains. ------------------------------------------
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.leave_coach((
  select id from public.coach_athlete_links
  where athlete_id = auth.uid() and status = 'active'
));
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

do $$
declare
  n int;
begin
  if public.is_active_coach_of('bbbbbbbb-0000-4000-8000-00000000000b') then
    raise exception 'FAIL: revoked link is still active';
  end if;
  select count(*) into n from public.coach_list_athletes()
  where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
  if n <> 0 then raise exception 'FAIL: revoked athlete is still listed'; end if;
  select count(*) into n from public.coach_get_athlete_plan('bbbbbbbb-0000-4000-8000-00000000000b');
  if n <> 0 then raise exception 'FAIL: revoked plan read returned %', n; end if;
  select count(*) into n from public.coach_get_athletes_workouts(
    '2026-11-01', '2026-12-31', array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[]);
  if n <> 0 then raise exception 'FAIL: revoked workout read returned %', n; end if;
  select count(*) into n from public.coach_get_athletes_runs(
    '2026-11-01', '2026-12-31', array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[]);
  if n <> 0 then raise exception 'FAIL: revoked run read returned %', n; end if;
  if (select title from public.coach_get_athlete_plan('eeeeeeee-0000-4000-8000-00000000000e')) is distinct from 'Easy start' then
    raise exception 'FAIL: revoking B also hid E';
  end if;
end $$;

-- No link, another coach, and the athlete themselves ------------------------------
reset role;
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_list_athletes();
  if n <> 0 then raise exception 'FAIL: coach C lists % athletes', n; end if;
  select count(*) into n from public.coach_get_athlete_plan('eeeeeeee-0000-4000-8000-00000000000e');
  if n <> 0 then raise exception 'FAIL: coach C read E''s plan'; end if;
  select count(*) into n from public.coach_get_athletes_workouts('2026-11-01', '2026-12-31', null);
  if n <> 0 then raise exception 'FAIL: coach C read workouts'; end if;
  select count(*) into n from public.coach_get_athletes_runs('2026-11-01', '2026-12-31', null);
  if n <> 0 then raise exception 'FAIL: coach C read runs'; end if;
  if public.is_active_coach_of('eeeeeeee-0000-4000-8000-00000000000e') then
    raise exception 'FAIL: coach C is an active coach of E';
  end if;
end $$;

select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  n int;
begin
  select count(*) into n from public.coach_list_athletes();
  if n <> 0 then raise exception 'FAIL: athlete B listed athletes'; end if;
  select count(*) into n from public.coach_get_athlete_plan('bbbbbbbb-0000-4000-8000-00000000000b');
  if n <> 0 then raise exception 'FAIL: athlete B read their plan through the coach RPC'; end if;
  select count(*) into n from public.coach_get_athletes_runs('2026-11-01', '2026-12-31', null);
  if n <> 0 then raise exception 'FAIL: athlete B read runs through the coach RPC'; end if;
end $$;

-- anon ----------------------------------------------------------------------------
reset role;
set local role anon;
select pg_temp.expect_error('select public.coach_list_athletes()', '42501', 'anon list');
select pg_temp.expect_error(
  $q$select public.coach_get_athlete_plan('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', 'anon plan');
select pg_temp.expect_error(
  $q$select public.coach_get_athletes_workouts('2026-11-16', '2026-11-22', null)$q$,
  '42501', 'anon workouts');
select pg_temp.expect_error(
  $q$select public.coach_get_athletes_runs('2026-11-16', '2026-11-22', null)$q$,
  '42501', 'anon runs');
select pg_temp.expect_error(
  $q$select public.is_active_coach_of('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', 'anon is_active_coach_of');
select pg_temp.expect_error(
  $q$select public.athlete_display_name('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', 'anon athlete_display_name');

reset role;
do $$
begin
  if (select title from public.plans where id = '10000000-0000-4000-8000-0000000000b1') is distinct from '10K build' then
    raise exception 'FAIL: a denied write changed the plan';
  end if;
  if (select count(*) from public.runs where source_activity_id = 'run-b') <> 1 then
    raise exception 'FAIL: a denied delete removed the run';
  end if;
  raise notice 'coach_read: PASS';
end $$;

rollback;
