-- Story 3.3. get_my_coach() returns the caller's ACTIVE coach with the coach's Plan
-- Mode; a revoked link or no link returns nothing; another user gets nothing; anon is
-- denied.
--
-- Blank throwaway Postgres only. Apply coach_read_fixture, Stories 1.2, 1.3, 1.5 and
-- 1.7, then this migration twice, then this file.

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'get_my_coach.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'third-d@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name, plan_mode) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana', 'group'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Avi', 'individual');

-- B is actively linked to Dana. E was linked to Avi and that link is revoked.
insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now()),
  ('cccccccc-0000-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-00000000000e', 'revoked', now());

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

grant execute on function pg_temp.act_as(text), pg_temp.expect_error(text, text, text) to authenticated, anon;

-- Security: definer, empty search_path ----------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_my_coach'
      and p.prosecdef
      -- Postgres may store an empty search_path as either form.
      and exists (select 1 from unnest(p.proconfig) cfg where cfg in ('search_path=""', 'search_path='))
  ) then
    raise exception 'FAIL: get_my_coach is not security definer with an empty search_path';
  end if;
end $$;

-- Active link returns the coach and the Plan Mode -----------------------------------
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');

do $$
declare
  row_json json;
begin
  if (select count(*) from public.get_my_coach()) <> 1 then
    raise exception 'FAIL: active athlete sees % rows, expected 1', (select count(*) from public.get_my_coach());
  end if;
  select row_to_json(c) into row_json from public.get_my_coach() c;
  if (row_json->>'coach_id') is distinct from 'aaaaaaaa-0000-4000-8000-00000000000a'
     or (row_json->>'display_name') is distinct from 'Dana'
     or (row_json->>'plan_mode') is distinct from 'group' then
    raise exception 'FAIL: wrong coach row: %', row_json;
  end if;
end $$;

-- Revoked link returns nothing --------------------------------------------------------
select pg_temp.act_as('eeeeeeee-0000-4000-8000-00000000000e');
do $$
begin
  if (select count(*) from public.get_my_coach()) <> 0 then
    raise exception 'FAIL: athlete with a revoked link sees a coach';
  end if;
end $$;

-- Another user (no link) gets nothing, and so does a coach ---------------------------
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
do $$
begin
  if (select count(*) from public.get_my_coach()) <> 0 then
    raise exception 'FAIL: an unlinked user sees a coach';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
do $$
begin
  if (select count(*) from public.get_my_coach()) <> 0 then
    raise exception 'FAIL: the coach sees a coach of their own';
  end if;
end $$;

-- After B leaves, B gets nothing ------------------------------------------------------
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.leave_coach(
  (select id from public.coach_athlete_links
   where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'active'));
do $$
begin
  if (select count(*) from public.get_my_coach()) <> 0 then
    raise exception 'FAIL: after leaving the athlete still sees the coach';
  end if;
end $$;

-- A signed-out caller with the authenticated role is refused -------------------------
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.expect_error($q$select * from public.get_my_coach()$q$, '42501', 'no auth.uid');

-- anon is denied -----------------------------------------------------------------------
-- Checked as a privilege, so the auth.uid() guard above can't make this pass by itself.
reset role;
do $$
begin
  if pg_catalog.has_function_privilege('anon', 'public.get_my_coach()', 'EXECUTE') then
    raise exception 'FAIL: anon can execute get_my_coach';
  end if;
  if not pg_catalog.has_function_privilege('authenticated', 'public.get_my_coach()', 'EXECUTE') then
    raise exception 'FAIL: authenticated cannot execute get_my_coach';
  end if;
end $$;
set local role anon;
select pg_temp.expect_error($q$select * from public.get_my_coach()$q$, '42501', 'anon reads');

rollback;
