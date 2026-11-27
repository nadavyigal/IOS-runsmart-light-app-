-- Rollback for 20261127110000_coach_plan_locks.sql (C8.1b, M6b, Batch C).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- flipping runtime_flags.coach_v2 to false is the first move. With the flag off,
-- coach writes and athlete skip / move stop (v2_unavailable); plan replacement
-- and link end keep working.
--
-- Run this before the M6a rollback (20261127100000_coach_workout_locks.sql):
-- the functions restored here do not need M6a, but M6a's rollback assumes M6b is
-- gone.
--
-- WARNING: once athletes have coach-published plans or coach workouts, dropping
-- the plans trigger lets 1.2.6 clients, the web sync and persistGeneratedPlan
-- deactivate or delete those plans again (deleting a plan cascades to its locked
-- workouts). Ending a link stops releasing locks: after this file, unlock rows
-- with supabase/rollback/release_all_coach_locks.sql when needed.
--
-- Data-preserving:
--   * The triggers plans_protect_coach_plans and
--     coach_links_release_locks_on_delete and their functions are dropped.
--   * athlete_replace_training_plan, athlete_change_coach_workout,
--     coach_plan_locked_future_count and coach_release_athlete_locks are dropped.
--   * end_coach_link is restored to its M5b body (20261121160000) and
--     replace_group_training_plan to its Story 1.8 body (20261117163000), same
--     signatures and grants.
--   * The plans columns coach_published and coach_id stay, with their values.
--     coach_athlete_events rows (athlete_skip, athlete_move, goal_change) stay.
--     workouts rows keep their athlete_change, athlete_changed_at, original_date.
--   * Re-applying the migration later finds the columns and changes nothing in them.
--
-- What clients see after this runs: v2 athletes get "function not found" on
-- skip / move / replace and keep them queued; persistGeneratedPlan's direct
-- deactivation works again for linked athletes. 1.2.6 apps see no change.

begin;

drop trigger if exists plans_protect_coach_plans on public.plans;
drop function if exists public.plans_protect_coach_plans();

drop trigger if exists coach_links_release_locks_on_delete on public.coach_athlete_links;
drop function if exists public.coach_links_release_locks_on_delete();

drop function if exists public.athlete_replace_training_plan(uuid, jsonb, jsonb, integer);
drop function if exists public.athlete_change_coach_workout(uuid, text, date, uuid);

-- end_coach_link: the M5b body (20261121160000_coach_link_end.sql), verbatim.
create or replace function public.end_coach_link(p_link_id uuid, p_ended_by text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_coach uuid;
  v_athlete uuid;
begin
  if p_link_id is null then
    raise exception 'missing link' using errcode = '22023';
  end if;
  if p_ended_by is null or p_ended_by not in ('athlete', 'coach') then
    raise exception 'invalid ended_by' using errcode = '22023';
  end if;

  update public.coach_athlete_links
  set status = 'revoked',
      revoked_at = now(),
      ended_by = p_ended_by
  where id = p_link_id
    and status = 'active'
  returning coach_id, athlete_id into v_coach, v_athlete;

  if not found then
    return false;
  end if;

  insert into public.coach_athlete_events (coach_id, athlete_id, kind)
  values (v_coach, v_athlete, case p_ended_by when 'athlete' then 'left' else 'removed' end);

  -- Later create or replace files add here, in this order: M6b (C8.1b) clears
  -- locked / coach_published on this athlete's future workouts; M7 (C8.6)
  -- deletes this athlete's drafts for v_coach. Neither table or column exists
  -- yet, so this version must not touch them.

  return true;
end;
$$;

revoke all on function public.end_coach_link(uuid, text) from public, anon, authenticated;

-- replace_group_training_plan: the Story 1.8 body (20261117163000), verbatim.
create or replace function public.replace_group_training_plan(
  expected_athlete uuid, new_plan jsonb, new_workouts jsonb
) returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  athlete uuid := auth.uid();
  plan_row public.plans%rowtype;
  new_plan_id uuid;
begin
  if athlete is null or athlete is distinct from expected_athlete then
    raise exception 'Plan replacement requires the confirming athlete' using errcode = '42501';
  end if;
  if jsonb_typeof(new_workouts) is distinct from 'array' then
    raise exception 'Workouts must be an array' using errcode = '22023';
  end if;
  if jsonb_array_length(new_workouts) = 0 then
    raise exception 'A replacement plan requires workouts' using errcode = '22023';
  end if;

  -- Existing owner RLS applies. Serialize concurrent group replacements.
  perform pg_advisory_xact_lock(hashtextextended(athlete::text, 18));
  plan_row := jsonb_populate_record(null::public.plans, new_plan);
  update public.plans
  set is_active = false
  where is_active and (
    auth_user_id = athlete
    or (auth_user_id is null and profile_id = plan_row.profile_id)
  );

  insert into public.plans (
    profile_id, auth_user_id, title, description, start_date, end_date,
    total_weeks, is_active, plan_type, training_days_per_week, target_distance,
    target_time, peak_weekly_volume
  ) values (
    plan_row.profile_id, athlete, plan_row.title, plan_row.description,
    plan_row.start_date, plan_row.end_date, plan_row.total_weeks, true,
    plan_row.plan_type, plan_row.training_days_per_week, plan_row.target_distance,
    plan_row.target_time, plan_row.peak_weekly_volume
  )
  returning id into new_plan_id;

  insert into public.workouts (
    plan_id, auth_user_id, week, day, type, distance, duration, pace,
    completed, scheduled_date, notes, workout_structure, intensity, training_phase
  )
  select
    new_plan_id, athlete, w.week, w.day, w.type, w.distance, w.duration, w.pace,
    false, w.scheduled_date, w.notes, w.workout_structure, w.intensity, w.training_phase
  from jsonb_populate_recordset(null::public.workouts, new_workouts) w;
end
$$;

revoke all on function public.replace_group_training_plan(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.replace_group_training_plan(uuid, jsonb, jsonb) to authenticated;

-- Dropped last: the M5b end_coach_link above no longer calls them.
drop function if exists public.coach_release_athlete_locks(uuid);
drop function if exists public.coach_plan_locked_future_count(uuid);

commit;
