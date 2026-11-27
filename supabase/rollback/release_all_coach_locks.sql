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
-- To release one athlete only, put their auth user id between the quotes on the
-- RELEASE_ATHLETE line below, for example
--   select set_config('runsmart.release_athlete', '0b1c...-uuid', true);
-- Leave it empty ('') to release every athlete. The plan locks, the before
-- count, the update, the plans block and the after check all use that same
-- filter, so another athlete's locks never make a single-athlete release roll
-- back. A workout's athlete is resolved the way the coach RPCs resolve it:
-- coalesce(workouts.auth_user_id, plans.auth_user_id, plans.profile_id), so a
-- locked row with a null auth_user_id is still found.
--
-- Lock order (same as the M6a coach RPCs: plan before workout): it locks the
-- affected plans FOR UPDATE first, then updates workouts, then plans. A coach
-- write holds the plan FOR SHARE and then locks its workout, so this script
-- waits for it instead of deadlocking with it.

begin;

-- RELEASE_ATHLETE: '' = every athlete, or one athlete's auth user id.
select set_config('runsmart.release_athlete', '', true);

-- 1. Lock the affected plans first (FOR UPDATE, in id order).
do $$
begin
  perform 1 from public.plans p
  where exists (
      select 1 from public.workouts w
      where w.plan_id = p.id and w.locked
        and (nullif(current_setting('runsmart.release_athlete', true), '') is null
         or coalesce(w.auth_user_id, p.auth_user_id, p.profile_id)
            = nullif(current_setting('runsmart.release_athlete', true), '')::uuid)
    )
  order by p.id
  for update of p;

  -- M6b adds plans.coach_published. Lock those plans too, before any workout.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'plans' and column_name = 'coach_published'
  ) then
    execute $u$
      select 1 from public.plans p
      where p.coach_published
        and (nullif(current_setting('runsmart.release_athlete', true), '') is null
         or coalesce(p.auth_user_id, p.profile_id)
            = nullif(current_setting('runsmart.release_athlete', true), '')::uuid)
      order by p.id
      for update of p
    $u$;
  end if;
end $$;

do $$
declare
  v_before bigint;
begin
  select count(*) into v_before
  from public.workouts w
  left join public.plans p on p.id = w.plan_id
  where w.locked
    and (nullif(current_setting('runsmart.release_athlete', true), '') is null
         or coalesce(w.auth_user_id, p.auth_user_id, p.profile_id)
            = nullif(current_setting('runsmart.release_athlete', true), '')::uuid);
  raise notice 'release_all_coach_locks: % locked workouts before', v_before;
end $$;

select set_config('runsmart.coach_write', 'on', true);

-- 2. Workouts.
update public.workouts w
set locked = false
where w.locked
  and w.id in (
    select w2.id
    from public.workouts w2
    left join public.plans p on p.id = w2.plan_id
    where w2.locked
      and (nullif(current_setting('runsmart.release_athlete', true), '') is null
         or coalesce(w2.auth_user_id, p.auth_user_id, p.profile_id)
            = nullif(current_setting('runsmart.release_athlete', true), '')::uuid)
  );

-- 3. Plans (M6b's plans.coach_published). Skipped when the column is absent.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'plans' and column_name = 'coach_published'
  ) then
    execute $u$
      update public.plans p set coach_published = false
      where p.coach_published
        and (nullif(current_setting('runsmart.release_athlete', true), '') is null
         or coalesce(p.auth_user_id, p.profile_id)
            = nullif(current_setting('runsmart.release_athlete', true), '')::uuid)
    $u$;
  end if;
end $$;

select set_config('runsmart.coach_write', 'off', true);

do $$
declare
  v_after bigint;
begin
  select count(*) into v_after
  from public.workouts w
  left join public.plans p on p.id = w.plan_id
  where w.locked
    and (nullif(current_setting('runsmart.release_athlete', true), '') is null
         or coalesce(w.auth_user_id, p.auth_user_id, p.profile_id)
            = nullif(current_setting('runsmart.release_athlete', true), '')::uuid);
  if v_after <> 0 then
    raise exception 'release_all_coach_locks: % rows still locked; nothing was committed', v_after;
  end if;
  raise notice 'release_all_coach_locks: 0 locked workouts after';
end $$;

commit;
