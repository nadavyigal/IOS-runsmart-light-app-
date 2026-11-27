-- Test for 20261127110000_coach_plan_locks.sql (story C8.1b, M6b, Batch C).
--
-- Proves:
--   * AC1: plans_protect_coach_plans. A coach-published plan cannot be deactivated
--     or deleted by a non-coach (plan_locked_by_coach). A plan that is not
--     published but has locked future workouts cannot be deactivated or deleted
--     (coach_workouts_present), and a client that sets runsmart.goal_change
--     itself is still blocked. A non-coach cannot set coach_published / coach_id
--     on UPDATE or INSERT. The plans columns exist with constant defaults.
--   * AC2: athlete_replace_training_plan. Another user -> 42501. A wrong count ->
--     count_changed (detail = the count) and nothing changes. The right count ->
--     one transaction: old plan inactive, new plan active with unlocked AI
--     workouts, goal_change logged for the coach. A published plan ->
--     plan_locked_by_coach. A bad count -> invalid_ack_count.
--   * AC3: athlete_change_coach_workout. Skip and move change only the allowed
--     columns, the row stays locked, athlete_skip / athlete_move is logged, a
--     repeated p_request_id is a no-op. Errors: past or completed row and past
--     date -> workout_not_editable; taken day -> date_taken; unlocked row ->
--     workout_not_locked; another athlete's row -> workout_not_found; no or
--     revoked link -> link_inactive; pair not on v2 -> v2_unavailable; bad input; anon denied.
--     (The kill switch case is in kill_switch.sql.)
--   * AC4: end_coach_link (through leave_coach and coach_remove_athlete) unlocks
--     the athlete's future rows and clears coach_published; the rows stay; past
--     locked rows stay; a solo plan regenerates after leaving. Account deletion
--     releases too: purge_coach_data_for_deleted_account (delete_account) and a
--     direct coach auth delete (FK cascade), including rows whose coach_id became
--     null (the M6a coach-delete case). Deleting an athlete account and the
--     service role's plan delete still pass the plans trigger.
--   * AC5: replace_group_training_plan raises plan_locked_by_coach /
--     coach_workouts_present with a detail and hint, and changes nothing; with
--     no lock it still replaces the plan as before.
--   * AC6: a 1.2.6-style direct plans.update(is_active = false) on an unlocked
--     plan works, and so does inserting a new active plan.
--
-- Raises on the first failure; prints "coach_plan_locks: PASS" otherwise.
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (CI's matrix row lists the same files):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_plan_locks_fixture.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115194500_leave_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114130000_runs_workout_link.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117120000_complete_run_workout.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117163000_replace_group_training_plan.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117164500_coach_read_rpcs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121130000_coach_last_seen_and_events.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121160000_coach_link_end.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261122100000_push_tokens_and_prefs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261127100000_coach_workout_locks.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261127110000_coach_plan_locks.sql   (twice)
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_plan_locks.sql
-- The purge path also needs purge_coach_data_for_deleted_account; this file
-- defines the production body (live read 2026-11-27) for the test when missing.

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_plan_locks.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

-- Users: A coaches B, V (not v2) and had R (revoked). S is solo, X a stranger.
-- C2 coaches W and Y; C3 coaches Z. All but V are on v2.
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'athlete-r@example.com', 'authenticated', 'authenticated'),
  ('66666666-0000-4000-8000-000000000006', 'athlete-v@example.com', 'authenticated', 'authenticated'),
  ('55555555-0000-4000-8000-000000000005', 'solo-s@example.com', 'authenticated', 'authenticated'),
  ('77777777-0000-4000-8000-000000000007', 'stranger-x@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c2@example.com', 'authenticated', 'authenticated'),
  ('88888888-0000-4000-8000-000000000008', 'athlete-w@example.com', 'authenticated', 'authenticated'),
  ('13131313-0000-4000-8000-000000000013', 'athlete-y@example.com', 'authenticated', 'authenticated'),
  ('99999999-0000-4000-8000-000000000009', 'coach-c3@example.com', 'authenticated', 'authenticated'),
  ('12121212-0000-4000-8000-000000000012', 'athlete-z@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron'),
  ('99999999-0000-4000-8000-000000000009', 'Gil');

insert into public.coach_athlete_links (id, coach_id, athlete_id, status, consented_at, revoked_at) values
  ('11111111-0000-4000-8000-0000000000b0', 'aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now(), null),
  ('11111111-0000-4000-8000-0000000000d0', 'aaaaaaaa-0000-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-00000000000d', 'revoked', now() - interval '2 days', now() - interval '1 day'),
  ('11111111-0000-4000-8000-000000000060', 'aaaaaaaa-0000-4000-8000-00000000000a', '66666666-0000-4000-8000-000000000006', 'active', now(), null),
  ('11111111-0000-4000-8000-000000000080', 'cccccccc-0000-4000-8000-00000000000c', '88888888-0000-4000-8000-000000000008', 'active', now(), null),
  ('11111111-0000-4000-8000-000000000013', 'cccccccc-0000-4000-8000-00000000000c', '13131313-0000-4000-8000-000000000013', 'active', now(), null),
  ('11111111-0000-4000-8000-000000000012', '99999999-0000-4000-8000-000000000009', '12121212-0000-4000-8000-000000000012', 'active', now(), null);

insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight'),
  ('dddddddd-0000-4000-8000-00000000000d', true, 'testflight'),
  ('66666666-0000-4000-8000-000000000006', false, 'app_store'),
  ('cccccccc-0000-4000-8000-00000000000c', true, 'testflight'),
  ('88888888-0000-4000-8000-000000000008', true, 'testflight'),
  ('13131313-0000-4000-8000-000000000013', true, 'testflight'),
  ('99999999-0000-4000-8000-000000000009', true, 'testflight'),
  ('12121212-0000-4000-8000-000000000012', true, 'testflight');

-- One active plan each, started a week ago.
insert into public.plans (id, profile_id, auth_user_id, title, start_date, end_date, is_active) values
  ('b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b', 'B plan', current_date - 7, current_date + 60, true),
  ('d1000000-0000-4000-8000-0000000000d1', 'dddddddd-0000-4000-8000-00000000000d', 'dddddddd-0000-4000-8000-00000000000d', 'R plan', current_date - 7, current_date + 60, true),
  ('61000000-0000-4000-8000-000000000061', '66666666-0000-4000-8000-000000000006', '66666666-0000-4000-8000-000000000006', 'V plan', current_date - 7, current_date + 60, true),
  ('51000000-0000-4000-8000-000000000051', '55555555-0000-4000-8000-000000000005', '55555555-0000-4000-8000-000000000005', 'S plan', current_date - 7, current_date + 60, true),
  ('81000000-0000-4000-8000-000000000081', '88888888-0000-4000-8000-000000000008', '88888888-0000-4000-8000-000000000008', 'W plan', current_date - 7, current_date + 60, true),
  ('13100000-0000-4000-8000-000000000131', '13131313-0000-4000-8000-000000000013', '13131313-0000-4000-8000-000000000013', 'Y plan', current_date - 7, current_date + 60, true),
  ('12100000-0000-4000-8000-000000000121', '12121212-0000-4000-8000-000000000012', '12121212-0000-4000-8000-000000000012', 'Z plan', current_date - 7, current_date + 60, true);

insert into public.workouts (id, plan_id, auth_user_id, week, day, type, distance, duration, pace, notes,
                             completed, scheduled_date) values
  ('b0000001-0000-4000-8000-0000000000b1', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, 'AI easy', false, current_date + 2),
  ('b0000002-0000-4000-8000-0000000000b2', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
   2, to_char(current_date + 3, 'Dy'), 'tempo', 8, 45, 300, 'AI tempo', false, current_date + 3),
  ('b0000003-0000-4000-8000-0000000000b3', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
   1, to_char(current_date - 2, 'Dy'), 'easy', 4, 25, 370, 'past', false, current_date - 2),
  ('b0000004-0000-4000-8000-0000000000b4', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
   2, to_char(current_date + 4, 'Dy'), 'long', 12, 80, 380, 'done early', true, current_date + 4),
  ('b0000005-0000-4000-8000-0000000000b5', 'b1000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b',
   3, to_char(current_date + 8, 'Dy'), 'easy', 6, 35, 360, 'B unlocked', false, current_date + 8),
  ('d0000001-0000-4000-8000-0000000000d1', 'd1000000-0000-4000-8000-0000000000d1', 'dddddddd-0000-4000-8000-00000000000d',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, null, false, current_date + 2),
  ('60000001-0000-4000-8000-000000000061', '61000000-0000-4000-8000-000000000061', '66666666-0000-4000-8000-000000000006',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, null, false, current_date + 2),
  ('50000001-0000-4000-8000-000000000051', '51000000-0000-4000-8000-000000000051', '55555555-0000-4000-8000-000000000005',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, 'S one', false, current_date + 2),
  ('80000001-0000-4000-8000-000000000081', '81000000-0000-4000-8000-000000000081', '88888888-0000-4000-8000-000000000008',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, null, false, current_date + 2),
  ('13000001-0000-4000-8000-000000000131', '13100000-0000-4000-8000-000000000131', '13131313-0000-4000-8000-000000000013',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, null, false, current_date + 2),
  ('12000001-0000-4000-8000-000000000121', '12100000-0000-4000-8000-000000000121', '12121212-0000-4000-8000-000000000012',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, 30, 360, null, false, current_date + 2);

-- purge_coach_data_for_deleted_account is defined by Story 1.3 / later migrations
-- that this suite does not apply. Production body (live read 2026-11-27), minus
-- the guarded parts for tables this fixture lacks: replies, flags and runs.
do $$
begin
  if to_regprocedure('public.purge_coach_data_for_deleted_account(uuid)') is null then
    execute $f$
      create function public.purge_coach_data_for_deleted_account(p_user_id uuid)
      returns void language plpgsql security definer set search_path = '' as $b$
      begin
        delete from public.coach_athlete_links where athlete_id = p_user_id or coach_id = p_user_id;
        delete from public.coach_profiles where user_id = p_user_id;
      end;
      $b$;
    $f$;
  end if;
end $$;

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

-- Like expect_error_msg, and also checks the DETAIL text.
create function pg_temp.expect_error_detail(stmt text, expected_message text, expected_detail text, label text)
returns void language plpgsql as $$
declare
  v_detail text;
begin
  execute stmt;
  raise exception 'FAIL: % succeeded but should have failed with %', label, expected_message;
exception when others then
  if sqlstate = 'P0001' and sqlerrm like 'FAIL:%' then raise; end if;
  get stacked diagnostics v_detail = pg_exception_detail;
  if sqlerrm <> expected_message or v_detail is distinct from expected_detail then
    raise exception 'FAIL: % failed with % / detail %, expected % / detail %',
      label, sqlerrm, v_detail, expected_message, expected_detail;
  end if;
end $$;

create function pg_temp.expect_text(actual text, expected text, label text) returns void
language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL: % was %, expected %', label, actual, expected;
  end if;
end $$;

create function pg_temp.expect_int(actual bigint, expected bigint, label text) returns void
language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL: % was %, expected %', label, actual, expected;
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.act_as_anon(),
  pg_temp.expect_error_msg(text, text, text, text), pg_temp.expect_error_detail(text, text, text, text),
  pg_temp.expect_text(text, text, text), pg_temp.expect_int(bigint, bigint, text)
  to authenticated, anon;

-- Lock B's rows. w1 and w2 through the coach RPC; w3 (past) and w4 (completed)
-- with owner SQL, since the coach RPCs refuse them. R's and V's rows the same way.
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.coach_update_workout('b0000001-0000-4000-8000-0000000000b1', 0, 'tempo', 8, 45, 300, 'Coach tempo');
select public.coach_update_workout('b0000002-0000-4000-8000-0000000000b2', 0, 'intervals', 6, 40, 280, 'Coach intervals');
reset role;

select set_config('runsmart.coach_write', 'on', true);
update public.workouts
set locked = true, source = 'coach', coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a', coach_revision = 1
where id in ('b0000003-0000-4000-8000-0000000000b3', 'b0000004-0000-4000-8000-0000000000b4',
             'd0000001-0000-4000-8000-0000000000d1', '60000001-0000-4000-8000-000000000061');
select set_config('runsmart.coach_write', 'off', true);

-- AC1: columns, defaults, trigger ---------------------------------------------------
do $$
begin
  if (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'plans'
        and column_name in ('coach_published', 'coach_id')) <> 2 then
    raise exception 'FAIL: AC1 plans columns missing';
  end if;
  if exists (select 1 from public.plans where coach_published or coach_id is not null) then
    raise exception 'FAIL: AC1 existing plans do not read coach_published = false';
  end if;
  if (select count(*) from pg_trigger
      where tgrelid = 'public.plans'::regclass and tgname = 'plans_protect_coach_plans') <> 1
     or (select count(*) from pg_trigger
         where tgrelid = 'public.coach_athlete_links'::regclass
           and tgname = 'coach_links_release_locks_on_delete') <> 1 then
    raise exception 'FAIL: a trigger is missing or duplicated after applying twice';
  end if;
end $$;

-- AC1: not published, locked future rows -> coach_workouts_present.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_int(public.coach_plan_locked_future_count('b1000000-0000-4000-8000-0000000000b1'), 3,
  'locked future rows on B plan (w1, w2, completed w4; past w3 not counted)');
select pg_temp.expect_error_msg(
  $q$update public.plans set is_active = false where id = 'b1000000-0000-4000-8000-0000000000b1'$q$,
  'P0001', 'coach_workouts_present', 'athlete deactivates a plan with locked future rows');
select pg_temp.expect_error_msg(
  $q$delete from public.plans where id = 'b1000000-0000-4000-8000-0000000000b1'$q$,
  'P0001', 'coach_workouts_present', 'athlete deletes a plan with locked future rows');
-- persistGeneratedPlan's exact filter (auth_user_id + is_active).
select pg_temp.expect_error_msg(
  $q$update public.plans set is_active = false
     where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and is_active = true$q$,
  'P0001', 'coach_workouts_present', 'persistGeneratedPlan deactivation with locked rows');
-- A client that sets runsmart.goal_change itself is still blocked.
select set_config('runsmart.goal_change', 'on', true);
select pg_temp.expect_error_msg(
  $q$update public.plans set is_active = false where id = 'b1000000-0000-4000-8000-0000000000b1'$q$,
  'P0001', 'coach_workouts_present', 'client-set goal_change');
select set_config('runsmart.goal_change', 'off', true);
-- Another user's count reads 0.
select pg_temp.act_as('77777777-0000-4000-8000-000000000007');
select pg_temp.expect_int(public.coach_plan_locked_future_count('b1000000-0000-4000-8000-0000000000b1'), 0,
  'a stranger counting B plan');
-- Non-coach writers cannot set the coach columns.
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
update public.plans set coach_published = true, coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a', title = 'B plan renamed'
where id = 'b1000000-0000-4000-8000-0000000000b1';
insert into public.plans (id, profile_id, auth_user_id, title, start_date, end_date, is_active, coach_published, coach_id)
values ('b2000000-0000-4000-8000-0000000000b2', 'bbbbbbbb-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b',
        'B spare', current_date, current_date + 30, false, true, 'aaaaaaaa-0000-4000-8000-00000000000a');
reset role;
do $$
begin
  if not exists (select 1 from public.plans
                 where id = 'b1000000-0000-4000-8000-0000000000b1'
                   and not coach_published and coach_id is null and title = 'B plan renamed' and is_active) then
    raise exception 'FAIL: AC1 an athlete UPDATE set coach columns or lost its other change';
  end if;
  if not exists (select 1 from public.plans
                 where id = 'b2000000-0000-4000-8000-0000000000b2' and not coach_published and coach_id is null) then
    raise exception 'FAIL: AC1 an athlete INSERT kept coach_published';
  end if;
end $$;

-- AC1: coach-published -> plan_locked_by_coach.
select set_config('runsmart.coach_write', 'on', true);
update public.plans set coach_published = true, coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a'
where id = 'b1000000-0000-4000-8000-0000000000b1';
select set_config('runsmart.coach_write', 'off', true);

set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error_msg(
  $q$update public.plans set is_active = false where id = 'b1000000-0000-4000-8000-0000000000b1'$q$,
  'P0001', 'plan_locked_by_coach', 'athlete deactivates a published plan');
select pg_temp.expect_error_msg(
  $q$delete from public.plans where id = 'b1000000-0000-4000-8000-0000000000b1'$q$,
  'P0001', 'plan_locked_by_coach', 'athlete deletes a published plan');
update public.plans set coach_published = false where id = 'b1000000-0000-4000-8000-0000000000b1';

-- AC5: replace_group_training_plan, published -> clear error, nothing changes.
select pg_temp.expect_error_detail(
  $q$select public.replace_group_training_plan('bbbbbbbb-0000-4000-8000-00000000000b',
     '{"profile_id":"bbbbbbbb-0000-4000-8000-00000000000b","title":"Group","start_date":"2026-12-01","end_date":"2027-01-01","total_weeks":4,"plan_type":"basic"}'::jsonb,
     '[{"week":1,"day":"Mon","type":"easy","distance":5,"scheduled_date":"2026-12-01"}]'::jsonb)$q$,
  'plan_locked_by_coach', 'replace_group_training_plan: the active plan is published by the coach.',
  'group replace on a published plan');
-- AC2: athlete_replace_training_plan on a published plan.
select pg_temp.expect_error_msg(
  $q$select public.athlete_replace_training_plan('bbbbbbbb-0000-4000-8000-00000000000b',
     '{"title":"New"}'::jsonb, '[{"week":1,"day":"Mon","type":"easy","distance":5,"scheduled_date":"2026-12-01"}]'::jsonb, 3)$q$,
  'P0001', 'plan_locked_by_coach', 'athlete replace on a published plan');
reset role;
do $$
begin
  if not exists (select 1 from public.plans where id = 'b1000000-0000-4000-8000-0000000000b1' and coach_published and is_active) then
    raise exception 'FAIL: AC1 an athlete cleared coach_published, or a blocked replace changed the plan';
  end if;
  if (select count(*) from public.plans where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b') <> 2 then
    raise exception 'FAIL: AC5 a blocked replace inserted a plan';
  end if;
end $$;

select set_config('runsmart.coach_write', 'on', true);
update public.plans set coach_published = false where id = 'b1000000-0000-4000-8000-0000000000b1';
select set_config('runsmart.coach_write', 'off', true);

-- AC5: not published, locked rows -> coach_workouts_present with the hint.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error_detail(
  $q$select public.replace_group_training_plan('bbbbbbbb-0000-4000-8000-00000000000b',
     '{"profile_id":"bbbbbbbb-0000-4000-8000-00000000000b","title":"Group","start_date":"2026-12-01","end_date":"2027-01-01","total_weeks":4,"plan_type":"basic"}'::jsonb,
     '[{"week":1,"day":"Mon","type":"easy","distance":5,"scheduled_date":"2026-12-01"}]'::jsonb)$q$,
  'coach_workouts_present', 'replace_group_training_plan: the active plan has coach-set future workouts.',
  'group replace with locked rows');
reset role;

-- AC3: athlete_change_coach_workout -----------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
-- Skip w1.
select pg_temp.expect_text(
  public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'skip', null,
    'e1000001-0000-4000-8000-0000000000e1'), 'changed', 'skip w1');
select pg_temp.expect_text(
  public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'skip', null,
    'e1000001-0000-4000-8000-0000000000e1'), 'duplicate', 'repeated skip request');
-- Move w2 from +3 to +6, then to +7: original_date keeps the first date.
select pg_temp.expect_text(
  public.athlete_change_coach_workout('b0000002-0000-4000-8000-0000000000b2', 'move', current_date + 6,
    'e1000002-0000-4000-8000-0000000000e2'), 'changed', 'move w2');
select pg_temp.expect_text(
  public.athlete_change_coach_workout('b0000002-0000-4000-8000-0000000000b2', 'move', current_date + 7,
    'e1000003-0000-4000-8000-0000000000e3'), 'changed', 'move w2 again');
-- A replayed move request after another move changes nothing.
select pg_temp.expect_text(
  public.athlete_change_coach_workout('b0000002-0000-4000-8000-0000000000b2', 'move', current_date + 6,
    'e1000002-0000-4000-8000-0000000000e2'), 'duplicate', 'replayed first move');

select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'move', current_date + 7,
     'e1000004-0000-4000-8000-0000000000e4')$q$, 'P0001', 'date_taken', 'move onto a day with a workout');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'move', current_date + 8,
     'e1000004-0000-4000-8000-0000000000e4')$q$, 'P0001', 'date_taken', 'move onto a day with an AI workout');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'move', current_date - 1,
     'e1000004-0000-4000-8000-0000000000e4')$q$, 'P0001', 'workout_not_editable', 'move to a past date');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'move', current_date + 2,
     'e1000004-0000-4000-8000-0000000000e4')$q$, '22023', 'invalid_workout', 'move to the same day');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'move', null,
     'e1000004-0000-4000-8000-0000000000e4')$q$, 'P0001', 'workout_not_editable', 'move with no date');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000003-0000-4000-8000-0000000000b3', 'skip', null,
     'e1000004-0000-4000-8000-0000000000e4')$q$, 'P0001', 'workout_not_editable', 'skip a past row');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000004-0000-4000-8000-0000000000b4', 'skip', null,
     'e1000004-0000-4000-8000-0000000000e4')$q$, 'P0001', 'workout_not_editable', 'skip a completed row');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000005-0000-4000-8000-0000000000b5', 'skip', null,
     'e1000004-0000-4000-8000-0000000000e4')$q$, 'P0001', 'workout_not_locked', 'skip an unlocked row');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'swap', null,
     'e1000004-0000-4000-8000-0000000000e4')$q$, '22023', 'invalid_action', 'unknown action');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'skip', null, null)$q$,
  '22023', 'bad_request_id', 'missing request id');
select pg_temp.act_as('77777777-0000-4000-8000-000000000007');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'skip', null,
     'e1000005-0000-4000-8000-0000000000e5')$q$, 'P0001', 'link_inactive', 'an unlinked user skips B''s row');
-- V is linked (to A), so the link check passes; B's row is still not found.
select pg_temp.act_as('66666666-0000-4000-8000-000000000006');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'skip', null,
     'e1000005-0000-4000-8000-0000000000e5')$q$, 'P0002', 'workout_not_found', 'another linked athlete skips B''s row');
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('d0000001-0000-4000-8000-0000000000d1', 'skip', null,
     'e1000006-0000-4000-8000-0000000000e6')$q$, 'P0001', 'link_inactive', 'skip after the link was revoked');
select pg_temp.act_as('66666666-0000-4000-8000-000000000006');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('60000001-0000-4000-8000-000000000061', 'skip', null,
     'e1000007-0000-4000-8000-0000000000e7')$q$, 'P0001', 'v2_unavailable', 'skip on a pair not on v2');
reset role;
set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b0000001-0000-4000-8000-0000000000b1', 'skip', null,
     'e1000008-0000-4000-8000-0000000000e8')$q$, '42501', null, 'anon skip');
select pg_temp.expect_error_msg(
  $q$select public.athlete_replace_training_plan('bbbbbbbb-0000-4000-8000-00000000000b', '{}'::jsonb, '[]'::jsonb, 0)$q$,
  '42501', null, 'anon replace');
reset role;
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error_msg(
  $q$select public.coach_release_athlete_locks('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', null, 'a client calls the internal lock release');
reset role;

do $$
begin
  if not exists (select 1 from public.workouts
                 where id = 'b0000001-0000-4000-8000-0000000000b1'
                   and athlete_change = 'skipped' and athlete_changed_at is not null and original_date is null
                   and scheduled_date = current_date + 2 and locked and source = 'coach'
                   and type = 'tempo' and notes = 'Coach tempo' and coach_revision = 1) then
    raise exception 'FAIL: AC3 skip changed more than the allowed fields, or unlocked the row';
  end if;
  if not exists (select 1 from public.workouts
                 where id = 'b0000002-0000-4000-8000-0000000000b2'
                   and athlete_change = 'moved' and original_date = current_date + 3
                   and scheduled_date = current_date + 7 and day = to_char(current_date + 7, 'Dy')
                   and week = greatest(1, ((current_date + 7 - (current_date - 7)) / 7) + 1)
                   and locked and type = 'intervals' and distance = 6 and coach_revision = 1) then
    raise exception 'FAIL: AC3 move changed more than the allowed fields, lost original_date, or unlocked the row';
  end if;
  if (select count(*) from public.coach_athlete_events
      where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and kind = 'athlete_skip'
        and ref_id = 'b0000001-0000-4000-8000-0000000000b1'
        and coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a') <> 1
     or (select count(*) from public.coach_athlete_events
         where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and kind = 'athlete_move') <> 2 then
    raise exception 'FAIL: AC3 events: one skip and two moves expected (repeats are no-ops)';
  end if;
  if exists (select 1 from public.workouts
             where id in ('b0000003-0000-4000-8000-0000000000b3', 'b0000004-0000-4000-8000-0000000000b4',
                          'b0000005-0000-4000-8000-0000000000b5', 'd0000001-0000-4000-8000-0000000000d1',
                          '60000001-0000-4000-8000-000000000061')
               and athlete_change is not null) then
    raise exception 'FAIL: AC3 a refused change still wrote a row';
  end if;
end $$;

-- AC2: athlete_replace_training_plan -------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('77777777-0000-4000-8000-000000000007');
select pg_temp.expect_error_msg(
  $q$select public.athlete_replace_training_plan('bbbbbbbb-0000-4000-8000-00000000000b',
     '{"title":"New"}'::jsonb, '[{"week":1,"day":"Mon","type":"easy","distance":5,"scheduled_date":"2026-12-01"}]'::jsonb, 3)$q$,
  '42501', 'Plan replacement requires the confirming athlete', 'another user replaces B''s plan');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error_detail(
  $q$select public.athlete_replace_training_plan('bbbbbbbb-0000-4000-8000-00000000000b',
     '{"title":"New"}'::jsonb, '[{"week":1,"day":"Mon","type":"easy","distance":5,"scheduled_date":"2026-12-01"}]'::jsonb, 2)$q$,
  'count_changed', '3', 'replace with a stale count');
select pg_temp.expect_error_msg(
  $q$select public.athlete_replace_training_plan('bbbbbbbb-0000-4000-8000-00000000000b',
     '{"title":"New"}'::jsonb, '[{"week":1,"day":"Mon","type":"easy","distance":5,"scheduled_date":"2026-12-01"}]'::jsonb, -1)$q$,
  '22023', 'invalid_ack_count', 'replace with a negative count');
select pg_temp.expect_error_msg(
  $q$select public.athlete_replace_training_plan('bbbbbbbb-0000-4000-8000-00000000000b',
     '{"title":"New"}'::jsonb, '[]'::jsonb, 3)$q$,
  '22023', 'A replacement plan requires workouts', 'replace with no workouts');
reset role;
do $$
begin
  if not exists (select 1 from public.plans where id = 'b1000000-0000-4000-8000-0000000000b1' and is_active)
     or (select count(*) from public.plans where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b') <> 2
     or exists (select 1 from public.coach_athlete_events
                where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and kind = 'goal_change') then
    raise exception 'FAIL: AC2 a refused replace changed something';
  end if;
end $$;

-- The right count. The payload carries a legacy numeric profile_id, a foreign
-- auth_user_id and coach columns; all are ignored.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select set_config('test.new_plan', public.athlete_replace_training_plan('bbbbbbbb-0000-4000-8000-00000000000b',
  jsonb_build_object('profile_id', 42, 'auth_user_id', '77777777-0000-4000-8000-000000000007',
                     'coach_published', true, 'title', 'Half marathon', 'description', 'New goal',
                     'start_date', current_date, 'end_date', current_date + 56, 'total_weeks', 8,
                     'plan_type', 'basic', 'training_days_per_week', 4, 'target_distance', 21.1,
                     'target_time', 7200, 'peak_weekly_volume', 40),
  jsonb_build_array(
    jsonb_build_object('week', 1, 'day', to_char(current_date + 1, 'Dy'), 'type', 'easy', 'distance', 5,
                       'scheduled_date', current_date + 1, 'source', 'coach', 'locked', true),
    jsonb_build_object('week', 1, 'day', to_char(current_date + 3, 'Dy'), 'type', 'tempo', 'distance', 7,
                       'scheduled_date', current_date + 3, 'intensity', 'threshold')),
  3)::text, true);
reset role;
do $$
declare
  v_new uuid := current_setting('test.new_plan')::uuid;
begin
  if exists (select 1 from public.plans where id = 'b1000000-0000-4000-8000-0000000000b1' and is_active) then
    raise exception 'FAIL: AC2 the old plan is still active';
  end if;
  if not exists (select 1 from public.plans
                 where id = v_new and is_active and profile_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
                   and auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and not coach_published
                   and title = 'Half marathon' and total_weeks = 8 and target_distance = 21.1) then
    raise exception 'FAIL: AC2 the new plan is missing or took owner / coach columns from the payload';
  end if;
  if (select count(*) from public.workouts where plan_id = v_new and source = 'ai' and not locked) <> 2 then
    raise exception 'FAIL: AC2 the new workouts are missing or arrived locked';
  end if;
  if (select count(*) from public.coach_athlete_events
      where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and kind = 'goal_change'
        and ref_id = v_new and coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a') <> 1 then
    raise exception 'FAIL: AC2 goal_change was not logged once';
  end if;
  -- The old plan keeps its locked rows (inactive; the link end releases them).
  if (select count(*) from public.workouts
      where plan_id = 'b1000000-0000-4000-8000-0000000000b1' and locked) <> 4 then
    raise exception 'FAIL: AC2 the replaced plan''s locked rows changed';
  end if;
end $$;

-- AC4: lock release at link end -----------------------------------------------------------
-- The coach adds a workout to the new plan and publishes it.
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'c0000001-0000-4000-8000-0000000000c1',
  current_date + 5, 'long', 14);
reset role;
select set_config('runsmart.coach_write', 'on', true);
update public.plans set coach_published = true, coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a'
where id = current_setting('test.new_plan')::uuid;
select set_config('runsmart.coach_write', 'off', true);

set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.leave_coach('11111111-0000-4000-8000-0000000000b0');
reset role;
do $$
begin
  if exists (select 1 from public.workouts w join public.plans p on p.id = w.plan_id
             where p.auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
               and w.locked and w.scheduled_date >= current_date) then
    raise exception 'FAIL: AC4 a future row is still locked after leaving';
  end if;
  if not exists (select 1 from public.workouts
                 where id = 'b0000003-0000-4000-8000-0000000000b3' and locked) then
    raise exception 'FAIL: AC4 the past locked row was unlocked';
  end if;
  if exists (select 1 from public.plans where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and coach_published) then
    raise exception 'FAIL: AC4 coach_published is still set after leaving';
  end if;
  if (select count(*) from public.workouts
      where id in ('b0000001-0000-4000-8000-0000000000b1', 'b0000002-0000-4000-8000-0000000000b2',
                   'b0000004-0000-4000-8000-0000000000b4', 'c0000001-0000-4000-8000-0000000000c1')
        and source = 'coach' and not locked) <> 4 then
    raise exception 'FAIL: AC4 the released rows did not stay as coach rows';
  end if;
  if not exists (select 1 from public.coach_athlete_links
                 where id = '11111111-0000-4000-8000-0000000000b0' and status = 'revoked' and ended_by = 'athlete')
     or not exists (select 1 from public.coach_athlete_events
                    where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and kind = 'left') then
    raise exception 'FAIL: AC4 end_coach_link lost its M5b behavior';
  end if;
end $$;

-- After leaving, the solo plan regenerates the 1.2.6 way: deactivate, insert.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
update public.plans set is_active = false
where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and is_active = true;
insert into public.plans (profile_id, auth_user_id, title, start_date, end_date, is_active)
values ('bbbbbbbb-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b', 'Solo again',
        current_date, current_date + 30, true);
-- The replaced plan can be deleted now too.
delete from public.plans where id = 'b2000000-0000-4000-8000-0000000000b2';
reset role;
do $$
begin
  if (select count(*) from public.plans
      where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and is_active) <> 1
     or not exists (select 1 from public.plans
                    where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and is_active and title = 'Solo again') then
    raise exception 'FAIL: AC4 the solo plan did not regenerate after leaving';
  end if;
end $$;

-- coach_remove_athlete also releases (through end_coach_link). W: C2 locks a row.
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select public.coach_update_workout('80000001-0000-4000-8000-000000000081', 0, 'tempo', 7);
select pg_temp.expect_text(public.coach_remove_athlete('88888888-0000-4000-8000-000000000008'), 'removed',
  'C2 removes W');
reset role;
do $$
begin
  if exists (select 1 from public.workouts where id = '80000001-0000-4000-8000-000000000081' and locked) then
    raise exception 'FAIL: AC4 coach_remove_athlete did not release the lock';
  end if;
end $$;

-- Account deletion, purge path (delete_account calls the purge as the service
-- role, then deletes the auth user). C2 still coaches Y: lock and publish first.
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select public.coach_update_workout('13000001-0000-4000-8000-000000000131', 0, 'tempo', 7);
reset role;
select set_config('runsmart.coach_write', 'on', true);
update public.plans set coach_published = true, coach_id = 'cccccccc-0000-4000-8000-00000000000c'
where id = '13100000-0000-4000-8000-000000000131';
select set_config('runsmart.coach_write', 'off', true);
set local role service_role;
select public.purge_coach_data_for_deleted_account('cccccccc-0000-4000-8000-00000000000c');
reset role;
delete from auth.users where id = 'cccccccc-0000-4000-8000-00000000000c';
do $$
begin
  if exists (select 1 from public.workouts where id = '13000001-0000-4000-8000-000000000131' and locked)
     or exists (select 1 from public.plans where id = '13100000-0000-4000-8000-000000000131' and coach_published) then
    raise exception 'FAIL: AC4 the purge path left Y''s rows locked';
  end if;
  if exists (select 1 from public.workouts where coach_id = 'cccccccc-0000-4000-8000-00000000000c')
     or exists (select 1 from public.plans where coach_id = 'cccccccc-0000-4000-8000-00000000000c') then
    raise exception 'FAIL: a row still points at the deleted coach C2';
  end if;
end $$;

-- Account deletion, direct auth delete of a coach (FK cascades: coach_profiles ->
-- links, and workouts.coach_id / plans.coach_id set null in the same statement).
set local role authenticated;
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
select public.coach_update_workout('12000001-0000-4000-8000-000000000121', 0, 'tempo', 7);
reset role;
select set_config('runsmart.coach_write', 'on', true);
update public.plans set coach_published = true, coach_id = '99999999-0000-4000-8000-000000000009'
where id = '12100000-0000-4000-8000-000000000121';
select set_config('runsmart.coach_write', 'off', true);
delete from auth.users where id = '99999999-0000-4000-8000-000000000009';
do $$
begin
  if not exists (select 1 from public.workouts
                 where id = '12000001-0000-4000-8000-000000000121'
                   and not locked and coach_id is null and source = 'coach' and type = 'tempo') then
    raise exception 'FAIL: AC4 deleting coach C3 left Z''s row locked (M6a coach_id null case)';
  end if;
  if not exists (select 1 from public.plans
                 where id = '12100000-0000-4000-8000-000000000121' and not coach_published and coach_id is null) then
    raise exception 'FAIL: AC4 deleting coach C3 left Z''s plan published';
  end if;
end $$;

-- A row already left locked with coach_id null (M6a, from a coach deleted before
-- M6b) is released when the athlete's link ends. V gets one, then A removes V.
select set_config('runsmart.coach_write', 'on', true);
update public.workouts set coach_id = null where id = '60000001-0000-4000-8000-000000000061';
select set_config('runsmart.coach_write', 'off', true);
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.coach_remove_athlete('66666666-0000-4000-8000-000000000006');
reset role;
do $$
begin
  if exists (select 1 from public.workouts where id = '60000001-0000-4000-8000-000000000061' and locked) then
    raise exception 'FAIL: AC4 a locked row with coach_id null survived the link end';
  end if;
end $$;

-- Athlete account deletion still passes the plans trigger: the service role's
-- direct plan delete (delete_account) and the auth.users FK cascade. R still has
-- a locked future row on an active plan; publish it too.
select set_config('runsmart.coach_write', 'on', true);
update public.plans set coach_published = true where id = 'd1000000-0000-4000-8000-0000000000d1';
select set_config('runsmart.coach_write', 'off', true);
set local role service_role;
delete from public.workouts where auth_user_id = 'dddddddd-0000-4000-8000-00000000000d';
delete from public.plans where auth_user_id = 'dddddddd-0000-4000-8000-00000000000d';
reset role;
select set_config('runsmart.coach_write', 'on', true);
update public.workouts set locked = true, source = 'coach', coach_revision = 1
where id = '50000001-0000-4000-8000-000000000051';
update public.plans set coach_published = true where id = '51000000-0000-4000-8000-000000000051';
select set_config('runsmart.coach_write', 'off', true);
delete from auth.users where id = '55555555-0000-4000-8000-000000000005';
do $$
begin
  if exists (select 1 from public.plans where auth_user_id = 'dddddddd-0000-4000-8000-00000000000d') then
    raise exception 'FAIL: the service role could not delete a published plan (delete_account would warn)';
  end if;
  if exists (select 1 from public.plans where auth_user_id = '55555555-0000-4000-8000-000000000005')
     or exists (select 1 from public.workouts where auth_user_id = '55555555-0000-4000-8000-000000000005') then
    raise exception 'FAIL: deleting an athlete account did not cascade through a published plan';
  end if;
end $$;

-- AC6: an unlocked plan, 1.2.6 style. X has no coach. ------------------------------------
insert into public.plans (id, profile_id, auth_user_id, title, start_date, end_date, is_active) values
  ('71000000-0000-4000-8000-000000000071', '77777777-0000-4000-8000-000000000007', '77777777-0000-4000-8000-000000000007',
   'X plan', current_date - 7, current_date + 60, true);
set local role authenticated;
select pg_temp.act_as('77777777-0000-4000-8000-000000000007');
update public.plans set is_active = false
where auth_user_id = '77777777-0000-4000-8000-000000000007' and is_active = true;
insert into public.plans (profile_id, auth_user_id, title, start_date, end_date, is_active)
values ('77777777-0000-4000-8000-000000000007', '77777777-0000-4000-8000-000000000007', 'X plan 2',
        current_date, current_date + 30, true);
-- AC5 regression: the group replace still works with no lock.
select public.replace_group_training_plan('77777777-0000-4000-8000-000000000007',
  '{"profile_id":"77777777-0000-4000-8000-000000000007","title":"Group X","start_date":"2026-12-01","end_date":"2027-01-01","total_weeks":4,"plan_type":"basic"}'::jsonb,
  '[{"week":1,"day":"Mon","type":"easy","distance":5,"scheduled_date":"2026-12-01"}]'::jsonb);
delete from public.plans where id = '71000000-0000-4000-8000-000000000071';
reset role;
do $$
begin
  if (select count(*) from public.plans where auth_user_id = '77777777-0000-4000-8000-000000000007' and is_active) <> 1
     or not exists (select 1 from public.plans
                    where auth_user_id = '77777777-0000-4000-8000-000000000007' and is_active and title = 'Group X')
     or exists (select 1 from public.plans where id = '71000000-0000-4000-8000-000000000071') then
    raise exception 'FAIL: AC6 a 1.2.6-style plan change on an unlocked plan stopped working';
  end if;
end $$;

do $$ begin raise notice 'coach_plan_locks: PASS'; end $$;

rollback;
