-- Test for 20261127100000_coach_workout_locks.sql (story C8.1a, M6a, Batch C).
--
-- Proves:
--   * AC1: the new columns exist with constant defaults; rows written before
--     the migration read source='ai', locked=false, coach_revision=0.
--   * AC2: with an active v2 link and a future, not-completed workout,
--     coach_create_workout / coach_update_workout / coach_move_workout /
--     coach_delete_workout set source='coach', locked=true, coach_id, raise
--     coach_revision by one and upsert athlete_plan_update_queue. Stale revision
--     -> edit_conflict; past or completed -> workout_not_editable; taken day ->
--     date_taken; no link -> not_coach / workout_not_found; revoked link ->
--     link_inactive; link_is_v2 false -> v2_unavailable; anon cannot execute.
--     (The kill switch case is in kill_switch.sql.)
--   * AC3: coach_delete_workout leaves a locked coach 'rest' row on that day.
--   * AC4: workout_structure must be an object <= 16 KB with a "steps" array of
--     objects, else invalid_structure.
--   * AC5: the trigger. An athlete PATCH cannot unlock or change a locked row and
--     does not raise; completion fields still change; DELETE raises
--     workout_locked; a non-coach INSERT with locked=true becomes false/ai; a
--     web-style upsert on (plan_id, local_id) keeps the coach fields;
--     complete_run_workout completes a locked workout; a client that sets
--     runsmart.coach_write itself is still blocked; with the kill switch on the
--     trigger still protects; FK cascades and the service role (delete_account)
--     can still delete.
--   * AC6: solo users and unlocked rows behave as before: amendWorkout,
--     pushWorkoutTomorrow, removeWorkout and the flex-week apply (the same
--     PostgREST writes TrainingPlanRepository.swift sends), plus a plain insert.
--   * The queue has no client access.
--
-- Raises on the first failure; prints "coach_workout_locks: PASS" otherwise.
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (CI's matrix row lists the same files):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_workout_locks_fixture.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115194500_leave_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114130000_runs_workout_link.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117120000_complete_run_workout.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117164500_coach_read_rpcs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261122100000_push_tokens_and_prefs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261127100000_coach_workout_locks.sql   (twice)
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_workout_locks.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_workout_locks.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

-- Users: A coaches B (v2, TestFlight). C is a coach with no link to B. R left A
-- (revoked link). S is a solo user. V is linked to A but not on v2.
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'athlete-r@example.com', 'authenticated', 'authenticated'),
  ('55555555-0000-4000-8000-000000000005', 'solo-s@example.com', 'authenticated', 'authenticated'),
  ('66666666-0000-4000-8000-000000000006', 'athlete-v@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at, revoked_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now(), null),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-00000000000d', 'revoked', now() - interval '2 days', now() - interval '1 day'),
  ('aaaaaaaa-0000-4000-8000-00000000000a', '66666666-0000-4000-8000-000000000006', 'active', now(), null);

insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight'),
  ('cccccccc-0000-4000-8000-00000000000c', true, 'testflight'),
  ('dddddddd-0000-4000-8000-00000000000d', true, 'testflight'),
  ('66666666-0000-4000-8000-000000000006', false, 'app_store');

insert into public.notification_prefs (user_id, time_zone) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'Asia/Jerusalem');

-- Plans. B, R, V and S each have one active plan that started a week ago.
insert into public.plans (id, profile_id, auth_user_id, title, start_date, end_date, is_active) values
  ('b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b',
   'B plan', current_date - 7, current_date + 60, true),
  ('d1000000-0000-4000-8000-0000000000d1', 'dddddddd-0000-4000-8000-00000000000d', 'dddddddd-0000-4000-8000-00000000000d',
   'R plan', current_date - 7, current_date + 60, true),
  ('61000000-0000-4000-8000-000000000061', '66666666-0000-4000-8000-000000000006', '66666666-0000-4000-8000-000000000006',
   'V plan', current_date - 7, current_date + 60, true),
  ('51000000-0000-4000-8000-000000000051', '55555555-0000-4000-8000-000000000005', '55555555-0000-4000-8000-000000000005',
   'S plan', current_date - 7, current_date + 60, true);

-- B's workouts (written as AI rows, like persistGeneratedPlan does).
insert into public.workouts (id, plan_id, auth_user_id, week, day, type, distance, duration, pace, notes,
                             completed, scheduled_date, local_id) values
  ('b0000001-0000-4000-8000-0000000000b1', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, 'AI easy', false, current_date + 2, 101),
  ('b0000002-0000-4000-8000-0000000000b2', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
   2, to_char(current_date + 3, 'Dy'), 'tempo', 8, 45, 300, 'AI tempo', false, current_date + 3, 102),
  ('b0000003-0000-4000-8000-0000000000b3', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
   1, to_char(current_date - 2, 'Dy'), 'easy', 4, 25, 370, 'past', false, current_date - 2, 103),
  ('b0000004-0000-4000-8000-0000000000b4', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
   2, to_char(current_date + 4, 'Dy'), 'long', 12, 80, 380, 'done early', true, current_date + 4, 104),
  ('b0000005-0000-4000-8000-0000000000b5', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
   3, to_char(current_date + 8, 'Dy'), 'easy', 6, 35, 360, 'B unlocked', false, current_date + 8, 105),
  ('d0000001-0000-4000-8000-0000000000d1', 'd1000000-0000-4000-8000-0000000000d1', 'dddddddd-0000-4000-8000-00000000000d',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, null, false, current_date + 2, null),
  ('60000001-0000-4000-8000-000000000061', '61000000-0000-4000-8000-000000000061', '66666666-0000-4000-8000-000000000006',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, null, false, current_date + 2, null),
  ('50000001-0000-4000-8000-000000000051', '51000000-0000-4000-8000-000000000051', '55555555-0000-4000-8000-000000000005',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, 'S one', false, current_date + 2, 201),
  ('50000002-0000-4000-8000-000000000052', '51000000-0000-4000-8000-000000000051', '55555555-0000-4000-8000-000000000005',
   2, to_char(current_date + 3, 'Dy'), 'tempo', 8, 45, 300, 'S two', false, current_date + 3, 202),
  ('50000003-0000-4000-8000-000000000053', '51000000-0000-4000-8000-000000000051', '55555555-0000-4000-8000-000000000005',
   2, to_char(current_date + 5, 'Dy'), 'long', 14, 90, 390, 'S three', false, current_date + 5, 203);

create function pg_temp.act_as(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
end $$;

create function pg_temp.expect_error_msg(stmt text, expected_state text, expected_message text, label text)
returns void language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL: % succeeded but should have failed with %', label, expected_message;
exception when others then
  if sqlstate = 'P0001' and sqlerrm like 'FAIL:%' then raise; end if;
  if sqlstate <> expected_state or (expected_message is not null and sqlerrm <> expected_message) then
    raise exception 'FAIL: % failed with % (%), expected % (%)', label, sqlstate, sqlerrm, expected_state, expected_message;
  end if;
end $$;

create function pg_temp.expect_int(actual integer, expected integer, label text) returns void
language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL: % was %, expected %', label, actual, expected;
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.act_as_anon(),
  pg_temp.expect_error_msg(text, text, text, text), pg_temp.expect_int(integer, integer, text)
  to authenticated, anon;

-- AC1: columns and defaults ---------------------------------------------------------
do $$
begin
  if (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'workouts'
        and column_name in ('source', 'locked', 'coach_id', 'coach_revision', 'published_version_id',
                            'coach_edited', 'athlete_change', 'athlete_changed_at', 'original_date')) <> 9 then
    raise exception 'FAIL: AC1 workouts columns missing';
  end if;
  if exists (select 1 from public.workouts
             where source <> 'ai' or locked or coach_id is not null or coach_revision <> 0
                or coach_edited or athlete_change is not null or original_date is not null) then
    raise exception 'FAIL: AC1 existing rows do not read source=ai, locked=false';
  end if;
  if (select count(*) from pg_trigger
      where tgrelid = 'public.workouts'::regclass and tgname = 'workouts_protect_coach_rows') <> 1 then
    raise exception 'FAIL: the trigger is missing or duplicated after applying twice';
  end if;
end $$;

-- AC2 + AC4: coach_create_workout -----------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

select pg_temp.expect_int(
  public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000001-0000-4000-8000-0000000000c1',
    current_date + 6, 'intervals', 7, 50, 280, '6 x 800m',
    '{"steps":[{"type":"warmup","duration_seconds":600},{"type":"interval","reps_count":6,"rep_distance":"800m"}]}'::jsonb,
    'threshold'),
  1, 'create returns revision 1');
-- Outbox retry with the same id: same answer, still one row.
select pg_temp.expect_int(
  public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000001-0000-4000-8000-0000000000c1',
    current_date + 6, 'intervals', 7, 50, 280, '6 x 800m', null, 'threshold'),
  1, 'create retry returns the same revision');

select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000002-0000-4000-8000-0000000000c2',
    current_date + 2, 'easy', 5)$q$, 'P0001', 'date_taken', 'create on a day that has a workout');
select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000002-0000-4000-8000-0000000000c2',
    current_date - 3, 'easy', 5)$q$, 'P0001', 'workout_not_editable', 'create in the past');
select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000002-0000-4000-8000-0000000000c2',
    current_date + 10, 'jog', 5)$q$, '22023', 'invalid_workout', 'create with an unknown type');
select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'b0000001-0000-4000-8000-0000000000b1',
    current_date + 10, 'easy', 5)$q$, '22023', 'bad_workout_id', 'create reusing an existing AI row id');
-- AC4: structure guard.
select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000002-0000-4000-8000-0000000000c2',
    current_date + 10, 'easy', 5, null, null, null, '"warmup then run"'::jsonb)$q$,
  '22023', 'invalid_structure', 'structure that is a string');
select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000002-0000-4000-8000-0000000000c2',
    current_date + 10, 'easy', 5, null, null, null, '{"blocks":[]}'::jsonb)$q$,
  '22023', 'invalid_structure', 'structure without steps');
select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000002-0000-4000-8000-0000000000c2',
    current_date + 10, 'easy', 5, null, null, null, '{"steps":[1,2]}'::jsonb)$q$,
  '22023', 'invalid_structure', 'structure with non-object steps');
select pg_temp.expect_error_msg(
  format($q$select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000002-0000-4000-8000-0000000000c2',
    current_date + 10, 'easy', 5, null, null, null, %L::jsonb)$q$,
    jsonb_build_object('steps', jsonb_build_array(jsonb_build_object('type', 'run', 'note', repeat('x', 16400))))::text),
  '22023', 'invalid_structure', 'structure over 16 KB');

-- Errors by caller: C has no link, B is not a coach, anon cannot execute.
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000003-0000-4000-8000-0000000000c3',
    current_date + 10, 'easy', 5)$q$, '42501', 'not_coach', 'create by an unlinked coach');
select pg_temp.expect_error_msg(
  $q$select public.coach_update_workout('b0000002-0000-4000-8000-0000000000b2', 0, 'easy', 5)$q$,
  'P0002', 'workout_not_found', 'update by an unlinked coach');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error_msg(
  $q$select public.coach_update_workout('b0000002-0000-4000-8000-0000000000b2', 0, 'easy', 5)$q$,
  'P0002', 'workout_not_found', 'the athlete calling a coach RPC on their own row');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_error_msg(
  $q$select public.coach_update_workout('d0000001-0000-4000-8000-0000000000d1', 0, 'easy', 5)$q$,
  'P0001', 'link_inactive', 'update after the athlete left');
select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('dddddddd-0000-4000-8000-00000000000d', 'c0000004-0000-4000-8000-0000000000c4',
    current_date + 10, 'easy', 5)$q$, 'P0001', 'link_inactive', 'create after the athlete left');
select pg_temp.expect_error_msg(
  $q$select public.coach_update_workout('60000001-0000-4000-8000-000000000061', 0, 'easy', 5)$q$,
  'P0001', 'v2_unavailable', 'update when link_is_v2 is false');
select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('66666666-0000-4000-8000-000000000006', 'c0000005-0000-4000-8000-0000000000c5',
    current_date + 10, 'easy', 5)$q$, 'P0001', 'v2_unavailable', 'create when link_is_v2 is false');
reset role;
set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error_msg(
  $q$select public.coach_delete_workout('b0000002-0000-4000-8000-0000000000b2', 0)$q$,
  '42501', null, 'anon cannot execute coach_delete_workout');
reset role;

do $$
begin
  if not exists (select 1 from public.workouts
                 where id = 'c0000001-0000-4000-8000-0000000000c1'
                   and source = 'coach' and locked and coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a'
                   and coach_revision = 1 and not coach_edited and type = 'intervals'
                   and day = to_char(current_date + 6, 'Dy') and week = 2
                   and auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
                   and workout_structure -> 'steps' -> 1 ->> 'reps_count' = '6') then
    raise exception 'FAIL: AC2 create did not write a locked coach row';
  end if;
  if (select count(*) from public.workouts where plan_id = 'b1000000-0000-4000-8000-0000000000b1') <> 6 then
    raise exception 'FAIL: a rejected create wrote a row, or the retry wrote a second one';
  end if;
  if not exists (select 1 from public.athlete_plan_update_queue
                 where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
                   and coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a'
                   and change_count = 1 and jsonb_array_length(changes) = 1 and sent_at is null
                   and changes -> 0 ->> 'action' = 'create') then
    raise exception 'FAIL: AC2 create did not upsert athlete_plan_update_queue once';
  end if;
  if exists (select 1 from public.workouts
             where plan_id in ('d1000000-0000-4000-8000-0000000000d1', '61000000-0000-4000-8000-000000000061')
               and (locked or source = 'coach')) then
    raise exception 'FAIL: a rejected coach write changed R or V';
  end if;
end $$;

-- AC2: update, move, delete ---------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_int(
  public.coach_update_workout('b0000001-0000-4000-8000-0000000000b1', 0, 'tempo', 6, 35, 310, 'Coach tempo', null, 'moderate'),
  1, 'update of an AI row returns revision 1');
select pg_temp.expect_error_msg(
  $q$select public.coach_update_workout('b0000001-0000-4000-8000-0000000000b1', 0, 'easy', 5)$q$,
  '40001', 'edit_conflict', 'update with a stale revision');
select pg_temp.expect_error_msg(
  $q$select public.coach_update_workout('b0000003-0000-4000-8000-0000000000b3', 0, 'easy', 5)$q$,
  'P0001', 'workout_not_editable', 'update of a past workout');
select pg_temp.expect_error_msg(
  $q$select public.coach_update_workout('b0000004-0000-4000-8000-0000000000b4', 0, 'easy', 5)$q$,
  'P0001', 'workout_not_editable', 'update of a completed workout');
select pg_temp.expect_error_msg(
  $q$select public.coach_update_workout('b0000001-0000-4000-8000-0000000000b1', 1, 'easy', 5, null, null, null, '[]'::jsonb)$q$,
  '22023', 'invalid_structure', 'update with an array structure');

select pg_temp.expect_int(
  public.coach_move_workout('b0000001-0000-4000-8000-0000000000b1', current_date + 9, 1),
  2, 'move returns revision 2');
select pg_temp.expect_error_msg(
  $q$select public.coach_move_workout('b0000001-0000-4000-8000-0000000000b1', current_date + 3, 2)$q$,
  'P0001', 'date_taken', 'move onto a day that has a workout');
select pg_temp.expect_error_msg(
  $q$select public.coach_move_workout('b0000001-0000-4000-8000-0000000000b1', current_date - 1, 2)$q$,
  'P0001', 'workout_not_editable', 'move into the past');
select pg_temp.expect_error_msg(
  $q$select public.coach_move_workout('b0000001-0000-4000-8000-0000000000b1', current_date + 11, 1)$q$,
  '40001', 'edit_conflict', 'move with a stale revision');
select pg_temp.expect_error_msg(
  $q$select public.coach_move_workout('b0000003-0000-4000-8000-0000000000b3', current_date + 11, 0)$q$,
  'P0001', 'workout_not_editable', 'move of a past workout');

select pg_temp.expect_error_msg(
  $q$select public.coach_move_workout('b0000001-0000-4000-8000-0000000000b1', current_date + 11, null)$q$,
  '40001', 'edit_conflict', 'move without a revision');
select pg_temp.expect_error_msg(
  $q$select public.coach_delete_workout('b0000001-0000-4000-8000-0000000000b1', null)$q$,
  '40001', 'edit_conflict', 'delete without a revision');
-- Move and delete share the gate: revoked link, not v2, unlinked coach.
select pg_temp.expect_error_msg(
  $q$select public.coach_move_workout('d0000001-0000-4000-8000-0000000000d1', current_date + 11, 0)$q$,
  'P0001', 'link_inactive', 'move after the athlete left');
select pg_temp.expect_error_msg(
  $q$select public.coach_delete_workout('60000001-0000-4000-8000-000000000061', 0)$q$,
  'P0001', 'v2_unavailable', 'delete when link_is_v2 is false');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_error_msg(
  $q$select public.coach_move_workout('b0000002-0000-4000-8000-0000000000b2', current_date + 11, 0)$q$,
  'P0002', 'workout_not_found', 'move by an unlinked coach');
select pg_temp.expect_error_msg(
  $q$select public.coach_delete_workout('b0000002-0000-4000-8000-0000000000b2', 0)$q$,
  'P0002', 'workout_not_found', 'delete by an unlinked coach');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

-- AC3: delete leaves a locked coach rest row.
select pg_temp.expect_int(
  public.coach_delete_workout('b0000002-0000-4000-8000-0000000000b2', 0),
  1, 'delete returns revision 1');
select pg_temp.expect_error_msg(
  $q$select public.coach_delete_workout('b0000004-0000-4000-8000-0000000000b4', 0)$q$,
  'P0001', 'workout_not_editable', 'delete of a completed workout');
select pg_temp.expect_error_msg(
  $q$select public.coach_delete_workout('b0000002-0000-4000-8000-0000000000b2', 0)$q$,
  '40001', 'edit_conflict', 'delete with a stale revision');
reset role;

do $$
begin
  if not exists (select 1 from public.workouts
                 where id = 'b0000001-0000-4000-8000-0000000000b1'
                   and source = 'coach' and locked and coach_edited and coach_revision = 2
                   and coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a'
                   and type = 'tempo' and distance = 6 and notes = 'Coach tempo' and intensity = 'moderate'
                   and scheduled_date = current_date + 9 and day = to_char(current_date + 9, 'Dy')
                   and local_id = 101) then
    raise exception 'FAIL: AC2 update + move did not leave a locked, coach-edited row on the new day';
  end if;
  if not exists (select 1 from public.workouts
                 where id = 'b0000002-0000-4000-8000-0000000000b2'
                   and scheduled_date = current_date + 3
                   and type = 'rest' and distance = 0 and duration is null and pace is null
                   and notes is null and workout_structure is null
                   and source = 'coach' and locked and not coach_edited and coach_revision = 1) then
    raise exception 'FAIL: AC3 delete did not leave a locked coach rest row on the same day';
  end if;
  if exists (select 1 from public.workouts
             where id in ('b0000003-0000-4000-8000-0000000000b3', 'b0000004-0000-4000-8000-0000000000b4')
               and (locked or source = 'coach')) then
    raise exception 'FAIL: a rejected write locked a past or completed row';
  end if;
  if not exists (select 1 from public.athlete_plan_update_queue
                 where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
                   and change_count = 4 and jsonb_array_length(changes) = 4
                   and changes -> 3 ->> 'action' = 'delete') then
    raise exception 'FAIL: AC2 the queue does not hold create, update, move, delete';
  end if;
end $$;

-- A sent queue row starts a fresh window on the next change.
update public.athlete_plan_update_queue set sent_at = now()
where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_int(
  public.coach_update_workout('c0000001-0000-4000-8000-0000000000c1', 1, 'intervals', 7, 50, 280, '5 x 1000m', null, 'threshold'),
  2, 'second edit of a coach row');
reset role;
do $$
begin
  if not exists (select 1 from public.athlete_plan_update_queue
                 where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
                   and change_count = 1 and jsonb_array_length(changes) = 1 and sent_at is null) then
    raise exception 'FAIL: a change after a sent digest did not start a fresh queue window';
  end if;
  if exists (select 1 from public.workouts
             where id = 'c0000001-0000-4000-8000-0000000000c1' and coach_edited) then
    raise exception 'FAIL: editing a coach-created row marked it coach_edited';
  end if;
end $$;

-- The queue has no client access.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error_msg(
  $q$select 1 from public.athlete_plan_update_queue$q$, '42501', null, 'athlete reads the queue');
select pg_temp.expect_error_msg(
  $q$select public.coach_queue_plan_update('bbbbbbbb-0000-4000-8000-00000000000b', null, null, 'create', current_date)$q$,
  '42501', null, 'athlete calls the internal queue helper');
reset role;

-- AC5: the trigger, as the athlete (PostgREST role authenticated) ----------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

-- A direct PATCH cannot unlock or change the locked row, and does not raise.
update public.workouts
set type = 'easy', distance = 99, duration = 1, pace = 1, notes = 'athlete edit',
    workout_structure = '{"steps":[{"type":"run"}]}', intensity = 'easy',
    scheduled_date = current_date + 20, day = 'Sun', week = 9,
    locked = false, source = 'ai', coach_id = null, coach_revision = 0, coach_edited = false,
    athlete_change = 'moved', original_date = current_date
where id = 'b0000001-0000-4000-8000-0000000000b1';

-- An UPDATE on an unlocked row cannot turn it into a locked coach row.
update public.workouts
set locked = true, source = 'coach', coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a', coach_revision = 99,
    coach_edited = true, published_version_id = 'f0000000-0000-4000-8000-0000000000f0',
    athlete_change = 'skipped', athlete_changed_at = now(), original_date = current_date, notes = 'B unlocked edit'
where id = 'b0000005-0000-4000-8000-0000000000b5';

-- A client that sets the coach setting itself is still an athlete.
select set_config('runsmart.coach_write', 'on', true);
update public.workouts set type = 'easy', locked = false where id = 'b0000002-0000-4000-8000-0000000000b2';
select set_config('runsmart.athlete_change', 'on', true);
update public.workouts set scheduled_date = current_date + 21 where id = 'b0000002-0000-4000-8000-0000000000b2';
select set_config('runsmart.coach_write', 'off', true);
select set_config('runsmart.athlete_change', 'off', true);

-- Completion fields still change.
update public.workouts
set completed = true, completed_at = now(), actual_distance_km = 6.2, actual_duration_minutes = 36, actual_pace = 348
where id = 'b0000001-0000-4000-8000-0000000000b1';

-- DELETE raises workout_locked.
select pg_temp.expect_error_msg(
  $q$delete from public.workouts where id = 'c0000001-0000-4000-8000-0000000000c1'$q$,
  'P0001', 'workout_locked', 'athlete deletes a locked row');

-- A non-coach INSERT with lock columns gets an AI, unlocked row.
insert into public.workouts (id, plan_id, auth_user_id, week, day, type, distance, scheduled_date,
                             source, locked, coach_id, coach_revision, coach_edited, athlete_change, original_date)
values ('b0000009-0000-4000-8000-0000000000b9', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
        4, to_char(current_date + 15, 'Dy'), 'easy', 5, current_date + 15,
        'coach', true, 'aaaaaaaa-0000-4000-8000-00000000000a', 7, true, 'skipped', current_date);

-- A web-style upsert on (plan_id, local_id), like plan-workout-sync.ts, with full
-- planned fields for the locked row (local_id 101) and an unlocked one (105).
-- The WHERE clause is needed because the only unique index on (plan_id, local_id)
-- is partial (live read 2026-11-27); a bare ON CONFLICT (plan_id, local_id) raises
-- 42P10 on this fixture. Either way the trigger sees the same UPDATE.
insert into public.workouts (plan_id, auth_user_id, local_id, week, day, type, distance, duration, pace,
                             intensity, workout_structure, notes, completed, scheduled_date)
values
  ('b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b', 101, 1, 'Mon', 'long', 20, 120, 400,
   'easy', null, 'web copy', false, current_date + 2),
  ('b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b', 105, 3, to_char(current_date + 8, 'Dy'),
   'hill', 7, 40, 350, null, null, 'web edit', false, current_date + 8)
on conflict (plan_id, local_id) where local_id is not null do update
  set week = excluded.week, day = excluded.day, type = excluded.type, distance = excluded.distance,
      duration = excluded.duration, pace = excluded.pace, intensity = excluded.intensity,
      workout_structure = excluded.workout_structure, notes = excluded.notes,
      completed = excluded.completed, scheduled_date = excluded.scheduled_date;
reset role;

do $$
begin
  -- Planned fields and lock columns kept; completion from the PATCH above, then
  -- the web upsert set completed=false again (completion fields are not protected).
  if not exists (select 1 from public.workouts
                 where id = 'b0000001-0000-4000-8000-0000000000b1'
                   and type = 'tempo' and distance = 6 and duration = 35 and pace = 310
                   and notes = 'Coach tempo' and intensity = 'moderate' and workout_structure is null
                   and scheduled_date = current_date + 9 and day = to_char(current_date + 9, 'Dy') and week = 3
                   and locked and source = 'coach' and coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a'
                   and coach_revision = 2 and coach_edited
                   and athlete_change is null and original_date is null
                   and local_id = 101 and actual_distance_km = 6.2 and actual_pace = 348) then
    raise exception 'FAIL: AC5 an athlete PATCH or the web upsert changed a locked row';
  end if;
  if not exists (select 1 from public.workouts
                 where id = 'b0000002-0000-4000-8000-0000000000b2'
                   and type = 'rest' and locked and scheduled_date = current_date + 3) then
    raise exception 'FAIL: AC5 a client-set runsmart.coach_write / athlete_change got past the trigger';
  end if;
  if not exists (select 1 from public.workouts
                 where id = 'c0000001-0000-4000-8000-0000000000c1' and locked) then
    raise exception 'FAIL: AC5 the locked row is gone after the delete attempt';
  end if;
  if not exists (select 1 from public.workouts
                 where id = 'b0000005-0000-4000-8000-0000000000b5'
                   and not locked and source = 'ai' and coach_id is null and coach_revision = 0
                   and not coach_edited and published_version_id is null
                   and athlete_change is null and athlete_changed_at is null and original_date is null) then
    raise exception 'FAIL: AC5 an athlete UPDATE set lock columns on an unlocked row';
  end if;
  if not exists (select 1 from public.workouts
                 where id = 'b0000009-0000-4000-8000-0000000000b9'
                   and source = 'ai' and not locked and coach_id is null and coach_revision = 0
                   and not coach_edited and athlete_change is null and original_date is null) then
    raise exception 'FAIL: AC5 a non-coach insert kept lock columns';
  end if;
  if not exists (select 1 from public.workouts
                 where id = 'b0000005-0000-4000-8000-0000000000b5'
                   and type = 'hill' and distance = 7 and notes = 'web edit' and not locked) then
    raise exception 'FAIL: AC5 the web upsert no longer updates an unlocked row';
  end if;
end $$;

-- complete_run_workout completes a locked workout (the coach rest row b2 is
-- locked; use the locked coach-created row c1 instead, it is a real session).
insert into public.runs (auth_user_id, type, distance, duration, completed_at, source_provider, source_activity_id)
values ('bbbbbbbb-0000-4000-8000-00000000000b', 'intervals', 7.1, 2900, now(), 'healthkit', 'hk-c81a-1');
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
do $$
declare
  v text;
begin
  v := public.complete_run_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000001-0000-4000-8000-0000000000c1',
                                   'healthkit', 'hk-c81a-1', now(), 7.1, 48, 405);
  if v <> 'completed' then
    raise exception 'FAIL: AC5 complete_run_workout on a locked workout returned %', v;
  end if;
end $$;
reset role;
do $$
begin
  if not exists (select 1 from public.workouts
                 where id = 'c0000001-0000-4000-8000-0000000000c1'
                   and completed and actual_distance_km = 7.1 and actual_pace = 405
                   and locked and source = 'coach' and type = 'intervals' and notes = '5 x 1000m') then
    raise exception 'FAIL: AC5 complete_run_workout did not complete the locked row, or changed its plan';
  end if;
end $$;

-- The coach cannot edit it now that it is completed.
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_error_msg(
  $q$select public.coach_update_workout('c0000001-0000-4000-8000-0000000000c1', 2, 'easy', 5)$q$,
  'P0001', 'workout_not_editable', 'coach edits a workout the athlete completed');
reset role;

-- Kill switch on: the trigger still protects (coach RPC errors are in kill_switch.sql).
update public.runtime_flags set enabled = false where key = 'coach_v2';
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
update public.workouts set type = 'easy', distance = 1 where id = 'b0000002-0000-4000-8000-0000000000b2';
select pg_temp.expect_error_msg(
  $q$delete from public.workouts where id = 'b0000002-0000-4000-8000-0000000000b2'$q$,
  'P0001', 'workout_locked', 'athlete deletes a locked row with the kill switch on');
reset role;
update public.runtime_flags set enabled = true where key = 'coach_v2';
do $$
begin
  if not exists (select 1 from public.workouts
                 where id = 'b0000002-0000-4000-8000-0000000000b2' and type = 'rest' and distance = 0 and locked) then
    raise exception 'FAIL: AC5 the kill switch let an athlete change a locked row';
  end if;
end $$;

-- The service role (delete_account) can delete a locked row.
set local role service_role;
delete from public.workouts where id = 'b0000002-0000-4000-8000-0000000000b2';
reset role;
do $$
begin
  if exists (select 1 from public.workouts where id = 'b0000002-0000-4000-8000-0000000000b2') then
    raise exception 'FAIL: the service role could not delete a locked row (delete_account would warn)';
  end if;
end $$;

-- AC6: solo user S and unlocked rows, through the same writes the app sends --------
set local role authenticated;
select pg_temp.act_as('55555555-0000-4000-8000-000000000005');
-- amendWorkout (DBWorkoutUpdate): scheduled_date, day, type, distance, duration, pace, notes, workout_structure.
update public.workouts
set scheduled_date = current_date + 6, day = to_char(current_date + 6, 'Dy'), type = 'recovery', distance = 4,
    duration = 25, pace = 420, notes = 'amended', workout_structure = '"jog easy"'::jsonb
where id = '50000001-0000-4000-8000-000000000051';
-- pushWorkoutTomorrow: moveWorkout on the conflict, then on the workout.
update public.workouts set scheduled_date = current_date + 4, day = to_char(current_date + 4, 'Dy')
where id = '50000002-0000-4000-8000-000000000052';
update public.workouts set scheduled_date = current_date + 3, day = to_char(current_date + 3, 'Dy')
where id = '50000003-0000-4000-8000-000000000053';
-- applyFlexWeek (DBWorkoutFlexUpdate) on an unlocked row of a linked athlete (B).
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
update public.workouts set type = 'easy', distance = 5, duration = 30, intensity = 'easy', notes = 'flexed'
where id = 'b0000005-0000-4000-8000-0000000000b5';
-- A plain insert keeps its values (persistGeneratedPlan / saveSuggestedWorkout).
select pg_temp.act_as('55555555-0000-4000-8000-000000000005');
insert into public.workouts (id, plan_id, auth_user_id, week, day, type, distance, duration, pace, notes,
                             workout_structure, intensity, training_phase, completed, scheduled_date)
values ('50000004-0000-4000-8000-000000000054', '51000000-0000-4000-8000-000000000051', '55555555-0000-4000-8000-000000000005',
        3, to_char(current_date + 9, 'Dy'), 'fartlek', 9, 50, 330, 'new', '"8 x 1 min"'::jsonb, 'vo2max', 'build',
        false, current_date + 9);
-- removeWorkout.
delete from public.workouts where id = '50000002-0000-4000-8000-000000000052';
reset role;

do $$
begin
  if not exists (select 1 from public.workouts
                 where id = '50000001-0000-4000-8000-000000000051'
                   and scheduled_date = current_date + 6 and type = 'recovery' and distance = 4 and duration = 25
                   and pace = 420 and notes = 'amended' and workout_structure = '"jog easy"'::jsonb and not locked) then
    raise exception 'FAIL: AC6 amendWorkout no longer changes a solo row';
  end if;
  if not exists (select 1 from public.workouts
                 where id = '50000003-0000-4000-8000-000000000053' and scheduled_date = current_date + 3) then
    raise exception 'FAIL: AC6 pushWorkoutTomorrow no longer moves a solo row';
  end if;
  if exists (select 1 from public.workouts where id = '50000002-0000-4000-8000-000000000052') then
    raise exception 'FAIL: AC6 removeWorkout no longer deletes a solo row';
  end if;
  if not exists (select 1 from public.workouts
                 where id = 'b0000005-0000-4000-8000-0000000000b5'
                   and type = 'easy' and distance = 5 and intensity = 'easy' and notes = 'flexed') then
    raise exception 'FAIL: AC6 the flex-week apply no longer changes an unlocked row';
  end if;
  if not exists (select 1 from public.workouts
                 where id = '50000004-0000-4000-8000-000000000054'
                   and type = 'fartlek' and intensity = 'vo2max' and training_phase = 'build'
                   and source = 'ai' and not locked) then
    raise exception 'FAIL: AC6 a solo insert lost its values';
  end if;
end $$;

-- Deleting a whole plan still cascades through locked rows (account deletion and
-- the 1.2.6 plan delete keep working; plan-level protection is M6b's).
delete from public.plans where id = 'b1000000-0000-4000-8000-0000000000b1';
do $$
begin
  if exists (select 1 from public.workouts where plan_id = 'b1000000-0000-4000-8000-0000000000b1') then
    raise exception 'FAIL: deleting a plan did not cascade to its locked workouts';
  end if;
end $$;

do $$ begin raise notice 'coach_workout_locks: PASS'; end $$;

rollback;
