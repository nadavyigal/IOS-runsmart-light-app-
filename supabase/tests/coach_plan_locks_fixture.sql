-- THROWAWAY DATABASES ONLY. Never run against production or staging.
--
-- coach_workout_locks_fixture.sql plus the plans columns that the two plan
-- replacement RPCs write (replace_group_training_plan, Story 1.8, and M6b's
-- athlete_replace_training_plan, 20261127110000_coach_plan_locks.sql), and the
-- one-active-plan-per-profile index. Types, defaults and CHECKs match the live
-- production read of 2026-11-27.
--
-- One deliberate difference: plans.total_weeks is NOT NULL in production with no
-- default. Here it defaults to 1 so the older suites that share the base fixture
-- can keep inserting plans without it.

\ir coach_workout_locks_fixture.sql

begin;

alter table public.plans
  add column description text,
  add column total_weeks integer not null default 1,
  add column plan_type text not null default 'basic'
    constraint plans_plan_type_check check (plan_type in ('basic', 'advanced', 'periodized')),
  add column training_days_per_week integer
    constraint plans_training_days_per_week_check check (training_days_per_week between 1 and 7),
  add column peak_weekly_volume numeric;

create unique index idx_plans_single_active on public.plans (profile_id) where is_active = true;

commit;
