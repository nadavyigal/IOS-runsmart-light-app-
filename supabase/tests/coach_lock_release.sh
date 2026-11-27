#!/usr/bin/env bash
# THROWAWAY DATABASES ONLY. Never run against production or staging.
#
# Test for supabase/rollback/release_all_coach_locks.sql (C8.1a, M6a). The
# script commits, so this runs it for real against seeded rows.
#
# Proves:
#   1. Lock order: with a plan held FOR SHARE (as a coach write holds it), the
#      script waits on the plan before it locks any workout, so it cannot
#      deadlock with a coach write.
#   2. The single-athlete release finds the athlete's rows through the plan, so a
#      locked workout with a null auth_user_id is released too, and another
#      athlete's lock neither stops nor rolls back the run.
#   3. The all-athletes release then unlocks the rest.
#
# CI: its own row in the pr-checks.yml db matrix. Locally, run after the same
# files as coach_workout_locks.sql, minus that suite:
#   psql "$DB_URL" -f supabase/tests/coach_workout_locks_fixture.sql
#   psql "$DB_URL" -f <the prerequisite migrations listed in coach_workout_locks.sql>
#   psql "$DB_URL" -f supabase/migrations/20261127100000_coach_workout_locks.sql
#   DB_URL=... bash supabase/tests/coach_lock_release.sh
# Refuses to run if auth.users is not empty. Prints "coach_lock_release: PASS".
set -euo pipefail

: "${DB_URL:?set DB_URL to a throwaway Postgres}"
P() { psql "$DB_URL" -v ON_ERROR_STOP=1 -q -t -A "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/rollback/release_all_coach_locks.sql"

X=11111111-0000-4000-8000-000000000001
Y=22222222-0000-4000-8000-000000000002
PX=11111111-0000-4000-8000-0000000000a1
PY=22222222-0000-4000-8000-0000000000a2

[ "$(P -c 'select count(*) from auth.users')" = "0" ] || fail "auth.users is not empty; run only on a blank throwaway Postgres"

P <<SQL >/dev/null
insert into auth.users (id, aud, role) values ('$X', 'authenticated', 'authenticated'), ('$Y', 'authenticated', 'authenticated');
insert into public.plans (id, profile_id, auth_user_id, title, start_date, end_date, is_active) values
  ('$PX', '$X', '$X', 'x', current_date, current_date + 30, true),
  ('$PY', '$Y', '$Y', 'y', current_date, current_date + 30, true);
begin;
select set_config('runsmart.coach_write', 'on', true);
insert into public.workouts (plan_id, auth_user_id, type, distance, scheduled_date, locked, source, coach_revision) values
  ('$PX', '$X', 'tempo', 8, current_date + 2, true, 'coach', 3),
  ('$PX', '$X', 'rest', 0, current_date + 3, true, 'coach', 1),
  ('$PX', null, 'easy', 5, current_date + 5, true, 'coach', 1),
  ('$PY', '$Y', 'long', 14, current_date + 4, true, 'coach', 2);
commit;
SQL

locked() { P -c "select count(*) from public.workouts w left join public.plans p on p.id = w.plan_id where w.locked and coalesce(w.auth_user_id, p.auth_user_id, p.profile_id) = '$1'"; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
sed "s/set_config('runsmart.release_athlete', '', true)/set_config('runsmart.release_athlete', '$X', true)/" "$SCRIPT" >"$T/release_x.sql"
grep -q "release_athlete', '$X'" "$T/release_x.sql" || fail "could not set RELEASE_ATHLETE in a copy of the script"

# 1 + 2. Hold X's plan FOR SHARE, start the single-athlete release, and check it
#        waits on the plan while every workout is still unlocked by it.
(P -c "begin; select 1 from public.plans where id = '$PX' for share; select pg_sleep(4); commit;" >"$T/hold" 2>&1) &
sleep 1
(PGAPPNAME=race_release psql "$DB_URL" -v ON_ERROR_STOP=1 -q -t -A -f "$T/release_x.sql" >"$T/rx" 2>&1 || true) &
waiting=0
for i in $(seq 1 30); do
  [ "$(P -c "select count(*) from pg_stat_activity where application_name = 'race_release' and wait_event_type = 'Lock'")" = "1" ] && { waiting=1; break; }
  sleep 0.1
done
[ "$waiting" = "1" ] || fail "1: the release did not wait on the held plan"
P -c "begin; select id from public.workouts where plan_id = '$PX' for update nowait; rollback;" >/dev/null 2>"$T/nowait" \
  || fail "1: the release locked a workout before its plan: $(cat "$T/nowait")"
wait
grep -q 'release_all_coach_locks: 3 locked workouts before' "$T/rx" || fail "2: expected 3 rows for X (one with a null auth_user_id): $(cat "$T/rx")"
grep -q 'release_all_coach_locks: 0 locked workouts after' "$T/rx" || fail "2: the single-athlete release did not finish: $(cat "$T/rx")"
[ "$(locked "$X")" = "0" ] || fail "2: X still has locked rows"
[ "$(locked "$Y")" = "1" ] || fail "2: the single-athlete release touched Y"
echo "1. release waited on the held plan before locking any workout"
echo "2. single-athlete release for X: 3 before (one null auth_user_id) / 0 after; Y still locked"

# 3. All athletes.
P -f "$SCRIPT" >"$T/rall" 2>&1 || fail "3: $(cat "$T/rall")"
grep -q 'release_all_coach_locks: 1 locked workouts before' "$T/rall" || fail "3: expected 1 row left: $(cat "$T/rall")"
[ "$(P -c 'select count(*) from public.workouts where locked')" = "0" ] || fail "3: rows still locked"
[ "$(P -c "select count(*) from public.workouts where source = 'coach' and type in ('tempo', 'rest', 'easy', 'long')")" = "4" ] \
  || fail "3: the release changed planned fields or source"
echo "3. all-athletes release: 1 before / 0 after; planned fields and source kept"

echo "coach_lock_release: PASS"
