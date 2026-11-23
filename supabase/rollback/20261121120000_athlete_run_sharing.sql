-- Rollback for 20261121120000_athlete_run_sharing.sql (C7.3, M1a, Batch A).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- flipping runtime_flags.coach_v2 to false is the first move, and it needs no
-- rollback at all. With the flag off, coaches get no effort and no notes, and
-- athletes' changes stay queued on their phones. Use this file only when the M1a
-- functions themselves are broken.
--
-- Do not run it while a later Batch A file that relies on these columns or
-- functions is applied (M1b and later). Roll back newer files first, newest first.
--
-- Data-preserving:
--   * coach_get_athletes_runs goes back to Story 2.2's ten columns (same
--     arguments), so every coach app keeps reading runs.
--   * purge_coach_data_for_deleted_account goes back to Story 1.5's body.
--   * The M1a functions are dropped: athlete_set_run_rpe, athlete_set_run_note,
--     athlete_set_run_note_hidden, coach_get_run_notes, athlete_own_run_id,
--     athlete_sharing_ack_time.
--   * runs.rpe, runs.athlete_note and runs.note_hidden_from_coach stay, with their
--     values and both check constraints. Re-applying the migration later finds them
--     and changes nothing. With the read functions gone, no coach can read them.
--
-- What clients see after this runs: v2 athlete apps get "function not found" on the
-- sharing writes and keep them queued; coach apps read runs without effort or notes.
-- 1.2.6 apps see no change.

begin;

drop function if exists public.coach_get_athletes_runs(date, date, uuid[]);

create function public.coach_get_athletes_runs(
  p_from date,
  p_to date,
  p_athlete_ids uuid[] default null
)
returns table (
  id bigint,
  athlete_id uuid,
  workout_id uuid,
  completed_at timestamptz,
  type text,
  distance_km numeric,
  duration_seconds integer,
  pace numeric,
  average_heart_rate integer,
  source text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    r.id,
    l.athlete_id,
    r.workout_id,
    r.completed_at,
    r.type,
    r.distance::numeric,
    r.duration::integer,
    r.pace::numeric,
    r.heart_rate::integer,
    r.source_provider
  from public.coach_athlete_links l
  join public.runs r
    on r.auth_user_id = l.athlete_id
   and (r.completed_at at time zone 'utc')::date between p_from and p_to
  where l.status = 'active'
    and public.is_active_coach_of(l.athlete_id)
    and (p_athlete_ids is null or l.athlete_id = any (p_athlete_ids))
  order by r.completed_at, l.athlete_id, r.id;
$$;

revoke all on function public.coach_get_athletes_runs(date, date, uuid[]) from public, anon;
grant execute on function public.coach_get_athletes_runs(date, date, uuid[]) to authenticated;

create or replace function public.purge_coach_data_for_deleted_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then
    raise exception 'missing user' using errcode = '22023';
  end if;

  delete from public.coach_athlete_links
  where athlete_id = p_user_id
     or coach_id = p_user_id;

  -- Coach profile row. Invites cascade from coach_profiles.
  delete from public.coach_profiles
  where user_id = p_user_id;

  -- Later stories. Skip entirely until the table exists.
  if to_regclass('public.coach_feedback') is not null then
    delete from public.coach_feedback
    where athlete_id = p_user_id
       or coach_id = p_user_id;
  end if;

  if to_regclass('public.coach_plan_drafts') is not null then
    delete from public.coach_plan_drafts
    where athlete_id = p_user_id
       or coach_id = p_user_id;
  end if;

  -- delete_account deletes run rows, so an uploaded route stored on runs.route
  -- goes away with the row. If any run row for this user is still present,
  -- drop that column. Guarded so this works before the column exists.
  if to_regclass('public.runs') is not null
     and exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name = 'runs'
         and column_name = 'route'
     )
     and exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name = 'runs'
         and column_name = 'auth_user_id'
     ) then
    execute 'update public.runs set route = null where auth_user_id = $1'
      using p_user_id;
  end if;
end;
$$;

revoke all on function public.purge_coach_data_for_deleted_account(uuid) from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.purge_coach_data_for_deleted_account(uuid) to service_role;
  end if;
end $$;

drop function if exists public.coach_get_run_notes(bigint[]);
drop function if exists public.athlete_set_run_note_hidden(text, text, boolean);
drop function if exists public.athlete_set_run_note(text, text, text);
drop function if exists public.athlete_set_run_rpe(text, text, integer);
drop function if exists public.athlete_sharing_ack_time();
drop function if exists public.athlete_own_run_id(text, text);

commit;

-- Optional, NOT part of the rollback. Deletes every synced effort and note.
-- Export first if you ever run it.
-- alter table public.runs drop constraint if exists runs_athlete_note_length;
-- alter table public.runs drop constraint if exists runs_rpe_range;
-- alter table public.runs drop column if exists note_hidden_from_coach;
-- alter table public.runs drop column if exists athlete_note;
-- alter table public.runs drop column if exists rpe;
