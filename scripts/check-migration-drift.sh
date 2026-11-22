#!/bin/sh
# check-migration-drift.sh: compare the coach migrations (20261114120000 onward)
# between this iOS repo and the web repo. Read-only: it never writes or changes a file.
#
# Usage: scripts/check-migration-drift.sh /path/to/Running-coach-
#   (the web repo root; migrations are read from <web>/v0/supabase/migrations)
# Exit 0: every file is in both trees and byte-identical. Exit 1: drift. Exit 2: bad usage.

FROM="20261114120000"

if [ $# -ne 1 ]; then
  echo "usage: $0 /path/to/Running-coach-" >&2
  exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
IOS_DIR="$SCRIPT_DIR/../supabase/migrations"
WEB_DIR="$1/v0/supabase/migrations"

for d in "$IOS_DIR" "$WEB_DIR"; do
  if [ ! -d "$d" ]; then
    echo "error: not a directory: $d" >&2
    exit 2
  fi
done

# Union of file names at or after $FROM, sorted. Timestamps are fixed-width, so a
# string compare on the name is correct.
NAMES=$( { ls "$IOS_DIR"; ls "$WEB_DIR"; } | grep '\.sql$' | sort -u | awk -v from="$FROM" '$0 >= from')

printf '%-58s %-4s %-4s %s\n' "file" "iOS" "web" "identical"
DRIFT=0
TOTAL=0
for f in $NAMES; do
  TOTAL=$((TOTAL + 1))
  in_ios=n; in_web=n; same=n
  [ -f "$IOS_DIR/$f" ] && in_ios=y
  [ -f "$WEB_DIR/$f" ] && in_web=y
  if [ "$in_ios" = y ] && [ "$in_web" = y ]; then
    if cmp -s "$IOS_DIR/$f" "$WEB_DIR/$f"; then same=y; fi
  fi
  if [ "$same" != y ]; then DRIFT=$((DRIFT + 1)); fi
  printf '%-58s %-4s %-4s %s\n' "$f" "$in_ios" "$in_web" "$same"
done

echo "files checked: $TOTAL, drifted: $DRIFT"
if [ "$DRIFT" -ne 0 ]; then
  echo "DRIFT"
  exit 1
fi
echo "CLEAN"
exit 0
