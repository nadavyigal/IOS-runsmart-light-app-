-- Release every coach lock on workouts (Coach Experience v2, C8.1a, M6a).
--
-- NADAV ONLY, owner role (the Supabase SQL editor runs as postgres). Agents never
-- run this file. Read docs/coach-v2-rollback.md first.
--
-- When to use it: only when coach locks themselves must go, for example before
-- dropping the M6 triggers, or when a pilot ends and athletes should get a fully
-- adaptive RunSmart plan back. On a bad day, flip runtime_flags.coach_v2 to false
-- instead: coach writes stop and the locks keep protecting what coaches set.
--
-- What it does, in one transaction:
--   * every workouts row with locked = true becomes locked = false. The planned
--     fields stay exactly as the coach left them, and so do source, coach_id,
--     coach_revision, coach_edited and the athlete-change columns, so the app
--     still knows which workouts a coach wrote. Completed rows are included.
--   * When M6b is applied, plans.coach_published goes back to false as well, so
--     the athlete can regenerate their plan.
--   * It prints the row counts before and after.
--
-- After it runs: the AI, the athlete and 1.2.6 clients can change and delete
-- those workouts again, as for any solo user. It does not delete anything.
--
-- How it gets past the trigger: it sets runsmart.coach_write for this
-- transaction only. The trigger accepts that setting only from a non-client role,
-- so this works from the SQL editor and never from the app.
--
-- To release one athlete only, replace "where w.locked" below with
--   where w.locked and w.auth_user_id = '<athlete user id>'
-- and do the same in the plans block.

begin;

do $$
declare
  v_before bigint;
begin
  select count(*) into v_before from public.workouts where locked;
  raise notice 'release_all_coach_locks: % locked workouts before', v_before;
end $$;

select set_config('runsmart.coach_write', 'on', true);

update public.workouts w
set locked = false
where w.locked;

-- M6b adds plans.coach_published. Skip this block when the column is absent.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'plans' and column_name = 'coach_published'
  ) then
    execute 'update public.plans set coach_published = false where coach_published';
  end if;
end $$;

select set_config('runsmart.coach_write', 'off', true);

do $$
declare
  v_after bigint;
begin
  select count(*) into v_after from public.workouts where locked;
  if v_after <> 0 then
    raise exception 'release_all_coach_locks: % rows still locked; nothing was committed', v_after;
  end if;
  raise notice 'release_all_coach_locks: 0 locked workouts after';
end $$;

commit;
