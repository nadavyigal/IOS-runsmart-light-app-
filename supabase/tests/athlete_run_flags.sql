-- Test for 20261121150000_athlete_run_flags.sql (story C7.4, M1b).
--
-- Users: A (Dana) and C (Ron) are coaches. B, E, F, G, H are athletes.
--   A-B: TestFlight v2 pair, consent v2 acked (sharing).
--   A-E: v2 pair, consent v1 (no ack yet).
--   A-F: F is a 1.2.6 client (no capability row), acked: not a v2 pair.
--   A-G: v2 pair, acked. Used for the account-deletion case.
--   A-H: v2, acked, then revoked; later H rejoins A on a new link.
--   C: v2, linked to nobody.
-- Proves:
--   * Shape: RLS on with one owner-select policy, authenticated may only select,
--     anon nothing; kind and note checks; every function is security definer with
--     search_path = '', anon is denied, authenticated may execute.
--   * Athlete writes (AC1, AC2, AC4): saved with its run; idempotent by p_id (one
--     row, the first write stands); run-less flag; a run with no server row and
--     another user's run both save run-less; bad kind, a long note and a null id
--     are rejected; no link, no consent and a pair that is not v2 are refused and
--     write nothing.
--   * Owner select: the athlete sees only their own flags; a coach reading the
--     table gets nothing; no client insert, update or delete.
--   * Coach reads (AC6, AC10): the active coach sees open flags with the note;
--     another coach, an athlete, anon, no consent and a revoked link see nothing;
--     a rejoin does not bring old flags back.
--   * Resolve (AC7, AC10): only the flag's active coach resolves; the athlete and
--     another coach get flag_not_found; repeat is idempotent; a revoked link gets
--     link_inactive; resolved flags show only with p_include_resolved.
--   * Remove (AC5): own unresolved flag only; a resolved flag stays; repeat and
--     another user's flag return 'missing' and change nothing.
--   * Run deleted (AC10): the flag stays and reports run_deleted.
--   * coach_roster_summary: new_flags counts open flags after the baseline, only
--     for a sharing pair, drops after the coach opens the athlete, and C7.2's run
--     and event counts are unchanged.
--   * Account deletion (AC10): the purge deletes the athlete's flags, clears
--     resolved_by for a deleted coach, and keeps every C7.3 block (rpe and note
--     cleared on a leftover run row).
-- The kill-switch case lives in kill_switch.sql (C7.12 DoD).
-- Raises on the first failure; prints "athlete_run_flags: PASS" otherwise.
--
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (CI's matrix row lists the same files):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_read_fixture.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115194500_leave_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117164500_coach_read_rpcs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121110000_coach_consent_v2.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121120000_athlete_run_sharing.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121130000_coach_last_seen_and_events.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121150000_athlete_run_flags.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121150000_athlete_run_flags.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/athlete_run_flags.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'athlete_run_flags.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated'),
  ('ffffffff-0000-4000-8000-00000000000f', 'athlete-f@example.com', 'authenticated', 'authenticated'),
  ('99999999-0000-4000-8000-000000000009', 'athlete-g@example.com', 'authenticated', 'authenticated'),
  ('88888888-0000-4000-8000-000000000008', 'athlete-h@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_athlete_links
  (id, coach_id, athlete_id, status, consented_at, revoked_at, consent_version, consent_acknowledged_at) values
  ('11111111-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b',
   'active', now() - interval '30 days', null, 2, now() - interval '20 days'),
  ('11111111-0000-4000-8000-00000000000e', 'aaaaaaaa-0000-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-00000000000e',
   'active', now() - interval '30 days', null, 1, null),
  ('11111111-0000-4000-8000-00000000000f', 'aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f',
   'active', now() - interval '30 days', null, 2, now() - interval '20 days'),
  ('11111111-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-00000000000a', '99999999-0000-4000-8000-000000000009',
   'active', now() - interval '30 days', null, 2, now() - interval '20 days'),
  ('11111111-0000-4000-8000-000000000008', 'aaaaaaaa-0000-4000-8000-00000000000a', '88888888-0000-4000-8000-000000000008',
   'active', now() - interval '30 days', null, 2, now() - interval '20 days');

insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight'),
  ('cccccccc-0000-4000-8000-00000000000c', true, 'testflight'),
  ('eeeeeeee-0000-4000-8000-00000000000e', true, 'testflight'),
  ('99999999-0000-4000-8000-000000000009', true, 'testflight'),
  ('88888888-0000-4000-8000-000000000008', true, 'testflight');

-- Runs: B has one with a server row; another for G (account deletion); one for E.
insert into public.runs (auth_user_id, type, distance, duration, completed_at, source_provider, source_activity_id, rpe, athlete_note) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5, 1800, now() - interval '2 hours', 'runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001', null, null),
  ('99999999-0000-4000-8000-000000000009', 'easy', 5, 1800, now() - interval '2 hours', 'runsmart_ios', 'G1G1G1G1-0000-4000-8000-000000000001', 6, 'tired'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'easy', 5, 1800, now() - interval '2 hours', 'runsmart_ios', 'E1E1E1E1-0000-4000-8000-000000000001', null, null);

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

-- expected_message null checks only the SQLSTATE.
create function pg_temp.expect_error(stmt text, expected_state text, expected_message text, label text)
returns void language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL: % succeeded but should have failed with %', label, expected_state;
exception when others then
  if sqlstate = 'P0001' and sqlerrm like 'FAIL:%' then raise; end if;
  if sqlstate <> expected_state then
    raise exception 'FAIL: % failed with % (%), expected %', label, sqlstate, sqlerrm, expected_state;
  end if;
  if expected_message is not null and sqlerrm <> expected_message then
    raise exception 'FAIL: % failed with message "%", expected "%"', label, sqlerrm, expected_message;
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

-- Shape -------------------------------------------------------------------------------
do $$
declare
  fn text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.athlete_run_flags'::regclass) then
    raise exception 'FAIL: RLS is off on athlete_run_flags';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'athlete_run_flags') <> 1
     or not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'athlete_run_flags'
                    and policyname = 'athlete_run_flags_owner_select' and cmd = 'SELECT') then
    raise exception 'FAIL: athlete_run_flags must have exactly one policy, the owner select';
  end if;
  if not has_table_privilege('authenticated', 'public.athlete_run_flags', 'select')
     or has_table_privilege('authenticated', 'public.athlete_run_flags', 'insert,update,delete')
     or has_table_privilege('anon', 'public.athlete_run_flags', 'select,insert,update,delete') then
    raise exception 'FAIL: wrong table grants on athlete_run_flags';
  end if;
  foreach fn in array array[
    'public.athlete_flag_run(uuid, text, text, text, text)',
    'public.athlete_remove_flag(uuid)',
    'public.coach_get_athlete_flags(uuid[], boolean)',
    'public.coach_resolve_flag(uuid)',
    'public.coach_roster_summary()'
  ] loop
    if not exists (
      select 1 from pg_proc
      where oid = fn::regprocedure and prosecdef
        and proconfig @> array['search_path=""']
    ) then
      raise exception 'FAIL: % is not security definer with search_path = ''''', fn;
    end if;
    if has_function_privilege('anon', fn, 'execute') then
      raise exception 'FAIL: anon can execute %', fn;
    end if;
    if not has_function_privilege('authenticated', fn, 'execute') then
      raise exception 'FAIL: authenticated cannot execute %', fn;
    end if;
  end loop;
  if has_function_privilege('authenticated', 'public.purge_coach_data_for_deleted_account(uuid)', 'execute') then
    raise exception 'FAIL: authenticated can execute the purge';
  end if;
end $$;

select pg_temp.expect_error(
  $q$insert into public.athlete_run_flags (id, athlete_id, kind) values (gen_random_uuid(), 'bbbbbbbb-0000-4000-8000-00000000000b', 'other')$q$,
  '23514', null, 'unknown flag kind');
select pg_temp.expect_error(
  $q$insert into public.athlete_run_flags (id, athlete_id, kind, note) values (gen_random_uuid(), 'bbbbbbbb-0000-4000-8000-00000000000b', 'pain', repeat('x', 501))$q$,
  '23514', null, 'note over 500 characters');

-- Athlete writes ----------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

-- Flag 1: pain on a run with a server row (lower-case id still matches).
select pg_temp.expect_text(
  public.athlete_flag_run('f1000000-0000-4000-8000-000000000001', 'pain', '  left knee, last 2 reps  ',
                          'runsmart_ios', 'b1b1b1b1-0000-4000-8000-000000000001'),
  'saved', 'flag with its run');
-- The same client id again: one row, the first note stands.
select pg_temp.expect_text(
  public.athlete_flag_run('f1000000-0000-4000-8000-000000000001', 'off', 'edited',
                          'runsmart_ios', 'B1B1B1B1-0000-4000-8000-000000000001'),
  'saved', 'repeated flag id');
-- Flag 2: run-less ("Something off?" on Today).
select pg_temp.expect_text(
  public.athlete_flag_run('f2000000-0000-4000-8000-000000000002', 'off', null),
  'saved_without_run', 'run-less flag');
-- Flag 3: a run with no server row yet saves run-less.
select pg_temp.expect_text(
  public.athlete_flag_run('f3000000-0000-4000-8000-000000000003', 'pain', '',
                          'runsmart_ios', 'NOPE0000-0000-4000-8000-000000000000'),
  'saved_without_run', 'flag on a run with no server row');
-- Flag 4: another athlete's run is never attached.
select pg_temp.expect_text(
  public.athlete_flag_run('f4000000-0000-4000-8000-000000000004', 'off', 'whose run?',
                          'runsmart_ios', 'G1G1G1G1-0000-4000-8000-000000000001'),
  'saved_without_run', 'flag naming another athlete''s run');

select pg_temp.expect_error(
  $q$select public.athlete_flag_run(gen_random_uuid(), 'other', null)$q$, '22023', 'bad_kind', 'bad kind');
select pg_temp.expect_error(
  $q$select public.athlete_flag_run(gen_random_uuid(), 'pain', repeat('x', 501))$q$, '22023', 'note_too_long', 'note too long');
select pg_temp.expect_error(
  $q$select public.athlete_flag_run(null, 'pain', null)$q$, '22023', 'bad_flag_id', 'null id');

-- Owner select: B sees 4 flags; no direct writes.
select pg_temp.expect_count('select 1 from public.athlete_run_flags', 4, 'B reads own flags');
select pg_temp.expect_error(
  $q$insert into public.athlete_run_flags (id, athlete_id, kind) values (gen_random_uuid(), 'bbbbbbbb-0000-4000-8000-00000000000b', 'pain')$q$,
  '42501', null, 'athlete inserts directly');
select pg_temp.expect_error(
  $q$update public.athlete_run_flags set resolved_at = now()$q$, '42501', null, 'athlete updates directly');
select pg_temp.expect_error(
  $q$delete from public.athlete_run_flags$q$, '42501', null, 'athlete deletes directly');

-- No link: C is a coach with no coach. No consent: E. Not a v2 pair: F.
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_error(
  $q$select public.athlete_flag_run(gen_random_uuid(), 'pain', null)$q$, 'P0001', 'link_inactive', 'flag with no link');
select pg_temp.expect_count('select 1 from public.athlete_run_flags', 0, 'C reads the table');
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_error(
  $q$select public.athlete_flag_run(gen_random_uuid(), 'pain', null)$q$, 'P0001', 'consent_required', 'flag before the ack');
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_error(
  $q$select public.athlete_flag_run(gen_random_uuid(), 'pain', null)$q$, 'P0001', 'v2_unavailable', 'flag on a pair that is not v2');
-- An id that is already someone else's flag.
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
select pg_temp.expect_error(
  $q$select public.athlete_flag_run('f1000000-0000-4000-8000-000000000001', 'pain', null)$q$, '22023', 'bad_flag_id', 'another user''s flag id');
reset role;

do $$
begin
  if (select count(*) from public.athlete_run_flags) <> 4 then
    raise exception 'FAIL: a refused write stored a flag';
  end if;
  if not exists (select 1 from public.athlete_run_flags where id = 'f1000000-0000-4000-8000-000000000001'
                 and kind = 'pain' and note = 'left knee, last 2 reps' and run_linked and run_id is not null
                 and link_id = '11111111-0000-4000-8000-00000000000b') then
    raise exception 'FAIL: flag 1 was not stored once, trimmed, with its run and link';
  end if;
  if exists (select 1 from public.athlete_run_flags where id <> 'f1000000-0000-4000-8000-000000000001'
             and (run_id is not null or run_linked)) then
    raise exception 'FAIL: a run-less flag got a run';
  end if;
  if (select note from public.athlete_run_flags where id = 'f3000000-0000-4000-8000-000000000003') is not null then
    raise exception 'FAIL: a blank note was stored';
  end if;
end $$;

-- Flags that the RPCs refuse to write, inserted directly to test the read gates:
-- E has no ack (consent), H is about to be revoked, G is for account deletion.
insert into public.athlete_run_flags (id, athlete_id, link_id, kind, note, created_at) values
  ('fe000000-0000-4000-8000-00000000000e', 'eeeeeeee-0000-4000-8000-00000000000e', '11111111-0000-4000-8000-00000000000e', 'pain', 'no ack', now()),
  ('f8000000-0000-4000-8000-000000000008', '88888888-0000-4000-8000-000000000008', '11111111-0000-4000-8000-000000000008', 'pain', 'before leaving', now());
set local role authenticated;
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
select pg_temp.expect_text(
  public.athlete_flag_run('f9000000-0000-4000-8000-000000000009', 'pain', 'shin',
                          'runsmart_ios', 'G1G1G1G1-0000-4000-8000-000000000001'),
  'saved', 'G flags a run');
reset role;

-- Coach reads -------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_flags(array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[])$q$,
  4, 'A reads B''s open flags');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_flags() where id = 'f1000000-0000-4000-8000-000000000001'
     and kind = 'pain' and note = 'left knee, last 2 reps' and run_id is not null and not run_deleted
     and resolved_at is null and not resolved_by_me$q$,
  1, 'A reads the note verbatim');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_flags(array['eeeeeeee-0000-4000-8000-00000000000e']::uuid[])$q$,
  0, 'no consent: no flags');
select pg_temp.expect_count('select 1 from public.coach_get_athlete_flags()', 6, 'A reads B, G and H');
select pg_temp.expect_count('select 1 from public.athlete_run_flags', 0, 'A reads the table directly');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count('select 1 from public.coach_get_athlete_flags()', 0, 'another coach reads flags');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count('select 1 from public.coach_get_athlete_flags()', 0, 'the athlete calls the coach read');
reset role;

set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error($q$select * from public.coach_get_athlete_flags()$q$, '42501', null, 'anon reads flags');
select pg_temp.expect_error($q$select public.athlete_flag_run(gen_random_uuid(), 'pain', null)$q$, '42501', null, 'anon flags');
select pg_temp.expect_error($q$select public.athlete_remove_flag('f2000000-0000-4000-8000-000000000002')$q$, '42501', null, 'anon removes');
select pg_temp.expect_error($q$select public.coach_resolve_flag('f2000000-0000-4000-8000-000000000002')$q$, '42501', null, 'anon resolves');
select pg_temp.expect_error($q$select * from public.coach_roster_summary()$q$, '42501', null, 'anon summary');
select pg_temp.expect_error($q$select * from public.athlete_run_flags$q$, '42501', null, 'anon reads the table');
reset role;

-- Roster summary ----------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
-- B: one run in the last 7 days and 4 open flags. E: a run, no flags (no consent).
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
     and new_runs = 1 and new_flags = 4 and new_replies = 0 and new_events = 0 and oldest_new_at is not null$q$,
  1, 'summary counts B''s flags');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = 'eeeeeeee-0000-4000-8000-00000000000e'
     and new_runs = 1 and new_flags = 0$q$,
  1, 'summary: no consent, no flag count');
reset role;

-- Resolve -----------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error(
  $q$select public.coach_resolve_flag('f1000000-0000-4000-8000-000000000001')$q$, 'P0001', 'flag_not_found', 'the athlete resolves');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_error(
  $q$select public.coach_resolve_flag('f1000000-0000-4000-8000-000000000001')$q$, 'P0001', 'flag_not_found', 'another coach resolves');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.coach_resolve_flag('f1000000-0000-4000-8000-000000000001');
reset role;

do $$
declare
  v_first timestamptz;
begin
  select resolved_at into v_first from public.athlete_run_flags where id = 'f1000000-0000-4000-8000-000000000001';
  if v_first is null or (select resolved_by from public.athlete_run_flags where id = 'f1000000-0000-4000-8000-000000000001')
                         <> 'aaaaaaaa-0000-4000-8000-00000000000a' then
    raise exception 'FAIL: A''s resolve did not store resolved_at and resolved_by';
  end if;
  perform set_config('test.first_resolved', v_first::text, true);
end $$;

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_text(
  public.coach_resolve_flag('f1000000-0000-4000-8000-000000000001')::text,
  current_setting('test.first_resolved'), 'repeated resolve keeps the first time');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_flags(array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[])$q$,
  3, 'resolved flag leaves the open list');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_flags(array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[], true)
     where id = 'f1000000-0000-4000-8000-000000000001' and resolved_at is not null and resolved_by_me$q$,
  1, 'resolved flag with p_include_resolved');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and new_flags = 3$q$,
  1, 'summary drops the resolved flag');
reset role;

-- Remove ------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error(
  $q$select public.athlete_remove_flag('f1000000-0000-4000-8000-000000000001')$q$, 'P0001', 'flag_resolved', 'remove a resolved flag');
select pg_temp.expect_text(public.athlete_remove_flag('f2000000-0000-4000-8000-000000000002'), 'removed', 'remove an open flag');
select pg_temp.expect_text(public.athlete_remove_flag('f2000000-0000-4000-8000-000000000002'), 'missing', 'remove it again');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_text(public.athlete_remove_flag('f3000000-0000-4000-8000-000000000003'), 'missing', 'remove another user''s flag');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_text(public.athlete_remove_flag('f3000000-0000-4000-8000-000000000003'), 'missing', 'the coach removes a flag');
select pg_temp.expect_error(
  $q$select public.coach_resolve_flag('f2000000-0000-4000-8000-000000000002')$q$, 'P0001', 'flag_not_found', 'resolve a removed flag');
reset role;

do $$
begin
  if not exists (select 1 from public.athlete_run_flags where id = 'f1000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.athlete_run_flags where id = 'f2000000-0000-4000-8000-000000000002')
     or not exists (select 1 from public.athlete_run_flags where id = 'f3000000-0000-4000-8000-000000000003') then
    raise exception 'FAIL: remove changed the wrong rows';
  end if;
end $$;

-- Seen: opening B clears the flag count; a flag sent after that counts again.
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
     and new_runs = 0 and new_flags = 0$q$,
  1, 'seen clears the flag count');
reset role;
-- now() is fixed inside this transaction: move the earlier flags an hour back and
-- the visit a minute back, so only the next flag is after the visit.
update public.athlete_run_flags set created_at = now() - interval '1 hour';
update public.coach_athlete_seen set seen_at = now() - interval '1 minute'
where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.athlete_flag_run('f5000000-0000-4000-8000-000000000005', 'pain', 'again');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and new_flags = 1$q$,
  1, 'a flag after the visit counts');
reset role;

-- Run deleted -------------------------------------------------------------------------
delete from public.runs where source_activity_id = 'B1B1B1B1-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_flags(null, true) where id = 'f1000000-0000-4000-8000-000000000001'
     and run_id is null and run_deleted$q$,
  1, 'deleting the run keeps the flag and reports it');
reset role;

-- Revoked link, then a rejoin -----------------------------------------------------------
update public.coach_athlete_links set status = 'revoked', revoked_at = now()
where id = '11111111-0000-4000-8000-000000000008';
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_flags(array['88888888-0000-4000-8000-000000000008']::uuid[], true)$q$,
  0, 'revoked link: no flags');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = '88888888-0000-4000-8000-000000000008'$q$,
  0, 'revoked link: no summary row');
select pg_temp.expect_error(
  $q$select public.coach_resolve_flag('f8000000-0000-4000-8000-000000000008')$q$, 'P0001', 'link_inactive', 'resolve on a revoked link');
-- The athlete still sees and can remove their own flag after leaving.
select pg_temp.act_as('88888888-0000-4000-8000-000000000008');
select pg_temp.expect_count('select 1 from public.athlete_run_flags', 1, 'H reads own flag after leaving');
reset role;

insert into public.coach_athlete_links
  (id, coach_id, athlete_id, status, consented_at, consent_version, consent_acknowledged_at) values
  ('22222222-0000-4000-8000-000000000008', 'aaaaaaaa-0000-4000-8000-00000000000a', '88888888-0000-4000-8000-000000000008',
   'active', now(), 2, now());
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_athlete_flags(array['88888888-0000-4000-8000-000000000008']::uuid[], true)$q$,
  0, 'a rejoin does not bring old flags back');
reset role;

-- Account deletion --------------------------------------------------------------------
select public.purge_coach_data_for_deleted_account('99999999-0000-4000-8000-000000000009');
do $$
begin
  if exists (select 1 from public.athlete_run_flags where athlete_id = '99999999-0000-4000-8000-000000000009') then
    raise exception 'FAIL: the purge left the athlete''s flags';
  end if;
  if exists (select 1 from public.runs where auth_user_id = '99999999-0000-4000-8000-000000000009'
             and (rpe is not null or athlete_note is not null)) then
    raise exception 'FAIL: the purge lost the C7.3 block';
  end if;
  if not exists (select 1 from public.athlete_run_flags where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b') then
    raise exception 'FAIL: the purge removed another athlete''s flags';
  end if;
end $$;

-- The coach deletes their account: B's flags stay, "handled by" goes.
select public.purge_coach_data_for_deleted_account('aaaaaaaa-0000-4000-8000-00000000000a');
do $$
begin
  if not exists (select 1 from public.athlete_run_flags where id = 'f1000000-0000-4000-8000-000000000001'
                 and resolved_by is null and resolved_at is not null and link_id is null) then
    raise exception 'FAIL: a deleted coach left resolved_by, or the athlete lost the flag';
  end if;
end $$;

-- Deleting the auth user cascades too.
delete from auth.users where id = '88888888-0000-4000-8000-000000000008';
do $$
begin
  if exists (select 1 from public.athlete_run_flags where athlete_id = '88888888-0000-4000-8000-000000000008') then
    raise exception 'FAIL: deleting the auth user left flags';
  end if;
end $$;

do $$ begin raise notice 'athlete_run_flags: PASS'; end $$;

rollback;
