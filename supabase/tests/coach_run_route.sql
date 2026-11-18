-- Story 6.2. A coach reads a run's map only through coach_get_run_route(): active link +
-- shared → route; revoked, no link, another coach → nothing; hidden_by_athlete and
-- too_short → their state and NO route even with route data; route set but route_status
-- null → no_map; a direct coach select on runs.route still returns nothing.
--
-- Blank throwaway Postgres only. Apply coach_read_fixture, Stories 1.2, 1.3, 1.5, 2.2
-- and 6.1, then this migration twice, then this file.

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_run_route.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'athlete-d@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Ron');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', now()),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-00000000000d', 'revoked', now());

insert into public.runs (id, auth_user_id, type, distance, duration, completed_at, route, route_status) values
  (1, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 8.2, 2900, '2026-11-14T07:00:00Z',
   '[{"lat":32.08,"lng":34.78},{"lat":32.09,"lng":34.79}]', 'shared'),
  (2, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 5, 1800, '2026-11-15T07:00:00Z',
   '[{"lat":32.08,"lng":34.78},{"lat":32.09,"lng":34.79}]', 'hidden_by_athlete'),
  (3, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 0.3, 120, '2026-11-16T07:00:00Z',
   '[{"lat":32.08,"lng":34.78},{"lat":32.09,"lng":34.79}]', 'too_short'),
  (4, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 6, 2100, '2026-11-17T07:00:00Z',
   '[{"lat":32.08,"lng":34.78},{"lat":32.09,"lng":34.79}]', null),
  (5, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 6, 2100, '2026-11-17T08:00:00Z', null, null),
  (6, 'dddddddd-0000-4000-8000-00000000000d', 'easy', 6, 2100, '2026-11-17T07:00:00Z',
   '[{"lat":32.08,"lng":34.78},{"lat":32.09,"lng":34.79}]', 'shared');

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

-- Dana is actively linked to B ------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');

do $$
declare
  r record;
begin
  select * into r from public.coach_get_run_route(1);
  if r.state <> 'map' or r.route is null or jsonb_array_length(r.route) <> 2 then
    raise exception 'FAIL: shared run: % %', r.state, r.route;
  end if;

  select * into r from public.coach_get_run_route(2);
  if r.state <> 'hidden' or r.route is not null then
    raise exception 'FAIL: hidden run leaked: % %', r.state, r.route;
  end if;

  select * into r from public.coach_get_run_route(3);
  if r.state <> 'route_hidden' or r.route is not null then
    raise exception 'FAIL: too_short run leaked: % %', r.state, r.route;
  end if;

  select * into r from public.coach_get_run_route(4);
  if r.state <> 'no_map' or r.route is not null then
    raise exception 'FAIL: route with null route_status leaked: % %', r.state, r.route;
  end if;

  select * into r from public.coach_get_run_route(5);
  if r.state <> 'no_map' or r.route is not null then
    raise exception 'FAIL: run with no route: % %', r.state, r.route;
  end if;

  -- D's link is revoked: nothing, not even a state.
  if exists (select 1 from public.coach_get_run_route(6)) then
    raise exception 'FAIL: revoked link returned a row';
  end if;
  -- Unknown run: nothing.
  if exists (select 1 from public.coach_get_run_route(999)) then
    raise exception 'FAIL: unknown run returned a row';
  end if;
  -- Direct table reads stay owner-only.
  if exists (select 1 from public.runs where route is not null) then
    raise exception 'FAIL: coach reads runs.route directly';
  end if;
end $$;

-- Ron is a coach with no link to B ---------------------------------------------------
select pg_temp.act_as('cccccccc-0000-4000-8000-00000000000c');
do $$
begin
  if exists (select 1 from public.coach_get_run_route(1)) then
    raise exception 'FAIL: another coach got a route';
  end if;
end $$;

-- The athlete themself is not a coach of themself: nothing through the coach RPC.
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
do $$
begin
  if exists (select 1 from public.coach_get_run_route(1)) then
    raise exception 'FAIL: the athlete got a row through the coach RPC';
  end if;
end $$;

-- After B leaves, Dana gets nothing ------------------------------------------------
select public.leave_coach(
  (select id from public.coach_athlete_links
   where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b' and status = 'active'));
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
do $$
begin
  if exists (select 1 from public.coach_get_run_route(1)) then
    raise exception 'FAIL: route returned after the athlete left';
  end if;
end $$;

-- anon has no access -----------------------------------------------------------------
reset role;
set local role anon;
select pg_temp.expect_error($q$select * from public.coach_get_run_route(1)$q$, '42501', 'anon reads a route');

rollback;
