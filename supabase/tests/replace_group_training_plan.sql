begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'This test requires a throwaway database';
  end if;
end
$$;

alter table public.plans
  add column description text, add column start_date date, add column end_date date,
  add column total_weeks integer, add column plan_type text,
  add column training_days_per_week integer, add column target_distance numeric,
  add column target_time integer, add column peak_weekly_volume numeric;
alter table public.workouts
  add column week integer, add column day text, add column type text,
  add column distance numeric check (distance > 0), add column duration integer,
  add column pace integer, add column scheduled_date date, add column notes text,
  add column workout_structure text, add column intensity text, add column training_phase text;

insert into auth.users(id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'athlete@example.test', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'other@example.test', 'authenticated', 'authenticated');

insert into public.plans (profile_id, auth_user_id, title)
select id, id, 'Existing' from auth.users;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-4000-8000-000000000001', true);

do $$
declare
  athlete uuid := auth.uid();
  replacement jsonb := jsonb_build_object('profile_id', athlete, 'title', 'Group plan');
begin
  begin
    perform public.replace_group_training_plan(
      'bbbbbbbb-0000-4000-8000-000000000001', replacement, '[{"distance":5}]'
    );
    raise exception 'wrong athlete accepted';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform public.replace_group_training_plan(
      athlete, replacement, '[{"distance":5},{"distance":0}]'
    );
    raise exception 'invalid workout accepted';
  exception when check_violation then
    null;
  end;

  if not exists (select 1 from public.plans where title = 'Existing' and is_active)
     or exists (select 1 from public.plans where title = 'Group plan') then
    raise exception 'failed replacement changed the active plan';
  end if;

  perform public.replace_group_training_plan(athlete, replacement, '[{"distance":5}]');
  if exists (select 1 from public.plans where title = 'Existing' and is_active)
     or not exists (
       select 1 from public.plans p join public.workouts w on w.plan_id = p.id
       where p.title = 'Group plan' and p.is_active and w.distance = 5
     ) then
    raise exception 'replacement and workouts were not saved together';
  end if;
end
$$;

reset role;
do $$
begin
  if not exists (select 1 from public.plans
                 where auth_user_id = 'bbbbbbbb-0000-4000-8000-000000000001' and is_active) then
    raise exception 'unrelated athlete changed';
  end if;
end
$$;
rollback;
