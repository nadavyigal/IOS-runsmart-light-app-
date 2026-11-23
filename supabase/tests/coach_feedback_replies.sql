-- Test for 20261121180000_coach_feedback_replies.sql (story C7.7, M4).
--
-- Users: A (Dana) and C (Ron) are coaches. B, E, F, G, H are athletes.
--   A-B: TestFlight v2 pair, consent v2 acked (sharing).
--   A-E: v2 pair, consent v1 (no ack yet).
--   A-F: F is a 1.2.6 client (no capability row), acked: not a v2 pair.
--   A-G: v2 pair, acked. Used for the account-deletion case.
--   A-H: v2, acked, then revoked; later H rejoins A on a new link.
--   C: v2, linked to nobody. C wrote one note to B (an earlier coach).
-- Proves:
--   * Shape: RLS on with one owner-select policy, authenticated may only select,
--     anon nothing; the 1..1000 text check; every function is security definer with
--     search_path = '', anon is denied, authenticated may execute.
--   * Athlete writes (AC1, AC3, AC5, AC8): sent and trimmed; idempotent by p_id (one
--     row, the first text stands); several replies on one note; a reply to the
--     welcome; exactly 1000 characters is fine, 1001 is reply_too_long; blank and a
--     null id are rejected; a reply to a reply is reply_to_reply; another athlete's
--     note and an unknown id are feedback_not_found; a note from a coach the athlete
--     is not linked to is link_inactive; a broadcast kind is reply_not_allowed; no
--     consent and a pair that is not v2 are refused; nothing refused is stored.
--   * Owner select (AC3, AC6): the athlete sees only their own replies, also through
--     my_feedback_replies; no client insert, update or delete, so no edit or delete.
--   * Coach reads (AC4, AC6): the active coach reads the reply verbatim; another
--     coach, the athlete, anon, no consent and a revoked link read nothing; a rejoin
--     does not bring old replies back.
--   * Read receipt: coach_mark_reply_read marks once, only the coach's own readable
--     replies, and never another coach's.
--   * coach_roster_summary (AC4): new_replies counts replies after the baseline, only
--     for a sharing pair, drops after the coach opens the athlete, and C7.2's run
--     count and C7.4's flag count are unchanged.
--   * Link ended (AC6, AC7): the coach removes H through C7.11's coach_remove_athlete
--     and reads none of H's replies; the athlete's queued reply gets link_inactive; a retry of
--     a reply stored before the end returns 'sent' and stores nothing new; the
--     athlete still reads their replies.
--   * Account deletion: the purge deletes the athlete's replies, the replies on a
--     deleted coach's notes, and keeps the C7.4 (flags) and C7.3 (effort, note)
--     blocks; deleting the auth user cascades.
-- The kill-switch case lives in kill_switch.sql (C7.12 DoD).
-- Raises on the first failure; prints "coach_feedback_replies: PASS" otherwise.
--
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (CI's matrix row lists the same files):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_read_fixture.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261114210000_coach_role_and_invites.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115091000_coach_athlete_links.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261115194500_leave_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117130000_coach_plan_mode_group_settings.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261117164500_coach_read_rpcs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261118100000_coach_feedback.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261118120000_athlete_feedback_read.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261118160000_get_my_coach.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261118180000_coach_welcome_note.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121100000_coach_v2_gate.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121110000_coach_consent_v2.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121120000_athlete_run_sharing.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121130000_coach_last_seen_and_events.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121150000_athlete_run_flags.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121160000_coach_link_end.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121180000_coach_feedback_replies.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261121180000_coach_feedback_replies.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coach_feedback_replies.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_feedback_replies.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
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

-- Notes. n = week note, w = welcome. created_at a day back, so a reply always follows.
insert into public.coach_feedback (id, coach_id, athlete_id, week_start, kind, text, created_at) values
  ('d1000000-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b',
   current_date - 3, 'note', 'Good week. Keep Thursday easy.', now() - interval '1 day'),
  ('d2000000-0000-4000-8000-00000000000b', 'cccccccc-0000-4000-8000-00000000000c', 'bbbbbbbb-0000-4000-8000-00000000000b',
   current_date - 60, 'note', 'Old note from an earlier coach.', now() - interval '60 days'),
  ('d1000000-0000-4000-8000-00000000000e', 'aaaaaaaa-0000-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-00000000000e',
   current_date - 3, 'note', 'Note for E.', now() - interval '1 day'),
  ('d1000000-0000-4000-8000-00000000000f', 'aaaaaaaa-0000-4000-8000-00000000000a', 'ffffffff-0000-4000-8000-00000000000f',
   current_date - 3, 'note', 'Note for F.', now() - interval '1 day'),
  ('d1000000-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-00000000000a', '99999999-0000-4000-8000-000000000009',
   current_date - 3, 'note', 'Note for G.', now() - interval '1 day'),
  ('d1000000-0000-4000-8000-000000000008', 'aaaaaaaa-0000-4000-8000-00000000000a', '88888888-0000-4000-8000-000000000008',
   current_date - 3, 'note', 'Note for H.', now() - interval '1 day');
insert into public.coach_feedback (id, coach_id, athlete_id, kind, text, created_at) values
  ('d3000000-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b',
   'welcome', 'Welcome to the group, B.', now() - interval '29 days');

-- G's run and flag, to prove the purge keeps the C7.3 and C7.4 blocks.
insert into public.runs (auth_user_id, type, distance, duration, completed_at, source_provider, source_activity_id, rpe, athlete_note) values
  ('99999999-0000-4000-8000-000000000009', 'easy', 5, 1800, now() - interval '2 hours', 'runsmart_ios', 'G1G1G1G1-0000-4000-8000-000000000001', 6, 'tired');
insert into public.athlete_run_flags (id, athlete_id, link_id, kind, note) values
  ('f9000000-0000-4000-8000-000000000009', '99999999-0000-4000-8000-000000000009', '11111111-0000-4000-8000-000000000009', 'pain', 'shin');

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
  if not (select relrowsecurity from pg_class where oid = 'public.coach_feedback_replies'::regclass) then
    raise exception 'FAIL: RLS is off on coach_feedback_replies';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'coach_feedback_replies') <> 1
     or not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'coach_feedback_replies'
                    and policyname = 'coach_feedback_replies_owner_select' and cmd = 'SELECT') then
    raise exception 'FAIL: coach_feedback_replies must have exactly one policy, the owner select';
  end if;
  if not has_table_privilege('authenticated', 'public.coach_feedback_replies', 'select')
     or has_table_privilege('authenticated', 'public.coach_feedback_replies', 'insert,update,delete')
     or has_table_privilege('anon', 'public.coach_feedback_replies', 'select,insert,update,delete') then
    raise exception 'FAIL: wrong table grants on coach_feedback_replies';
  end if;
  -- AC5: no parent-reply column exists.
  if exists (select 1 from information_schema.columns where table_schema = 'public'
             and table_name = 'coach_feedback_replies' and column_name like '%parent%') then
    raise exception 'FAIL: coach_feedback_replies has a parent column';
  end if;
  foreach fn in array array[
    'public.athlete_reply_to_feedback(uuid, text, uuid)',
    'public.my_feedback_replies()',
    'public.coach_get_feedback_replies(uuid[])',
    'public.coach_mark_reply_read(uuid[])',
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
  $q$insert into public.coach_feedback_replies (id, feedback_id, author_id, text) values (gen_random_uuid(), 'd1000000-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b', repeat('x', 1001))$q$,
  '23514', null, 'text over 1000 characters');
select pg_temp.expect_error(
  $q$insert into public.coach_feedback_replies (id, feedback_id, author_id, text) values (gen_random_uuid(), 'd1000000-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b', '   ')$q$,
  '23514', null, 'blank text');

-- Athlete writes ----------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

-- Reply 1 on the week note, trimmed.
select pg_temp.expect_text(
  public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000b', E'  Thanks, legs felt heavy on Tuesday \n',
                                   'e1000000-0000-4000-8000-000000000001'),
  'sent', 'reply to a week note');
-- The same client id again: one row, the first text stands.
select pg_temp.expect_text(
  public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000b', 'edited',
                                   'e1000000-0000-4000-8000-000000000001'),
  'sent', 'repeated reply id');
-- AC3: a second reply on the same note.
select pg_temp.expect_text(
  public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000b', 'שבוע טוב, תודה',
                                   'e2000000-0000-4000-8000-000000000002'),
  'sent', 'second reply on one note (Hebrew)');
-- The welcome is a coach_feedback row: replies are allowed.
select pg_temp.expect_text(
  public.athlete_reply_to_feedback('d3000000-0000-4000-8000-00000000000b', 'Happy to be here',
                                   'e3000000-0000-4000-8000-000000000003'),
  'sent', 'reply to the welcome');
-- Exactly 1000 characters (code points) is fine.
select pg_temp.expect_text(
  public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000b', repeat('ש', 1000),
                                   'e4000000-0000-4000-8000-000000000004'),
  'sent', 'reply of exactly 1000 characters');

select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000b', repeat('x', 1001), gen_random_uuid())$q$,
  '22023', 'reply_too_long', 'reply of 1001 characters');
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000b', E'  \n\t ', gen_random_uuid())$q$,
  '22023', 'reply_empty', 'blank reply');
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000b', 'hi', null)$q$,
  '22023', 'bad_reply_id', 'null reply id');
-- AC5: a reply has no replies.
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('e1000000-0000-4000-8000-000000000001', 'reply to my reply', gen_random_uuid())$q$,
  '22023', 'reply_to_reply', 'reply to a reply');
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000e', 'not my note', gen_random_uuid())$q$,
  '22023', 'feedback_not_found', 'reply to another athlete''s note');
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback(gen_random_uuid(), 'no such note', gen_random_uuid())$q$,
  '22023', 'feedback_not_found', 'reply to an unknown note');
-- A note from a coach B is not linked to (an earlier coach).
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d2000000-0000-4000-8000-00000000000b', 'hello Ron', gen_random_uuid())$q$,
  'P0001', 'link_inactive', 'reply to an earlier coach''s note');
-- The same id on a different note.
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d3000000-0000-4000-8000-00000000000b', 'moved', 'e1000000-0000-4000-8000-000000000001')$q$,
  '22023', 'bad_reply_id', 'reply id reused on another note');

-- Owner select: B sees 4 replies; no direct writes, so no edit or delete (AC3).
select pg_temp.expect_count('select 1 from public.coach_feedback_replies', 4, 'B reads own replies');
select pg_temp.expect_count('select 1 from public.my_feedback_replies()', 4, 'my_feedback_replies for B');
select pg_temp.expect_error(
  $q$insert into public.coach_feedback_replies (id, feedback_id, author_id, text) values (gen_random_uuid(), 'd1000000-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b', 'x')$q$,
  '42501', null, 'athlete inserts directly');
select pg_temp.expect_error(
  $q$update public.coach_feedback_replies set text = 'edited'$q$, '42501', null, 'athlete edits a reply');
select pg_temp.expect_error(
  $q$delete from public.coach_feedback_replies$q$, '42501', null, 'athlete deletes a reply');

-- No consent: E. Not a v2 pair: F. Another user's reply id: G.
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000e', 'hi', gen_random_uuid())$q$,
  'P0001', 'consent_required', 'reply before the ack');
select pg_temp.act_as('ffffffff-0000-4000-8000-00000000000f');
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000f', 'hi', gen_random_uuid())$q$,
  'P0001', 'v2_unavailable', 'reply on a pair that is not v2');
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-000000000009', 'hi', 'e1000000-0000-4000-8000-000000000001')$q$,
  '22023', 'bad_reply_id', 'another user''s reply id');
select pg_temp.expect_count('select 1 from public.coach_feedback_replies', 0, 'G reads the table');
select pg_temp.expect_count('select 1 from public.my_feedback_replies()', 0, 'my_feedback_replies for G');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count('select 1 from public.coach_feedback_replies', 0, 'the coach reads the table directly');
reset role;

-- AC8: any kind other than note or welcome (a future C8.12 broadcast) takes no reply.
-- The checks are relaxed inside this transaction only, to store such a row.
alter table public.coach_feedback drop constraint if exists coach_feedback_one_target;
alter table public.coach_feedback drop constraint if exists coach_feedback_kind_check;
insert into public.coach_feedback (id, coach_id, athlete_id, kind, text) values
  ('d4000000-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b',
   'broadcast', 'Track night moved to 19:00.');
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d4000000-0000-4000-8000-00000000000b', 'ok', gen_random_uuid())$q$,
  '22023', 'reply_not_allowed', 'reply to a broadcast');
reset role;

do $$
begin
  if (select count(*) from public.coach_feedback_replies) <> 4 then
    raise exception 'FAIL: a refused write stored a reply';
  end if;
  if not exists (select 1 from public.coach_feedback_replies where id = 'e1000000-0000-4000-8000-000000000001'
                 and text = 'Thanks, legs felt heavy on Tuesday' and link_id = '11111111-0000-4000-8000-00000000000b'
                 and author_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and read_at is null) then
    raise exception 'FAIL: reply 1 was not stored once, trimmed, with its link';
  end if;
  if (select char_length(text) from public.coach_feedback_replies where id = 'e4000000-0000-4000-8000-000000000004') <> 1000 then
    raise exception 'FAIL: the 1000-character reply was changed';
  end if;
end $$;

-- A reply that the RPC refuses (no ack), inserted directly to test the read gate.
insert into public.coach_feedback_replies (id, feedback_id, author_id, link_id, text) values
  ('ee000000-0000-4000-8000-00000000000e', 'd1000000-0000-4000-8000-00000000000e', 'eeeeeeee-0000-4000-8000-00000000000e',
   '11111111-0000-4000-8000-00000000000e', 'no ack');
set local role authenticated;
select pg_temp.act_as('88888888-0000-4000-8000-000000000008');
select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-000000000008', 'Before leaving', 'e8000000-0000-4000-8000-000000000008');
select pg_temp.act_as('99999999-0000-4000-8000-000000000009');
select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-000000000009', 'Shin is sore', 'e9000000-0000-4000-8000-000000000009');
reset role;

-- Coach reads (AC4) ---------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_feedback_replies(array['bbbbbbbb-0000-4000-8000-00000000000b']::uuid[])$q$,
  4, 'A reads B''s replies');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_feedback_replies() where id = 'e1000000-0000-4000-8000-000000000001'
     and feedback_id = 'd1000000-0000-4000-8000-00000000000b' and athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
     and text = 'Thanks, legs felt heavy on Tuesday' and read_at is null$q$,
  1, 'A reads the reply verbatim, under its note');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_feedback_replies(array['eeeeeeee-0000-4000-8000-00000000000e']::uuid[])$q$,
  0, 'no consent: no replies');
select pg_temp.expect_count('select 1 from public.coach_get_feedback_replies()', 6, 'A reads B, G and H');
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_count('select 1 from public.coach_get_feedback_replies()', 0, 'another coach reads replies');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count('select 1 from public.coach_get_feedback_replies()', 0, 'the athlete calls the coach read');
reset role;

set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error($q$select * from public.coach_get_feedback_replies()$q$, '42501', null, 'anon reads replies');
select pg_temp.expect_error($q$select * from public.my_feedback_replies()$q$, '42501', null, 'anon reads own replies');
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000b', 'hi', gen_random_uuid())$q$,
  '42501', null, 'anon replies');
select pg_temp.expect_error(
  $q$select public.coach_mark_reply_read(array['e1000000-0000-4000-8000-000000000001']::uuid[])$q$,
  '42501', null, 'anon marks read');
select pg_temp.expect_error($q$select * from public.coach_feedback_replies$q$, '42501', null, 'anon reads the table');
reset role;

-- Read receipt ------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_text(
  public.coach_mark_reply_read(array['e1000000-0000-4000-8000-000000000001']::uuid[])::text, '0', 'another coach marks read');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_text(
  public.coach_mark_reply_read(array['e1000000-0000-4000-8000-000000000001']::uuid[])::text, '0', 'the athlete marks read');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_text(
  public.coach_mark_reply_read(array['e1000000-0000-4000-8000-000000000001', 'ee000000-0000-4000-8000-00000000000e']::uuid[])::text,
  '1', 'A marks a reply read (the no-ack one is skipped)');
select pg_temp.expect_text(
  public.coach_mark_reply_read(array['e1000000-0000-4000-8000-000000000001']::uuid[])::text, '0', 'marking it again');
select pg_temp.expect_text(public.coach_mark_reply_read(array[]::uuid[])::text, '0', 'marking nothing');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_feedback_replies() where id = 'e1000000-0000-4000-8000-000000000001' and read_at is not null$q$,
  1, 'the read time shows to the coach');
reset role;
do $$
begin
  if (select read_at from public.coach_feedback_replies where id = 'ee000000-0000-4000-8000-00000000000e') is not null then
    raise exception 'FAIL: a reply the coach cannot read was marked read';
  end if;
end $$;

-- Roster summary (AC4) ----------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
     and new_runs = 0 and new_flags = 0 and new_replies = 4 and new_events = 0 and oldest_new_at is not null$q$,
  1, 'summary counts B''s replies');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = 'eeeeeeee-0000-4000-8000-00000000000e' and new_replies = 0$q$,
  1, 'summary: no consent, no reply count');
-- C7.3 and C7.4 counts are unchanged for G: one run, one flag, one reply.
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = '99999999-0000-4000-8000-000000000009'
     and new_runs = 1 and new_flags = 1 and new_replies = 1$q$,
  1, 'summary keeps run and flag counts');

-- Seen: opening B clears the count; a reply sent after that counts again.
select public.coach_mark_athlete_seen('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and new_replies = 0$q$,
  1, 'seen clears the reply count');
reset role;
-- now() is fixed inside this transaction: move the earlier replies an hour back and
-- the visit a minute back, so only the next reply is after the visit.
update public.coach_feedback_replies set created_at = now() - interval '1 hour';
update public.coach_athlete_seen set seen_at = now() - interval '1 minute'
where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-00000000000b', 'One more thing', 'e5000000-0000-4000-8000-000000000005');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and new_replies = 1$q$,
  1, 'a reply after the visit counts');
reset role;

-- Link ended, then a rejoin (AC6, AC7) ----------------------------------------------------
-- The coach removes H (C7.11, M5b): the coach then reads none of H's replies.
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_feedback_replies(array['88888888-0000-4000-8000-000000000008']::uuid[])$q$,
  1, 'H''s reply before the removal');
select pg_temp.expect_text(public.coach_remove_athlete('88888888-0000-4000-8000-000000000008'), 'removed', 'A removes H');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_feedback_replies(array['88888888-0000-4000-8000-000000000008']::uuid[])$q$,
  0, 'revoked link: no replies');
select pg_temp.expect_count(
  $q$select 1 from public.coach_roster_summary() where athlete_id = '88888888-0000-4000-8000-000000000008'$q$,
  0, 'revoked link: no summary row');
select pg_temp.expect_text(
  public.coach_mark_reply_read(array['e8000000-0000-4000-8000-000000000008']::uuid[])::text, '0', 'mark read on a revoked link');
-- The athlete: a queued reply flushes after the link ended (AC7).
select pg_temp.act_as('88888888-0000-4000-8000-000000000008');
select pg_temp.expect_error(
  $q$select public.athlete_reply_to_feedback('d1000000-0000-4000-8000-000000000008', 'queued while offline', gen_random_uuid())$q$,
  'P0001', 'link_inactive', 'reply after the link ended');
-- A retry of the reply stored before the end: the first write stands.
select pg_temp.expect_text(
  public.athlete_reply_to_feedback('d1000000-0000-4000-8000-000000000008', 'Before leaving', 'e8000000-0000-4000-8000-000000000008'),
  'sent', 'retry of a reply stored before the end');
-- The athlete still reads their note and reply (AC6).
select pg_temp.expect_count('select 1 from public.my_feedback_replies()', 1, 'H reads own reply after leaving');
select pg_temp.expect_count('select 1 from public.my_coach_feedback()', 1, 'H reads the note after leaving');
reset role;

insert into public.coach_athlete_links
  (id, coach_id, athlete_id, status, consented_at, consent_version, consent_acknowledged_at) values
  ('22222222-0000-4000-8000-000000000008', 'aaaaaaaa-0000-4000-8000-00000000000a', '88888888-0000-4000-8000-000000000008',
   'active', now(), 2, now());
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_feedback_replies(array['88888888-0000-4000-8000-000000000008']::uuid[])$q$,
  0, 'a rejoin does not bring old replies back');
select pg_temp.act_as('88888888-0000-4000-8000-000000000008');
select pg_temp.expect_text(
  public.athlete_reply_to_feedback('d1000000-0000-4000-8000-000000000008', 'Back again', 'e8100000-0000-4000-8000-000000000008'),
  'sent', 'reply on the new link');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_feedback_replies(array['88888888-0000-4000-8000-000000000008']::uuid[])
     where id = 'e8100000-0000-4000-8000-000000000008'$q$,
  1, 'the coach reads the reply sent on the new link only');
select pg_temp.expect_count(
  $q$select 1 from public.coach_get_feedback_replies(array['88888888-0000-4000-8000-000000000008']::uuid[])$q$,
  1, 'only the new link''s reply');
reset role;

-- Account deletion --------------------------------------------------------------------
select public.purge_coach_data_for_deleted_account('99999999-0000-4000-8000-000000000009');
do $$
begin
  if exists (select 1 from public.coach_feedback_replies where author_id = '99999999-0000-4000-8000-000000000009') then
    raise exception 'FAIL: the purge left the athlete''s replies';
  end if;
  if exists (select 1 from public.athlete_run_flags where athlete_id = '99999999-0000-4000-8000-000000000009') then
    raise exception 'FAIL: the purge lost the C7.4 block';
  end if;
  if exists (select 1 from public.runs where auth_user_id = '99999999-0000-4000-8000-000000000009'
             and (rpe is not null or athlete_note is not null)) then
    raise exception 'FAIL: the purge lost the C7.3 block';
  end if;
  if (select count(*) from public.coach_feedback_replies where author_id = 'bbbbbbbb-0000-4000-8000-00000000000b') <> 5 then
    raise exception 'FAIL: the purge removed another athlete''s replies';
  end if;
end $$;

-- The coach deletes their account: replies to their notes go with the notes. B's reply
-- to the broadcast row would go too; none exists.
select public.purge_coach_data_for_deleted_account('aaaaaaaa-0000-4000-8000-00000000000a');
do $$
begin
  if exists (select 1 from public.coach_feedback_replies r join public.coach_feedback f on f.id = r.feedback_id
             where f.coach_id = 'aaaaaaaa-0000-4000-8000-00000000000a')
     or (select count(*) from public.coach_feedback_replies) <> 0 then
    raise exception 'FAIL: a deleted coach''s notes kept their replies';
  end if;
end $$;

-- Deleting the auth user cascades too (a reply stored directly, then the user goes).
insert into public.coach_feedback_replies (id, feedback_id, author_id, text) values
  ('e2200000-0000-4000-8000-00000000000b', 'd2000000-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b', 'kept?');
delete from auth.users where id = 'bbbbbbbb-0000-4000-8000-00000000000b';
do $$
begin
  if exists (select 1 from public.coach_feedback_replies where author_id = 'bbbbbbbb-0000-4000-8000-00000000000b') then
    raise exception 'FAIL: deleting the auth user left replies';
  end if;
end $$;

do $$ begin raise notice 'coach_feedback_replies: PASS'; end $$;

rollback;
