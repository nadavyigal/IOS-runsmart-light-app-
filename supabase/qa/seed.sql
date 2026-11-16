-- Synthetic accounts for the generated, isolated local stack.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_admin')
     or to_regclass('public.runsmart_local_qa_marker') is null then
    raise exception 'Seed requires the RunSmart local QA bootstrap';
  end if;
end $$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
)
select '00000000-0000-0000-0000-000000000000', id::uuid, 'authenticated', 'authenticated',
       email, extensions.crypt('LocalCoachQA123!', extensions.gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', name),
       now(), now(), '', '', '', '', '', '', '', ''
from (values
  ('10000000-0000-4000-8000-000000000001','coach@qa.example.test','Dana QA'),
  ('10000000-0000-4000-8000-000000000002','athlete1@qa.example.test','Ari QA'),
  ('10000000-0000-4000-8000-000000000003','athlete2@qa.example.test','Noa QA')
) v(id,email,name)
on conflict (id) do nothing;

insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), id::text, id, jsonb_build_object('sub',id,'email',email,'email_verified',true),
       'email', now(), now(), now()
from auth.users where email in ('coach@qa.example.test','athlete1@qa.example.test','athlete2@qa.example.test')
on conflict (provider_id,provider) do nothing;

insert into public.profiles (auth_user_id,email,name,onboarding_complete)
select id,email,raw_user_meta_data->>'display_name',true
from auth.users where email in ('coach@qa.example.test','athlete1@qa.example.test','athlete2@qa.example.test')
on conflict (auth_user_id) do update set onboarding_complete = true;

insert into public.coach_profiles (user_id,display_name)
values ('10000000-0000-4000-8000-000000000001','Dana QA') on conflict (user_id) do nothing;

insert into public.coach_invites (id, coach_id, code, active)
values ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','QA2345',true)
on conflict (id) do nothing;

insert into public.plans (id,profile_id,auth_user_id,title,start_date,end_date,total_weeks,is_active,plan_type)
select format('30000000-0000-4000-8000-00000000000%s', n)::uuid, u, u,
       'Local QA training plan', current_date - 6, current_date + 21, 4, true, 'adaptive'
from (values
  (2,'10000000-0000-4000-8000-000000000002'::uuid),
  (3,'10000000-0000-4000-8000-000000000003'::uuid)
) v(n,u) on conflict (id) do nothing;

insert into public.workouts (id,plan_id,auth_user_id,week,day,type,distance,duration,pace,scheduled_date,completed)
select format('40000000-0000-4000-8000-0000000000%s%s', n, w)::uuid,
       format('30000000-0000-4000-8000-00000000000%s', n)::uuid,
       format('10000000-0000-4000-8000-00000000000%s', n)::uuid,
       1,w,'easy',5+w,35,360,current_date+w-2,false
from generate_series(2,3) n cross join generate_series(1,3) w
on conflict (id) do nothing;

insert into public.runs (auth_user_id,profile_id,type,distance,duration,pace,heart_rate,completed_at,source_provider,source_activity_id)
select auth_user_id,id,'easy',6.0,2160,360,141,now() - interval '1 day','healthkit',
       'local-qa-' || auth_user_id::text
from public.profiles where email in ('athlete1@qa.example.test','athlete2@qa.example.test')
on conflict (source_provider,source_activity_id) do nothing;
