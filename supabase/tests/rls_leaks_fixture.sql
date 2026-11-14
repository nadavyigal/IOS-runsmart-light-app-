-- THROWAWAY DATABASES ONLY. Never run against production or staging.
--
-- Recreates the parts of the production schema that rls_leaks.sql exercises:
-- the six tables (only the columns the policies and test touch) with the
-- production policies as listed on 2026-11-14, plus the older broad policies
-- and a web 007 admin-read policy so the migration has something to drop.
-- Needed because these tables are created by the web repo's migrations, not
-- this repo's, so a bare local Postgres has none of them.
--
-- Expects a supabase/postgres image (roles anon/authenticated/service_role,
-- auth.users, auth.uid(), auth.role()).

create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;
grant execute on function auth.jwt() to anon, authenticated, service_role;

create table if not exists public.analytics_events (
  id uuid primary key default gen_random_uuid(),
  event_name text not null,
  user_id text,
  properties jsonb not null default '{}'::jsonb,
  "timestamp" timestamptz not null default now()
);

create table if not exists public.idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  key text not null,
  profile_id uuid not null,
  operation_type text not null,
  result jsonb
);

create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null,
  auth_user_id uuid references auth.users(id) on delete cascade,
  title text not null
);

create table if not exists public.workouts (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans(id) on delete cascade,
  auth_user_id uuid references auth.users(id) on delete cascade,
  completed boolean not null default false
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null,
  auth_user_id uuid references auth.users(id)
);

create table if not exists public.conversation_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  auth_user_id uuid references auth.users(id),
  role text not null,
  content text not null
);

create table if not exists public.runs (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid
);

alter table public.analytics_events enable row level security;
alter table public.idempotency_keys enable row level security;
alter table public.plans enable row level security;
alter table public.workouts enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_messages enable row level security;
alter table public.runs enable row level security;

grant all on public.analytics_events, public.idempotency_keys, public.plans,
  public.workouts, public.conversations, public.conversation_messages,
  public.runs
  to anon, authenticated, service_role;

-- Production policies (pg_policies, 2026-11-14) -------------------------------
create policy "Allow anonymous event inserts" on public.analytics_events
  for insert to anon with check (true);
create policy "Authenticated users can insert events" on public.analytics_events
  for insert to authenticated with check (true);
create policy "Authenticated users can view all events" on public.analytics_events
  for select to authenticated using (true);
create policy "Service role has full access" on public.analytics_events
  for all to service_role using (true) with check (true);

create policy "Authenticated users can manage idempotency keys" on public.idempotency_keys
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "Service role full access to idempotency_keys" on public.idempotency_keys
  for all using ((auth.jwt() ->> 'role') = 'service_role');

create policy "Service role full access to plans" on public.plans
  for all using ((auth.jwt() ->> 'role') = 'service_role');
create policy plans_owner_access on public.plans
  for all to authenticated
  using ((auth_user_id = (select auth.uid())) or (profile_id = (select auth.uid())))
  with check ((auth_user_id = (select auth.uid())) and (profile_id = (select auth.uid())));

create policy "Service role full access to workouts" on public.workouts
  for all using ((auth.jwt() ->> 'role') = 'service_role');
create policy workouts_owner_access on public.workouts
  for all to authenticated
  using ((auth_user_id = (select auth.uid())) or exists (
    select 1 from public.plans p where p.id = workouts.plan_id
      and ((p.auth_user_id = (select auth.uid())) or (p.profile_id = (select auth.uid())))))
  with check ((auth_user_id = (select auth.uid())) and exists (
    select 1 from public.plans p where p.id = workouts.plan_id
      and ((p.auth_user_id = (select auth.uid())) or (p.profile_id = (select auth.uid())))));

create policy "Service role full access to conversations" on public.conversations
  for all using ((auth.jwt() ->> 'role') = 'service_role');
create policy conversations_insert_own on public.conversations
  for insert to authenticated
  with check ((auth_user_id = auth.uid()) or (profile_id = auth.uid()));
create policy conversations_select_own on public.conversations
  for select to authenticated
  using ((auth_user_id = auth.uid()) or (profile_id = auth.uid()));
create policy conversations_update_own on public.conversations
  for update to authenticated
  using ((auth_user_id = auth.uid()) or (profile_id = auth.uid()))
  with check ((auth_user_id = auth.uid()) or (profile_id = auth.uid()));

create policy "Service role full access to conversation_messages" on public.conversation_messages
  for all using ((auth.jwt() ->> 'role') = 'service_role');
create policy conversation_messages_insert_own on public.conversation_messages
  for insert to authenticated
  with check ((auth_user_id = auth.uid()) and exists (
    select 1 from public.conversations c where c.id = conversation_messages.conversation_id
      and ((c.auth_user_id = auth.uid()) or (c.profile_id = auth.uid()))));
create policy conversation_messages_select_own on public.conversation_messages
  for select
  using (auth_user_id = coalesce(
    (nullif(current_setting('request.jwt.claim.sub', true), ''))::uuid,
    ((nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid));

-- Older broad policies not live in production, but present in some environments
create policy "Authenticated users can manage plans" on public.plans
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "Authenticated users can manage workouts" on public.workouts
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "Authenticated users can manage conversations" on public.conversations
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "Authenticated users can read messages" on public.conversation_messages
  for select using (auth.role() = 'authenticated');
create policy "Admins can view all runs" on public.runs
  for select using (exists (
    select 1 from auth.users where auth.users.id = auth.uid()
      and auth.users.raw_user_meta_data ->> 'role' = 'admin'));
