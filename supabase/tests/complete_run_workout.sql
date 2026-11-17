-- Run only on a throwaway Postgres with runs_workout_link_fixture.sql and both migrations.
begin;

insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
insert into public.plans (id, profile_id, auth_user_id, title) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Plan A'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Plan B');
insert into public.workouts (id, plan_id, auth_user_id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
insert into public.runs (auth_user_id, source_provider, source_activity_id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'healthkit', 'winner'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'garmin', 'other'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'healthkit', 'private');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);

do $$
declare
  a constant uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  b constant uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  workout_a constant uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2';
  second_workout constant uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3';
  workout_b constant uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2';
  ended constant timestamptz := '2026-11-15T11:00:00Z';
begin
  if public.complete_run_workout(a, workout_a, 'healthkit', 'missing', ended, 5, 25, 300) is distinct from 'run_not_synced'
     or exists (select 1 from public.workouts where id = workout_a and completed) then
    raise exception 'Missing run must leave workout incomplete';
  end if;
  if public.complete_run_workout(b, workout_b, 'healthkit', 'private', ended, 5, 25, 300) is distinct from 'not_available'
     or public.complete_run_workout(a, workout_b, 'healthkit', 'winner', ended, 5, 25, 300) is distinct from 'not_available'
     or public.complete_run_workout(a, workout_a, 'healthkit', 'private', ended, 5, 25, 300) is distinct from 'run_not_synced' then
    raise exception 'Other account must not complete or link its workout/run';
  end if;

  -- Force the second write (workout actuals) to fail. The saved run must not retain its link.
  begin
    perform public.complete_run_workout(a, workout_a, 'healthkit', 'winner', ended, 5, 0, 300);
    raise exception 'Expected workout constraint failure';
  exception when check_violation then
    null;
  end;
  if exists (select 1 from public.runs where source_activity_id = 'winner' and workout_id is not null)
     or exists (select 1 from public.workouts where id = workout_a and completed) then
    raise exception 'Workout failure must roll back the run link';
  end if;

  if public.complete_run_workout(a, workout_a, 'healthkit', 'winner', ended, 5.12, 26, 305) is distinct from 'completed' then
    raise exception 'Eligible run did not complete the workout';
  end if;
  if not exists (select 1 from public.runs where source_activity_id = 'winner' and workout_id = workout_a)
     or not exists (
      select 1 from public.workouts where id = workout_a and completed and completed_at = ended
        and actual_distance_km = 5.12 and actual_duration_minutes = 26 and actual_pace = 305
     ) then
    raise exception 'Completion must set both the link and actuals';
  end if;
  if public.complete_run_workout(a, workout_a, 'healthkit', 'winner', ended, 9, 38, 421) is distinct from 'already_completed'
     or public.complete_run_workout(a, workout_a, 'garmin', 'other', ended, 9, 38, 421) is distinct from 'not_available'
     or public.complete_run_workout(a, second_workout, 'healthkit', 'winner', ended, 9, 38, 421) is distinct from 'not_available'
     or not exists (select 1 from public.workouts where id = workout_a and actual_distance_km = 5.12)
     or exists (select 1 from public.workouts where id = second_workout and completed)
     or exists (select 1 from public.runs where source_activity_id = 'other' and workout_id is not null) then
    raise exception 'Retry or a competing run must not change the winning link or actuals';
  end if;

  -- A legacy link that won its slot while the old completion write failed can
  -- finish only from that same run; a different run cannot claim the slot.
  update public.runs set workout_id = second_workout where source_activity_id = 'other';
  insert into public.runs (auth_user_id, source_provider, source_activity_id)
  values (a, 'healthkit', 'competing');
  if public.complete_run_workout(a, second_workout, 'healthkit', 'competing', ended, 8, 44, 330) is distinct from 'not_available'
     or exists (select 1 from public.workouts where id = second_workout and completed) then
    raise exception 'The legacy holder of the workout slot must retain it';
  end if;
  if public.complete_run_workout(a, second_workout, 'garmin', 'other', ended, 4, 21) is distinct from 'completed' then
    raise exception 'The exact incumbent can finish a legacy pending workout';
  end if;
  if not exists (
    select 1 from public.workouts w
    join public.runs r on r.workout_id = w.id
    where w.id = second_workout and w.completed and w.completed_at = ended
      and w.actual_distance_km = 4 and w.actual_duration_minutes = 21 and w.actual_pace is null
      and r.auth_user_id = a and r.source_provider = 'garmin' and r.source_activity_id = 'other'
  ) then
    raise exception 'Upgrade must complete the exact legacy incumbent with its actuals and preserve missing pace';
  end if;

  update public.plans set is_active = false where auth_user_id = a;
  if public.complete_run_workout(a, workout_a, 'healthkit', 'winner', ended, 5, 25, 300) is distinct from 'not_available' then
    raise exception 'A stale client must not complete a workout from an inactive plan';
  end if;
end $$;

reset role;
do $$
begin
  if has_function_privilege('anon', 'public.complete_run_workout(uuid,uuid,text,text,timestamptz,numeric,integer,integer)', 'execute') then
    raise exception 'Anon can execute complete_run_workout';
  end if;
end $$;

rollback;
