#!/usr/bin/env bash
# THROWAWAY DATABASES ONLY. Never run against production or staging.
#
# Two-connection race test for 20261127100000_coach_workout_locks.sql (C8.1a,
# M6a). coach_workout_locks.sql runs in one transaction and cannot show two
# sessions waiting on each other; this script commits real rows and does.
#
# Proves the lock order (link, then plan, then workout, then advisory):
#   1. A coach write holds the link row: a concurrent revoke waits for it.
#   2. A revoke that is already open: the coach write waits, then raises
#      link_inactive, and no workout is written.
#   3. A coach write holds the plan row: a concurrent plan deactivation waits.
#   4. A deactivation that is already open: the coach create waits, then raises
#      no_active_plan, and no workout is written.
#   5. An athlete account delete during a coach create that already holds the
#      link and plan: the delete waits on the athlete's auth.users row (lock 0)
#      instead of deadlocking, the create lands, then the delete cascades.
# Cases 2, 4 and 5 check pg_stat_activity that the waiting connection is really
# blocked on a lock before the competing transaction commits.
#
# CI: its own row in the pr-checks.yml db matrix. Locally, run after the same
# files as coach_workout_locks.sql, minus that suite:
#   psql "$DB_URL" -f supabase/tests/coach_workout_locks_fixture.sql
#   psql "$DB_URL" -f <the prerequisite migrations listed in coach_workout_locks.sql>
#   psql "$DB_URL" -f supabase/migrations/20261127100000_coach_workout_locks.sql
#   DB_URL=... bash supabase/tests/coach_workout_locks_race.sh
# Refuses to run if auth.users is not empty. Prints "coach_workout_locks_race: PASS".
set -euo pipefail

: "${DB_URL:?set DB_URL to a throwaway Postgres}"
P() { psql "$DB_URL" -v ON_ERROR_STOP=1 -q -t -A "$@"; }

A=aaaaaaaa-0000-4000-8000-00000000000a
B=bbbbbbbb-0000-4000-8000-00000000000b
PLAN=b1000000-0000-4000-8000-0000000000b1
W1=b0000001-0000-4000-8000-0000000000b1
AS_A="set role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$A','role','authenticated')::text, false), set_config('request.jwt.claim.sub', '$A', false), set_config('request.jwt.claim.role', 'authenticated', false);"
WAIT_SQL() { # $1 = statement; prints the seconds it waited
  echo "do \$w\$ declare t timestamptz := clock_timestamp(); begin $1; raise notice 'waited=%', round(extract(epoch from clock_timestamp() - t)::numeric, 1); end \$w\$;"
}
fail() { echo "FAIL: $*" >&2; exit 1; }
# Polls up to ~4s until the connection named $1 waits on a lock (optionally of type $2).
lock_wait() {
  local i n
  for i in $(seq 1 40); do
    n=$(P -c "select count(*) from pg_stat_activity where application_name = '$1' and wait_event_type = 'Lock' ${2:+and wait_event = '$2'}")
    [ "$n" = "1" ] && return 0
    sleep 0.1
  done
  return 1
}
PC() { PGAPPNAME=$1 psql "$DB_URL" -v ON_ERROR_STOP=1 -q -t -A "${@:2}"; }
waited() { sed -n 's/.*waited=\([0-9.]*\).*/\1/p' "$1"; }

[ "$(P -c 'select count(*) from auth.users')" = "0" ] || fail "auth.users is not empty; run only on a blank throwaway Postgres"

P <<SQL >/dev/null
insert into auth.users (id, email, aud, role) values
  ('$A', 'coach-a@example.com', 'authenticated', 'authenticated'),
  ('$B', 'athlete-b@example.com', 'authenticated', 'authenticated');
insert into public.coach_profiles (user_id, display_name) values ('$A', 'Dana');
insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values ('$A', '$B', 'active', now());
insert into public.client_capabilities (user_id, coach_v2, channel) values ('$A', true, 'testflight'), ('$B', true, 'testflight');
insert into public.plans (id, profile_id, auth_user_id, title, start_date, end_date, is_active)
  values ('$PLAN', '$B', '$B', 'B plan', current_date - 7, current_date + 60, true);
insert into public.workouts (id, plan_id, auth_user_id, week, day, type, distance, completed, scheduled_date)
  values ('$W1', '$PLAN', '$B', 2, to_char(current_date + 2, 'Dy'), 'easy', 5, false, current_date + 2);
SQL

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
relink() { P -c "update public.coach_athlete_links set status = 'active', revoked_at = null where coach_id = '$A' and athlete_id = '$B'" >/dev/null; }

# 1. Coach update holds the link; the revoke waits for it.
(P -c "begin; $AS_A select public.coach_update_workout('$W1', 0, 'tempo', 8, null, null, null, null); select pg_sleep(3); commit;" >"$T/1a" 2>&1) &
sleep 1
P -c "$(WAIT_SQL "update public.coach_athlete_links set status = 'revoked', revoked_at = now() where coach_id = '$A' and athlete_id = '$B'")" >"$T/1b" 2>&1
wait
w=$(waited "$T/1b")
awk "BEGIN{exit !($w >= 1.5)}" || fail "1: the revoke did not wait for the coach write (waited ${w}s)"
[ "$(P -c "select locked and coach_revision = 1 and type = 'tempo' from public.workouts where id = '$W1'")" = "t" ] \
  || fail "1: the coach write did not land"
echo "1. revoke waited ${w}s for the coach update; the update landed, then the link was revoked"
relink

# 2. Revoke is open first; the coach create waits, then raises link_inactive.
(P -c "begin; update public.coach_athlete_links set status = 'revoked', revoked_at = now() where coach_id = '$A' and athlete_id = '$B'; select pg_sleep(6); commit;" >"$T/2a" 2>&1) &
sleep 1
(PC race_coach -c "$AS_A $(WAIT_SQL "perform public.coach_create_workout('$B', 'c0000002-0000-4000-8000-0000000000c2', current_date + 10, 'easy', 5)")" >"$T/2b" 2>&1 || true) &
lock_wait race_coach || fail "2: the coach create was not waiting on a lock while the revoke was open"
wait
grep -q 'link_inactive' "$T/2b" || fail "2: expected link_inactive, got: $(cat "$T/2b")"
[ "$(P -c "select count(*) from public.workouts where id = 'c0000002-0000-4000-8000-0000000000c2'")" = "0" ] \
  || fail "2: a workout was written after the revoke"
echo "2. coach create waited for the open revoke, then raised link_inactive; no row written"
relink

# 3. Coach create holds the plan; the deactivation waits for it.
(P -c "begin; $AS_A select public.coach_create_workout('$B', 'c0000003-0000-4000-8000-0000000000c3', current_date + 11, 'easy', 5); select pg_sleep(3); commit;" >"$T/3a" 2>&1) &
sleep 1
P -c "$(WAIT_SQL "update public.plans set is_active = false where id = '$PLAN'")" >"$T/3b" 2>&1
wait
w=$(waited "$T/3b")
awk "BEGIN{exit !($w >= 1.5)}" || fail "3: the deactivation did not wait for the coach write (waited ${w}s)"
[ "$(P -c "select count(*) from public.workouts where id = 'c0000003-0000-4000-8000-0000000000c3' and locked")" = "1" ] \
  || fail "3: the coach create did not land"
echo "3. plan deactivation waited ${w}s for the coach create; the create landed first"
P -c "update public.plans set is_active = true where id = '$PLAN'" >/dev/null

# 4. Deactivation is open first; the coach create waits, then raises no_active_plan.
(P -c "begin; update public.plans set is_active = false where id = '$PLAN'; select pg_sleep(6); commit;" >"$T/4a" 2>&1) &
sleep 1
(PC race_coach -c "$AS_A $(WAIT_SQL "perform public.coach_create_workout('$B', 'c0000004-0000-4000-8000-0000000000c4', current_date + 12, 'easy', 5)")" >"$T/4b" 2>&1 || true) &
lock_wait race_coach || fail "4: the coach create was not waiting on a lock while the deactivation was open"
wait
grep -q 'no_active_plan' "$T/4b" || fail "4: expected no_active_plan, got: $(cat "$T/4b")"
[ "$(P -c "select count(*) from public.workouts where id = 'c0000004-0000-4000-8000-0000000000c4'")" = "0" ] \
  || fail "4: a workout was written on a deactivated plan"
echo "4. coach create waited for the open deactivation, then raised no_active_plan; no row written"
P -c "update public.plans set is_active = true where id = '$PLAN'" >/dev/null

# 5. Athlete account delete while a coach create holds locks 0-2. A third
#    connection holds the create's plan-day advisory lock (key 61), so the create
#    stops after taking the auth, link and plan locks. The delete then starts.
#    Without lock 0 the delete holds the athlete's auth.users row and waits on the
#    link; the create's insert then needs KEY SHARE on that auth row: deadlock.
D5="(current_date + 13)"
(P -c "begin; select pg_advisory_xact_lock(hashtextextended('$PLAN' || $D5::text, 61)); select pg_sleep(4); commit;" >"$T/5h" 2>&1) &
sleep 1
(PC race_coach -c "$AS_A select public.coach_create_workout('$B', 'c0000005-0000-4000-8000-0000000000c5', $D5, 'easy', 5);" >"$T/5c" 2>&1 || true) &
lock_wait race_coach advisory || fail "5: the coach create did not stop on the advisory lock"
(PC race_delete -c "delete from auth.users where id = '$B'" >"$T/5d" 2>&1 || true) &
lock_wait race_delete || fail "5: the account delete did not wait on the coach write"
wait
if grep -qi 'deadlock' "$T/5c" "$T/5d"; then fail "5: deadlock: $(cat "$T/5c" "$T/5d")"; fi
grep -q '^1$' "$T/5c" || fail "5: the coach create did not land first: $(cat "$T/5c")"
[ "$(P -c "select count(*) from auth.users where id = '$B'")" = "0" ] || fail "5: the athlete account was not deleted: $(cat "$T/5d")"
[ "$(P -c "select count(*) from public.workouts where auth_user_id = '$B'")" = "0" ] || fail "5: the delete did not cascade"
echo "5. account delete waited for the coach create (no deadlock); the create landed, then the delete cascaded"

echo "coach_workout_locks_race: PASS"
