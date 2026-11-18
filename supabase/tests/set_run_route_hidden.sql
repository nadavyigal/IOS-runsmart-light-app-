-- Story 6.3. Throwaway database with the Story 6.2 fixtures and migrations.
begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'set_run_route_hidden.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'athlete-d@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', '2026-11-01');

insert into public.runs (id, auth_user_id, type, distance, duration, completed_at, route, route_status) values
  (1, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 8.2, 2900, '2026-11-14T07:00:00Z',
   '[{"lat":32.08,"lng":34.78},{"lat":32.09,"lng":34.79}]', 'shared'),
  (3, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 0.3, 120, '2026-11-16T07:00:00Z',
   '[{"lat":32.08,"lng":34.78},{"lat":32.09,"lng":34.79}]', 'too_short'),
  (4, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 6, 2100, '2026-11-17T07:00:00Z',
   '[{"lat":32.08,"lng":34.78},{"lat":32.09,"lng":34.79}]', null),
  (5, 'bbbbbbbb-0000-4000-8000-00000000000b', 'easy', 6, 2100, '2026-11-17T08:00:00Z', null, null);

update public.runs set source_provider = 'runsmart_ios',
  source_activity_id = 'eeeeeeee-0000-4000-8000-00000000000e', pace = 354, heart_rate = 145 where id = 1;

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

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
select pg_temp.expect_error('select public.set_run_route_hidden(1,true)','42501','coach hide');
select pg_temp.act_as('dddddddd-0000-4000-8000-00000000000d');
select pg_temp.expect_error('select public.set_run_route_hidden(1,true)','42501','other athlete hide');
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error('select public.set_run_route_hidden(3,false)','22023','too short');
select pg_temp.expect_error('select public.set_run_route_hidden(4,true)','22023','unmarked route');
select pg_temp.expect_error('select public.set_run_route_hidden(5,true)','22023','missing route');
select public.set_run_route_hidden(1,true);
select public.set_run_route_hidden(1,true);
do $$ begin
  if public.save_coach_run_route(auth.uid(), (select id from public.coach_athlete_links where athlete_id=auth.uid()),
      'eeeeeeee-0000-4000-8000-00000000000e','[{"lat":1,"lng":1},{"lat":2,"lng":2}]') <> 'stopped' then
    raise exception 'upload retry overwrote hidden map';
  end if;
  if not exists (select from public.runs where id=1 and jsonb_array_length(route)=2) then
    raise exception 'stored route lost';
  end if;
end $$;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
do $$ begin
  if not exists (select from public.coach_get_run_route(1) where state='hidden' and route is null)
     or not exists (select from public.coach_get_athletes_runs('2026-11-14','2026-11-14')
                    where id=1 and distance_km=8.2 and duration_seconds=2900 and pace=354 and average_heart_rate=145) then
    raise exception 'hidden map or summary incorrect';
  end if;
end $$;
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select public.set_run_route_hidden(1,false);
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
do $$ begin
  if not exists (select from public.coach_get_run_route(1) where state='map' and jsonb_array_length(route)=2) then
    raise exception 'unhide failed';
  end if;
end $$;
set local role anon;
select pg_temp.expect_error('select public.set_run_route_hidden(1,true)','42501','anonymous hide');
rollback;
