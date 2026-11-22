-- Test for 20261121120000_athlete_run_sharing.sql (story C7.3, M1a).
--
-- Users: A (Dana) and C (Ron) are coaches. B, E, F, G are athletes.
--   B: TestFlight v2, linked to A, accepted the v2 copy (ack moved to 2 days ago).
--   E: TestFlight v2, linked to C, still on consent v1 (no ack).
--   F: linked to A, ack recorded, but F's build is not v2 (link_is_v2 false).
--   G: solo, no link.
-- Runs (completed_at): B1 1 day ago (after the ack), B2 5 days ago (before the ack,
-- inside the 14-day RPE window), B3 20 days ago (outside the window), E1, F1, G1.
--
-- Proves:
--   * Shape: the three runs columns and both checks exist, every new function is
--     security definer with search_path = '', the internal helpers are not callable
--     by clients, and no policy on runs changes (the coach has no direct access).
--   * AC1: an acked v2 athlete saves RPE and a note on a run with a server row;
--     the coach sees them; an edit after the coach read shows the latest version.
--   * AC2 (server half): no ack -> consent_required, pair not v2 -> v2_unavailable,
--     solo -> link_inactive, and nothing is stored. Values written another way
--     still never reach the coach.
--   * AC3 / D7: a note on a run completed before the ack is refused and never read;
--     RPE inside the 14-day window is accepted, outside it is refused and never read.
--   * AC5: a hidden note is not returned and has_note is false; unhiding restores it.
--     Hiding works even when the pair is not v2.
--   * AC6: a 1.2.6-style upsert without the new keys keeps rpe and athlete_note.
--   * AC7: run ids of another coach's athlete, or of a revoked link, are dropped.
--   * AC10: purge_coach_data_for_deleted_account clears the new columns.
--   * Inputs: RPE outside 1..10, a note over 1000 characters (char_length) fail;
--     1000 emoji (1000 code points) pass, so a note the app counts as 1000 is never
--     rejected (C7.15 AC4). More than 500 run ids fail.
--   * anon is denied on every new RPC.
-- The kill-switch case for these RPCs lives in kill_switch.sql (C7.12 DoD).
-- Raises on the first failure; prints "athlete_run_sharing: PASS" otherwise.
--
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (fixture, prerequisites, then this migration twice; CI's matrix row lists the
-- same files):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_read_fixture.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115194500_leave_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117164500_coach_read_rpcs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121110000_coach_consent_v2.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121120000_athlete_run_sharing.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121120000_athlete_run_sharing.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/athlete_run_sharing.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'athlete_run_sharing.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated'),
  ('ffffffff-0000-4000-8000-00000000000f', 'athlete-f@example.com', 'authenticated', 'authenticated'),
  ('99999999-0000-4000-8000-000000000009', 'solo-g@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now() - interval '30 days'),
  ('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e', 'active', now() - interval '30 days'),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f', 'active', now() - interval '30 days');

insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight'),
  ('cccccccc-0000-4000-8000-00000000000c', true, 'testflight'),
  ('eeeeeeee-0000-4000-8000-00000000000e', true, 'testflight'),
  ('ffffffff-0000-4000-8000-00000000000f', false, 'app_store');

-- F's ack is in the table, but F's build is not v2.
update public.coach_athlete_links
   set consent_version = 2, consent_acknowledged_at = now() - interval '2 days'
 where athlete_id = 'ffffffff-0000-4000-8000-00000000000f';

insert into public.runs (auth_user_id, type, distance, duration, completed_at, notes, source_provider, source_activity_id) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5, 1800, now() - interval '1 day', 'Recorded in RunSmart', 'runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 6, 2100, now() - interval '5 days', 'Recorded in RunSmart', 'runsmart_ios', 'B2B2B2B2-0000-4000-8000-000000000002'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'long', 12, 4500, now() - interval '20 days', 'Recorded in RunSmart', 'runsmart_ios', 'B3B3B3B3-0000-4000-8000-000000000003'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'easy', 4, 1500, now() - interval '1 day', null, 'runsmart_ios', 'E1E1E1E1-0000-4000-8000-000000000001'),
  ('ffffffff-0000-4000-8000-00000000000f', 'easy', 4, 1500, now() - interval '1 day', null, 'runsmart_ios', 'F1F1F1F1-0000-4000-8000-000000000001'),
  ('99999999-0000-4000-8000-000000000009', 'easy', 3, 1200, now() - interval '1 day', null, 'runsmart_ios', '91919191-0000-4000-8000-000000000001');

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

-- Fails unless stmt raises with this SQLSTATE and, when given, this message.
create function pg_temp.expect_error(stmt text, expected_state text, label text, expected_msg text default null)
returns void language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL: % succeeded but should have failed with %', label, expected_state;
exception when others then
  if sqlstate = 'P0001' and sqlerrm like 'FAIL:%' then raise; end if;
  if sqlstate <> expected_state or (expected_msg is not null and sqlerrm <> expected_msg) then
    raise exception 'FAIL: % failed with % (%), expected % (%)', label, sqlstate, sqlerrm, expected_state, expected_msg;
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

create function pg_temp.expect_text(actual text, expected text, label text) returns void
language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL: % was %, expected %', label, actual, expected;
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.act_as_anon(),
  pg_temp.expect_error(text, text, text, text), pg_temp.expect_count(text, int, text),
  pg_temp.expect_text(text, text, text) to authenticated, anon;

-- Shape ---------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'runs'
        and column_name in ('rpe', 'athlete_note', 'note_hidden_from_coach')) <> 3 then
    raise exception 'FAIL: runs is missing a C7.3 column';
  end if;
  if (select count(*) from pg_constraint
      where conrelid = 'public.runs'::regclass
        and conname in ('runs_rpe_range', 'runs_athlete_note_length')) <> 2 then
    raise exception 'FAIL: a C7.3 check constraint is missing';
  end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('athlete_set_run_rpe', 'athlete_set_run_note', 'athlete_set_run_note_hidden',
                        'coach_get_athletes_runs', 'coach_get_run_notes', 'athlete_own_run_id',
                        'athlete_sharing_ack_time', 'purge_coach_data_for_deleted_account')
      and (not p.prosecdef or not coalesce(p.proconfig, '{}') @> array['search_path=""'])
  ) then
    raise exception 'FAIL: a C7.3 function is not security definer with search_path = ''''';
  end if;
  -- Only the fixture's owner policies exist on runs. No coach policy was added.
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'runs') <> 4
     or exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'runs'
                and policyname not in ('runs_select_own', 'runs_insert_own', 'runs_update_own', 'runs_delete_own')) then
    raise exception 'FAIL: the policies on runs changed';
  end if;
end $$;

select pg_temp.expect_error(
  $q$update public.runs set rpe = 11 where source_activity_id = 'B1B1B1B1-0000-4000-8000-000000000001'$q$,
  '23514', 'rpe 11 hits the check');

-- B accepts the v2 copy. The ack is then moved 2 days back so B2 sits before it.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.ack_coach_consent(2);
reset role;
update public.coach_athlete_links
   set consent_acknowledged_at = now() - interval '2 days'
 where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b';

-- AC1: B saves effort and a note --------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
-- Lower-case id: the app's uuidString is upper case, older rows may be lower case.
select pg_temp.expect_text(public.athlete_set_run_rpe('runsmart_ios', 'b1b1b1b1-0000-4000-8000-000000000001', 7),
  'saved', 'B sets RPE on B1');
select pg_temp.expect_text(public.athlete_set_run_rpe('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', 7),
  'saved', 'B sets the same RPE again (idempotent)');
select pg_temp.expect_text(public.athlete_set_run_note('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', '  Felt strong  '),
  'saved', 'B saves a note on B1');
-- D7: B2 is before the ack. RPE inside 14 days is fine, a note is refused.
select pg_temp.expect_text(public.athlete_set_run_rpe('runsmart_ios', 'B2B2B2B2-0000-4000-8000-000000000002', 6),
  'saved', 'RPE inside the 14-day window');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_note('runsmart_ios', 'B2B2B2B2-0000-4000-8000-000000000002', 'old note')$q$,
  'P0001', 'note on a run before the ack', 'note_before_consent');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_rpe('runsmart_ios', 'B3B3B3B3-0000-4000-8000-000000000003', 5)$q$,
  'P0001', 'RPE outside the 14-day window', 'rpe_before_window');
-- Inputs.
select pg_temp.expect_error(
  $q$select public.athlete_set_run_rpe('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', 11)$q$,
  '22023', 'RPE 11', 'bad_rpe');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_rpe('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', 0)$q$,
  '22023', 'RPE 0', 'bad_rpe');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_note('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', repeat('a', 1001))$q$,
  '22023', 'note of 1001 characters', 'note_too_long');
-- No server row yet, and another athlete's run: both answer missing, nothing changes.
select pg_temp.expect_text(public.athlete_set_run_rpe('runsmart_ios', '00000000-0000-4000-8000-000000000000', 4),
  'missing', 'run with no server row');
select pg_temp.expect_text(public.athlete_set_run_rpe('runsmart_ios', 'E1E1E1E1-0000-4000-8000-000000000001', 4),
  'missing', 'another athlete''s run');
select pg_temp.expect_text(public.athlete_set_run_note_hidden('runsmart_ios', 'E1E1E1E1-0000-4000-8000-000000000001', true),
  'missing', 'hide on another athlete''s run');
-- Clients cannot call the internal helpers.
select pg_temp.expect_error(
  $q$select public.athlete_own_run_id('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001')$q$,
  '42501', 'client calls athlete_own_run_id');
select pg_temp.expect_error($q$select public.athlete_sharing_ack_time()$q$, '42501', 'client calls athlete_sharing_ack_time');
select pg_temp.expect_error(
  $q$select public.purge_coach_data_for_deleted_account('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', 'client calls the purge');
reset role;

do $$
begin
  if (select athlete_note from public.runs where source_activity_id = 'B1B1B1B1-0000-4000-8000-000000000001') <> 'Felt strong'
     or (select rpe from public.runs where source_activity_id = 'B1B1B1B1-0000-4000-8000-000000000001') <> 7
     or (select notes from public.runs where source_activity_id = 'B1B1B1B1-0000-4000-8000-000000000001') <> 'Recorded in RunSmart' then
    raise exception 'FAIL: B1 did not store the trimmed note and RPE, or runs.notes changed';
  end if;
  if (select athlete_note from public.runs where source_activity_id = 'B2B2B2B2-0000-4000-8000-000000000002') is not null
     or (select rpe from public.runs where source_activity_id = 'B3B3B3B3-0000-4000-8000-000000000003') is not null
     or (select rpe from public.runs where source_activity_id = 'E1E1E1E1-0000-4000-8000-000000000001') is not null then
    raise exception 'FAIL: a refused write stored something';
  end if;
end $$;

-- 1000 emoji are 1000 code points (char_length), so they pass.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_text(public.athlete_set_run_note('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', repeat('🏃', 1000)),
  'saved', '1000 emoji');
select pg_temp.expect_text(public.athlete_set_run_note('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', 'Felt strong'),
  'saved', 'B restores the note');
reset role;

-- Values written another way (a direct owner write) stay outside the D7 windows.
update public.runs set athlete_note = 'written before the ack' where source_activity_id = 'B2B2B2B2-0000-4000-8000-000000000002';
update public.runs set rpe = 9 where source_activity_id = 'B3B3B3B3-0000-4000-8000-000000000003';

-- Coach A reads -----------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 30, current_date, array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[])$q$,
  3, 'A reads B''s three runs');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 30, current_date, array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[])
     where source = 'runsmart_ios' and ((rpe = 7 and has_note) or (rpe = 6 and not has_note) or (rpe is null and not has_note))$q$,
  3, 'B1 effort 7 with a note, B2 effort 6 without, B3 nothing');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select r.id from public.coach_get_athletes_runs(current_date - 30, current_date) r))
     where athlete_note = 'Felt strong'$q$,
  1, 'A reads only B1''s note');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select r.id from public.coach_get_athletes_runs(current_date - 30, current_date) r))$q$,
  1, 'no note from before the ack');
-- A direct table read is still owner-only.
select pg_temp.expect_count(
  $q$select 1 from public.runs where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b'$q$,
  0, 'A selects B''s runs directly');
select pg_temp.expect_error(
  $q$select * from public.coach_get_run_notes(array(select g from generate_series(1, 501) g)::bigint[])$q$,
  '22023', 'more than 500 run ids', 'too_many_runs');
reset role;

-- AC1: an edit after the coach read shows the latest version.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.athlete_set_run_note('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', 'Felt strong, legs heavy at 4 km');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select id from public.coach_get_athletes_runs(current_date - 30, current_date)))
     where athlete_note = 'Felt strong, legs heavy at 4 km'$q$,
  1, 'A sees the edited note');
reset role;

-- AC5: hide, then unhide.
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_text(public.athlete_set_run_note_hidden('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', true),
  'saved', 'B hides the note');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select id from public.coach_get_athletes_runs(current_date - 30, current_date)))$q$,
  0, 'hidden note');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 30, current_date) where has_note$q$,
  0, 'has_note with the note hidden');
-- Effort stays visible: only the note is hidden.
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 30, current_date) where rpe = 7$q$,
  1, 'effort with the note hidden');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.athlete_set_run_note_hidden('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', false);
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select id from public.coach_get_athletes_runs(current_date - 30, current_date)))$q$,
  1, 'note after unhide');
reset role;

-- AC7: another coach asks for B's run ids explicitly (ids taken as the superuser) -------------
create temp table b_runs as
  select id from public.runs where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
grant select on b_runs to authenticated;
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select id from b_runs))$q$,
  0, 'C asks for B''s notes');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 30, current_date, array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[])$q$,
  0, 'C asks for B''s runs');
reset role;

-- AC2: no ack, pair not v2, solo --------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_rpe('runsmart_ios', 'E1E1E1E1-0000-4000-8000-000000000001', 5)$q$,
  'P0001', 'E has not acked: RPE', 'consent_required');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_note('runsmart_ios', 'E1E1E1E1-0000-4000-8000-000000000001', 'hi')$q$,
  'P0001', 'E has not acked: note', 'consent_required');
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_rpe('runsmart_ios', 'F1F1F1F1-0000-4000-8000-000000000001', 5)$q$,
  'P0001', 'F is not v2', 'v2_unavailable');
-- Hiding is always allowed.
select pg_temp.expect_text(public.athlete_set_run_note_hidden('runsmart_ios', 'F1F1F1F1-0000-4000-8000-000000000001', true),
  'saved', 'F hides without v2');
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_rpe('runsmart_ios', '91919191-0000-4000-8000-000000000001', 5)$q$,
  'P0001', 'solo athlete', 'link_inactive');
reset role;

-- Values written another way for E and F still never reach their coaches.
update public.runs set rpe = 5, athlete_note = 'direct write'
 where source_activity_id in ('E1E1E1E1-0000-4000-8000-000000000001', 'F1F1F1F1-0000-4000-8000-000000000001');
update public.runs set note_hidden_from_coach = false
 where source_activity_id = 'F1F1F1F1-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 30, current_date) where rpe is null and not has_note$q$,
  1, 'C: E''s run has no effort and no note (no ack)');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select id from public.coach_get_athletes_runs(current_date - 30, current_date)))$q$,
  0, 'C: no note for E');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 30, current_date, array['ffffffff-0000-4000-8000-00000000000f']::uuid[])
     where rpe is null and not has_note$q$,
  1, 'A: F''s run has no effort and no note (not v2)');
reset role;

-- AC6: a 1.2.6-style upsert without the new keys keeps them --------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
insert into public.runs (auth_user_id, type, distance, duration, completed_at, notes, source_provider, source_activity_id)
values ('bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5.2, 1850, now() - interval '1 day', 'Recorded in RunSmart',
        'runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001')
on conflict (source_provider, source_activity_id) do update
  set type = excluded.type, distance = excluded.distance, duration = excluded.duration,
      completed_at = excluded.completed_at, notes = excluded.notes;
reset role;
do $$
begin
  if not exists (select 1 from public.runs
                 where source_activity_id = 'B1B1B1B1-0000-4000-8000-000000000001'
                   and distance = 5.2 and rpe = 7 and athlete_note = 'Felt strong, legs heavy at 4 km'
                   and not note_hidden_from_coach) then
    raise exception 'FAIL: a 1.2.6-style upsert changed rpe, athlete_note or note_hidden_from_coach';
  end if;
end $$;

-- anon -------------------------------------------------------------------------------------------
set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error(
  $q$select public.athlete_set_run_rpe('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', 3)$q$, '42501', 'anon sets RPE');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_note('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', 'x')$q$, '42501', 'anon sets a note');
select pg_temp.expect_error(
  $q$select public.athlete_set_run_note_hidden('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', true)$q$, '42501', 'anon hides');
select pg_temp.expect_error(
  $q$select * from public.coach_get_athletes_runs(current_date - 30, current_date)$q$, '42501', 'anon reads runs');
select pg_temp.expect_error(
  $q$select * from public.coach_get_run_notes(array[1]::bigint[])$q$, '42501', 'anon reads notes');
reset role;

-- AC7: a revoked link ------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.leave_coach((select id from public.coach_athlete_links
                           where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'active'));
select pg_temp.expect_error(
  $q$select public.athlete_set_run_rpe('runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', 3)$q$,
  'P0001', 'RPE after leaving', 'link_inactive');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_run_notes(array(select id from b_runs))$q$,
  0, 'A asks for B''s notes after B left');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athletes_runs(current_date - 30, current_date, array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[])$q$,
  0, 'A asks for B''s runs after B left');
reset role;

-- AC10: account deletion clears the new columns ------------------------------------------------------
select public.purge_coach_data_for_deleted_account('bbbbbbbb-0000-4000-8000-00000000000b');
do $$
begin
  if exists (select 1 from public.runs
             where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
               and (rpe is not null or athlete_note is not null or note_hidden_from_coach)) then
    raise exception 'FAIL: the purge left effort or a note on a run row';
  end if;
  if exists (select 1 from public.runs where auth_user_id = 'eeeeeeee-0000-4000-8000-00000000000e' and rpe is null) then
    raise exception 'FAIL: the purge touched another athlete''s run';
  end if;
end $$;

do $$ begin raise notice 'athlete_run_sharing: PASS'; end $$;

rollback;
