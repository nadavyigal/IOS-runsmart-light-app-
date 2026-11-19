-- Two-user test for 20261114130000_runs_workout_link.sql.
--
-- Proves: the owner can link their own workout (directly owned, or owned through
-- the plan); linking another user's workout raises on UPDATE and INSERT; one
-- workout takes at most one run; deleting a workout sets runs.workout_id to
-- null through the FK; the trigger function is not callable by anon/authenticated;
-- and the migration left exactly one column, FK, index and trigger (so applying it
-- twice, as in the run steps below, changed nothing).
-- Raises on the first failure; prints "runs_workout_link: PASS" otherwise.
-- Runs in one transaction and rolls back, but it inserts auth.users rows while
-- it runs: use a local throwaway database, never production.
--
-- Run (blank throwaway supabase/postgres container):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/runs_workout_link_fixture.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114130000_runs_workout_link.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114130000_runs_workout_link.sql   # no-op
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/runs_workout_link.sql
-- Use a superuser-capable role (supabase_admin) so fixture inserts bypass RLS
-- before the test switches roles.

begin;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'link-test-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'link-test-b@example.com', 'authenticated', 'authenticated');

insert into public.plans (id, profile_id, auth_user_id, title) values
  ('aaaaaaaa-0004-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a', 'A plan'),
  ('bbbbbbbb-0004-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b', 'B plan');

insert into public.workouts (id, plan_id, auth_user_id) values
  -- A owns this directly and through the plan.
  ('aaaaaaaa-0005-4000-8000-000000000001', 'aaaaaaaa-0004-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a'),
  -- A owns this only through the plan (no auth_user_id on the workout).
  ('aaaaaaaa-0005-4000-8000-000000000002', 'aaaaaaaa-0004-4000-8000-00000000000a', null),
  -- A third A workout for the unique-index check and the FK delete check.
  ('aaaaaaaa-0005-4000-8000-000000000003', 'aaaaaaaa-0004-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a'),
  ('bbbbbbbb-0005-4000-8000-000000000001', 'bbbbbbbb-0004-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b');

insert into public.runs (id, auth_user_id, source_provider, source_activity_id) values
  (1, 'aaaaaaaa-0000-4000-8000-00000000000a', 'garmin', 'a-1'),
  (2, 'aaaaaaaa-0000-4000-8000-00000000000a', 'garmin', 'a-2'),
  (3, 'aaaaaaaa-0000-4000-8000-00000000000a', 'garmin', 'a-3'),
  (4, 'bbbbbbbb-0000-4000-8000-00000000000b', 'garmin', 'b-1');

-- Structure: one of each, nothing duplicated by a second apply ------------------
do $$
begin
  if (select count(*) from information_schema.columns
        where table_schema = 'public' and table_name = 'runs'
          and column_name = 'workout_id' and data_type = 'uuid' and is_nullable = 'YES') <> 1 then
    raise exception 'runs.workout_id (uuid, nullable) missing';
  end if;
  if (select count(*) from pg_constraint
        where conrelid = 'public.runs'::regclass and conname = 'runs_workout_id_fkey'
          and confdeltype = 'n') <> 1 then
    raise exception 'FK runs_workout_id_fkey ON DELETE SET NULL missing';
  end if;
  if (select count(*) from pg_indexes
        where schemaname = 'public' and tablename = 'runs' and indexname = 'runs_workout_id_unique'
          and indexdef ilike '%unique%' and indexdef ilike '%where%workout_id is not null%') <> 1 then
    raise exception 'partial unique index runs_workout_id_unique missing';
  end if;
  if (select count(*) from pg_trigger
        where tgrelid = 'public.runs'::regclass and tgname = 'runs_enforce_workout_owner'
          and not tgisinternal) <> 1 then
    raise exception 'trigger runs_enforce_workout_owner missing or duplicated';
  end if;
  if has_function_privilege('anon', 'public.runs_enforce_workout_owner()', 'execute')
     or has_function_privilege('authenticated', 'public.runs_enforce_workout_owner()', 'execute') then
    raise exception 'trigger function is executable by anon or authenticated';
  end if;
end $$;

-- As user A -------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-4000-8000-00000000000a', true);
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-4000-8000-00000000000a","role":"authenticated"}', true);

do $$
declare
  linked int;
begin
  -- Owner links a workout they own directly.
  update public.runs set workout_id = 'aaaaaaaa-0005-4000-8000-000000000001' where id = 1;
  get diagnostics linked = row_count;
  if linked <> 1 then raise exception 'owner could not link own workout'; end if;

  -- Owner links a workout they own only through the plan.
  update public.runs set workout_id = 'aaaaaaaa-0005-4000-8000-000000000002' where id = 2;
  get diagnostics linked = row_count;
  if linked <> 1 then raise exception 'owner could not link plan-owned workout'; end if;

  -- Null is always allowed.
  update public.runs set workout_id = null where id = 2;
  update public.runs set workout_id = 'aaaaaaaa-0005-4000-8000-000000000002' where id = 2;

  -- Another user's workout raises on UPDATE.
  begin
    update public.runs set workout_id = 'bbbbbbbb-0005-4000-8000-000000000001' where id = 3;
    raise exception 'A linked B''s workout';
  exception when insufficient_privilege then
    null;
  end;

  -- ... and on INSERT.
  begin
    insert into public.runs (auth_user_id, source_provider, source_activity_id, workout_id)
    values ('aaaaaaaa-0000-4000-8000-00000000000a', 'garmin', 'a-new', 'bbbbbbbb-0005-4000-8000-000000000001');
    raise exception 'A inserted a run on B''s workout';
  exception when insufficient_privilege then
    null;
  end;

  -- A workout id that does not exist is rejected by the trigger too.
  begin
    update public.runs set workout_id = 'aaaaaaaa-0005-4000-8000-0000000000ff' where id = 3;
    raise exception 'A linked a workout that does not exist';
  exception when insufficient_privilege then
    null;
  end;

  -- One workout, one run: a second run on the same workout hits the unique index.
  begin
    update public.runs set workout_id = 'aaaaaaaa-0005-4000-8000-000000000001' where id = 3;
    raise exception 'two runs linked to one workout';
  exception when unique_violation then
    null;
  end;

  update public.runs set workout_id = 'aaaaaaaa-0005-4000-8000-000000000003' where id = 3;
end $$;

-- The trigger function is not callable by the signed-in user.
do $$
begin
  begin
    perform public.runs_enforce_workout_owner();
    raise exception 'authenticated could execute the trigger function';
  exception when insufficient_privilege then
    null;
  end;
end $$;

-- As user B: cannot take A's workout slot -------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-4000-8000-00000000000b', true);
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-4000-8000-00000000000b","role":"authenticated"}', true);

do $$
begin
  begin
    update public.runs set workout_id = 'aaaaaaaa-0005-4000-8000-000000000001' where id = 4;
    raise exception 'B linked A''s workout';
  exception when insufficient_privilege then
    null;
  end;
  update public.runs set workout_id = 'bbbbbbbb-0005-4000-8000-000000000001' where id = 4;
end $$;

-- FK: deleting a workout unlinks the run and keeps it -------------------------
reset role;

delete from public.workouts where id = 'aaaaaaaa-0005-4000-8000-000000000003';

do $$
begin
  if (select count(*) from public.runs where id = 3) <> 1 then
    raise exception 'deleting a workout deleted the run';
  end if;
  if (select workout_id from public.runs where id = 3) is not null then
    raise exception 'deleting a workout did not null runs.workout_id';
  end if;
  -- Untouched links survive.
  if (select count(*) from public.runs where workout_id is not null) <> 3 then
    raise exception 'unexpected link count after delete';
  end if;
end $$;

rollback;

select 'runs_workout_link: PASS' as result;
