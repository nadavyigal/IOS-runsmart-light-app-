-- Test for 20261122110000_notification_log_and_deferred.sql (story C7.5, M2b).
--
-- Users: A (Dana) and C (Ron) are coaches. B, E, F, G, H are athletes of A.
--   A-B: v2 pair, consent v2 acked (sharing).
--   A-E: v2 pair, consent v1 (no ack): link_v2 but no sharing.
--   A-F: F is a 1.2.6 client (no capability row): not a v2 pair.
--   A-G: v2, acked. G-H: used for the burst.
--   A-H: revoked. H has no active link.
-- Proves:
--   * C7.5 AC13 SQL: both tables are server-only. RLS on, no policy, no table
--     privilege for anon or authenticated (a signed-in client reads and writes
--     nothing), the three functions are security definer with search_path = '',
--     anon and authenticated cannot execute them, service_role can.
--   * coach_notify_link_state (AC9): the active link with link_v2 and
--     sharing_allowed per pair, both names; zero rows for a revoked link; the kill
--     switch (coach_v2 off) turns link_v2 false.
--   * coach_notify_claim: first claim writes one pending log row; a retried event
--     is 'duplicate'; a second run of the same athlete within 30 minutes is
--     'deduped' (D6, AC2), also when the first one is deferred; dedupe 0 always
--     claims; a different athlete claims; after 3 sends in 10 minutes the next is
--     'deferred_burst' due at the end of that window (AC3), later ones join it.
--   * coach_notify_defer (AC7): a 'quiet' row with ids only; the same event is
--     'duplicate'; the same athlete within the window is 'deduped'; an unknown
--     link raises link_missing.
--   * Checks: unknown kinds, a quiet row with deliver_after, a burst row without
--     it, a ref_id with free text and an oversize payload are rejected.
--   * Account deletion: log and deferred rows go with the auth user (recipient,
--     athlete or coach), through on delete cascade.
-- Raises on the first failure; prints "notification_log_and_deferred: PASS" otherwise.
--
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (CI's matrix row lists the same files):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_read_fixture.sql
--   then every prerequisite of the notification_log_and_deferred row in
--   .github/workflows/pr-checks.yml, in order (Batch A and M2a), then
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261122110000_notification_log_and_deferred.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261122110000_notification_log_and_deferred.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/notification_log_and_deferred.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'notification_log_and_deferred.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
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

insert into public.profiles (auth_user_id, name) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'Yoni'),
  ('eeeeeeee-0000-4000-8000-00000000000e', '   ');

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
   'revoked', now() - interval '30 days', now() - interval '1 day', 2, now() - interval '20 days');

insert into public.client_capabilities (user_id, coach_v2, channel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', true, 'testflight'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', true, 'testflight'),
  ('cccccccc-0000-4000-8000-00000000000c', true, 'testflight'),
  ('eeeeeeee-0000-4000-8000-00000000000e', true, 'testflight'),
  ('99999999-0000-4000-8000-000000000009', true, 'testflight'),
  ('88888888-0000-4000-8000-000000000008', true, 'testflight');

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

create function pg_temp.expect_text(actual text, expected text, label text) returns void
language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL: % was %, expected %', label, coalesce(actual, 'null'), coalesce(expected, 'null');
  end if;
end $$;

-- Ids, so the calls stay readable.
create function pg_temp.u(c text) returns uuid language sql as $$
  select (case c
    when 'A' then 'aaaaaaaa-0000-4000-8000-00000000000a'
    when 'B' then 'bbbbbbbb-0000-4000-8000-00000000000b'
    when 'C' then 'cccccccc-0000-4000-8000-00000000000c'
    when 'E' then 'eeeeeeee-0000-4000-8000-00000000000e'
    when 'F' then 'ffffffff-0000-4000-8000-00000000000f'
    when 'G' then '99999999-0000-4000-8000-000000000009'
    when 'H' then '88888888-0000-4000-8000-000000000008'
  end)::uuid;
$$;
create function pg_temp.link(c text) returns uuid language sql as $$
  select (case c
    when 'B' then '11111111-0000-4000-8000-00000000000b'
    when 'E' then '11111111-0000-4000-8000-00000000000e'
    when 'F' then '11111111-0000-4000-8000-00000000000f'
    when 'G' then '11111111-0000-4000-8000-000000000009'
    when 'H' then '11111111-0000-4000-8000-000000000008'
  end)::uuid;
$$;

-- Shape: server-only --------------------------------------------------------------------
do $$
declare
  t text;
  r text;
  p text;
  f regprocedure;
begin
  foreach t in array array['public.coach_notification_log', 'public.deferred_pushes'] loop
    if not (select relrowsecurity from pg_class where oid = t::regclass) then
      raise exception 'FAIL: RLS is off on %', t;
    end if;
    if exists (select 1 from pg_policies where schemaname || '.' || tablename = t) then
      raise exception 'FAIL: % has a policy; it must have none', t;
    end if;
    foreach r in array array['anon', 'authenticated'] loop
      foreach p in array array['select', 'insert', 'update', 'delete'] loop
        if has_table_privilege(r, t, p) then
          raise exception 'FAIL: % may % on %', r, p, t;
        end if;
      end loop;
    end loop;
  end loop;
  if not has_table_privilege('service_role', 'public.coach_notification_log', 'insert')
     or not has_table_privilege('service_role', 'public.deferred_pushes', 'delete') then
    raise exception 'FAIL: service_role lacks the sender grants';
  end if;

  foreach f in array array[
    'public.coach_notify_link_state(uuid)'::regprocedure,
    'public.coach_notify_claim(uuid, uuid, uuid, text, text, integer, integer, integer)'::regprocedure,
    'public.coach_notify_defer(uuid, uuid, uuid, text, text, integer, jsonb)'::regprocedure
  ] loop
    if not (select prosecdef from pg_proc where oid = f) then
      raise exception 'FAIL: % is not security definer', f;
    end if;
    if not exists (select 1 from pg_proc where oid = f and proconfig @> array['search_path=""']) then
      raise exception 'FAIL: % has no empty search_path', f;
    end if;
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception 'FAIL: a client may execute %', f;
    end if;
    if not has_function_privilege('service_role', f, 'execute') then
      raise exception 'FAIL: service_role may not execute %', f;
    end if;
  end loop;
end $$;

-- A signed-in client is refused, directly and through the functions.
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
set local role authenticated;
select pg_temp.expect_error('select 1 from public.coach_notification_log', '42501', 'coach reads the log');
select pg_temp.expect_error('select 1 from public.deferred_pushes', '42501', 'coach reads deferred');
select pg_temp.expect_error(
  $q$insert into public.deferred_pushes (recipient_id, kind, athlete_id, coach_id, link_id, reason)
     values ('aaaaaaaa-0000-4000-8000-00000000000a', 'coachRunFinished', 'bbbbbbbb-0000-4000-8000-00000000000b',
             'aaaaaaaa-0000-4000-8000-00000000000a', '11111111-0000-4000-8000-00000000000b', 'quiet')$q$,
  '42501', 'coach writes deferred');
select pg_temp.expect_error(
  $q$select * from public.coach_notify_link_state('bbbbbbbb-0000-4000-8000-00000000000b')$q$,
  '42501', 'coach calls link_state');
select pg_temp.expect_error(
  $q$select * from public.coach_notify_claim('aaaaaaaa-0000-4000-8000-00000000000a',
     'bbbbbbbb-0000-4000-8000-00000000000b', '11111111-0000-4000-8000-00000000000b',
     'coachRunFinished', '1', 0, null, null)$q$,
  '42501', 'coach calls claim');
reset role;
set local role anon;
select pg_temp.expect_error('select 1 from public.deferred_pushes', '42501', 'anon reads deferred');
reset role;

-- The rest runs as the sender.
set local role service_role;

-- Link state (AC9) ------------------------------------------------------------------------
do $$
declare
  s record;
begin
  select * into s from public.coach_notify_link_state(pg_temp.u('B'));
  if s.link_id is distinct from pg_temp.link('B') or s.coach_id is distinct from pg_temp.u('A')
     or not s.link_v2 or not s.sharing_allowed or s.coach_name <> 'Dana' or s.athlete_name <> 'Yoni' then
    raise exception 'FAIL: B link state %', row_to_json(s);
  end if;

  select * into s from public.coach_notify_link_state(pg_temp.u('E'));
  if not s.link_v2 or s.sharing_allowed or s.athlete_name <> 'Athlete' then
    raise exception 'FAIL: E (no ack) link state %', row_to_json(s);
  end if;

  select * into s from public.coach_notify_link_state(pg_temp.u('F'));
  if s.link_v2 or s.sharing_allowed then
    raise exception 'FAIL: F (1.2.6) counted as v2';
  end if;

  if exists (select 1 from public.coach_notify_link_state(pg_temp.u('H'))) then
    raise exception 'FAIL: a revoked link returned a state';
  end if;
  if exists (select 1 from public.coach_notify_link_state(pg_temp.u('C'))) then
    raise exception 'FAIL: a coach with no coach returned a state';
  end if;
end $$;

-- The kill switch turns link_v2 off (the sender also stops at its own flag check).
reset role;
update public.runtime_flags set enabled = false where key = 'coach_v2';
set local role service_role;
do $$
begin
  if (select link_v2 or sharing_allowed from public.coach_notify_link_state(pg_temp.u('B'))) then
    raise exception 'FAIL: link_v2 stayed true with coach_v2 off';
  end if;
end $$;
reset role;
update public.runtime_flags set enabled = true where key = 'coach_v2';
set local role service_role;

-- Claim: idempotency and the 30-minute dedupe (AC1, AC2) -----------------------------------
do $$
declare
  c record;
begin
  select * into c from public.coach_notify_claim(pg_temp.u('A'), pg_temp.u('B'), pg_temp.link('B'),
    'coachRunFinished', '101', 1800, 3, 600);
  perform pg_temp.expect_text(c.decision, 'claimed', 'first run of B');
  if not exists (select 1 from public.coach_notification_log
                 where id = c.log_id and outcome = 'pending' and ref_id = '101' and athlete_id = pg_temp.u('B')) then
    raise exception 'FAIL: the claim wrote no pending log row';
  end if;

  select * into c from public.coach_notify_claim(pg_temp.u('A'), pg_temp.u('B'), pg_temp.link('B'),
    'coachRunFinished', '101', 1800, 3, 600);
  perform pg_temp.expect_text(c.decision, 'duplicate', 'retried webhook for run 101');

  select * into c from public.coach_notify_claim(pg_temp.u('A'), pg_temp.u('B'), pg_temp.link('B'),
    'coachRunFinished', '102', 1800, 3, 600);
  perform pg_temp.expect_text(c.decision, 'deduped', 'second run of B within 30 minutes');

  if (select count(*) from public.coach_notification_log where recipient_id = pg_temp.u('A')) <> 1 then
    raise exception 'FAIL: duplicate or deduped claims wrote a log row';
  end if;

  -- An hour-old send no longer dedupes.
  update public.coach_notification_log set sent_at = now() - interval '31 minutes' where ref_id = '101';
  select * into c from public.coach_notify_claim(pg_temp.u('A'), pg_temp.u('B'), pg_temp.link('B'),
    'coachRunFinished', '103', 1800, 3, 600);
  perform pg_temp.expect_text(c.decision, 'claimed', 'B run after 31 minutes');

  -- Dedupe 0 (notes, flags, replies): every event is its own push.
  select * into c from public.coach_notify_claim(pg_temp.u('B'), pg_temp.u('B'), pg_temp.link('B'),
    'athleteCoachNote', 'd1000000-0000-4000-8000-00000000000b', 0, null, null);
  perform pg_temp.expect_text(c.decision, 'claimed', 'first note to B');
  select * into c from public.coach_notify_claim(pg_temp.u('B'), pg_temp.u('B'), pg_temp.link('B'),
    'athleteCoachNote', 'd2000000-0000-4000-8000-00000000000b', 0, null, null);
  perform pg_temp.expect_text(c.decision, 'claimed', 'second note to B');
end $$;

-- Burst (AC3): 3 run-finished sends in 10 minutes, then the 4th and later collect ---------
reset role;
delete from public.coach_notification_log;
insert into public.coach_notification_log (recipient_id, athlete_id, kind, ref_id, sent_at, outcome) values
  (pg_temp.u('A'), pg_temp.u('B'), 'coachRunFinished', '201', now() - interval '8 minutes', 'sent'),
  (pg_temp.u('A'), pg_temp.u('E'), 'coachRunFinished', '202', now() - interval '5 minutes', 'sent'),
  (pg_temp.u('A'), pg_temp.u('F'), 'coachRunFinished', '203', now() - interval '1 minute', 'sent');
set local role service_role;
do $$
declare
  c record;
  v_due timestamptz;
begin
  select * into c from public.coach_notify_claim(pg_temp.u('A'), pg_temp.u('G'), pg_temp.link('G'),
    'coachRunFinished', '204', 1800, 3, 600);
  perform pg_temp.expect_text(c.decision, 'deferred_burst', '4th run in 10 minutes');
  select deliver_after into v_due from public.deferred_pushes where ref_id = '204';
  if v_due is distinct from now() - interval '8 minutes' + interval '600 seconds' then
    raise exception 'FAIL: burst due at %, expected the end of the window', v_due;
  end if;
  if exists (select 1 from public.coach_notification_log where ref_id = '204') then
    raise exception 'FAIL: a burst push was logged as sent';
  end if;

  select * into c from public.coach_notify_claim(pg_temp.u('A'), pg_temp.u('G'), pg_temp.link('G'),
    'coachRunFinished', '204', 1800, 3, 600);
  perform pg_temp.expect_text(c.decision, 'duplicate', 'retried burst event');

  select * into c from public.coach_notify_claim(pg_temp.u('A'), pg_temp.u('G'), pg_temp.link('G'),
    'coachRunFinished', '205', 1800, 3, 600);
  perform pg_temp.expect_text(c.decision, 'deduped', 'G again within 30 minutes, held in the burst');

  -- Another athlete joins the same burst window, even with fewer recent sends.
  update public.coach_notification_log set sent_at = now() - interval '20 minutes' where ref_id in ('202', '203');
  select * into c from public.coach_notify_claim(pg_temp.u('A'), pg_temp.u('C'), pg_temp.link('B'),
    'coachRunFinished', '206', 0, 3, 600);
  perform pg_temp.expect_text(c.decision, 'deferred_burst', 'a later run joins the open burst');
  if (select deliver_after from public.deferred_pushes where ref_id = '206') is distinct from v_due then
    raise exception 'FAIL: the later run did not join the open burst window';
  end if;

  -- Another coach is not limited by A's burst.
  select * into c from public.coach_notify_claim(pg_temp.u('C'), pg_temp.u('B'), pg_temp.link('B'),
    'coachRunFinished', '204', 1800, 3, 600);
  perform pg_temp.expect_text(c.decision, 'claimed', 'another recipient');
end $$;

-- Defer (AC7) ------------------------------------------------------------------------------
reset role;
delete from public.deferred_pushes;
delete from public.coach_notification_log;
set local role service_role;
do $$
declare
  d text;
  c record;
begin
  d := public.coach_notify_defer(pg_temp.u('A'), pg_temp.u('B'), pg_temp.link('B'),
    'coachPainFlag', 'f1000000-0000-4000-8000-00000000000b', 0, jsonb_build_object('flag_id', 'f1000000-0000-4000-8000-00000000000b'));
  perform pg_temp.expect_text(d, 'deferred', 'pain flag in quiet hours');
  if not exists (select 1 from public.deferred_pushes
                 where ref_id = 'f1000000-0000-4000-8000-00000000000b' and reason = 'quiet'
                   and deliver_after is null and coach_id = pg_temp.u('A') and link_id = pg_temp.link('B')) then
    raise exception 'FAIL: the quiet row is wrong';
  end if;
  d := public.coach_notify_defer(pg_temp.u('A'), pg_temp.u('B'), pg_temp.link('B'),
    'coachPainFlag', 'f1000000-0000-4000-8000-00000000000b', 0, '{}'::jsonb);
  perform pg_temp.expect_text(d, 'duplicate', 'retried flag webhook in quiet hours');

  d := public.coach_notify_defer(pg_temp.u('A'), pg_temp.u('B'), pg_temp.link('B'), 'coachRunFinished', '301', 1800, '{}'::jsonb);
  perform pg_temp.expect_text(d, 'deferred', 'run in quiet hours');
  d := public.coach_notify_defer(pg_temp.u('A'), pg_temp.u('B'), pg_temp.link('B'), 'coachRunFinished', '302', 1800, '{}'::jsonb);
  perform pg_temp.expect_text(d, 'deduped', 'second copy of the run in quiet hours');

  -- A deferred run also dedupes a send right after quiet hours.
  select * into c from public.coach_notify_claim(pg_temp.u('A'), pg_temp.u('B'), pg_temp.link('B'),
    'coachRunFinished', '303', 1800, 3, 600);
  perform pg_temp.expect_text(c.decision, 'deduped', 'send after a deferred run within 30 minutes');

  -- An athlete gets every note (dedupe 0).
  d := public.coach_notify_defer(pg_temp.u('B'), pg_temp.u('B'), pg_temp.link('B'), 'athleteCoachNote', 'n1', 0, '{}'::jsonb);
  perform pg_temp.expect_text(d, 'deferred', 'note 1 in quiet hours');
  d := public.coach_notify_defer(pg_temp.u('B'), pg_temp.u('B'), pg_temp.link('B'), 'athleteCoachNote', 'n2', 0, '{}'::jsonb);
  perform pg_temp.expect_text(d, 'deferred', 'note 2 in quiet hours');
end $$;
select pg_temp.expect_error(
  $q$select public.coach_notify_defer('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b',
     '00000000-0000-4000-8000-000000000000', 'coachRunFinished', '399', 0, '{}'::jsonb)$q$,
  'P0002', 'unknown link');
select pg_temp.expect_error(
  $q$select public.coach_notify_defer(null, 'bbbbbbbb-0000-4000-8000-00000000000b',
     '11111111-0000-4000-8000-00000000000b', 'coachRunFinished', '399', 0, '{}'::jsonb)$q$,
  '22023', 'missing recipient');

-- Checks -----------------------------------------------------------------------------------
select pg_temp.expect_error(
  $q$select * from public.coach_notify_claim('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b',
     '11111111-0000-4000-8000-00000000000b', 'selfTest', '1', 0, null, null)$q$,
  '23514', 'selfTest is never logged');
select pg_temp.expect_error(
  $q$select * from public.coach_notify_claim('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b',
     '11111111-0000-4000-8000-00000000000b', 'coachRunFinished', 'knee hurts', 0, null, null)$q$,
  '23514', 'free text as ref_id');
select pg_temp.expect_error(
  $q$insert into public.deferred_pushes (recipient_id, kind, athlete_id, coach_id, link_id, reason, deliver_after)
     values ('aaaaaaaa-0000-4000-8000-00000000000a', 'coachRunFinished', 'bbbbbbbb-0000-4000-8000-00000000000b',
             'aaaaaaaa-0000-4000-8000-00000000000a', '11111111-0000-4000-8000-00000000000b', 'quiet', now())$q$,
  '23514', 'quiet row with deliver_after');
select pg_temp.expect_error(
  $q$insert into public.deferred_pushes (recipient_id, kind, athlete_id, coach_id, link_id, reason)
     values ('aaaaaaaa-0000-4000-8000-00000000000a', 'coachRunFinished', 'bbbbbbbb-0000-4000-8000-00000000000b',
             'aaaaaaaa-0000-4000-8000-00000000000a', '11111111-0000-4000-8000-00000000000b', 'burst')$q$,
  '23514', 'burst row without deliver_after');
select pg_temp.expect_error(
  $q$select public.coach_notify_defer('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b',
     '11111111-0000-4000-8000-00000000000b', 'coachRunFinished', '398', 0,
     jsonb_build_object('x', repeat('a', 1100)))$q$,
  '23514', 'oversize payload');
select pg_temp.expect_error(
  $q$insert into public.coach_notification_log (recipient_id, athlete_id, kind, ref_id, outcome)
     values ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b',
             'coachRunFinished', '397', 'delivered')$q$,
  '23514', 'unknown outcome');

-- Account deletion -------------------------------------------------------------------------
reset role;
insert into public.coach_notification_log (recipient_id, athlete_id, kind, ref_id)
  values (pg_temp.u('A'), pg_temp.u('B'), 'coachPainFlag', 'f2000000-0000-4000-8000-00000000000b');
do $$
begin
  if not exists (select 1 from public.deferred_pushes where athlete_id = pg_temp.u('B'))
     or not exists (select 1 from public.coach_notification_log where athlete_id = pg_temp.u('B')) then
    raise exception 'FAIL: setup: B has no rows to delete';
  end if;
end $$;
delete from auth.users where id = 'bbbbbbbb-0000-4000-8000-00000000000b';
do $$
begin
  if exists (select 1 from public.deferred_pushes where athlete_id = pg_temp.u('B') or recipient_id = pg_temp.u('B'))
     or exists (select 1 from public.coach_notification_log where athlete_id = pg_temp.u('B') or recipient_id = pg_temp.u('B')) then
    raise exception 'FAIL: deleting the athlete left log or deferred rows';
  end if;
end $$;

insert into public.coach_notification_log (recipient_id, athlete_id, kind, ref_id)
  values (pg_temp.u('A'), pg_temp.u('G'), 'coachRunFinished', '401');
insert into public.deferred_pushes (recipient_id, kind, athlete_id, coach_id, link_id, ref_id, reason)
  values (pg_temp.u('G'), 'athleteCoachNote', pg_temp.u('G'), pg_temp.u('A'), pg_temp.link('G'), 'n9', 'quiet');
delete from auth.users where id = 'aaaaaaaa-0000-4000-8000-00000000000a';
do $$
begin
  if exists (select 1 from public.coach_notification_log where recipient_id = pg_temp.u('A'))
     or exists (select 1 from public.deferred_pushes where coach_id = pg_temp.u('A')) then
    raise exception 'FAIL: deleting the coach left log or deferred rows';
  end if;
end $$;

do $$ begin raise notice 'notification_log_and_deferred: PASS'; end $$;

rollback;
