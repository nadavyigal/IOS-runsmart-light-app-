-- Story 3.2. The athlete reads their feedback through my_coach_feedback() with the
-- coach's name and the run's source key; after leaving the coach the rows are still
-- returned; another user gets nothing; only the owner can mark a row read, once;
-- text never changes; RLS on coach_feedback is unchanged.
--
-- Blank throwaway Postgres only. Apply coach_read_fixture, Stories 1.2, 1.3, 1.5,
-- 2.2 and 3.1, then this migration twice, then this file.

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'athlete_feedback_read.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'third-d@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now());

insert into public.runs (id, auth_user_id, type, distance, duration, completed_at, source_provider, source_activity_id) values
  (101, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5, 1800, '2026-11-16T07:00:00Z',
   'runsmart_ios', '11111111-2222-4333-8444-555555555555');

insert into public.coach_feedback (id, coach_id, athlete_id, run_id, week_start, text, created_at) values
  ('40000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000a',
   'bbbbbbbb-0000-4000-8000-00000000000b', 101, null, 'Strong finish.', '2026-11-16T09:00:00Z'),
  ('40000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-00000000000a',
   'bbbbbbbb-0000-4000-8000-00000000000b', null, '2026-11-16', 'שבוע טוב', '2026-11-17T09:00:00Z');

create function pg_temp.act_as(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

create function pg_temp.expect_error(stmt text, expected_state text, label text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL: % succeeded but should have failed with %', label, expected_state;
exception when others then
  if sqlstate = 'P0001' and sqlerrm like 'FAIL:%' then raise; end if;
  if sqlstate <> expected_state then
    raise exception 'FAIL: % failed with % (%), expected %', label, sqlstate, sqlerrm, expected_state;
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.expect_error(text, text, text) to authenticated, anon;

-- RLS unchanged: still SELECT-only policies -------------------------------------
do $$
begin
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'coach_feedback'
             and cmd <> 'SELECT') then
    raise exception 'FAIL: coach_feedback gained a write policy';
  end if;
end $$;

-- The athlete reads both notes, newest first, with the coach name and run key ------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  rows_json json;
begin
  if (select count(*) from public.my_coach_feedback()) <> 2 then
    raise exception 'FAIL: athlete sees % rows, expected 2', (select count(*) from public.my_coach_feedback());
  end if;
  if (select id from public.my_coach_feedback() limit 1) <> '40000000-0000-4000-8000-000000000002' then
    raise exception 'FAIL: rows are not newest first';
  end if;
  select json_agg(f) into rows_json from public.my_coach_feedback() f where f.run_id = 101;
  -- `is distinct from`, so a missing (null) field fails instead of passing silently.
  if (rows_json->0->>'coach_name') is distinct from 'Dana'
     or (rows_json->0->>'run_source_provider') is distinct from 'runsmart_ios'
     or (rows_json->0->>'run_source_activity_id') is distinct from '11111111-2222-4333-8444-555555555555'
     or (rows_json->0->>'read_at') is not null then
    raise exception 'FAIL: run note fields wrong: %', rows_json;
  end if;
end $$;

-- The athlete still can't read coach_profiles directly.
do $$
begin
  if exists (select 1 from public.coach_profiles) then
    raise exception 'FAIL: athlete reads coach_profiles directly';
  end if;
exception when insufficient_privilege then
  null;
end $$;

-- Mark read: sets read_at once, text unchanged ---------------------------------------
do $$
declare
  first_read timestamptz;
begin
  first_read := public.mark_feedback_read('40000000-0000-4000-8000-000000000001');
  if first_read is null then raise exception 'FAIL: mark read returned null'; end if;
  if (select read_at from public.my_coach_feedback() where id = '40000000-0000-4000-8000-000000000001')
     is distinct from first_read then
    raise exception 'FAIL: read_at not stored';
  end if;
end $$;

-- now() is the same inside one transaction, so pin the stored time to a known past value
-- and check that a second call keeps it instead of writing a new one.
reset role;
update public.coach_feedback set read_at = '2026-01-01T00:00:00Z'
where id = '40000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
do $$
declare
  returned timestamptz;
  stored timestamptz;
begin
  -- Two statements: the stored value is read after the call, not in its snapshot.
  returned := public.mark_feedback_read('40000000-0000-4000-8000-000000000001');
  select f.read_at into stored from public.my_coach_feedback() f
  where f.id = '40000000-0000-4000-8000-000000000001';
  if returned is distinct from '2026-01-01T00:00:00Z'::timestamptz
     or stored is distinct from '2026-01-01T00:00:00Z'::timestamptz then
    raise exception 'FAIL: a second mark read overwrote the first read_at (returned %, stored %)', returned, stored;
  end if;
  if (select text from public.my_coach_feedback() where id = '40000000-0000-4000-8000-000000000001')
     is distinct from 'Strong finish.' then
    raise exception 'FAIL: marking read changed the text';
  end if;
end $$;

select pg_temp.expect_error(
  $q$update public.coach_feedback set text = 'changed'$q$, '42501', 'athlete direct update');
select pg_temp.expect_error(
  $q$select public.mark_feedback_read('99999999-0000-4000-8000-000000000009')$q$, 'P0002', 'mark a missing note');

-- Another user gets nothing and can't mark B's note --------------------------------
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
do $$
begin
  if (select count(*) from public.my_coach_feedback()) <> 0 then
    raise exception 'FAIL: a third user sees feedback';
  end if;
end $$;
select pg_temp.expect_error(
  $q$select public.mark_feedback_read('40000000-0000-4000-8000-000000000002')$q$, 'P0002', 'third user marks read');

-- The coach can't mark it read either (only the athlete records read_at).
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_error(
  $q$select public.mark_feedback_read('40000000-0000-4000-8000-000000000002')$q$, 'P0002', 'coach marks read');

-- After B leaves, B still reads both notes -----------------------------------------
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.leave_coach(
  (select id from public.coach_athlete_links
   where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'active'));
do $$
begin
  if (select count(*) from public.my_coach_feedback()) <> 2 then
    raise exception 'FAIL: after leaving the athlete sees % rows, expected 2', (select count(*) from public.my_coach_feedback());
  end if;
  if (select coach_name from public.my_coach_feedback() limit 1) is distinct from 'Dana' then
    raise exception 'FAIL: coach name missing after leaving';
  end if;
end $$;

-- anon has nothing ------------------------------------------------------------------
reset role;
set local role anon;
select pg_temp.expect_error($q$select * from public.my_coach_feedback()$q$, '42501', 'anon reads');
select pg_temp.expect_error(
  $q$select public.mark_feedback_read('40000000-0000-4000-8000-000000000002')$q$, '42501', 'anon marks read');

rollback;
