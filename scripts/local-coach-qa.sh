#!/usr/bin/env bash
# RunSmart Coach QA uses an unlinked, generated Supabase project.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
local_dir="$root/.local-coach-qa"
network=runsmart-coach-qa-loopback
project=runsmart-coach-local-qa
cli="$(command -v supabase || true)"
cli="${cli:-$HOME/.local/bin/supabase}"
if [[ ! -x "$cli" ]]; then
  echo 'Install the Supabase CLI before starting local QA.' >&2
  exit 1
fi

case "${1:-start}" in
start)
  docker info >/dev/null
  for dir in "$local_dir" "$local_dir/supabase" "$local_dir/supabase/migrations"; do
    [[ ! -L "$dir" ]] || { echo "Refusing symlink: $dir" >&2; exit 1; }
    mkdir -p "$dir"
  done
  [[ ! -e "$local_dir/supabase/.temp/project-ref" ]] || { echo 'Refusing a linked project.' >&2; exit 1; }
  mkdir -p "$local_dir/supabase/tests"
  cp "$root"/supabase/tests/*.sql "$local_dir/supabase/tests/"
  cp "$root/supabase/qa/config.toml" "$local_dir/supabase/config.toml"
  cp "$root/supabase/qa/seed.sql" "$local_dir/supabase/seed.sql"
  {
    printf "SET runsmart.local_qa = 'on';\n"
    cat "$root/supabase/qa/bootstrap.sql"
  } > "$local_dir/supabase/migrations/20250101000000_local_qa_bootstrap.sql"
  cp "$root"/supabase/migrations/*.sql "$local_dir/supabase/migrations/"
  for pair in \
    'fix/runsmart-coach-adherence 20261115170000_complete_run_workout.sql' \
    'feat/leave-coach 20261115194500_leave_coach.sql'; do
    read -r branch file <<< "$pair"
    if [[ ! -f "$root/supabase/migrations/$file" ]]; then
      local_sql="$(git -C "$root" show "refs/remotes/origin/$branch:supabase/migrations/$file")"
      printf '%s\n' "$local_sql" > "$local_dir/supabase/migrations/$file"
    fi
    case "$branch" in
      fix/*)
        for suite in complete_run_workout runs_workout_link_fixture; do
          git -C "$root" show "refs/remotes/origin/$branch:supabase/tests/$suite.sql" > "$local_dir/supabase/tests/$suite.sql"
        done ;;
      feat/*)
        git -C "$root" show "refs/remotes/origin/$branch:supabase/tests/leave_coach.sql" > "$local_dir/supabase/tests/leave_coach.sql" ;;
    esac
  done
  if ! docker network inspect "$network" >/dev/null 2>&1; then
    docker network create --driver bridge -o com.docker.network.bridge.host_binding_ipv4=127.0.0.1 "$network" >/dev/null
  fi
  [[ "$(docker network inspect --format '{{index .Options "com.docker.network.bridge.host_binding_ipv4"}}' "$network")" == 127.0.0.1 ]]
  # :5532x avoids collisions with other Supabase workspaces. No host DB credentials.
  "$cli" start --workdir "$local_dir" --network-id "$network" -x logflare,vector,supavisor,edge-runtime,storage-api,imgproxy
  for service in db kong studio inbucket; do
    bindings="$(docker inspect -f '{{json .NetworkSettings.Ports}}' "supabase_${service}_$project")"
    if ! jq -e '[.[] | .[]? | .HostIp] | length > 0 and all(. == "127.0.0.1")' <<< "$bindings" >/dev/null; then
      "$cli" stop --workdir "$local_dir"
      echo "Stopped QA: $service was not bound exclusively to 127.0.0.1" >&2
      exit 1
    fi
  done
  ;;
status|stop)
  [[ -f "$local_dir/supabase/config.toml" && ! -L "$local_dir" ]] || exit 1
  "$cli" "$1" --workdir "$local_dir"
  ;;
*)
  echo "Usage: $0 [start|status|stop]" >&2
  exit 2
  ;;
esac
