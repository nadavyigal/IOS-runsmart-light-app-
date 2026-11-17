-- Minimal legacy runs table for a blank, throwaway Supabase database.
do $$
begin
  if to_regclass('public.runs') is not null or exists (select 1 from auth.users) then
    raise exception 'Coach route fixture requires an empty throwaway Supabase database';
  end if;
end $$;

create table public.runs (
  auth_user_id uuid not null references auth.users(id),
  source_provider text not null,
  source_activity_id text not null,
  completed_at timestamptz not null,
  route jsonb,
  primary key (source_provider, source_activity_id)
);
alter table public.runs enable row level security;
