-- Test for 20261121160000_coach_link_end.sql (C7.11, M5b): the coach removes an
-- athlete, and leave_coach goes through the same end_coach_link.
--
-- Proves:
--   * Grants: anon cannot call the new RPCs; no client can call end_coach_link or
--     coach_link_notice_allowed; every function is security definer with
--     search_path = ''.
--   * AC4: leave_coach keeps Story 1.5's signature (expected_link_id uuid) and
--     void return, its errors (not_linked for a third user, a stale id and a
--     second leave) and its effect, and now also sets ended_by = 'athlete' and
--     logs one left event.
--   * AC6: a non-coach, another coach and the athlete themselves cannot remove;
--     the link stays active. A repeated remove returns already_ended and logs
--     nothing more.
--   * AC2: a removal sets status revoked, revoked_at, ended_by = 'coach' and logs
--     one removed event. The coach's other athletes are untouched.
--   * AC3 parity: after a removal and after a leave, every coach read that exists
--     at this point returns zero rows for that athlete (get_coach_welcome raises
--     not_linked, as it does for any unlinked athlete). C7.4's
--     coach_get_athlete_flags is included. Each read is checked
--     non-empty first, so a zero means the link end did it.
--   * AC7: a queued coach write for the removed athlete raises link_inactive.
--   * AC5: the removed v2 athlete sees one notice with the coach's name, once.
--     An athlete who left sees none. A 1.2.6 athlete (no v2 capability row) sees
--     none and cannot mark it. Joining a coach again hides an unseen old notice.
--   * The athlete cannot write ended_by or ended_notice_seen_at directly.
--
-- Raises on the first failure; prints "coach_link_end: PASS" otherwise.
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (the runs fixture, the coach migrations whose reads the parity test covers,
-- every earlier v2 migration, then M5b twice; CI's matrix row lists the same files):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_read_fixture.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115194500_leave_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117100000_coach_route_upload.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117130000_coach_plan_mode_group_settings.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117164500_coach_read_rpcs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261118100000_coach_feedback.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261118120000_athlete_feedback_read.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261118140000_coach_run_route.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261118160000_get_my_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261118180000_coach_welcome_note.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121110000_coach_consent_v2.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121120000_athlete_run_sharing.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121130000_coach_last_seen_and_events.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121150000_athlete_run_flags.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121160000_coach_link_end.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121160000_coach_link_end.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_link_end.sql
--
-- Later stories that add a coach read (C7.7, C8.1b, C8.6, C9.1) add it to
-- pg_temp.parity below, so the parity test grows with end_coach_link.

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_link_end.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

-- A Dana and C Ron are coaches. B and F are Dana's athletes, E is Ron's.
-- D is a signed-in user with no coach role and no link.
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'third-d@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated'),
  ('ffffffff-0000-4000-8000-00000000000f', 'athlete-f@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.profiles (auth_user_id, name) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'Bea'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'Eli'),
  ('ffffffff-0000-4000-8000-00000000000f', 'Fay');

insert into public.coach_athlete_links (id, coach_id, athlete_id, status, consented_at, created_at) values
  ('0000000b-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-00000000000a',
   'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now() - interval '20 days', now() - interval '20 days'),
  ('0000000e-0000-4000-8000-00000000000e', 'cccccccc-0000-4000-8000-00000000000c',
   'eeeeeeee-0000-4000-8000-00000000000e', 'active', now() - interval '20 days', now() - interval '20 days'),
  ('0000000f-0000-4000-8000-00000000000f', 'aaaaaaaa-0000-4000-8000-00000000000a',
   'ffffffff-0000-4000-8000-00000000000f', 'active', now() - interval '20 days', now() - interval '20 days');

-- A, B, C and E run the v2 TestFlight build. F is on 1.2.6: no capability row.
insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight'),
  ('cccccccc-0000-4000-8000-00000000000c', true, 'testflight'),
  ('eeeeeeee-0000-4000-8000-00000000000e', true, 'testflight');

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

create function pg_temp.expect_error(stmt text, expected_state text, expected_message text, label text)
returns void language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL: % succeeded but should have failed with %', label, expected_state;
exception when others then
  if sqlstate = 'P0001' and sqlerrm like 'FAIL:%' then raise; end if;
  if sqlstate <> expected_state or (expected_message is not null and sqlerrm <> expected_message) then
    raise exception 'FAIL: % failed with % (%), expected % (%)', label, sqlstate, sqlerrm,
      expected_state, coalesce(expected_message, 'any message');
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

-- Every coach read that exists after M5b, for one athlete, as the signed-in coach.
-- p_expected = 0 after the link ended; the baseline run checks each read is non-empty.
-- When the link is gone, get_coach_welcome raises not_linked (42501) instead of rows.
-- p_run is the athlete's seeded run (the coach cannot read runs directly).
create function pg_temp.parity(p_athlete uuid, p_run bigint, p_linked boolean, label text) returns void
language plpgsql as $$
declare
  a text := quote_literal(p_athlete::text) || '::uuid';
  -- Each read counts as one row when it returns any, so "1" means "not empty".
  want int := case when p_linked then 1 else 0 end;
  run_id bigint := p_run;
begin

  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_athlete_links where athlete_id = ' || a || ')', want, label || ': links');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_list_athletes() where athlete_id = ' || a || ')', want, label || ': coach_list_athletes');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_get_athlete_plan(' || a || '))', want, label || ': coach_get_athlete_plan');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_get_athletes_workouts(current_date - 7, current_date + 7, array[' || a || ']))',
    want, label || ': coach_get_athletes_workouts');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_get_athletes_runs(current_date - 7, current_date + 7, array[' || a || ']))',
    want, label || ': coach_get_athletes_runs');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_get_athletes_runs(current_date - 7, current_date + 7) where athlete_id = ' || a || ')',
    want, label || ': coach_get_athletes_runs (all athletes)');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_get_run_route(' || run_id || '))', want, label || ': coach_get_run_route');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_get_run_notes(array[' || run_id || ']::bigint[]))', want, label || ': coach_get_run_notes');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_feedback where athlete_id = ' || a || ')', want, label || ': coach_feedback');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_get_athlete_flags(array[' || a || '], true))',
    want, label || ': coach_get_athlete_flags');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_get_athlete_events(' || a || '))', want, label || ': coach_get_athlete_events');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_roster_summary() where athlete_id = ' || a || ')', want, label || ': coach_roster_summary');
  perform pg_temp.expect_count(
    'select 1 where exists (select 1 from public.coach_v2_roster_status() where athlete_id = ' || a || ')', want, label || ': coach_v2_roster_status');
  if p_linked then
    perform pg_temp.expect_count(
      'select 1 from public.get_coach_welcome(' || a || ')', 1, label || ': get_coach_welcome');
  else
    perform pg_temp.expect_error(
      'select * from public.get_coach_welcome(' || a || ')', '42501', 'not_linked', label || ': get_coach_welcome');
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.act_as_anon(),
  pg_temp.expect_error(text, text, text, text), pg_temp.expect_count(text, int, text),
  pg_temp.parity(uuid, bigint, boolean, text) to authenticated, anon;

-- Grants and function shape ------------------------------------------------------------

do $$
declare
  f record;
begin
  -- leave_coach keeps Story 1.5's shape (AC4).
  if not exists (
    select 1 from pg_proc p
    where p.oid = 'public.leave_coach(uuid)'::regprocedure
      and p.prorettype = 'void'::regtype
      and p.proargnames = array['expected_link_id']
  ) then
    raise exception 'FAIL: leave_coach is not leave_coach(expected_link_id uuid) returns void';
  end if;
  if (select count(*) from pg_proc where proname = 'leave_coach'
      and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'FAIL: more than one leave_coach overload';
  end if;

  for f in
    select unnest(array[
      'public.end_coach_link(uuid,text)', 'public.leave_coach(uuid)',
      'public.coach_remove_athlete(uuid)', 'public.coach_link_notice_allowed(uuid)',
      'public.my_coach_link_notice()', 'public.mark_link_notice_seen(uuid)'
    ])::regprocedure as fn
  loop
    if not exists (select 1 from pg_proc p where p.oid = f.fn and p.prosecdef
                   and p.proconfig @> array['search_path=""']) then
      raise exception 'FAIL: % is not security definer with search_path = ''''', f.fn;
    end if;
    if has_function_privilege('anon', f.fn, 'execute') then
      raise exception 'FAIL: anon can execute %', f.fn;
    end if;
  end loop;

  if has_function_privilege('authenticated', 'public.end_coach_link(uuid,text)', 'execute')
     or has_function_privilege('authenticated', 'public.coach_link_notice_allowed(uuid)', 'execute') then
    raise exception 'FAIL: a client can call an internal link-end function';
  end if;
  if not has_function_privilege('authenticated', 'public.coach_remove_athlete(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.leave_coach(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.my_coach_link_notice()', 'execute')
     or not has_function_privilege('authenticated', 'public.mark_link_notice_seen(uuid)', 'execute') then
    raise exception 'FAIL: authenticated is missing execute on a client RPC';
  end if;
end $$;

set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.ack_coach_consent(2);
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select public.ack_coach_consent(2);
reset role;

-- Data each coach read returns while linked ---------------------------------------------
-- B and E each get an active plan, a workout, a shared run with effort and a note
-- after the ack, a route, a coach note, a welcome and a goal-change event.
do $$
declare
  ath uuid;
  coach uuid;
  plan uuid;
  run bigint;
begin
  foreach ath in array array['bbbbbbbb-0000-4000-8000-00000000000b', 'eeeeeeee-0000-4000-8000-00000000000e']::uuid[] loop
    coach := case when ath = 'bbbbbbbb-0000-4000-8000-00000000000b'
                  then 'aaaaaaaa-0000-4000-8000-00000000000a'::uuid
                  else 'cccccccc-0000-4000-8000-00000000000c'::uuid end;
    insert into public.plans (profile_id, auth_user_id, title, start_date, end_date, is_active)
    values (gen_random_uuid(), ath, '10K plan', current_date - 7, current_date + 60, true)
    returning id into plan;
    insert into public.workouts (plan_id, auth_user_id, type, distance, scheduled_date)
    values (plan, ath, 'easy', 6, current_date);
    insert into public.runs (auth_user_id, type, distance, duration, completed_at, route, route_status, rpe, athlete_note)
    values (ath, 'easy', 6, 2100, now(), '{"type":"LineString","coordinates":[]}'::jsonb,
            'shared', 7, 'Legs felt heavy')
    returning id into run;
    perform set_config('test.run_' || left(ath::text, 1), run::text, true);
    insert into public.coach_feedback (coach_id, athlete_id, run_id, text)
    values (coach, ath, run, 'Nice and steady.');
    insert into public.coach_feedback (coach_id, athlete_id, kind, text)
    values (coach, ath, 'welcome', 'Welcome aboard.');
    insert into public.coach_athlete_events (coach_id, athlete_id, kind)
    values (coach, ath, 'goal_change');
  end loop;
end $$;

-- Baseline: every read sees B (as Dana) and E (as Ron).
set local role authenticated;
-- C7.4 (M1b): each athlete sends one flag while linked.
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.athlete_flag_run('f000000b-0000-4000-8000-00000000000b', 'pain', 'Left knee');
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select public.athlete_flag_run('f000000e-0000-4000-8000-00000000000e', 'off', null);
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.parity('bbbbbbbb-0000-4000-8000-00000000000b', current_setting('test.run_b')::bigint, true, 'B before removal');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.parity('eeeeeeee-0000-4000-8000-00000000000e', current_setting('test.run_e')::bigint, true, 'E before leave');

-- AC6: only the link's coach can remove -------------------------------------------------
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_error($q$select public.coach_remove_athlete('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  'P0001', 'not_linked', 'non-coach removes B');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_error($q$select public.coach_remove_athlete('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  'P0001', 'not_linked', 'another coach removes B');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error($q$select public.coach_remove_athlete('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  'P0001', 'not_linked', 'B removes themselves');
select pg_temp.expect_error($q$select public.coach_remove_athlete(null)$q$, '22023', null, 'remove with no athlete');
-- The athlete cannot end the link or mark a notice by writing the row.
select pg_temp.expect_error(
  $q$update public.coach_athlete_links set ended_by = 'coach', status = 'revoked'$q$, '42501', null,
  'client writes ended_by');
select pg_temp.expect_error(
  $q$update public.coach_athlete_links set ended_notice_seen_at = now()$q$, '42501', null,
  'client writes ended_notice_seen_at');
reset role;

set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error($q$select public.coach_remove_athlete('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', null, 'anon removes B');
select pg_temp.expect_error($q$select * from public.my_coach_link_notice()$q$, '42501', null, 'anon reads a notice');
reset role;

do $$
begin
  if (select count(*) from public.coach_athlete_links where status = 'active') <> 3
     or exists (select 1 from public.coach_athlete_links where ended_by is not null)
     or exists (select 1 from public.coach_athlete_events where kind in ('left', 'removed')) then
    raise exception 'FAIL: a denied remove changed a link or logged an event';
  end if;
end $$;

-- AC1 + AC2: Dana removes B -------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 where public.coach_remove_athlete('bbbbbbbb-0000-4000-8000-00000000000b') = 'removed'$q$,
  1, 'Dana removes B');
-- AC6: a repeat is a no-op.
select pg_temp.expect_count(
  $q$select 1 where public.coach_remove_athlete('bbbbbbbb-0000-4000-8000-00000000000b') = 'already_ended'$q$,
  1, 'Dana removes B again');
reset role;

do $$
begin
  if not exists (select 1 from public.coach_athlete_links
                 where id = '0000000b-0000-4000-8000-00000000000b' and status = 'revoked'
                   and revoked_at is not null and ended_by = 'coach' and ended_notice_seen_at is null) then
    raise exception 'FAIL: the removal did not set revoked, revoked_at and ended_by = coach';
  end if;
  if (select count(*) from public.coach_athlete_events
      where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and kind = 'removed'
        and coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a') <> 1 then
    raise exception 'FAIL: the removal did not log exactly one removed event';
  end if;
  if not exists (select 1 from public.coach_athlete_links
                 where id = '0000000f-0000-4000-8000-00000000000f' and status = 'active' and ended_by is null) then
    raise exception 'FAIL: removing B touched Dana''s link with F';
  end if;
  -- Rows stay at link end.
  if (select count(*) from public.coach_feedback where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b') <> 2
     or not exists (select 1 from public.runs where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
                    and rpe = 7 and athlete_note = 'Legs felt heavy') then
    raise exception 'FAIL: the removal deleted feedback or run data';
  end if;
end $$;

-- AC3 parity and AC7 after the removal --------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.parity('bbbbbbbb-0000-4000-8000-00000000000b', current_setting('test.run_b')::bigint, false, 'B after removal');
select pg_temp.expect_count(
  $q$select 1 from public.coach_list_athletes() where athlete_id = 'ffffffff-0000-4000-8000-00000000000f'$q$,
  1, 'Dana still sees F');
select pg_temp.expect_error(
  $q$select public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  'P0001', 'link_inactive', 'queued seen mark after removal');
select pg_temp.expect_error(
  $q$select public.coach_set_athlete_welcome('bbbbbbbb-0000-4000-8000-00000000000b', 'Hi')$q$,
  '42501', null, 'queued welcome after removal');

-- AC5: B (v2) sees the notice once ------------------------------------------------------
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_link_notice()
     where link_id = '0000000b-0000-4000-8000-00000000000b' and coach_name = 'Dana' and ended_at is not null$q$,
  1, 'B sees the removal notice');
select pg_temp.expect_count(
  $q$select 1 where public.mark_link_notice_seen('0000000e-0000-4000-8000-00000000000e') = false$q$,
  1, 'B cannot mark another athlete''s link');
select pg_temp.expect_count(
  $q$select 1 where public.mark_link_notice_seen('0000000b-0000-4000-8000-00000000000b') = true$q$,
  1, 'B marks the notice seen');
select pg_temp.expect_count(
  $q$select 1 where public.mark_link_notice_seen('0000000b-0000-4000-8000-00000000000b') = false$q$,
  1, 'B marks it again');
select pg_temp.expect_count('select 1 from public.my_coach_link_notice()', 0, 'B after seeing the notice');
-- B still reads their own revoked row, now with ended_by.
select pg_temp.expect_count(
  $q$select 1 from public.coach_athlete_links where ended_by = 'coach' and ended_notice_seen_at is not null$q$,
  1, 'B reads the ended link');
reset role;

-- AC4: E leaves Ron the 1.2.6 way ---------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_error($q$select public.leave_coach('0000000e-0000-4000-8000-00000000000e')$q$,
  'P0001', 'not_linked', 'third user leaves for E');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_error($q$select public.leave_coach('0000000e-0000-4000-8000-00000000000e')$q$,
  'P0001', 'not_linked', 'coach calls leave_coach for E');
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_error($q$select public.leave_coach('0000000b-0000-4000-8000-00000000000b')$q$,
  'P0001', 'not_linked', 'E leaves with a stale link id');
-- The 1.2.6 call: one uuid argument, void result.
select pg_temp.expect_count(
  $q$select 1 from (select public.leave_coach('0000000e-0000-4000-8000-00000000000e') as r) q
     where pg_typeof(r) = 'void'::regtype$q$,
  1, 'E leaves Ron (void)');
select pg_temp.expect_error($q$select public.leave_coach('0000000e-0000-4000-8000-00000000000e')$q$,
  'P0001', 'not_linked', 'E leaves twice');
-- An athlete who left sees no notice.
select pg_temp.expect_count('select 1 from public.my_coach_link_notice()', 0, 'E after leaving');
select pg_temp.expect_count(
  $q$select 1 where public.mark_link_notice_seen('0000000e-0000-4000-8000-00000000000e') = false$q$,
  1, 'E cannot mark a leave as a notice');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.parity('eeeeeeee-0000-4000-8000-00000000000e', current_setting('test.run_e')::bigint, false, 'E after leave');
-- Ron's stale remove after E left is a no-op.
select pg_temp.expect_count(
  $q$select 1 where public.coach_remove_athlete('eeeeeeee-0000-4000-8000-00000000000e') = 'already_ended'$q$,
  1, 'Ron removes E after E left');
reset role;

do $$
begin
  if not exists (select 1 from public.coach_athlete_links
                 where id = '0000000e-0000-4000-8000-00000000000e' and status = 'revoked'
                   and revoked_at is not null and ended_by = 'athlete') then
    raise exception 'FAIL: leave_coach did not set revoked, revoked_at and ended_by = athlete';
  end if;
  if (select count(*) from public.coach_athlete_events
      where athlete_id = 'eeeeeeee-0000-4000-8000-00000000000e' and kind = 'left') <> 1
     or exists (select 1 from public.coach_athlete_events
                where athlete_id = 'eeeeeeee-0000-4000-8000-00000000000e' and kind = 'removed') then
    raise exception 'FAIL: the leave did not log exactly one left event';
  end if;
end $$;

-- AC5: a 1.2.6 athlete gets the MVP behavior ----------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 where public.coach_remove_athlete('ffffffff-0000-4000-8000-00000000000f') = 'removed'$q$,
  1, 'Dana removes F (1.2.6)');
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_count('select 1 from public.my_coach_link_notice()', 0, '1.2.6 athlete: no notice');
select pg_temp.expect_error(
  $q$select public.mark_link_notice_seen('0000000f-0000-4000-8000-00000000000f')$q$,
  'P0001', 'v2_unavailable', '1.2.6 athlete marks the notice');
-- F updates to v2: the unseen notice shows.
select public.report_client_capabilities(true, '1.2.7', 50, 'testflight');
select pg_temp.expect_count(
  $q$select 1 from public.my_coach_link_notice() where coach_name = 'Dana'$q$,
  1, 'F sees the notice after updating');
reset role;

-- F joins Ron before seeing it: the old notice is gone.
insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at)
values ('cccccccc-0000-4000-8000-00000000000c', 'ffffffff-0000-4000-8000-00000000000f', 'active', now());
set local role authenticated;
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_count('select 1 from public.my_coach_link_notice()', 0, 'F linked again');
reset role;

do $$ begin raise notice 'coach_link_end: PASS'; end $$;

rollback;
