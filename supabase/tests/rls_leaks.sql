-- Two-user RLS leak test for 20261114120000_close_cross_user_rls_leaks.sql.
--
-- Proves user B gets zero rows of user A's analytics_events, idempotency_keys,
-- plans, workouts, conversations and conversation_messages, and that A's own
-- flows (analytics logging, plan load, workout completion, AI chat) still work.
-- Raises an exception on the first failure; prints "rls_leaks: PASS" otherwise.
-- Everything runs in one transaction and is rolled back, but it still inserts
-- two auth.users rows while it runs: use a local or branch database, never
-- production.
--
-- Run (local throwaway database, after applying the migration):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_leaks.sql
-- Run as a superuser-capable role (postgres / supabase_admin) so the fixture
-- inserts can bypass RLS before the test switches roles.

begin;

-- Fixture rows for user A (inserted as the table owner, bypassing RLS) --------
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'rls-test-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'rls-test-b@example.com', 'authenticated', 'authenticated');

insert into public.analytics_events (id, event_name, user_id) values
  ('aaaaaaaa-0001-4000-8000-00000000000a', 'run_completed', 'aaaaaaaa-0000-4000-8000-00000000000a'),
  ('aaaaaaaa-0002-4000-8000-00000000000a', 'run_completed', '424242');

insert into public.idempotency_keys (id, key, profile_id, operation_type) values
  ('aaaaaaaa-0003-4000-8000-00000000000a', 'rls-test-key', 'aaaaaaaa-0000-4000-8000-00000000000a', 'plan_generation');

insert into public.plans (id, profile_id, auth_user_id, title) values
  ('aaaaaaaa-0004-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a', 'RLS test plan');

insert into public.workouts (id, plan_id, auth_user_id) values
  ('aaaaaaaa-0005-4000-8000-00000000000a', 'aaaaaaaa-0004-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a');

insert into public.conversations (id, profile_id, auth_user_id) values
  ('aaaaaaaa-0006-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a');

insert into public.conversation_messages (id, conversation_id, auth_user_id, role, content) values
  ('aaaaaaaa-0007-4000-8000-00000000000a', 'aaaaaaaa-0006-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a', 'user', 'private message');

-- User B: must see and touch none of A's rows ---------------------------------
set local role authenticated;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"bbbbbbbb-0000-4000-8000-00000000000b","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-4000-8000-00000000000b', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

do $$
declare
  n int;
begin
  select count(*) into n from public.analytics_events;
  if n <> 0 then raise exception 'FAIL: user B sees % analytics_events rows', n; end if;

  select count(*) into n from public.idempotency_keys;
  if n <> 0 then raise exception 'FAIL: user B sees % idempotency_keys rows', n; end if;

  select count(*) into n from public.plans;
  if n <> 0 then raise exception 'FAIL: user B sees % plans rows', n; end if;

  select count(*) into n from public.workouts;
  if n <> 0 then raise exception 'FAIL: user B sees % workouts rows', n; end if;

  select count(*) into n from public.conversations;
  if n <> 0 then raise exception 'FAIL: user B sees % conversations rows', n; end if;

  select count(*) into n from public.conversation_messages;
  if n <> 0 then raise exception 'FAIL: user B sees % conversation_messages rows', n; end if;

  update public.idempotency_keys set result = null where true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: user B updated % idempotency_keys rows', n; end if;

  delete from public.idempotency_keys where true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: user B deleted % idempotency_keys rows', n; end if;

  update public.plans set title = 'hijacked' where true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: user B updated % plans rows', n; end if;

  update public.workouts set completed = true where true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: user B updated % workouts rows', n; end if;

  begin
    insert into public.idempotency_keys (key, profile_id, operation_type)
    values ('b-key', 'bbbbbbbb-0000-4000-8000-00000000000b', 'plan_generation');
    raise exception 'FAIL: user B could insert into idempotency_keys';
  exception when insufficient_privilege then
    null;
  end;

  begin
    insert into public.conversation_messages (conversation_id, auth_user_id, role, content)
    values ('aaaaaaaa-0006-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'user', 'intrusion');
    raise exception 'FAIL: user B could post into user A''s conversation';
  exception when insufficient_privilege then
    null;
  end;
end $$;

reset role;

-- User A: owner flows still work ------------------------------------------------
set local role authenticated;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-0000-4000-8000-00000000000a","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-4000-8000-00000000000a', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

do $$
declare
  n int;
begin
  -- Analytics logging: write-only, same as the web POST /api/analytics/events.
  insert into public.analytics_events (event_name, user_id) values ('app_opened', '424242');

  -- Plan load.
  select count(*) into n from public.plans where id = 'aaaaaaaa-0004-4000-8000-00000000000a';
  if n <> 1 then raise exception 'FAIL: user A cannot load own plan'; end if;

  -- Workout completion.
  update public.workouts set completed = true where id = 'aaaaaaaa-0005-4000-8000-00000000000a';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FAIL: user A cannot complete own workout'; end if;

  -- AI chat: read own thread and post into it.
  select count(*) into n from public.conversations where id = 'aaaaaaaa-0006-4000-8000-00000000000a';
  if n <> 1 then raise exception 'FAIL: user A cannot read own conversation'; end if;

  select count(*) into n from public.conversation_messages where conversation_id = 'aaaaaaaa-0006-4000-8000-00000000000a';
  if n <> 1 then raise exception 'FAIL: user A cannot read own messages'; end if;

  insert into public.conversation_messages (conversation_id, auth_user_id, role, content)
  values ('aaaaaaaa-0006-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a', 'user', 'hello coach');
end $$;

reset role;

-- Anonymous analytics logging still works ---------------------------------------
set local role anon;
do $$ begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
end $$;
insert into public.analytics_events (event_name, user_id) values ('landing_viewed', null);
reset role;

-- Service role keeps full access (Edge Functions, delete_account) ---------------
set local role service_role;
do $$ begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
end $$;

do $$
declare
  n int;
begin
  select count(*) into n from public.analytics_events
  where id in ('aaaaaaaa-0001-4000-8000-00000000000a', 'aaaaaaaa-0002-4000-8000-00000000000a');
  if n <> 2 then raise exception 'FAIL: service role sees % of 2 analytics_events rows', n; end if;

  select count(*) into n from public.idempotency_keys where id = 'aaaaaaaa-0003-4000-8000-00000000000a';
  if n <> 1 then raise exception 'FAIL: service role cannot read idempotency_keys'; end if;
end $$;

reset role;

-- Policy shape: no broad policy and no user-editable admin check remain --------
do $$
declare
  offending text;
begin
  select string_agg(tablename || '.' || policyname, ', ') into offending
  from pg_policies
  where schemaname = 'public'
    and tablename in ('analytics_events', 'idempotency_keys', 'plans', 'workouts',
                      'conversations', 'conversation_messages')
    and cmd in ('SELECT', 'ALL', 'UPDATE', 'DELETE')
    and roles <> array['service_role']::name[]
    and coalesce(qual, '') in ('true', '(auth.role() = ''authenticated''::text)',
                               '(auth.uid() IS NOT NULL)');
  if offending is not null then
    raise exception 'FAIL: broad "any authenticated user" policy remains: %', offending;
  end if;

  select string_agg(tablename || '.' || policyname, ', ') into offending
  from pg_policies
  where coalesce(qual, '') ilike '%raw_user_meta_data%'
     or coalesce(with_check, '') ilike '%raw_user_meta_data%';
  if offending is not null then
    raise exception 'FAIL: user-editable raw_user_meta_data admin policy remains: %', offending;
  end if;
end $$;

select 'rls_leaks: PASS' as result;

rollback;
