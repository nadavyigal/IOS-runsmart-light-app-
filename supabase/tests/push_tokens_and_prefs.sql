-- Test for 20261122100000_push_tokens_and_prefs.sql: push tokens and notification
-- prefs (story C7.10, M2a).
--
-- Users: A has two devices. B is a second user. C is deleted at the end.
-- Proves:
--   * C7.10 AC5: one user on two devices has two push_tokens rows; unregistering
--     device 1 removes only device 1's row; a user cannot read, change or delete
--     another user's token, directly or through unregister_push_token.
--   * register_push_token: input checks, a re-register refreshes last_seen_at and
--     clears disabled_at (set by the sender on an APNs 410), and a token that
--     comes back under another account moves to that account.
--   * C7.10 AC9: the first my_notification_prefs read creates the row with the D6
--     defaults and the device time zone; a later read keeps it; the time zone
--     changes only through set_notification_time_zone; own row only.
--   * update_notification_prefs (C7.14's write path): partial updates, equal quiet
--     hours rejected, a missing row rejected.
--   * Shape: RLS on, select-only client policies, no direct client writes,
--     search_path = '' on every function, anon denied, rows cascade with the
--     auth user.
-- Raises on the first failure; prints "push_tokens_and_prefs: PASS" otherwise.
--
-- Inserts auth.users rows. Refuses to run if auth.users is not empty, so it can
-- only run on a blank throwaway Postgres (supabase/postgres image), never production.
--
-- Run (this migration twice to prove idempotence, then the test):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261122100000_push_tokens_and_prefs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261122100000_push_tokens_and_prefs.sql
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/push_tokens_and_prefs.sql

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'push_tokens_and_prefs.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'user-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'user-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'user-c@example.com', 'authenticated', 'authenticated');

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

create function pg_temp.expect_text(actual text, expected text, label text) returns void
language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL: % was %, expected %', label, actual, expected;
  end if;
end $$;

grant execute on function pg_temp.act_as(text), pg_temp.act_as_anon(),
  pg_temp.expect_error(text, text, text), pg_temp.expect_count(text, int, text),
  pg_temp.expect_text(text, text, text) to authenticated, anon;

-- 64-hex tokens. D1 and D2 are A's two devices, B1 is B's device.
create function pg_temp.tok(c text) returns text language sql immutable as $$
  select repeat(c, 64);
$$;
grant execute on function pg_temp.tok(text) to authenticated, anon;

-- Shape --------------------------------------------------------------------------
do $$
declare
  t text;
  f text;
begin
  foreach t in array array['push_tokens', 'notification_prefs'] loop
    if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
      raise exception 'FAIL: RLS is off on %', t;
    end if;
    if exists (select 1 from pg_policies where schemaname = 'public'
               and tablename = t and cmd <> 'SELECT') then
      raise exception 'FAIL: % has a client write policy', t;
    end if;
    if (select count(*) from pg_policies where schemaname = 'public' and tablename = t) <> 1 then
      raise exception 'FAIL: % does not have exactly one (owner select) policy', t;
    end if;
    if has_table_privilege('authenticated', 'public.' || t, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || t, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || t, 'DELETE')
       or has_table_privilege('anon', 'public.' || t, 'SELECT') then
      raise exception 'FAIL: % has a direct client write grant or an anon read grant', t;
    end if;
  end loop;
  foreach f in array array['notification_time_zone_ok', 'register_push_token', 'unregister_push_token',
                           'my_notification_prefs', 'set_notification_time_zone',
                           'update_notification_prefs'] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f and p.prosecdef
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'FAIL: % is not security definer with search_path = ''''', f;
    end if;
    if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = f) <> 1 then
      raise exception 'FAIL: more than one % signature', f;
    end if;
  end loop;
  if has_function_privilege('authenticated', 'public.notification_time_zone_ok(text)', 'EXECUTE') then
    raise exception 'FAIL: notification_time_zone_ok is callable by clients';
  end if;
  if (select confdeltype from pg_constraint where conname = 'push_tokens_user_id_fkey') <> 'c'
     or (select confdeltype from pg_constraint where conname = 'notification_prefs_user_id_fkey') <> 'c' then
    raise exception 'FAIL: a user FK does not cascade';
  end if;
end $$;

-- anon is denied everything ----------------------------------------------------------
set local role anon;
select pg_temp.act_as_anon();
select pg_temp.expect_error(
  $q$select public.register_push_token(pg_temp.tok('a'), 'sandbox')$q$, '42501', 'anon registers a token');
select pg_temp.expect_error(
  $q$select public.unregister_push_token(pg_temp.tok('a'))$q$, '42501', 'anon unregisters a token');
select pg_temp.expect_error(
  $q$select public.my_notification_prefs('UTC')$q$, '42501', 'anon reads prefs');
select pg_temp.expect_error(
  $q$select public.set_notification_time_zone('UTC')$q$, '42501', 'anon sets the time zone');
select pg_temp.expect_error(
  $q$select public.update_notification_prefs(p_coach_run_finished => false)$q$, '42501', 'anon updates prefs');
select pg_temp.expect_error(
  $q$select * from public.push_tokens$q$, '42501', 'anon reads push_tokens');
select pg_temp.expect_error(
  $q$select * from public.notification_prefs$q$, '42501', 'anon reads notification_prefs');
reset role;

-- AC5: one user, two devices -----------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
-- Device 1 sends its token in upper case with spaces: stored normalized.
select pg_temp.expect_text(
  public.register_push_token('  ' || upper(pg_temp.tok('1')) || ' ', 'sandbox', 'com.runsmart.lite'),
  'registered', 'A registers device 1');
select pg_temp.expect_text(
  public.register_push_token(pg_temp.tok('2'), 'production', 'com.runsmart.lite'),
  'registered', 'A registers device 2');
select pg_temp.expect_count('select 1 from public.push_tokens', 2, 'A reads two token rows');
select pg_temp.expect_count(
  $q$select 1 from public.push_tokens where token = pg_temp.tok('1') and environment = 'sandbox'
     and bundle_id = 'com.runsmart.lite' and disabled_at is null$q$,
  1, 'device 1 stored normalized');

-- Registering the same device again keeps one row.
select public.register_push_token(pg_temp.tok('1'), 'sandbox', 'com.runsmart.lite');
select pg_temp.expect_count('select 1 from public.push_tokens', 2, 'A still has two rows after a re-register');

-- Bad input.
select pg_temp.expect_error(
  $q$select public.register_push_token('not-a-token', 'sandbox')$q$, '22023', 'non-hex token');
select pg_temp.expect_error(
  $q$select public.register_push_token(repeat('a', 63), 'sandbox')$q$, '22023', 'short token');
select pg_temp.expect_error(
  $q$select public.register_push_token(repeat('a', 201), 'sandbox')$q$, '22023', 'long token');
select pg_temp.expect_error(
  $q$select public.register_push_token(null, 'sandbox')$q$, '22023', 'null token');
select pg_temp.expect_error(
  $q$select public.register_push_token(pg_temp.tok('3'), 'staging')$q$, '22023', 'bad environment');
select pg_temp.expect_error(
  $q$select public.register_push_token(pg_temp.tok('3'), null)$q$, '22023', 'null environment');
select pg_temp.expect_error(
  $q$select public.register_push_token(pg_temp.tok('3'), 'sandbox', repeat('x', 156))$q$, '22023', 'long bundle id');

-- No direct writes, even to your own rows.
select pg_temp.expect_error(
  $q$insert into public.push_tokens (user_id, token, environment)
     values ('aaaaaaaa-0000-4000-8000-00000000000a', pg_temp.tok('4'), 'sandbox')$q$,
  '42501', 'A inserts a token directly');
select pg_temp.expect_error(
  $q$update public.push_tokens set disabled_at = now() where token = pg_temp.tok('1')$q$,
  '42501', 'A updates own token directly');
select pg_temp.expect_error(
  $q$delete from public.push_tokens where token = pg_temp.tok('1')$q$,
  '42501', 'A deletes own token directly');

-- B registers B's device.
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.register_push_token(pg_temp.tok('b'), 'production');
select pg_temp.expect_count('select 1 from public.push_tokens', 1, 'B reads only B''s token');

-- A cannot read, change or delete B's token.
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count(
  $q$select 1 from public.push_tokens where token = pg_temp.tok('b')$q$, 0, 'A reads B''s token');
select pg_temp.expect_error(
  $q$update public.push_tokens set disabled_at = now() where token = pg_temp.tok('b')$q$,
  '42501', 'A updates B''s token');
select pg_temp.expect_error(
  $q$delete from public.push_tokens where token = pg_temp.tok('b')$q$,
  '42501', 'A deletes B''s token');
select pg_temp.expect_text(
  public.unregister_push_token(pg_temp.tok('b')), 'missing', 'A unregisters B''s token');

-- A signs out on device 1: only device 1 goes.
select pg_temp.expect_text(
  public.unregister_push_token(upper(pg_temp.tok('1'))), 'removed', 'A unregisters device 1');
select pg_temp.expect_text(
  public.unregister_push_token(pg_temp.tok('1')), 'missing', 'A unregisters device 1 again');
select pg_temp.expect_count('select 1 from public.push_tokens', 1, 'A has one row left');
select pg_temp.expect_count(
  $q$select 1 from public.push_tokens where token = pg_temp.tok('2')$q$, 1, 'device 2 kept');
reset role;

do $$
begin
  if not exists (select 1 from public.push_tokens
                 where token = repeat('b', 64) and user_id = 'bbbbbbbb-0000-4000-8000-00000000000b'
                   and disabled_at is null) then
    raise exception 'FAIL: B''s token changed after A''s attempts';
  end if;
end $$;

-- APNs 410 path: the sender (service role, here the test owner) disables device 2.
update public.push_tokens
   set disabled_at = now(), last_seen_at = now() - interval '3 days'
 where token = repeat('2', 64);

-- The device registers again (the app reinstalled or the token came back): live again.
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select public.register_push_token(pg_temp.tok('2'), 'production', 'com.runsmart.lite');
select pg_temp.expect_count(
  $q$select 1 from public.push_tokens where token = pg_temp.tok('2') and disabled_at is null
     and last_seen_at > now() - interval '1 minute'$q$,
  1, 're-register clears disabled_at and refreshes last_seen_at');

-- Device 2 signs out offline (its row stays for A), then B signs in on it.
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.register_push_token(pg_temp.tok('2'), 'production', 'com.runsmart.lite');
select pg_temp.expect_count('select 1 from public.push_tokens', 2, 'B now owns device 2 too');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count('select 1 from public.push_tokens', 0, 'A no longer gets device 2''s pushes');
reset role;

-- AC9: notification prefs ----------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_count('select 1 from public.notification_prefs', 0, 'A has no prefs before the first read');
-- Not created yet: the settings write is refused.
select pg_temp.expect_error(
  $q$select public.update_notification_prefs(p_coach_run_finished => false)$q$, 'P0002', 'update before the first read');

do $$
declare
  r public.notification_prefs;
begin
  r := public.my_notification_prefs('Asia/Jerusalem');
  if r.user_id <> 'aaaaaaaa-0000-4000-8000-00000000000a'
     or not r.coach_run_finished or not r.coach_evening_summary or not r.coach_pain_flag
     or not r.athlete_coach_note or not r.athlete_plan_updates or not r.athlete_broadcasts
     or r.quiet_start <> '21:30'::time or r.quiet_end <> '07:00'::time
     or r.time_zone <> 'Asia/Jerusalem' then
    raise exception 'FAIL: first read did not create D6 defaults: %', row_to_json(r);
  end if;

  -- A second read with another zone returns the row as stored.
  r := public.my_notification_prefs('Europe/London');
  if r.time_zone <> 'Asia/Jerusalem' then
    raise exception 'FAIL: a read changed the time zone to %', r.time_zone;
  end if;
end $$;
select pg_temp.expect_count('select 1 from public.notification_prefs', 1, 'A has one prefs row');

-- Foreground time-zone update.
select pg_temp.expect_text(public.set_notification_time_zone('Asia/Jerusalem'), 'unchanged', 'same zone');
select pg_temp.expect_text(public.set_notification_time_zone('Europe/London'), 'saved', 'new zone');
select pg_temp.expect_count(
  $q$select 1 from public.notification_prefs where time_zone = 'Europe/London'$q$, 1, 'zone stored');
select pg_temp.expect_error(
  $q$select public.set_notification_time_zone('Mars/Olympus')$q$, '22023', 'unknown zone');
select pg_temp.expect_error(
  $q$select public.set_notification_time_zone(null)$q$, '22023', 'null zone');

-- Settings write: partial update keeps the rest.
do $$
declare
  r public.notification_prefs;
begin
  r := public.update_notification_prefs(p_coach_run_finished => false, p_quiet_start => '22:00');
  if r.coach_run_finished or not r.coach_pain_flag or r.quiet_start <> '22:00'::time
     or r.quiet_end <> '07:00'::time or r.time_zone <> 'Europe/London' then
    raise exception 'FAIL: partial update stored %', row_to_json(r);
  end if;
end $$;
select pg_temp.expect_error(
  $q$select public.update_notification_prefs(p_quiet_end => '22:00')$q$, '22023', 'equal quiet hours');
select pg_temp.expect_error(
  $q$select public.update_notification_prefs(p_quiet_start => '06:00', p_quiet_end => '06:00')$q$,
  '22023', 'equal quiet hours, both given');

-- No direct writes to prefs.
select pg_temp.expect_error(
  $q$update public.notification_prefs set coach_pain_flag = false$q$, '42501', 'A updates prefs directly');
select pg_temp.expect_error(
  $q$insert into public.notification_prefs (user_id, time_zone)
     values ('bbbbbbbb-0000-4000-8000-00000000000b', 'UTC')$q$,
  '42501', 'A inserts B''s prefs directly');
select pg_temp.expect_error(
  $q$delete from public.notification_prefs$q$, '42501', 'A deletes prefs directly');

-- B: own row only. An unknown zone on the first read is stored as UTC.
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_count('select 1 from public.notification_prefs', 0, 'B reads A''s prefs');
select pg_temp.expect_text((public.my_notification_prefs('Not/AZone')).time_zone, 'UTC', 'unknown first-read zone');
select pg_temp.expect_count('select 1 from public.notification_prefs', 1, 'B reads only B''s prefs');
select public.update_notification_prefs(p_athlete_coach_note => false);

-- C: the foreground update creates the row when the first read never happened.
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
select pg_temp.expect_text(public.set_notification_time_zone('America/New_York'), 'saved', 'C first zone');
select pg_temp.expect_count(
  $q$select 1 from public.notification_prefs where time_zone = 'America/New_York' and coach_run_finished$q$,
  1, 'C row created with defaults');
select public.register_push_token(pg_temp.tok('c'), 'sandbox');
reset role;

do $$
begin
  if (select coach_run_finished from public.notification_prefs
      where user_id = 'aaaaaaaa-0000-4000-8000-00000000000a') then
    raise exception 'FAIL: B''s update changed A''s prefs';
  end if;
  if (select athlete_coach_note from public.notification_prefs
      where user_id = 'aaaaaaaa-0000-4000-8000-00000000000a') is not true then
    raise exception 'FAIL: B''s update reached A''s row';
  end if;
end $$;

-- Account deletion: rows go with the auth user. -----------------------------------------
delete from auth.users where id = 'cccccccc-0000-4000-8000-00000000000c';
do $$
begin
  if exists (select 1 from public.push_tokens where user_id = 'cccccccc-0000-4000-8000-00000000000c')
     or exists (select 1 from public.notification_prefs where user_id = 'cccccccc-0000-4000-8000-00000000000c') then
    raise exception 'FAIL: deleting the auth user left token or prefs rows';
  end if;
end $$;

do $$ begin raise notice 'push_tokens_and_prefs: PASS'; end $$;

rollback;
