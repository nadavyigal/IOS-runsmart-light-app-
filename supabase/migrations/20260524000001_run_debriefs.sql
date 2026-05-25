-- supabase/migrations/20260524000001_run_debriefs.sql
create table if not exists public.run_debriefs (
  id           uuid        primary key default gen_random_uuid(),
  auth_user_id uuid        not null references auth.users(id) on delete cascade,
  run_id       uuid        not null references public.runs(id) on delete cascade,
  headline     text        not null,
  debrief      text        not null,
  tomorrow     text        not null,
  plan_impact  text,
  source       text        not null default 'ai',
  created_at   timestamptz not null default now()
);

-- One debrief per run per user; re-running processCompletedActivity upserts safely
create unique index if not exists run_debriefs_user_run_uidx
  on public.run_debriefs (auth_user_id, run_id);

alter table public.run_debriefs enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'run_debriefs'
      and policyname = 'owner_all'
  ) then
    create policy "owner_all" on public.run_debriefs
      for all
      using  (auth_user_id = auth.uid())
      with check (auth_user_id = auth.uid());
  end if;
end
$$;
