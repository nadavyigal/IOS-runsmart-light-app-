-- Rollback for 20261121110000_coach_consent_v2.sql (C7.8, M5a, Batch A).
--
-- NADAV ONLY. Agents never run this file. Read docs/coach-v2-rollback.md first:
-- flipping runtime_flags.coach_v2 to false is the first move, and it needs no
-- rollback at all. Use this file only when the M5a functions themselves are
-- broken.
--
-- Do not run it while a later Batch A file that calls coach_v2_sharing_allowed
-- is applied (M1a and later). Roll back newer files first, newest first.
--
-- Data-preserving:
--   * join_coach goes back to Story 1.3's body (same signature, same payload), so
--     every client keeps joining. New joins get consent_version = 1 from the
--     column default.
--   * The M5a functions are dropped: join_coach_v2, coach_invite_consent_version,
--     ack_coach_consent, my_coach_consent_status, coach_v2_sharing_allowed.
--   * coach_athlete_links.consent_version and consent_acknowledged_at stay, with
--     their values and both check constraints. Every ack an athlete gave is kept.
--     Re-applying the migration later finds them and changes nothing.
--
-- What clients see after this runs: v2 apps fail my_coach_consent_status, so the
-- P9 notice never shows; coach_invite_consent_version fails, so the join screen
-- falls back to the A3 copy and Story 1.3's join_coach. 1.2.6 apps see no change.

begin;

create or replace function public.join_coach(
  code text,
  expected_invite_id uuid,
  expected_coach_id uuid,
  expected_athlete_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_invite uuid;
  v_coach uuid;
  v_name text;
  v_active boolean;
  v_existing_coach uuid;
  v_existing_name text;
  v_link_id uuid;
  v_consented_at timestamptz;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if v_uid is distinct from expected_athlete_id then
    raise exception 'consenting athlete changed' using errcode = '42501';
  end if;

  select ci.id, ci.coach_id, cp.display_name, ci.active
    into v_invite, v_coach, v_name, v_active
  from public.coach_invites ci
  join public.coach_profiles cp on cp.user_id = ci.coach_id
  where upper(ci.code) = upper(btrim(join_coach.code))
  limit 1
  for share of ci;

  if not found or v_active is not true then
    raise exception 'invalid_code' using errcode = 'P0001';
  end if;

  if v_invite is distinct from expected_invite_id
     or v_coach is distinct from expected_coach_id then
    raise exception 'consent_mismatch' using errcode = 'P0001';
  end if;

  if v_coach = v_uid then
    raise exception 'cannot_join_self' using errcode = 'P0001';
  end if;

  insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at)
  values (v_coach, v_uid, 'active', now())
  on conflict (athlete_id) where status = 'active' do nothing
  returning id, consented_at into v_link_id, v_consented_at;

  if found then
    return jsonb_build_object(
      'status', 'joined',
      'link_id', v_link_id,
      'consented_at', v_consented_at,
      'coach_id', v_coach,
      'display_name', v_name
    );
  end if;

  select l.coach_id, cp.display_name
    into v_existing_coach, v_existing_name
  from public.coach_athlete_links l
  join public.coach_profiles cp on cp.user_id = l.coach_id
  where l.athlete_id = v_uid
    and l.status = 'active';

  if not found then
    raise exception 'active link changed' using errcode = '40001';
  end if;

  return jsonb_build_object(
    'status', 'already_linked',
    'coach_id', v_existing_coach,
    'display_name', v_existing_name
  );
end;
$$;

revoke all on function public.join_coach(text, uuid, uuid, uuid) from public, anon;
grant execute on function public.join_coach(text, uuid, uuid, uuid) to authenticated;

drop function if exists public.my_coach_consent_status();
drop function if exists public.ack_coach_consent(integer);
drop function if exists public.coach_invite_consent_version(text);
drop function if exists public.join_coach_v2(text, uuid, uuid, uuid, integer);
drop function if exists public.coach_v2_sharing_allowed(uuid, uuid);

-- Optional, NOT part of the default rollback. This deletes every ack athletes
-- gave. Export first if you ever need it, then remove the leading "-- " to run:
-- alter table public.coach_athlete_links drop constraint if exists coach_athlete_links_consent_ack_required;
-- alter table public.coach_athlete_links drop constraint if exists coach_athlete_links_consent_version_min;
-- alter table public.coach_athlete_links drop column if exists consent_acknowledged_at;
-- alter table public.coach_athlete_links drop column if exists consent_version;

commit;
