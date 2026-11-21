#!/bin/sh
# Xcode Cloud runs this after every xcodebuild command, even a failed one.
# On an archive it runs the same live backend check as `fastlane beta`
# (scripts/verify-release-backend.py): the packaged Supabase URL and key must
# reach Auth, with Apple and email sign-in on. A failed check fails the build,
# so the archive is not handed to TestFlight.
#
# No secrets step: RunSmartConfig.xcconfig commits the public client keys.
set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
  echo "Action is '${CI_XCODEBUILD_ACTION:-none}', not archive: backend check skipped."
  exit 0
fi

if [ "${CI_XCODEBUILD_EXIT_CODE:-}" != "0" ]; then
  echo "xcodebuild exited with '${CI_XCODEBUILD_EXIT_CODE:-unknown}': backend check skipped, the build already failed."
  exit 0
fi

if [ -z "${CI_ARCHIVE_PATH:-}" ] || [ ! -d "$CI_ARCHIVE_PATH" ]; then
  echo "error: CI_ARCHIVE_PATH is missing, cannot check the archived app." >&2
  exit 1
fi

set -- "$CI_ARCHIVE_PATH"/Products/Applications/*.app
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "error: expected exactly one .app in $CI_ARCHIVE_PATH/Products/Applications." >&2
  exit 1
fi

# The repo may not be on disk in this phase; the symlink next to this script
# makes Xcode Cloud ship the checker with ci_scripts.
python3 "$(dirname "$0")/verify-release-backend.py" "$1"
