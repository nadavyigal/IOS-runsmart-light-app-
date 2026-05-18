#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

set -a
for env_file in ../env.local ../local.env env.local local.env; do
  if [[ -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    source "$env_file"
  fi
done
set +a

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" && -n "${UPABASE_ACCESS_TOKEN:-}" ]]; then
  export SUPABASE_ACCESS_TOKEN="$UPABASE_ACCESS_TOKEN"
fi

: "${SUPABASE_PROJECT_REF:?Missing SUPABASE_PROJECT_REF in ignored env files}"
: "${SUPABASE_ACCESS_TOKEN:?Missing SUPABASE_ACCESS_TOKEN in ignored env files. Create a Supabase personal access token and add it as SUPABASE_ACCESS_TOKEN=...}"
: "${OPENAI_API_KEY:?Missing OPENAI_API_KEY in ignored env files}"

OPENAI_MODEL="${OPENAI_MODEL:-gpt-4.1-mini}"
secrets_file="$(mktemp)"
trap 'rm -f "$secrets_file"' EXIT

{
  printf 'OPENAI_API_KEY=%s\n' "$OPENAI_API_KEY"
  printf 'OPENAI_MODEL=%s\n' "$OPENAI_MODEL"
} > "$secrets_file"

echo "Linking Supabase project ${SUPABASE_PROJECT_REF}..."
npx -y supabase@latest link --project-ref "$SUPABASE_PROJECT_REF"

echo "Setting Coach Edge Function secrets..."
npx -y supabase@latest secrets set \
  --env-file "$secrets_file" \
  --project-ref "$SUPABASE_PROJECT_REF"

echo "Deploying coach_message Edge Function..."
npx -y supabase@latest functions deploy coach_message \
  --project-ref "$SUPABASE_PROJECT_REF" \
  --use-api \
  --no-verify-jwt

echo "coach_message deployed."
