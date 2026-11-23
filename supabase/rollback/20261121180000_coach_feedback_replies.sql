-- Rollback for 20261121180000_coach_feedback_replies.sql (C7.7, M4, Batch A).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- flipping runtime_flags.coach_v2 to false is the first move, and it needs no
-- rollback at all. Use this file only when the M4 functions themselves are broken.
--
-- Do not run it while a later file that replaces coach_roster_summary or
-- purge_coach_data_for_deleted_account, or reads coach_feedback_replies, is applied.
-- Roll back newer files first, newest first.
--
-- Data-preserving:
--   * coach_roster_summary goes back to C7.4's body (same signature, new_replies 0).
--   * purge_coach_data_for_deleted_account goes back to C7.4's body (Story 1.5, the
--     C7.3 block and the C7.4 block). While coach_feedback_replies still exists, a
--     deleted user's replies still go: author_id is on delete cascade from auth.users,
--     feedback_id is on delete cascade from coach_feedback, and the C7.4 purge still
--     deletes the user's coach_feedback rows.
--   * The four reply functions are dropped: athlete_reply_to_feedback,
--     my_feedback_replies, coach_get_feedback_replies, coach_mark_reply_read.
--   * coach_feedback_replies stays, with every row, RLS on and its owner-select
--     policy. Re-applying the migration later finds it and changes nothing.
--
-- What clients see after this runs: v2 athlete apps get "function not found" on reply
-- sends and keep them queued (dropped after 14 days); replies already on the phone stay
-- readable there. v2 coach apps fail the replies read and show notes without replies.
-- 1.2.6 apps see no change.

begin;

-- C7.4 (20261121150000_athlete_run_flags.sql), verbatim.
create or replace function public.coach_roster_summary()
returns table (
  athlete_id uuid,
  seen_at timestamptz,
  new_runs integer,
  new_flags integer,
  new_replies integer,
  new_events integer,
  latest_event_kind text,
  oldest_new_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with pairs as (
    select
      l.id as link_id,
      l.coach_id,
      l.athlete_id,
      s.seen_at,
      greatest(coalesce(s.seen_at, '-infinity'::timestamptz), now() - interval '7 days') as baseline
    from public.coach_athlete_links l
    left join public.coach_athlete_seen s
      on s.coach_id = l.coach_id
     and s.athlete_id = l.athlete_id
    where auth.uid() is not null
      and l.coach_id = auth.uid()
      and l.status = 'active'
      and public.is_active_coach_of(l.athlete_id)
      and public.link_is_v2(l.coach_id, l.athlete_id)
  ),
  run_counts as (
    select p.athlete_id, count(r.id)::integer as n, min(r.completed_at) as oldest
    from pairs p
    join public.runs r
      on r.auth_user_id = p.athlete_id
     and r.completed_at > p.baseline
     and r.completed_at <= now()
    group by p.athlete_id
  ),
  flag_counts as (
    select p.athlete_id, count(f.id)::integer as n, min(f.created_at) as oldest
    from pairs p
    join public.athlete_run_flags f
      on f.link_id = p.link_id
     and f.athlete_id = p.athlete_id
     and f.resolved_at is null
     and f.created_at > p.baseline
    where public.coach_v2_sharing_allowed(p.coach_id, p.athlete_id)
    group by p.athlete_id
  ),
  event_counts as (
    select
      p.athlete_id,
      count(e.id)::integer as n,
      min(e.created_at) as oldest,
      (array_agg(e.kind order by e.created_at desc, e.id desc))[1] as latest_kind
    from pairs p
    join public.coach_athlete_events e
      on e.coach_id = auth.uid()
     and e.athlete_id = p.athlete_id
     and e.created_at > p.baseline
     and e.kind in ('goal_change', 'athlete_skip', 'athlete_move')
    group by p.athlete_id
  )
  select
    p.athlete_id,
    p.seen_at,
    coalesce(rc.n, 0),
    coalesce(fc.n, 0),
    0,
    coalesce(ec.n, 0),
    ec.latest_kind,
    (select min(t) from (values (rc.oldest), (fc.oldest), (ec.oldest)) v(t))
  from pairs p
  left join run_counts rc on rc.athlete_id = p.athlete_id
  left join flag_counts fc on fc.athlete_id = p.athlete_id
  left join event_counts ec on ec.athlete_id = p.athlete_id
  order by p.athlete_id;
$$;

-- C7.4 (20261121150000_athlete_run_flags.sql), verbatim.
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

  -- C7.4: flags first, while their links still exist. As the athlete the flags go;
  -- as the coach only the "handled by" reference goes (the flag is the athlete's).
  if to_regclass('public.athlete_run_flags') is not null then
    delete from public.athlete_run_flags
    where athlete_id = p_user_id;

    update public.athlete_run_flags
       set resolved_by = null
     where resolved_by = p_user_id;
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

  -- C7.3: effort and the athlete's note on any run row that is still present.
  if to_regclass('public.runs') is not null
     and exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name = 'runs'
         and column_name = 'athlete_note'
     ) then
    execute 'update public.runs set rpe = null, athlete_note = null, note_hidden_from_coach = false '
            'where auth_user_id = $1'
      using p_user_id;
  end if;
end;
$$;

drop function if exists public.coach_mark_reply_read(uuid[]);
drop function if exists public.coach_get_feedback_replies(uuid[]);
drop function if exists public.my_feedback_replies();
drop function if exists public.athlete_reply_to_feedback(uuid, text, uuid);

revoke all on function public.coach_roster_summary() from public, anon;
grant execute on function public.coach_roster_summary() to authenticated;
revoke all on function public.purge_coach_data_for_deleted_account(uuid) from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.purge_coach_data_for_deleted_account(uuid) to service_role;
  end if;
end $$;

commit;

-- Optional, destructive, NOT part of the rollback. Deletes every reply athletes sent.
-- It is text the athletes own: export first, and only with a reason.
-- drop table if exists public.coach_feedback_replies;
