-- Names fix (2026-11-26). Throwaway database with coach_read_fixture.sql, the coach
-- migrations, 20261120100000_athlete_display_name_placeholder and
-- 20261126100000_coach_display_name.
begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_display_name.sql refused: auth.users is not empty. Run it only on a blank throwaway Postgres.';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-00000000000c', 'coach-c@example.com', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'athlete-b@example.com', 'authenticated', 'authenticated'),
  ('dddddddd-0000-4000-8000-00000000000d', 'athlete-d@example.com', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'athlete-e@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Dana'),
  ('cccccccc-0000-4000-8000-00000000000c', 'Other');

insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b', 'active', '2026-11-01'),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-00000000000d', 'active', '2026-11-02'),
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-00000000000e', 'active', '2026-11-03');

-- b: legacy placeholder, d: blank, e: a Hebrew name.
insert into public.profiles (auth_user_id, name) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'RunSmart Runner'),
  ('dddddddd-0000-4000-8000-00000000000d', '   '),
  ('eeeeeeee-0000-4000-8000-00000000000e', 'נועה');

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

-- athlete_display_name (20261120100000): placeholder and blank read as 'Athlete'.
do $$ begin
  if public.athlete_display_name('bbbbbbbb-0000-4000-8000-00000000000b') <> 'Athlete'
     or public.athlete_display_name('dddddddd-0000-4000-8000-00000000000d') <> 'Athlete'
     or public.athlete_display_name('eeeeeeee-0000-4000-8000-00000000000e') <> 'נועה' then
    raise exception 'FAIL: athlete_display_name placeholder rule';
  end if;
end $$;

set local role authenticated;

-- A name the athlete saves reaches the coach roster on the next read.
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
do $$ begin
  if (select display_name from public.coach_list_athletes()
      where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b') <> 'Athlete' then
    raise exception 'FAIL: unnamed athlete should read Athlete';
  end if;
end $$;
reset role;
update public.profiles set name = 'Yoav', updated_at = now()
  where auth_user_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-00000000000a');
do $$ begin
  if (select display_name from public.coach_list_athletes()
      where athlete_id = 'bbbbbbbb-0000-4000-8000-00000000000b') <> 'Yoav' then
    raise exception 'FAIL: renamed athlete not on roster';
  end if;
end $$;

-- set_coach_display_name: trims, saves own row, returns stored name.
do $$ begin
  if public.set_coach_display_name('  Dana Levi  ') <> 'Dana Levi' then
    raise exception 'FAIL: set_coach_display_name return value';
  end if;
  if (select display_name from public.coach_profiles where user_id = auth.uid()) <> 'Dana Levi' then
    raise exception 'FAIL: coach name not stored';
  end if;
  if public.set_coach_display_name('דנה לוי') <> 'דנה לוי' then
    raise exception 'FAIL: Hebrew coach name';
  end if;
  -- 40 code points is allowed.
  perform public.set_coach_display_name(repeat('a', 40));
end $$;
select pg_temp.expect_error($s$select public.set_coach_display_name('')$s$, '22023', 'blank name');
select pg_temp.expect_error($s$select public.set_coach_display_name(null)$s$, '22023', 'null name');
select pg_temp.expect_error($s$select public.set_coach_display_name('  Your Coach ')$s$, '22023', 'placeholder name');
select pg_temp.expect_error($s$select public.set_coach_display_name('athlete')$s$, '22023', 'athlete placeholder');
select pg_temp.expect_error($s$select public.set_coach_display_name(repeat('a', 41))$s$, '22023', '41 characters');
select public.set_coach_display_name('Dana');

-- The other coach's row is untouched.
reset role;
do $$ begin
  if (select display_name from public.coach_profiles
      where user_id = 'cccccccc-0000-4000-8000-00000000000c') <> 'Other' then
    raise exception 'FAIL: another coach row changed';
  end if;
end $$;
set local role authenticated;

-- Athletes are not coaches.
select pg_temp.act_as('bbbbbbbb-0000-4000-8000-00000000000b');
select pg_temp.expect_error($s$select public.set_coach_display_name('Mallory')$s$, '42501', 'athlete sets coach name');

-- Anonymous callers have no execute grant.
set local role anon;
select pg_temp.expect_error($s$select public.set_coach_display_name('Mallory')$s$, '42501', 'anonymous');

rollback;
