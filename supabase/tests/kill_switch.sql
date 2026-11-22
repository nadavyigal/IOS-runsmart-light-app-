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
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_read_fixture.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115194500_leave_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117164500_coach_read_rpcs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121110000_coach_consent_v2.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121130000_coach_last_seen_and_events.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121130000_coach_last_seen_and_events.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kill_switch.sql

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

do $$ begin raise notice 'kill_switch: PASS'; end $$;

rollback;
