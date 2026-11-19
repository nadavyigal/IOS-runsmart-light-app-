begin;
do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'Coach route test requires an empty throwaway Supabase database';
  end if;
end $$;

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'coach@example.test'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'athlete@example.test'),
  ('cccccccc-0000-4000-8000-000000000001', 'other@example.test');

insert into public.coach_profiles (user_id, display_name)
values ('aaaaaaaa-0000-4000-8000-000000000001', 'Dana');

insert into public.coach_athlete_links (id, coach_id, athlete_id, status, consented_at) values
  ('dddddddd-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000001', 'active', '2026-11-15 00:00+00');

insert into public.runs (auth_user_id, source_provider, source_activity_id, completed_at, route, route_status)
select 'bbbbbbbb-0000-4000-8000-000000000001', provider, run_id, finished::timestamptz, route::jsonb, status
from (values
  ('runsmart_ios', 'EEEEEEEE-0000-4000-8000-000000000001', '2026-11-15 01:00+00', null, null),
  ('runsmart_ios', 'EEEEEEEE-0000-4000-8000-000000000002', '2026-11-14 01:00+00', null, null),
  ('runsmart_ios', 'EEEEEEEE-0000-4000-8000-000000000003', '2026-11-15 01:00+00', '[{"lat":0,"lng":0}]', 'hidden_by_athlete'),
  ('runsmart_ios', 'EEEEEEEE-0000-4000-8000-000000000004', '2026-11-15 01:00+00', null, 'too_short'),
  ('garmin', 'EEEEEEEE-0000-4000-8000-000000000005', '2026-11-15 01:00+00', '[{"lat":0,"lng":0}]', null)
) as scenarios(provider, run_id, finished, route, status);

create function pg_temp.expect_result(
  run_id uuid, expected text, payload jsonb default '[{"lat":32.12,"lng":34.9},{"lat":32.13,"lng":35}]',
  link_id uuid default 'dddddddd-0000-4000-8000-000000000001'
) returns void language plpgsql as $$
declare actual text;
begin
  actual := public.save_coach_run_route('bbbbbbbb-0000-4000-8000-000000000001', link_id, run_id, payload);
  if actual is distinct from expected then
    raise exception 'Run %: got %, expected %', run_id, actual, expected;
  end if;
end $$;

do $$
begin
  if has_function_privilege('anon', 'public.save_coach_run_route(uuid,uuid,uuid,jsonb)', 'EXECUTE') then
    raise exception 'Anon should not execute the route RPC';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'cccccccc-0000-4000-8000-000000000001', true);
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000001', 'stopped');

select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-4000-8000-000000000001', true);
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000001', 'stopped',
  '[{"lat":32.12,"lng":34.9,"timestamp":123},{"lat":32.13,"lng":35}]');
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000001', 'stopped',
  '[{"lat":91,"lng":34.9},{"lat":32.13,"lng":35}]');
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000001', 'stopped',
  '[{"lat":32.12,"lng":34.9},{"lat":32.13,"lng":35}]', 'dddddddd-0000-4000-8000-000000000002');
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000001', 'saved');
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000001', 'saved');
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000002', 'stopped');
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000003', 'stopped');
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000004', 'stopped');
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000005', 'missing');
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000006', 'missing');

select public.leave_coach('dddddddd-0000-4000-8000-000000000001');
select pg_temp.expect_result('eeeeeeee-0000-4000-8000-000000000001', 'stopped',
  '[{"lat":12,"lng":1},{"lat":13,"lng":2}]');

reset role;
do $$
begin
  if not exists (select 1 from public.runs where route_status = 'shared'
                  and route = '[{"lat":32.12,"lng":34.9},{"lat":32.13,"lng":35}]'::jsonb)
     or not exists (select 1 from public.runs where route_status = 'hidden_by_athlete'
                     and route = '[{"lat":0,"lng":0}]'::jsonb)
     or not exists (select 1 from public.runs where route_status = 'too_short' and route is null)
     or not exists (select 1 from public.runs where source_provider = 'garmin' and route_status is null)
     or (select count(*) from public.runs where route_status = 'shared') <> 1 then
    raise exception 'Route or visibility changed unexpectedly';
  end if;
end $$;
rollback;
