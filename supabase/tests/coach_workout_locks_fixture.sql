-- THROWAWAY DATABASES ONLY. Never run against production or staging.
--
-- coach_read_fixture.sql plus the plans / workouts columns that M6a
-- (20261127100000_coach_workout_locks.sql) and the writers it protects touch.
-- Column types, CHECKs, the (plan_id, local_id) partial unique index and the
-- updated_at trigger match the live production read of 2026-11-27.
--
-- One deliberate difference: workouts.week and workouts.day are NOT NULL in
-- production with no default. Here they default to 1 / 'Mon' so the older suites
-- that share this fixture (kill_switch) can keep inserting workouts without them.
-- Every M6a RPC and every test in coach_workout_locks.sql sets both explicitly.

\ir coach_read_fixture.sql

begin;

alter table public.plans
  add column created_in_timezone text default 'UTC',
  add column local_id bigint,
  add column created_at timestamptz not null default now(),
  add column updated_at timestamptz not null default now();

alter table public.workouts
  add column week integer not null default 1,
  add column day text not null default 'Mon'
    constraint workouts_day_check check (day in ('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')),
  add column intensity text
    constraint workouts_intensity_check check (intensity in ('easy', 'moderate', 'threshold', 'vo2max', 'anaerobic')),
  add column training_phase text
    constraint workouts_training_phase_check check (training_phase in ('base', 'build', 'peak', 'taper')),
  add column workout_structure jsonb,
  add column local_id bigint,
  add column created_at timestamptz not null default now(),
  add column updated_at timestamptz not null default now(),
  add constraint workouts_type_check check (type in ('easy', 'tempo', 'intervals', 'long', 'time-trial',
                                                     'hill', 'rest', 'race-pace', 'recovery', 'fartlek'));

create unique index idx_workouts_plan_local_id on public.workouts (plan_id, local_id) where local_id is not null;
create index idx_workouts_plan_id on public.workouts (plan_id);

create function public.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger update_workouts_updated_at before update on public.workouts
  for each row execute function public.update_updated_at_column();
create trigger update_plans_updated_at before update on public.plans
  for each row execute function public.update_updated_at_column();

commit;
