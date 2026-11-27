-- Test for the server kill switch in 20261121100000_coach_v2_gate.sql (story
-- C7.12, folded into C7.0).
--
-- Proves:
--   * C7.12 AC1: with runtime_flags.coach_v2 = false, link_is_v2 is false for
--     every pair (TestFlight pair, App Store pair with a listed coach), and the
--     v2 roster read returns zero rows. Back on, both return. A missing coach_v2
--     row counts as off.
--   * C7.12 AC3: an authenticated client cannot read, insert, update or delete
--     runtime_flags; get_runtime_flags() returns only the allow-listed keys;
--     anon is denied.
--   * The migration seeds coach_v2, coach_v2_push and coach_v2_ai as enabled.
--   * C7.8 (M5a): with the flag off, my_coach_consent_status shows no P9 and no
--     sharing, ack_coach_consent raises v2_unavailable and changes nothing,
--     coach_v2_sharing_allowed is false even for an acked pair, and
--     coach_invite_consent_version returns 1 (A3 copy). Back on, P9 shows again
--     for the athlete who has not acked, and the acked pair shares again.
--   * C7.2 (M3): with the flag off, coach_roster_summary and
--     coach_get_athlete_events return zero rows, coach_mark_athlete_seen and
--     athlete_log_goal_change raise v2_unavailable and write nothing (the app's
--     outbox keeps the items). Back on, both writes succeed and the counts return.
--   * C7.3 (M1a): with the flag off, coach_get_athletes_runs keeps its Story 2.2
--     rows but returns no effort and has_note = false, coach_get_run_notes returns
--     zero rows, the athlete's effort and note writes raise v2_unavailable and change
--     nothing, and hiding a note still works. Back on, effort returns and the note
--     hidden while the flag was off stays hidden.
--   * C7.4 (M1b): with the flag off, coach_get_athlete_flags returns zero rows and
--     the roster summary has no flag count, athlete_flag_run and coach_resolve_flag
--     raise v2_unavailable and change nothing (the app's outbox keeps them), and
--     athlete_remove_flag still works (a privacy action). Back on, the queued flag
--     lands, the coach reads it and resolves the open one.
--   * C7.11 (M5b): with the flag off, coach_remove_athlete and the 1.2.6
--     leave_coach still end the link and log removed / left (the switch never
--     blocks ending a link); my_coach_link_notice returns zero rows and
--     mark_link_notice_seen raises v2_unavailable and marks nothing. Back on, the
--     removed athlete sees the notice once; the athlete who left sees none.
--   * C7.7 (M4): with the flag off, coach_get_feedback_replies returns zero rows,
--     coach_mark_reply_read marks nothing, athlete_reply_to_feedback raises
--     v2_unavailable and stores nothing (the app's outbox keeps it), and the athlete
--     still reads their own replies. Back on, the queued reply lands and the coach
--     reads both.
--   * C8.1a (M6a): with the flag off, coach_create_workout, coach_update_workout,
--     coach_move_workout and coach_delete_workout raise v2_unavailable and change
--     nothing (no workout row, no queue row); the workouts lock trigger still keeps
--     a locked row's planned fields and still refuses its delete. Back on, the
--     queued edit lands.
--   * C8.1b (M6b): with the flag off, athlete_change_coach_workout raises
--     v2_unavailable and changes nothing (the app's outbox keeps it), and the plans
--     trigger still refuses a direct deactivation (coach_workouts_present). Back
--     on, the queued skip lands. With the flag off, athlete_replace_training_plan
--     still works (not gated, so an athlete with locked rows can always
--     regenerate) and coach_remove_athlete still ends the link and releases the
--     locks.
--
-- Every later v2 RPC adds its own case to this file (C7.12 DoD): with the flag
-- off, write RPCs raise v2_unavailable and read RPCs return zero rows.
--
-- Raises on the first failure; prints "kill_switch: PASS" otherwise.
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (the runs fixture, Stories 1.2, 1.3, 1.5 and 2.2, the gate and every earlier
-- v2 migration, then the newest v2 migration that adds a case here, twice; CI's
-- matrix row lists the same files):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_plan_locks_fixture.sql
--   (coach_read_fixture.sql plus the plans / workouts columns M6a and M6b need)
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115194500_leave_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117164500_coach_read_rpcs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121110000_coach_consent_v2.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121120000_athlete_run_sharing.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121130000_coach_last_seen_and_events.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121150000_athlete_run_flags.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121160000_coach_link_end.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121180000_coach_feedback_replies.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261122100000_push_tokens_and_prefs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261127100000_coach_workout_locks.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261127110000_coach_plan_locks.sql   (twice)
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kill_switch.sql
-- (C7.7 also needs Story 1.8, 3.1, 3.2, 3.3 and 3.4 before the v2 files:
-- 20261117130000_coach_plan_mode_group_settings, 20261118100000_coach_feedback,
-- 20261118120000_athlete_feedback_read, 20261118160000_get_my_coach and
-- 20261118180000_coach_welcome_note, as in CI's prerequisite list.)

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'kill_switch.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now()),
  ('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e', 'active', now());

-- A-B: TestFlight pair, A unlisted. C-E: App Store pair, C listed.
insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight'),
  ('cccccccc-0000-4000-8000-00000000000c', true, 'app_store'),
  ('eeeeeeee-0000-4000-8000-00000000000e', true, 'app_store');
insert into public.coach_v2_pilot_coaches (coach_id) values ('cccccccc-0000-4000-8000-00000000000c');

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

create function pg_temp.expect_bool(actual boolean, expected boolean, label text) returns void
language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL: % was %, expected %', label, actual, expected;
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.act_as_anon(),
  pg_temp.expect_error(text, text, text), pg_temp.expect_count(text, int, text),
  pg_temp.expect_bool(boolean, boolean, text) to authenticated, anon;

-- Seed ------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from public.runtime_flags
      where key in ('coach_v2', 'coach_v2_push', 'coach_v2_ai') and enabled) <> 3 then
    raise exception 'FAIL: the three v2 flags are not seeded as enabled';
  end if;
end $$;

-- C7.12 AC1: flag on, then off, then on again ------------------------------------------
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  true, 'TestFlight pair with the flag on');
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e'),
  true, 'listed App Store pair with the flag on');

-- Nadav's runbook line.
update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2';

select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  false, 'TestFlight pair with the kill switch on');
select pg_temp.expect_bool(public.link_is_v2('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e'),
  false, 'listed App Store pair with the kill switch on');

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count('select 1 from public.coach_v2_roster_status()', 0, 'roster status with the kill switch on');
-- The client reads the switch: coach_v2 comes back false.
select pg_temp.expect_count(
  $q$select 1 from public.get_runtime_flags() where key = 'coach_v2' and not enabled$q$,
  1, 'client sees coach_v2 = false');
-- Capability reports still work, so the server knows which clients are v2 when the flag returns.
select public.report_client_capabilities(true, '1.2.7', 50, 'testflight');
reset role;

-- The pilot list is untouched by the switch.
do $$
begin
  if not exists (select 1 from public.coach_v2_pilot_coaches where coach_id = 'cccccccc-0000-4000-8000-00000000000c') then
    raise exception 'FAIL: the kill switch changed the pilot list';
  end if;
end $$;

update public.runtime_flags set enabled = true, updated_at = now() where key = 'coach_v2';
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  true, 'TestFlight pair after the flag is back on');
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count('select 1 from public.coach_v2_roster_status()', 1, 'roster status after the flag is back on');
reset role;

-- A missing coach_v2 row fails closed.
delete from public.runtime_flags where key = 'coach_v2';
select pg_temp.expect_bool(public.link_is_v2('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  false, 'missing coach_v2 row');
insert into public.runtime_flags (key, enabled) values ('coach_v2', true);

-- C7.12 AC3: clients cannot touch runtime_flags; only allow-listed keys come back ----------
insert into public.runtime_flags (key, enabled, note) values ('internal_only', true, 'never returned to clients');

set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error(
  $q$select * from public.runtime_flags$q$, '42501', 'client reads runtime_flags');
select pg_temp.expect_error(
  $q$insert into public.runtime_flags (key, enabled) values ('coach_v2_extra', true)$q$, '42501', 'client inserts a flag');
select pg_temp.expect_error(
  $q$update public.runtime_flags set enabled = false$q$, '42501', 'client updates a flag');
select pg_temp.expect_error(
  $q$delete from public.runtime_flags$q$, '42501', 'client deletes a flag');
select pg_temp.expect_count('select 1 from public.get_runtime_flags()', 3, 'allow-listed flags');
select pg_temp.expect_count(
  $q$select 1 from public.get_runtime_flags() where key not in ('coach_v2', 'coach_v2_push', 'coach_v2_ai')$q$,
  0, 'non-allow-listed flag returned');
reset role;

set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error(
  $q$select * from public.get_runtime_flags()$q$, '42501', 'anon calls get_runtime_flags');
select pg_temp.expect_error(
  $q$select * from public.runtime_flags$q$, '42501', 'anon reads runtime_flags');
reset role;

do $$
begin
  if (select enabled from public.runtime_flags where key = 'coach_v2_push') is not true then
    raise exception 'FAIL: a client changed coach_v2_push';
  end if;
end $$;

-- C7.8 (M5a): consent v2 with the switch off ------------------------------------------
-- B (A-B, TestFlight) is on consent v1. E (C-E, listed App Store pair) acks first.
insert into public.coach_invites (coach_id, code, active)
values ('aaaaaaaa-0000-4000-8000-00000000000a', 'DANA22', true);
-- D is only a caller for the invite check: a TestFlight v2 client with no link.
insert into auth.users (id, email, aud, role)
values ('dddddddd-0000-4000-8000-00000000000d', 'third-d@example.com', 'authenticated', 'authenticated');
insert into public.client_capabilities (user_id, coach_v2, channel)
values ('dddddddd-0000-4000-8000-00000000000d', true, 'testflight');

set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select public.ack_coach_consent(2);
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_count(
  $q$select 1 where public.coach_invite_consent_version('DANA22') = 2$q$, 1, 'P8 copy with the flag on');
reset role;
select pg_temp.expect_bool(public.coach_v2_sharing_allowed('cccccccc-0000-4000-8000-00000000000c',
  'eeeeeeee-0000-4000-8000-00000000000e'), true, 'acked pair shares with the flag on');

update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2';

set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status() where not link_is_v2 and not needs_v2_ack and not sharing_active$q$,
  1, 'kill switch on: no P9, no sharing');
select pg_temp.expect_error($q$select public.ack_coach_consent(2)$q$, 'P0001', 'ack with the kill switch on');
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status() where not sharing_active$q$,
  1, 'kill switch on: acked athlete shares nothing');
-- An athlete who already acked gets the same answer back, with nothing changed.
select pg_temp.expect_count(
  $q$select 1 where public.ack_coach_consent(2)->>'status' = 'already_acked'$q$,
  1, 'repeat ack with the kill switch on');
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_count(
  $q$select 1 where public.coach_invite_consent_version('DANA22') = 1$q$, 1, 'A3 copy with the kill switch on');
reset role;
select pg_temp.expect_bool(public.coach_v2_sharing_allowed('cccccccc-0000-4000-8000-00000000000c',
  'eeeeeeee-0000-4000-8000-00000000000e'), false, 'acked pair with the kill switch on');
do $$
begin
  if not exists (select 1 from public.coach_athlete_links
                 where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'active'
                   and consent_version = 1 and consent_acknowledged_at is null) then
    raise exception 'FAIL: an ack with the kill switch on changed the link';
  end if;
end $$;

update public.runtime_flags set enabled = true, updated_at = now() where key = 'coach_v2';

set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_consent_status() where link_is_v2 and needs_v2_ack$q$,
  1, 'flag back on: P9 shows again');
reset role;
select pg_temp.expect_bool(public.coach_v2_sharing_allowed('cccccccc-0000-4000-8000-00000000000c',
  'eeeeeeee-0000-4000-8000-00000000000e'), true, 'acked pair shares again with the flag back on');

-- C7.2 (M3): seen state and coach events with the switch off ---------------------------
-- Same as expect_error, and also checks the message (v2_unavailable, not link_inactive).
create function pg_temp.expect_error_msg(stmt text, expected_state text, expected_message text, label text)
returns void language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL: % succeeded but should have failed with %', label, expected_message;
exception when others then
  if sqlstate = 'P0001' and sqlerrm like 'FAIL:%' then raise; end if;
  if sqlstate <> expected_state or sqlerrm <> expected_message then
    raise exception 'FAIL: % failed with % (%), expected % (%)', label, sqlstate, sqlerrm, expected_state, expected_message;
  end if;
end $$;
grant execute on function pg_temp.expect_error_msg(text, text, text, text) to authenticated;

-- A-B is the TestFlight pair. One run for B in the last hour.
insert into public.runs (auth_user_id, type, distance, duration, completed_at)
values ('bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5, 1800, now() - interval '1 hour');

set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_bool(public.athlete_log_goal_change('22222222-0000-4000-8000-000000000002'), true,
  'goal change with the flag on');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where new_runs = 1 and new_events = 1$q$,
  1, 'summary with the flag on');
reset role;

-- C7.3 (M1a): effort and notes with the switch off --------------------------------------
-- E (acked, C-E listed App Store pair) shares a run completed after the ack.
insert into public.runs (auth_user_id, type, distance, duration, completed_at, source_provider, source_activity_id)
values ('eeeeeeee-0000-4000-8000-00000000000e', 'easy', 5, 1800, now(), 'runsmart_ios', 'E7E7E7E7-0000-4000-8000-000000000007');

set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select public.athlete_set_run_rpe('runsmart_ios', 'E7E7E7E7-0000-4000-8000-000000000007', 8);
select public.athlete_set_run_note('runsmart_ios', 'E7E7E7E7-0000-4000-8000-000000000007', 'Hilly route');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 1, current_date + 1) where rpe = 8 and has_note$q$,
  1, 'C sees effort and a note with the flag on');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select id from public.coach_get_athletes_runs(current_date - 1, current_date + 1)))$q$,
  1, 'C reads the note with the flag on');
reset role;

update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2';

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count('select 1 from public.coach_roster_summary()', 0, 'summary with the kill switch on');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_events('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  0, 'events with the kill switch on');
select pg_temp.expect_error_msg(
  $q$select public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  'P0001', 'v2_unavailable', 'mark seen with the kill switch on');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error_msg(
  $q$select public.athlete_log_goal_change('33333333-0000-4000-8000-000000000003')$q$,
  'P0001', 'v2_unavailable', 'goal change with the kill switch on');
reset role;
do $$
begin
  if exists (select 1 from public.coach_athlete_seen) then
    raise exception 'FAIL: mark seen with the kill switch on wrote a row';
  end if;
  if (select count(*) from public.coach_athlete_events) <> 1 then
    raise exception 'FAIL: a goal change with the kill switch on wrote a row';
  end if;
end $$;

set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
-- The Story 2.2 row stays (1.2.6 coach behavior); only the v2 columns go empty.
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 1, current_date + 1) where rpe is null and not has_note$q$,
  1, 'kill switch on: no effort, no note flag');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select id from public.coach_get_athletes_runs(current_date - 1, current_date + 1)))$q$,
  0, 'kill switch on: no note text');
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
-- Writes raise v2_unavailable, so the app keeps them queued.
select pg_temp.expect_error(
  $q$select public.athlete_set_run_rpe('runsmart_ios', 'E7E7E7E7-0000-4000-8000-000000000007', 9)$q$,
  'P0001', 'RPE with the kill switch on');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_note('runsmart_ios', 'E7E7E7E7-0000-4000-8000-000000000007', 'edited')$q$,
  'P0001', 'note with the kill switch on');
-- Hiding still works, so the note stays hidden when the flag returns.
select pg_temp.expect_count(
  $q$select 1 where public.athlete_set_run_note_hidden('runsmart_ios', 'E7E7E7E7-0000-4000-8000-000000000007', true) = 'saved'$q$,
  1, 'hide with the kill switch on');
reset role;
do $$
begin
  if not exists (select 1 from public.runs where source_activity_id = 'E7E7E7E7-0000-4000-8000-000000000007'
                 and rpe = 8 and athlete_note = 'Hilly route' and note_hidden_from_coach) then
    raise exception 'FAIL: a write with the kill switch on changed effort or the note';
  end if;
end $$;

update public.runtime_flags set enabled = true, updated_at = now() where key = 'coach_v2';

-- The outbox retries after the switch is back on: both writes land, and the counts clear.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_bool(public.athlete_log_goal_change('33333333-0000-4000-8000-000000000003'), true,
  'queued goal change after the flag is back on');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where new_runs = 1 and new_events = 2$q$,
  1, 'summary after the flag is back on');
select public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where new_runs = 0 and new_events = 0$q$,
  1, 'seen after the flag is back on');
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 1, current_date + 1) where rpe = 8 and not has_note$q$,
  1, 'flag back on: effort returns, the hidden note stays hidden');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select id from public.coach_get_athletes_runs(current_date - 1, current_date + 1)))$q$,
  0, 'flag back on: hidden note');
reset role;

-- C7.4 (M1b): flags with the switch off ---------------------------------------------------
-- E (acked, C-E listed App Store pair) sends two flags while the flag is on.
set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select public.athlete_flag_run('f1000000-0000-4000-8000-0000000000e1', 'pain', 'knee');
select public.athlete_flag_run('f2000000-0000-4000-8000-0000000000e2', 'off', null);
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count('select 1 from public.coach_get_athlete_flags()', 2, 'C reads flags with the flag on');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = 'eeeeeeee-0000-4000-8000-00000000000e' and new_flags = 2$q$,
  1, 'flag count with the flag on');
reset role;

update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2';

set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count('select 1 from public.coach_get_athlete_flags(null, true)', 0, 'flags with the kill switch on');
select pg_temp.expect_count('select 1 from public.coach_roster_summary()', 0, 'summary (flags) with the kill switch on');
select pg_temp.expect_error_msg(
  $q$select public.coach_resolve_flag('f1000000-0000-4000-8000-0000000000e1')$q$,
  'P0001', 'v2_unavailable', 'resolve with the kill switch on');
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_error_msg(
  $q$select public.athlete_flag_run('f3000000-0000-4000-8000-0000000000e3', 'pain', 'queued')$q$,
  'P0001', 'v2_unavailable', 'flag with the kill switch on');
-- Removing is a privacy action and works with the switch on.
select pg_temp.expect_count(
  $q$select 1 where public.athlete_remove_flag('f2000000-0000-4000-8000-0000000000e2') = 'removed'$q$,
  1, 'remove with the kill switch on');
reset role;
do $$
begin
  if exists (select 1 from public.athlete_run_flags where id = 'f3000000-0000-4000-8000-0000000000e3')
     or exists (select 1 from public.athlete_run_flags where id = 'f2000000-0000-4000-8000-0000000000e2')
     or exists (select 1 from public.athlete_run_flags where resolved_at is not null) then
    raise exception 'FAIL: a flag write with the kill switch on changed the wrong rows';
  end if;
end $$;

update public.runtime_flags set enabled = true, updated_at = now() where key = 'coach_v2';

-- The outbox retries after the switch is back on.
set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select public.athlete_flag_run('f3000000-0000-4000-8000-0000000000e3', 'pain', 'queued');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select public.coach_resolve_flag('f1000000-0000-4000-8000-0000000000e1');
select pg_temp.expect_count('select 1 from public.coach_get_athlete_flags()', 1, 'flag back on: the queued flag is open');
select pg_temp.expect_count('select 1 from public.coach_get_athlete_flags(null, true)', 2, 'flag back on: with the resolved one');
reset role;

-- C7.11 (M5b): ending a link with the switch off --------------------------------------
-- G (v2 TestFlight) is Dana's athlete, H (v2 TestFlight) is Ron's.
insert into auth.users (id, email, aud, role) values
  ('99999999-0000-4000-8000-000000000009', 'athlete-g@example.com', 'authenticated', 'authenticated'),
  ('88888888-0000-4000-8000-000000000008', 'athlete-h@example.com', 'authenticated', 'authenticated');
insert into public.coach_athlete_links (id, coach_id, athlete_id, status, consented_at) values
  ('00000009-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-00000000000a',
   '99999999-0000-4000-8000-000000000009', 'active', now()),
  ('00000008-0000-4000-8000-000000000008', 'cccccccc-0000-4000-8000-00000000000c',
   '88888888-0000-4000-8000-000000000008', 'active', now());
insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('99999999-0000-4000-8000-000000000009', true, 'testflight'),
  ('88888888-0000-4000-8000-000000000008', true, 'testflight');

update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2';

set local role authenticated;
-- The switch never blocks ending a link: removal and the 1.2.6 leave both work.
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 where public.coach_remove_athlete('99999999-0000-4000-8000-000000000009') = 'removed'$q$,
  1, 'remove with the kill switch on');
select pg_temp.act_as('88888888-0000-4000-8000-000000000008');
select public.leave_coach('00000008-0000-4000-8000-000000000008');
-- The notice is a v2 surface: hidden, and it cannot be marked, while the switch is on.
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
select pg_temp.expect_count('select 1 from public.my_coach_link_notice()', 0, 'notice with the kill switch on');
select pg_temp.expect_error_msg(
  $q$select public.mark_link_notice_seen('00000009-0000-4000-8000-000000000009')$q$,
  'P0001', 'v2_unavailable', 'mark notice with the kill switch on');
reset role;
do $$
begin
  if not exists (select 1 from public.coach_athlete_links
                 where id = '00000009-0000-4000-8000-000000000009' and status = 'revoked'
                   and ended_by = 'coach' and ended_notice_seen_at is null)
     or not exists (select 1 from public.coach_athlete_links
                    where id = '00000008-0000-4000-8000-000000000008' and status = 'revoked'
                      and ended_by = 'athlete') then
    raise exception 'FAIL: a link end with the kill switch on did not revoke, or marked the notice';
  end if;
  if (select count(*) from public.coach_athlete_events
      where (athlete_id = '99999999-0000-4000-8000-000000000009' and kind = 'removed')
         or (athlete_id = '88888888-0000-4000-8000-000000000008' and kind = 'left')) <> 2 then
    raise exception 'FAIL: a link end with the kill switch on did not log its event';
  end if;
end $$;

update public.runtime_flags set enabled = true, updated_at = now() where key = 'coach_v2';

-- Back on: the unseen notice shows once.
set local role authenticated;
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_link_notice() where coach_name = 'Dana'$q$,
  1, 'notice after the flag is back on');
select pg_temp.expect_bool(public.mark_link_notice_seen('00000009-0000-4000-8000-000000000009'), true,
  'mark notice after the flag is back on');
select pg_temp.expect_count('select 1 from public.my_coach_link_notice()', 0, 'notice shown once');
select pg_temp.act_as('88888888-0000-4000-8000-000000000008');
select pg_temp.expect_count('select 1 from public.my_coach_link_notice()', 0, 'no notice after a leave');
reset role;

-- C7.7 (M4): replies with the switch off ---------------------------------------------------
-- C (listed App Store coach) wrote E a note. E replies while the flag is on.
insert into public.coach_feedback (id, coach_id, athlete_id, week_start, kind, text) values
  ('d7000000-0000-4000-8000-0000000000e7', 'cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e',
   current_date, 'note', 'Nice week.');
set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select public.athlete_reply_to_feedback('d7000000-0000-4000-8000-0000000000e7', 'Thanks', 'e7100000-0000-4000-8000-0000000000e7');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count('select 1 from public.coach_get_feedback_replies()', 1, 'C reads a reply with the flag on');
reset role;

update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2';

set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count('select 1 from public.coach_get_feedback_replies()', 0, 'replies with the kill switch on');
select pg_temp.expect_count(
  $q$select 1 where public.coach_mark_reply_read(array['e7100000-0000-4000-8000-0000000000e7']::uuid[]) = 0$q$,
  1, 'mark read with the kill switch on');
select pg_temp.expect_count('select 1 from public.coach_roster_summary()', 0, 'summary (replies) with the kill switch on');
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_error_msg(
  $q$select public.athlete_reply_to_feedback('d7000000-0000-4000-8000-0000000000e7', 'queued', 'e7200000-0000-4000-8000-0000000000e7')$q$,
  'P0001', 'v2_unavailable', 'reply with the kill switch on');
-- The athlete's own replies stay readable.
select pg_temp.expect_count('select 1 from public.my_feedback_replies()', 1, 'own replies with the kill switch on');
reset role;
do $$
begin
  if exists (select 1 from public.coach_feedback_replies where id = 'e7200000-0000-4000-8000-0000000000e7')
     or exists (select 1 from public.coach_feedback_replies where read_at is not null) then
    raise exception 'FAIL: a reply write with the kill switch on changed the wrong rows';
  end if;
end $$;

update public.runtime_flags set enabled = true, updated_at = now() where key = 'coach_v2';

-- The outbox retries after the switch is back on.
set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select public.athlete_reply_to_feedback('d7000000-0000-4000-8000-0000000000e7', 'queued', 'e7200000-0000-4000-8000-0000000000e7');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count('select 1 from public.coach_get_feedback_replies()', 2, 'flag back on: the queued reply lands');
reset role;

-- C8.1a (M6a): coach workout writes with the switch off -------------------------------
-- A coaches B (TestFlight pair). B has an active plan with one AI workout and one
-- coach-locked workout written while the flag is on.
insert into public.plans (id, profile_id, auth_user_id, title, start_date, end_date, is_active) values
  ('b8100000-0000-4000-8000-0000000000b8', 'bbbbbbbb-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b',
   'B plan', current_date - 7, current_date + 60, true);
insert into public.workouts (id, plan_id, auth_user_id, week, day, type, distance, scheduled_date) values
  ('b8000001-0000-4000-8000-0000000000b8', 'b8100000-0000-4000-8000-0000000000b8', 'bbbbbbbb-0000-4000-8000-00000000000b',
   2, to_char(current_date + 2, 'Dy'), 'easy', 5, current_date + 2),
  ('b8000002-0000-4000-8000-0000000000b8', 'b8100000-0000-4000-8000-0000000000b8', 'bbbbbbbb-0000-4000-8000-00000000000b',
   2, to_char(current_date + 3, 'Dy'), 'easy', 5, current_date + 3);
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.coach_update_workout('b8000002-0000-4000-8000-0000000000b8', 0, 'tempo', 8, null, null, null, null);
reset role;
delete from public.athlete_plan_update_queue;

update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2';

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_error_msg(
  $q$select public.coach_create_workout('bbbbbbbb-0000-4000-8000-00000000000b', 'b8000003-0000-4000-8000-0000000000b8',
    current_date + 5, 'easy', 5)$q$, 'P0001', 'v2_unavailable', 'coach_create_workout with the kill switch on');
select pg_temp.expect_error_msg(
  $q$select public.coach_update_workout('b8000001-0000-4000-8000-0000000000b8', 0, 'long', 15, null, null, null, null)$q$,
  'P0001', 'v2_unavailable', 'coach_update_workout with the kill switch on');
select pg_temp.expect_error_msg(
  $q$select public.coach_move_workout('b8000002-0000-4000-8000-0000000000b8', current_date + 6, 1)$q$,
  'P0001', 'v2_unavailable', 'coach_move_workout with the kill switch on');
select pg_temp.expect_error_msg(
  $q$select public.coach_delete_workout('b8000002-0000-4000-8000-0000000000b8', 1)$q$,
  'P0001', 'v2_unavailable', 'coach_delete_workout with the kill switch on');
-- The athlete still cannot change or delete the locked row.
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
update public.workouts set type = 'easy', distance = 1, locked = false
where id = 'b8000002-0000-4000-8000-0000000000b8';
select pg_temp.expect_error_msg(
  $q$delete from public.workouts where id = 'b8000002-0000-4000-8000-0000000000b8'$q$,
  'P0001', 'workout_locked', 'athlete deletes a locked workout with the kill switch on');
reset role;
do $$
begin
  if exists (select 1 from public.workouts where id = 'b8000003-0000-4000-8000-0000000000b8')
     or exists (select 1 from public.athlete_plan_update_queue)
     or not exists (select 1 from public.workouts
                    where id = 'b8000001-0000-4000-8000-0000000000b8'
                      and type = 'easy' and not locked and source = 'ai')
     or not exists (select 1 from public.workouts
                    where id = 'b8000002-0000-4000-8000-0000000000b8'
                      and type = 'tempo' and distance = 8 and locked and coach_revision = 1
                      and scheduled_date = current_date + 3) then
    raise exception 'FAIL: a coach workout write with the kill switch on changed something, or the lock gave way';
  end if;
end $$;

update public.runtime_flags set enabled = true, updated_at = now() where key = 'coach_v2';

-- The outbox retries after the switch is back on.
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.coach_update_workout('b8000001-0000-4000-8000-0000000000b8', 0, 'long', 15, null, null, null, null);
reset role;
do $$
begin
  if not exists (select 1 from public.workouts
                 where id = 'b8000001-0000-4000-8000-0000000000b8' and type = 'long' and locked and coach_revision = 1)
     or not exists (select 1 from public.athlete_plan_update_queue
                    where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and change_count = 1) then
    raise exception 'FAIL: flag back on: the queued coach edit did not land';
  end if;
end $$;

-- C8.1b (M6b): athlete skip / move, plan replacement and lock release ------------------
-- B's plan b81 has two locked future rows (b8000001, b8000002) from the C8.1a case.
update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2';

set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error_msg(
  $q$select public.athlete_change_coach_workout('b8000002-0000-4000-8000-0000000000b8', 'skip', null,
     'b8e00001-0000-4000-8000-0000000000b8')$q$,
  'P0001', 'v2_unavailable', 'athlete_change_coach_workout with the kill switch on');
select pg_temp.expect_error_msg(
  $q$update public.plans set is_active = false where id = 'b8100000-0000-4000-8000-0000000000b8'$q$,
  'P0001', 'coach_workouts_present', 'direct plan deactivation with the kill switch on');
reset role;
do $$
begin
  if exists (select 1 from public.workouts
             where id = 'b8000002-0000-4000-8000-0000000000b8' and athlete_change is not null)
     or exists (select 1 from public.coach_athlete_events
                where client_id = 'b8e00001-0000-4000-8000-0000000000b8')
     or not exists (select 1 from public.plans where id = 'b8100000-0000-4000-8000-0000000000b8' and is_active) then
    raise exception 'FAIL: an athlete change with the kill switch on changed something';
  end if;
end $$;

update public.runtime_flags set enabled = true, updated_at = now() where key = 'coach_v2';

-- The outbox retries after the switch is back on.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count(
  $q$select 1 where public.athlete_change_coach_workout('b8000002-0000-4000-8000-0000000000b8', 'skip', null,
     'b8e00001-0000-4000-8000-0000000000b8') = 'changed'$q$, 1, 'flag back on: the queued skip lands');
reset role;

update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2';

-- Plan replacement is not gated: the athlete acknowledges both coach rows.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.athlete_replace_training_plan('bbbbbbbb-0000-4000-8000-00000000000b',
  jsonb_build_object('title', 'New goal', 'start_date', current_date, 'end_date', current_date + 28, 'total_weeks', 4),
  jsonb_build_array(jsonb_build_object('week', 1, 'day', to_char(current_date + 1, 'Dy'), 'type', 'easy',
                                       'distance', 5, 'scheduled_date', current_date + 1)),
  2);
-- Ending the link with the switch on still releases the locks.
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.coach_remove_athlete('bbbbbbbb-0000-4000-8000-00000000000b');
reset role;
do $$
begin
  if exists (select 1 from public.plans where id = 'b8100000-0000-4000-8000-0000000000b8' and is_active)
     or not exists (select 1 from public.plans
                    where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and is_active and title = 'New goal') then
    raise exception 'FAIL: athlete_replace_training_plan did not work with the kill switch on';
  end if;
  if exists (select 1 from public.workouts
             where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and locked) then
    raise exception 'FAIL: coach_remove_athlete with the kill switch on did not release the locks';
  end if;
end $$;

update public.runtime_flags set enabled = true, updated_at = now() where key = 'coach_v2';

do $$ begin raise notice 'kill_switch: PASS'; end $$;

rollback;
