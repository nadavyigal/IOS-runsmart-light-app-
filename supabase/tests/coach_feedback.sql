-- Story 3.1. A coach writes feedback on a run or a week through two RPCs.
-- Only the author coach can add or edit; only that coach (while linked) and
-- that athlete can read; a third user sees nothing; a revoked coach can't add,
-- edit, or read; empty text, both or neither target, and another athlete's run
-- are rejected; the purge used by delete_account removes the rows.
--
-- Blank throwaway Postgres only. Apply coach_read_fixture, Stories 1.2, 1.3,
-- 1.5 and 2.2, then this migration twice, then this file.

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_feedback.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'third-d@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now()),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-00000000000e', 'active', now());

insert into public.runs (id, auth_user_id, type, distance, duration, completed_at) values
  (101, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5, 1800, '2026-11-16T07:00:00Z'),
  (202, 'eeeeeeee-0000-4000-8000-00000000000e', 'easy', 6, 2100, '2026-11-16T07:00:00Z');

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

create function pg_temp.expect_count(stmt text, expected int, label text) returns void
language plpgsql as $$
declare
  n int;
begin
  execute 'select count(*) from (' || stmt || ') q' into n;
  if n <> expected then
    raise exception 'FAIL: % returned % rows, expected %', label, n, expected;
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.expect_error(text, text, text),
  pg_temp.expect_count(text, int, text) to authenticated, anon;

-- Shape ------------------------------------------------------------------------
do $$
begin
  if (select data_type from information_schema.columns
      where table_schema = 'public' and table_name = 'coach_feedback' and column_name = 'run_id') <> 'bigint' then
    raise exception 'FAIL: run_id is not bigint';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.coach_feedback'::regclass) then
    raise exception 'FAIL: RLS is off on coach_feedback';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'coach_feedback'
             and cmd <> 'SELECT') then
    raise exception 'FAIL: coach_feedback has a client write policy';
  end if;
  if (select confdeltype from pg_constraint where conname = 'coach_feedback_athlete_id_fkey') <> 'c' then
    raise exception 'FAIL: athlete_id FK does not cascade';
  end if;
  if (select confdeltype from pg_constraint where conname = 'coach_feedback_run_id_fkey') <> 'c' then
    raise exception 'FAIL: run_id FK missing or does not cascade';
  end if;
end $$;

-- Dana writes on B's run and on E's week ----------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

do $$
declare
  r public.coach_feedback;
begin
  select * into r from public.coach_add_feedback(
    'bbbbbbbb-0000-4000-8000-00000000000b', 101, null, '  Strong finish.  ',
    '30000000-0000-4000-8000-000000000001');
  if r.text <> 'Strong finish.' or r.run_id <> 101 or r.week_start is not null
     or r.coach_id <> 'aaaaaaaa-0000-4000-8000-00000000000a' or r.read_at is not null then
    raise exception 'FAIL: run note stored wrong: %', row_to_json(r);
  end if;

  -- Same client id again: the stored row comes back, no duplicate.
  select * into r from public.coach_add_feedback(
    'bbbbbbbb-0000-4000-8000-00000000000b', 101, null, 'Strong finish.',
    '30000000-0000-4000-8000-000000000001');
  if (select count(*) from public.coach_feedback where run_id = 101) <> 1 then
    raise exception 'FAIL: a retried note was stored twice';
  end if;

  select * into r from public.coach_add_feedback(
    'eeeeeeee-0000-4000-8000-00000000000e', null, '2026-11-16', 'שבוע טוב, keep it easy.');
  if r.week_start <> '2026-11-16' or r.run_id is not null or r.text <> 'שבוע טוב, keep it easy.' then
    raise exception 'FAIL: week note stored wrong: %', row_to_json(r);
  end if;
end $$;

select pg_temp.expect_error(
  $q$select * from public.coach_add_feedback('bbbbbbbb-0000-4000-8000-00000000000b', 101, null, '   ')$q$,
  '22023', 'empty text');
select pg_temp.expect_error(
  $q$select * from public.coach_add_feedback('bbbbbbbb-0000-4000-8000-00000000000b', null, null, 'Hi')$q$,
  '22023', 'no target');
select pg_temp.expect_error(
  $q$select * from public.coach_add_feedback('bbbbbbbb-0000-4000-8000-00000000000b', 101, '2026-11-16', 'Hi')$q$,
  '22023', 'both targets');
select pg_temp.expect_error(
  $q$select * from public.coach_add_feedback('bbbbbbbb-0000-4000-8000-00000000000b', 202, null, 'Hi')$q$,
  '22023', 'run of another athlete');
select pg_temp.expect_error(
  $q$select * from public.coach_add_feedback('bbbbbbbb-0000-4000-8000-00000000000b', null, '2026-11-16', repeat('a', 2001))$q$,
  '22023', 'text over 2000 characters');
select pg_temp.expect_error(
  $q$insert into public.coach_feedback (coach_id, athlete_id, week_start, text)
     values ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', '2026-11-16', 'x')$q$,
  '42501', 'direct insert');
select pg_temp.expect_error(
  $q$update public.coach_feedback set text = 'x'$q$, '42501', 'direct update');
select pg_temp.expect_error(
  $q$delete from public.coach_feedback$q$, '42501', 'direct delete');

select pg_temp.expect_count('select 1 from public.coach_feedback', 2, 'Dana reads her notes');

-- Edit: text and edited_at change, read_at does not.
do $$
declare
  r public.coach_feedback;
begin
  select * into r from public.coach_edit_feedback('30000000-0000-4000-8000-000000000001', 'Strong finish, well paced.');
  if r.text <> 'Strong finish, well paced.' or r.edited_at is null or r.read_at is not null then
    raise exception 'FAIL: edit stored wrong: %', row_to_json(r);
  end if;
end $$;
select pg_temp.expect_error(
  $q$select * from public.coach_edit_feedback('30000000-0000-4000-8000-000000000001', ' ')$q$,
  '22023', 'edit to empty');

-- Revision: the edit above moved it to 1. An edit from revision 0 (another phone) is refused
-- and leaves the newer text alone; an edit from revision 1 applies and moves it to 2.
select pg_temp.expect_error(
  $q$select * from public.coach_edit_feedback('30000000-0000-4000-8000-000000000001', 'Stale phone',
     'aaaaaaaa-0000-4000-8000-00000000000a', 0)$q$,
  '40001', 'stale edit from another phone');
do $$
declare
  r public.coach_feedback;
begin
  select * into r from public.coach_feedback where id = '30000000-0000-4000-8000-000000000001';
  if r.text <> 'Strong finish, well paced.' or r.revision <> 1 then
    raise exception 'FAIL: stale edit changed the row: %', row_to_json(r);
  end if;
  select * into r from public.coach_edit_feedback('30000000-0000-4000-8000-000000000001', 'Current phone',
    'aaaaaaaa-0000-4000-8000-00000000000a', 1);
  if r.text <> 'Current phone' or r.revision <> 2 then
    raise exception 'FAIL: current-revision edit stored wrong: %', row_to_json(r);
  end if;
end $$;

-- Expected coach: a request meant for another coach writes nothing.
select pg_temp.expect_error(
  $q$select * from public.coach_add_feedback('bbbbbbbb-0000-4000-8000-00000000000b', null, '2026-11-16', 'Hi',
     null, 'cccccccc-0000-4000-8000-00000000000c')$q$,
  '28000', 'add meant for another coach');
select pg_temp.expect_error(
  $q$select * from public.coach_edit_feedback('30000000-0000-4000-8000-000000000001', 'Hi',
     'cccccccc-0000-4000-8000-00000000000c')$q$,
  '28000', 'edit meant for another coach');
do $$
begin
  if (select text from public.coach_feedback where id = '30000000-0000-4000-8000-000000000001') <> 'Current phone' then
    raise exception 'FAIL: a wrong-coach edit changed the row';
  end if;
end $$;

-- Ron is a coach but not linked --------------------------------------------------
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count('select 1 from public.coach_feedback', 0, 'another coach reads');
select pg_temp.expect_error(
  $q$select * from public.coach_add_feedback('bbbbbbbb-0000-4000-8000-00000000000b', null, '2026-11-16', 'Hi')$q$,
  'P0001', 'unlinked coach adds');
select pg_temp.expect_error(
  $q$select * from public.coach_edit_feedback('30000000-0000-4000-8000-000000000001', 'Mine now')$q$,
  'P0002', 'another coach edits');
select pg_temp.expect_error(
  $q$select * from public.coach_add_feedback('bbbbbbbb-0000-4000-8000-00000000000b', null, '2026-11-16', 'Hi',
     '30000000-0000-4000-8000-000000000001')$q$,
  'P0001', 'unlinked coach reuses an id');

-- D is a third user ----------------------------------------------------------------
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_count('select 1 from public.coach_feedback', 0, 'third user reads');

-- The athlete reads only their own row, and cannot write -------------------------
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count('select 1 from public.coach_feedback', 1, 'athlete B reads');
select pg_temp.expect_error(
  $q$select * from public.coach_edit_feedback('30000000-0000-4000-8000-000000000001', 'x')$q$,
  'P0002', 'athlete edits');

-- B leaves: Dana can't add, edit, or read B's notes; B still reads them ------------
select public.leave_coach(
  (select id from public.coach_athlete_links
   where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'active'));
select pg_temp.expect_count('select 1 from public.coach_feedback', 1, 'athlete reads after leaving');

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_feedback where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'$q$,
  0, 'revoked coach reads');
select pg_temp.expect_count('select 1 from public.coach_feedback', 1, 'Dana still reads E');
select pg_temp.expect_error(
  $q$select * from public.coach_add_feedback('bbbbbbbb-0000-4000-8000-00000000000b', null, '2026-11-16', 'Hi')$q$,
  'P0001', 'revoked coach adds');
select pg_temp.expect_error(
  $q$select * from public.coach_edit_feedback('30000000-0000-4000-8000-000000000001', 'Again')$q$,
  'P0001', 'revoked coach edits');

-- anon has no access ----------------------------------------------------------------
reset role;
set local role anon;
select pg_temp.expect_error(
  $q$select 1 from public.coach_feedback$q$, '42501', 'anon reads');
select pg_temp.expect_error(
  $q$select * from public.coach_add_feedback('bbbbbbbb-0000-4000-8000-00000000000b', null, '2026-11-16', 'Hi')$q$,
  '42501', 'anon adds');

-- delete_account purge removes the rows; deleting a run cascades ---------------------
reset role;
delete from public.runs where id = 101;
do $$
begin
  if exists (select 1 from public.coach_feedback where run_id = 101) then
    raise exception 'FAIL: run delete left its feedback';
  end if;
end $$;

select public.purge_coach_data_for_deleted_account('eeeeeeee-0000-4000-8000-00000000000e');
do $$
begin
  if exists (select 1 from public.coach_feedback where athlete_id = 'eeeeeeee-0000-4000-8000-00000000000e') then
    raise exception 'FAIL: purge left feedback for the deleted athlete';
  end if;
end $$;

rollback;
