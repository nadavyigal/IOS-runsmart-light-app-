-- Story 3.4. Blank throwaway Postgres only. See the coach_welcome_note CI matrix
-- entry for the fixture and ordered migrations. Apply the story migration twice.

begin;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'coach_welcome_note.sql requires a blank throwaway Postgres';
  end if;
end $$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'coach@example.com', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'early@example.com', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'yona@example.com', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'nameless@example.com', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-4000-8000-000000000005', 'revoked@example.com', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-4000-8000-000000000006', 'unlinked@example.com', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-4000-8000-000000000007', 'prior-override@example.com', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-4000-8000-000000000008', 'rejoin@example.com', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-4000-8000-000000000009', 'longname@example.com', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-4000-8000-000000000010', 'rejoin-override@example.com', 'authenticated', 'authenticated');

insert into public.coach_profiles (user_id, display_name)
values ('aaaaaaaa-0000-4000-8000-000000000001', 'Dana');
insert into public.profiles (auth_user_id, name)
values ('aaaaaaaa-0000-4000-8000-000000000003', 'יונה לוי');
insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at)
select 'aaaaaaaa-0000-4000-8000-000000000001', id,
       case when email = 'revoked@example.com' then 'revoked' else 'active' end, now()
from auth.users where email in ('early@example.com', 'yona@example.com', 'nameless@example.com',
                               'revoked@example.com', 'prior-override@example.com',
                               'rejoin@example.com', 'longname@example.com', 'rejoin-override@example.com');
insert into public.profiles (auth_user_id, name)
values ('aaaaaaaa-0000-4000-8000-000000000009', repeat('x', 300) || ' Levi');
-- The rejoining athlete left an earlier link with the same coach, and read that link's welcome.
insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at, revoked_at, welcome_claimed_at)
select 'aaaaaaaa-0000-4000-8000-000000000001', a::uuid, 'revoked',
       now() - interval '10 days', now() - interval '5 days', now() - interval '10 days'
from unnest(array['aaaaaaaa-0000-4000-8000-000000000008', 'aaaaaaaa-0000-4000-8000-000000000010']) a;
insert into public.coach_feedback (coach_id, athlete_id, kind, text, created_at, read_at)
select 'aaaaaaaa-0000-4000-8000-000000000001', a::uuid, 'welcome',
       'Old welcome', now() - interval '10 days', now() - interval '9 days'
from unnest(array['aaaaaaaa-0000-4000-8000-000000000008', 'aaaaaaaa-0000-4000-8000-000000000010']) a;

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
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000002');
select pg_temp.expect_error($q$select public.set_welcome_template('Hi')$q$, '42501', 'only coaches can set a template');
select public.claim_welcome_note();
do $$
begin
  if exists (select 1 from public.my_coach_feedback())
     or not exists (select 1 from public.coach_athlete_links
                    where athlete_id = auth.uid() and welcome_claimed_at is not null) then
    raise exception 'FAIL: an empty claim must record the attempt and produce no row';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000001');
select pg_temp.expect_error(
  $q$update public.coach_profiles set welcome_template = 'direct'$q$, '42501', 'no direct template writes');
select pg_temp.expect_error(
  $q$select public.coach_set_athlete_welcome('aaaaaaaa-0000-4000-8000-000000000005', 'No')$q$,
  '42501', 'revoked link cannot receive an override');
select pg_temp.expect_error(
  $q$select public.coach_set_athlete_welcome('aaaaaaaa-0000-4000-8000-000000000006', 'No')$q$,
  '42501', 'unlinked athlete cannot receive an override');
select public.set_welcome_template(E'  Hello, {first name}!\n\nSee you Sunday.\n ');
select public.coach_set_athlete_welcome('aaaaaaaa-0000-4000-8000-000000000007', 'An early override.');
do $$
begin
  if (select saved_text from public.get_coach_welcome()) is distinct from E'Hello, {first name}!\n\nSee you Sunday.' then
    raise exception 'FAIL: template should load in the editor with surrounding space trimmed';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000002');
select public.claim_welcome_note();
do $$
begin
  if exists (select 1 from public.my_coach_feedback()) then
    raise exception 'FAIL: a later template must not reach an athlete who already claimed';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000003');
select public.claim_welcome_note();
select public.claim_welcome_note();
do $$
begin
  if (select count(*) from public.my_coach_feedback()) <> 1
     or not exists (select 1 from public.my_coach_feedback()
                    where kind = 'welcome' and coach_name = 'Dana'
                      and run_id is null and week_start is null and read_at is null
                      and text = E'Hello, יונה!\n\nSee you Sunday.') then
    raise exception 'FAIL: two claims must yield one signed welcome with the first name substituted';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000008');
select public.claim_welcome_note();
do $$
begin
  if (select count(*) from public.my_coach_feedback()) <> 1
     or not exists (select 1 from public.my_coach_feedback()
                    where kind = 'welcome' and read_at is null and edited_at is null
                      and text = E'Hello!\n\nSee you Sunday.' and created_at >= now()) then
    raise exception 'FAIL: a returning athlete must get a fresh, unread welcome for the new link';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000001');
do $$
begin
  if (select row(saved_text, can_edit) from public.get_coach_welcome('aaaaaaaa-0000-4000-8000-000000000010'))
       is distinct from row(null::text, true) then
    raise exception 'FAIL: a welcome from an earlier link must not lock the editor';
  end if;
end $$;
select public.coach_set_athlete_welcome('aaaaaaaa-0000-4000-8000-000000000010', 'Welcome back!');
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000010');
select public.claim_welcome_note();
do $$
begin
  if (select count(*) from public.my_coach_feedback()) <> 1
     or not exists (select 1 from public.my_coach_feedback()
                    where text = 'Welcome back!' and read_at is null and edited_at is null) then
    raise exception 'FAIL: an override after rejoining must replace the old welcome as unread and survive the claim';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000009');
select public.claim_welcome_note();
do $$
begin
  if (select text from public.my_coach_feedback())
       is distinct from E'Hello, ' || repeat('x', 40) || E'!\n\nSee you Sunday.' then
    raise exception 'FAIL: the substituted first name must be capped at 40 characters';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000004');
select public.claim_welcome_note();
do $$
begin
  if (select text from public.my_coach_feedback()) is distinct from E'Hello!\n\nSee you Sunday.' then
    raise exception 'FAIL: missing first name must leave natural punctuation and preserve paragraphs';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000007');
select public.claim_welcome_note();
do $$
begin
  if (select text from public.my_coach_feedback()) is distinct from 'An early override.' then
    raise exception 'FAIL: claiming must preserve an existing override';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000001');
select public.coach_set_athlete_welcome('aaaaaaaa-0000-4000-8000-000000000003', 'Glad you joined, {first name}!');
do $$
begin
  if (select saved_text from public.get_coach_welcome('aaaaaaaa-0000-4000-8000-000000000003'))
       is distinct from 'Glad you joined, יונה!'
     or (select saved_text from public.get_coach_welcome('aaaaaaaa-0000-4000-8000-000000000004'))
       is distinct from E'Hello!\n\nSee you Sunday.'
     or (select saved_text from public.get_coach_welcome())
       is distinct from E'Hello, {first name}!\n\nSee you Sunday.' then
    raise exception 'FAIL: override must update only the intended athlete';
  end if;
  if (select default_text from public.get_coach_welcome('aaaaaaaa-0000-4000-8000-000000000003'))
       is distinct from E'Hello, {first name}!\n\nSee you Sunday.' then
    raise exception 'FAIL: the per-athlete editor must receive the coach template as its default';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000003');
select public.mark_feedback_read((select id from public.my_coach_feedback() where kind = 'welcome'));
select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000001');
select pg_temp.expect_error(
  $q$select public.coach_set_athlete_welcome('aaaaaaaa-0000-4000-8000-000000000003', 'Too late')$q$,
  'P0001', 'read welcome cannot be updated');
select pg_temp.expect_error(
  $q$select public.coach_edit_feedback((select id from public.coach_feedback
      where athlete_id = 'aaaaaaaa-0000-4000-8000-000000000003' and kind = 'welcome'), 'Too late')$q$,
  'P0002', 'ordinary note edit cannot bypass welcome read lock');
do $$
begin
  if (select can_edit from public.get_coach_welcome('aaaaaaaa-0000-4000-8000-000000000003')) is distinct from false then
    raise exception 'FAIL: the editor must report a read welcome as locked';
  end if;
end $$;
select public.set_welcome_template(E' \n\t ');
do $$
begin
  if (select saved_text from public.get_coach_welcome()) is not null then
    raise exception 'FAIL: empty input must clear the saved template';
  end if;
end $$;

select pg_temp.act_as('aaaaaaaa-0000-4000-8000-000000000006');
select pg_temp.expect_error($q$select public.claim_welcome_note()$q$, '42501', 'unlinked athlete cannot claim');
select pg_temp.expect_error(
  $q$select * from public.get_coach_welcome('aaaaaaaa-0000-4000-8000-000000000003')$q$,
  '42501', 'another user cannot load the editor');
do $$
begin
  if exists (select 1 from public.my_coach_feedback()) or exists (select 1 from public.coach_feedback) then
    raise exception 'FAIL: another user must not see the welcome';
  end if;
end $$;

reset role;
do $$
declare
  signature text;
begin
  foreach signature in array array[
    'public.set_welcome_template(text)', 'public.claim_welcome_note()',
    'public.coach_set_athlete_welcome(uuid,text)', 'public.get_coach_welcome(uuid)',
    'public.my_coach_feedback()'
  ] loop
    if pg_catalog.has_function_privilege('anon', signature, 'EXECUTE')
       or not pg_catalog.has_function_privilege('authenticated', signature, 'EXECUTE') then
      raise exception 'FAIL: unexpected execute grants for %', signature;
    end if;
  end loop;
  if pg_catalog.has_function_privilege('authenticated', 'public.render_coach_welcome(text,uuid)', 'EXECUTE') then
    raise exception 'FAIL: authenticated can execute internal helper';
  end if;
end $$;

rollback;
