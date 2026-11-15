-- Coach Mode, Story 1.3: an athlete joins a coach by invite code, with consent.
--
-- Creates coach_athlete_links and the authenticated RPCs lookup_invite(code)
-- and join_coach(code). Writes go through join_coach only. "Coach" here means a
-- HUMAN coach. It is unrelated to the AI coach (coach_message, coaching_style).
--
-- Web repo (Running-coach-): this same file must be copied to
-- v0/supabase/migrations/ so both migration trees stay in step.
-- Do not apply this to production from the app PR; Nadav applies it after review.
--
-- Depends on Story 1.2 (coach_profiles, coach_invites).
--
-- Idempotent: tables and indexes are create-if-not-exists, policies are dropped
-- only after their table exists, functions are create-or-replace.
--
-- Owner key: auth.users.id (the same value as profiles.auth_user_id), never the
-- legacy bigint profiles.id.

-- Table ----------------------------------------------------------------------

create table if not exists public.coach_athlete_links (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null references public.coach_profiles(user_id) on delete cascade,
  athlete_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('active', 'revoked')),
  consented_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

-- One active coach per athlete. Revoked rows may accumulate.
create unique index if not exists coach_athlete_links_one_active_per_athlete
  on public.coach_athlete_links (athlete_id) where status = 'active';

create index if not exists coach_athlete_links_coach_id_idx
  on public.coach_athlete_links (coach_id);

-- Row level security: the two parties can read; nobody writes from the client -----

alter table public.coach_athlete_links enable row level security;

revoke all on table public.coach_athlete_links from anon, authenticated;
grant select on table public.coach_athlete_links to authenticated;

drop policy if exists coach_athlete_links_select_own on public.coach_athlete_links;
create policy coach_athlete_links_select_own on public.coach_athlete_links
  for select to authenticated
  using (
    athlete_id = (select auth.uid())
    or coach_id = (select auth.uid())
  );

-- RPCs -----------------------------------------------------------------------

-- Coach name and id for an active code, case-insensitive. Zero rows when the
-- code is missing or inactive. Authenticated only.
create or replace function public.lookup_invite(code text)
returns table (coach_id uuid, display_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  return query
  select cp.user_id, cp.display_name
  from public.coach_invites ci
  join public.coach_profiles cp on cp.user_id = ci.coach_id
  where ci.active
    and upper(ci.code) = upper(btrim(lookup_invite.code));
end;
$$;

-- One transaction: reject a bad code, a self-join, or an athlete who already
-- has an active link (already_linked, with that coach's name). Otherwise insert
-- status = active and consented_at = now().
create or replace function public.join_coach(code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_coach uuid;
  v_name text;
  v_active boolean;
  v_existing_coach uuid;
  v_existing_name text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select ci.coach_id, cp.display_name, ci.active
    into v_coach, v_name, v_active
  from public.coach_invites ci
  join public.coach_profiles cp on cp.user_id = ci.coach_id
  where upper(ci.code) = upper(btrim(join_coach.code))
  limit 1;

  if not found or v_active is not true then
    raise exception 'invalid_code' using errcode = 'P0001';
  end if;

  if v_coach = v_uid then
    raise exception 'cannot_join_self' using errcode = 'P0001';
  end if;

  select l.coach_id, cp.display_name
    into v_existing_coach, v_existing_name
  from public.coach_athlete_links l
  join public.coach_profiles cp on cp.user_id = l.coach_id
  where l.athlete_id = v_uid
    and l.status = 'active';

  if found then
    return jsonb_build_object(
      'status', 'already_linked',
      'coach_id', v_existing_coach,
      'display_name', v_existing_name
    );
  end if;

  insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at)
  values (v_coach, v_uid, 'active', now());

  return jsonb_build_object(
    'status', 'joined',
    'coach_id', v_coach,
    'display_name', v_name
  );
end;
$$;

-- The athlete cannot read coach_profiles (Story 1.2 is select-own). This is how
-- the app reads "who am I linked to" including the coach's name.
create or replace function public.my_coach_link()
returns table (link_id uuid, coach_id uuid, display_name text, status text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  return query
  select l.id, l.coach_id, cp.display_name, l.status
  from public.coach_athlete_links l
  join public.coach_profiles cp on cp.user_id = l.coach_id
  where l.athlete_id = v_uid
    and l.status = 'active';
end;
$$;

revoke all on function public.lookup_invite(text) from public, anon;
revoke all on function public.join_coach(text) from public, anon;
revoke all on function public.my_coach_link() from public, anon;
grant execute on function public.lookup_invite(text) to authenticated;
grant execute on function public.join_coach(text) to authenticated;
grant execute on function public.my_coach_link() to authenticated;
