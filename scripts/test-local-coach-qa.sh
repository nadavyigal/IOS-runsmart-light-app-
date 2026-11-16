#!/usr/bin/env bash
# Regression suites intentionally refuse seeded/hosted databases.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/.local-coach-qa"
image=supabase/postgres:17.6.1.158
container="runsmart-coach-sql-$$"
cleanup() { docker stop "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT

run_suite() {
  local name="$1"
  container="runsmart-coach-sql-$$-$name"
  shift
  docker run -d --rm --network none --name "$container" \
    --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=throwaway-only "$image" >/dev/null
  local attempt
  for attempt in {1..40}; do
    if docker exec "$container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
    sleep 1
  done
  docker exec "$container" pg_isready -h 127.0.0.1 -U postgres >/dev/null
  local file db_user=postgres
  if [[ "$name" == rls_leaks ]]; then db_user=supabase_admin; fi
  for file in "$@" "supabase/tests/$name.sql"; do
    docker exec -i "$container" psql -X -q -U "$db_user" -d postgres -v ON_ERROR_STOP=1 < "$file"
  done
  echo "$name: PASS"
  cleanup
}

db=supabase/migrations
staged="$db"
links="$db/20261114130000_runs_workout_link.sql"
roles="$db/20261114210000_coach_role_and_invites.sql"
join="$db/20261115091000_coach_athlete_links.sql"
atomic="$staged/20261115170000_complete_run_workout.sql"
leave="$staged/20261115194500_leave_coach.sql"
# Use the PR regression fixtures until their migration stories land on main.
for part in complete_run_workout leave_coach; do
  if [[ ! -f "supabase/tests/$part.sql" ]]; then
    echo "Start the generated workspace first (see tasks/todo.md)." >&2
    exit 1
  fi
done
run_suite rls_leaks supabase/tests/rls_leaks_fixture.sql "$db/20261114120000_close_cross_user_rls_leaks.sql"
run_suite runs_workout_link supabase/tests/runs_workout_link_fixture.sql "$links"
run_suite coach_invites "$roles"
run_suite coach_athlete_links "$roles" "$join"
run_suite complete_run_workout supabase/tests/runs_workout_link_fixture.sql "$links" "$atomic"
run_suite leave_coach "$roles" "$join" "$leave"
