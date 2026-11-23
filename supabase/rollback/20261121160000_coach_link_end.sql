-- Rollback for 20261121160000_coach_link_end.sql (C7.11, M5b, Batch A).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- flipping runtime_flags.coach_v2 to false is the first move. With it off the
-- removal notice is hidden, but removal and leave keep working, because the
-- switch never blocks ending a link. Use this file only when the M5b functions
-- themselves are broken.
--
-- Do not run it while a later file that replaces end_coach_link is applied
-- (M6b in Batch C, M7 in Batch D). Roll back newer files first, newest first.
--
-- Data-preserving:
--   * leave_coach goes back to Story 1.5's body (same signature, void return,
--     same errors), so 1.2.6 and v2 athletes keep leaving. It no longer sets
--     ended_by or logs a left event.
--   * The M5b functions are dropped: coach_remove_athlete, mark_link_notice_seen,
--     my_coach_link_notice, coach_link_notice_allowed, end_coach_link.
--   * coach_athlete_links.ended_by and ended_notice_seen_at stay, with their
--     values and the check constraint. Every removed / left marker and every
--     "notice seen" time is kept. Re-applying the migration later finds them and
--     changes nothing, and a removal notice not yet seen shows again.
--   * coach_athlete_events rows (left / removed) stay: they belong to M3.
--
-- What clients see after this runs: v2 coach apps get "function not found" from
-- Remove {Athlete} and show the remove error; the athlete stays linked. v2
-- athlete apps fail the notice read and show nothing. 1.2.6 apps see no change.

begin;

create or replace function public.leave_coach(expected_link_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_coach uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  update public.coach_athlete_links
  set status = 'revoked',
      revoked_at = now()
  where athlete_id = v_uid
    and id = expected_link_id
    and status = 'active'
  returning coach_id into v_coach;

  if not found then
    raise exception 'not_linked' using errcode = 'P0001';
  end if;

  -- STORY 4.2 HOOK: also delete this athlete's public.coach_plan_drafts rows
  -- for v_coach (the coach returned above). The table does not exist yet, so
  -- this function must not query it. Story 4.2 adds that delete here.
end;
$$;

revoke all on function public.leave_coach(uuid) from public, anon;
grant execute on function public.leave_coach(uuid) to authenticated;

drop function if exists public.coach_remove_athlete(uuid);
drop function if exists public.mark_link_notice_seen(uuid);
drop function if exists public.my_coach_link_notice();
drop function if exists public.coach_link_notice_allowed(uuid);
drop function if exists public.end_coach_link(uuid, text);

commit;

-- Optional, destructive, NOT part of the rollback. Deletes who ended each link
-- and when each removal notice was seen. Export first.
-- alter table public.coach_athlete_links drop constraint if exists coach_athlete_links_ended_by;
-- alter table public.coach_athlete_links drop column if exists ended_notice_seen_at;
-- alter table public.coach_athlete_links drop column if exists ended_by;
