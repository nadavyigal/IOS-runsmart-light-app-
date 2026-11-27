#!/usr/bin/env bash
# THROWAWAY DATABASES ONLY. Never run against production or staging.
#
# Two-connection race test for 20261127110000_coach_plan_locks.sql (C8.1b, M6b).
# coach_plan_locks.sql runs in one transaction and cannot show two sessions
# waiting on each other; this script commits real rows and does.
#
# Proves:
#   1. While a coach account delete holds the coach's auth.users row,
#      athlete_replace_training_plan waits at its first lock (auth KEY SHARE)
#      and holds no plan or workout lock, so the delete's cascade (which locks
#      the athlete's plans) cannot deadlock with it.
#   2. The same for athlete_change_coach_workout.
#   3. A real coach account delete and a plan replacement, either order, finish
#      without a deadlock: replace first, the delete waits and then unlocks the
#      rows; delete first, the replace waits and then raises count_changed
#      (the delete released the locked rows the athlete had counted).
#   4. A retry of a skip that starts before the original commits, while the link
#      ends in between, returns 'duplicate' (not link_inactive); one event.
#   5. A plain plan deactivation that waits on a coach create sees the new
#      locked row once the coach commits (coach_workouts_present).
#   6, 7. leave_coach and coach_remove_athlete take the auth.users rows before
#      the link, so a concurrent account delete cannot deadlock with them.
#
# Run after the same files as coach_plan_locks.sql, minus that suite:
#   psql "$DB_URL" -f supabase/tests/coach_plan_locks_fixture.sql
#   psql "$DB_URL" -f <the prerequisite migrations listed in coach_plan_locks.sql>
#   psql "$DB_URL" -f supabase/migrations/20261127110000_coach_plan_locks.sql
#   DB_URL=... bash supabase/tests/coach_plan_locks_race.sh
# Refuses to run if auth.users is not empty. Prints "coach_plan_locks_race: PASS".
set -euo pipefail

: "${DB_URL:?set DB_URL to a throwaway Postgres}"
P() { psql "$DB_URL" -v ON_ERROR_STOP=1 -q -t -A "$@"; }

A=aaaaaaaa-0000-4000-8000-00000000000a
B=bbbbbbbb-0000-4000-8000-00000000000b
PLAN=b1000000-0000-4000-8000-0000000000b1
W1=b0000001-0000-4000-8000-0000000000b1
W2=b0000002-0000-4000-8000-0000000000b2
claims() { echo "set role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, false), set_config('request.jwt.claim.sub', '$1', false), set_config('request.jwt.claim.role', 'authenticated', false);"; }
AS_A=$(claims $A)
AS_B=$(claims $B)
WAIT_SQL() { # $1 = statement; prints the seconds it waited
  echo "do \$w\$ declare t timestamptz := clock_timestamp(); begin $1; raise notice 'waited=%', round(extract(epoch from clock_timestamp() - t)::numeric, 1); end \$w\$;"
}
fail() { echo "FAIL: $*" >&2; exit 1; }
waited() { sed -n 's/.*waited=\([0-9.]*\).*/\1/p' "$1"; }
REPLACE_SQL() { # $1 = acknowledged count
  echo "public.athlete_replace_training_plan('$B', jsonb_build_object('title','New','start_date',current_date,'end_date',current_date + 28,'total_weeks',4), jsonb_build_array(jsonb_build_object('week',1,'day',to_char(current_date + 1,'Dy'),'type','easy','distance',5,'scheduled_date',current_date + 1)), $1)"
}

[ "$(P -c 'select count(*) from auth.users')" = "0" ] || fail "auth.users is not empty; run only on a blank throwaway Postgres"

setup() {
  P <<SQL >/dev/null
-- Test reset only: owner SQL with the coach setting may clear locked rows.
select set_config('runsmart.coach_write', 'on', false);
insert into auth.users (id, email, aud, role) values
  ('$A', 'coach-a@example.com', 'authenticated', 'authenticated')
  on conflict (id) do nothing;
insert into auth.users (id, email, aud, role) values
  ('$B', 'athlete-b@example.com', 'authenticated', 'authenticated')
  on conflict (id) do nothing;
insert into public.coach_profiles (user_id, display_name) values ('$A', 'Dana') on conflict do nothing;
delete from public.coach_athlete_links where athlete_id = '$B';
insert into public.coach_athlete_links (coach_id, athlete_id, status, consented_at) values ('$A', '$B', 'active', now());
insert into public.client_capabilities (user_id, coach_v2, channel) values ('$A', true, 'testflight'), ('$B', true, 'testflight')
  on conflict do nothing;
delete from public.coach_athlete_events where athlete_id = '$B';
delete from public.workouts where auth_user_id = '$B';
delete from public.plans where auth_user_id = '$B';
insert into public.plans (id, profile_id, auth_user_id, title, start_date, end_date, is_active)
  values ('$PLAN', '$B', '$B', 'B plan', current_date - 7, current_date + 60, true);
insert into public.workouts (id, plan_id, auth_user_id, week, day, type, distance, completed, scheduled_date) values
  ('$W1', '$PLAN', '$B', 2, to_char(current_date + 2, 'Dy'), 'easy', 5, false, current_date + 2),
  ('$W2', '$PLAN', '$B', 2, to_char(current_date + 3, 'Dy'), 'easy', 5, false, current_date + 3);
SQL
  P -c "$AS_A select public.coach_update_workout('$W1', 0, 'tempo', 8, null, null, null, null); select public.coach_update_workout('$W2', 0, 'tempo', 8, null, null, null, null);" >/dev/null
}

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# 1 and 2. The coach's auth row is held (as a coach account delete holds it).
# The athlete RPC must wait before locking the plan or the workout.
for rpc in replace change; do
  setup
  (P -c "begin; select 1 from auth.users where id = '$A' for update; select pg_sleep(3); rollback;" >"$T/h" 2>&1) &
  sleep 1
  if [ "$rpc" = replace ]; then
    stmt="perform $(REPLACE_SQL 2)"
  else
    stmt="perform public.athlete_change_coach_workout('$W1', 'skip', null, 'e0000001-0000-4000-8000-0000000000e1')"
  fi
  (P -c "$AS_B $(WAIT_SQL "$stmt")" >"$T/r" 2>&1) &
  sleep 1
  # While the RPC waits, the plan and the workout are still free.
  P -c "begin; select 1 from public.plans where id = '$PLAN' for update nowait; select 1 from public.workouts where id = '$W1' for update nowait; rollback;" >"$T/n" 2>&1 \
    || fail "$rpc: the RPC locked the plan or the workout before the coach's auth row: $(cat "$T/n")"
  wait
  w=$(waited "$T/r")
  [ -n "$w" ] || fail "$rpc: the RPC failed: $(cat "$T/r")"
  awk "BEGIN{exit !($w >= 1.0)}" || fail "$rpc: the RPC did not wait for the coach's auth row (waited ${w}s)"
  echo "$( [ "$rpc" = replace ] && echo 1 || echo 2 ). $rpc waited ${w}s at the auth row, holding no plan or workout lock"
done

# 3a. Replace first (open), then a real coach account delete: the delete waits,
# then unlocks the rows. No deadlock.
setup
(P -c "begin; $AS_B select $(REPLACE_SQL 2); select pg_sleep(3); commit;" >"$T/3a" 2>&1) &
sleep 1
P -c "$(WAIT_SQL "delete from auth.users where id = '$A'")" >"$T/3b" 2>&1 || fail "3a: the coach delete failed: $(cat "$T/3b")"
wait
grep -qi deadlock "$T/3a" "$T/3b" && fail "3a: deadlock"
w=$(waited "$T/3b")
awk "BEGIN{exit !($w >= 1.5)}" || fail "3a: the coach delete did not wait for the replace (waited ${w}s)"
[ "$(P -c "select count(*) from public.plans where auth_user_id = '$B' and is_active and title = 'New'")" = "1" ] \
  || fail "3a: the replace did not land: $(cat "$T/3a")"
[ "$(P -c "select count(*) from public.workouts where auth_user_id = '$B' and locked")" = "0" ] \
  || fail "3a: rows still locked after the coach delete"
echo "3a. coach delete waited ${w}s for the replace; both finished, rows unlocked"

# 3b. Coach account delete first (open), then the replace: the replace waits,
# then raises count_changed (the delete released both counted rows).
setup
(P -c "begin; delete from auth.users where id = '$A'; select pg_sleep(3); commit;" >"$T/3c" 2>&1) &
sleep 1
P -c "$AS_B $(WAIT_SQL "perform $(REPLACE_SQL 2)")" >"$T/3d" 2>&1 || true
wait
grep -qi deadlock "$T/3c" "$T/3d" && fail "3b: deadlock"
grep -q 'count_changed' "$T/3d" || fail "3b: expected count_changed, got: $(cat "$T/3d")"
[ "$(P -c "select count(*) from auth.users where id = '$A'")" = "0" ] || fail "3b: the coach delete did not land"
[ "$(P -c "select count(*) from public.plans where id = '$PLAN' and is_active")" = "1" ] || fail "3b: the refused replace changed the plan"
echo "3b. replace waited for the coach delete, then raised count_changed; no deadlock"

# 4. Request-id race: the original skip holds its locks; a revoke queues behind
# it; the retry starts before the original commits. The retry returns duplicate.
setup
(P -c "begin; $AS_B select public.athlete_change_coach_workout('$W1', 'skip', null, 'e0000004-0000-4000-8000-0000000000e4'); select pg_sleep(3); commit;" >"$T/4a" 2>&1) &
sleep 0.5
(P -c "begin; update public.coach_athlete_links set status = 'revoked', revoked_at = now() where athlete_id = '$B' and status = 'active'; select pg_sleep(2); commit;" >"$T/4b" 2>&1) &
sleep 1
P -c "$AS_B select public.athlete_change_coach_workout('$W1', 'skip', null, 'e0000004-0000-4000-8000-0000000000e4');" >"$T/4c" 2>&1 || true
wait
grep -qx 'duplicate' "$T/4c" || fail "4: expected duplicate, got: $(cat "$T/4c")"
[ "$(P -c "select count(*) from public.coach_athlete_events where athlete_id = '$B' and client_id = 'e0000004-0000-4000-8000-0000000000e4'")" = "1" ] \
  || fail "4: expected exactly one event"
echo "4. a retry racing the original and a link end returned duplicate; one event"

# 5. The plans trigger counts with a fresh snapshot. A coach create holds the
# plan FOR SHARE; a plain athlete deactivation waits on it; once the coach commits,
# the deactivation must see the new locked row and raise coach_workouts_present.
setup
P -c "select set_config('runsmart.coach_write', 'on', false); update public.workouts set locked = false where auth_user_id = '$B';" >/dev/null
(P -c "begin; $AS_A select public.coach_create_workout('$B', 'c0000005-0000-4000-8000-0000000000c5', current_date + 10, 'easy', 5); select pg_sleep(3); commit;" >"$T/5a" 2>&1) &
sleep 1
P -c "$AS_B $(WAIT_SQL "update public.plans set is_active = false where id = '$PLAN'")" >"$T/5b" 2>&1 || true
wait
grep -q 'coach_workouts_present' "$T/5b" || fail "5: expected coach_workouts_present after the coach create committed, got: $(cat "$T/5b")"
[ "$(P -c "select count(*) from public.plans where id = '$PLAN' and is_active")" = "1" ] || fail "5: the plan was deactivated"
echo "5. a deactivation waiting on a coach create saw the new locked row and raised coach_workouts_present"

# 6. leave_coach takes the auth.users rows before the link: while a coach account
# delete holds the coach's row, leave_coach waits holding no link lock.
setup
LINK=$(P -c "select id from public.coach_athlete_links where athlete_id = '$B' and status = 'active'")
(P -c "begin; select 1 from auth.users where id = '$A' for update; select pg_sleep(3); rollback;" >"$T/6h" 2>&1) &
sleep 1
(P -c "$AS_B $(WAIT_SQL "perform public.leave_coach('$LINK')")" >"$T/6r" 2>&1) &
sleep 1
P -c "begin; select 1 from public.coach_athlete_links where id = '$LINK' for update nowait; rollback;" >"$T/6n" 2>&1 \
  || fail "6: leave_coach locked the link before the coach's auth row: $(cat "$T/6n")"
wait
w=$(waited "$T/6r")
[ -n "$w" ] || fail "6: leave_coach failed: $(cat "$T/6r")"
[ "$(P -c "select count(*) from public.workouts where auth_user_id = '$B' and locked")" = "0" ] || fail "6: rows still locked after leaving"
echo "6. leave_coach waited ${w}s at the auth row, holding no link lock; rows unlocked after"

# 7. coach_remove_athlete, the same.
setup
(P -c "begin; select 1 from auth.users where id = '$B' for update; select pg_sleep(3); rollback;" >"$T/7h" 2>&1) &
sleep 1
(P -c "$AS_A $(WAIT_SQL "perform public.coach_remove_athlete('$B')")" >"$T/7r" 2>&1) &
sleep 1
P -c "begin; select 1 from public.coach_athlete_links where athlete_id = '$B' and status = 'active' for update nowait; rollback;" >"$T/7n" 2>&1 \
  || fail "7: coach_remove_athlete locked the link before the auth rows: $(cat "$T/7n")"
wait
w=$(waited "$T/7r")
[ -n "$w" ] || fail "7: coach_remove_athlete failed: $(cat "$T/7r")"
echo "7. coach_remove_athlete waited ${w}s at the auth row, holding no link lock"

echo "coach_plan_locks_race: PASS"
