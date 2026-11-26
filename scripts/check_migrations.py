#!/usr/bin/env python3
"""Supabase migration sanity checks. Read-only: never connects to a database.

PR mode (CI):
  python3 scripts/check_migrations.py --dir supabase/migrations --base origin/main

Drift mode (manual, run by Nadav; compares files to what prod recorded):
  supabase migration list --linked > /tmp/remote.txt
  python3 scripts/check_migrations.py --dir supabase/migrations --remote-list /tmp/remote.txt
  # If another repo migrates the same Supabase project, add its folder so its
  # versions are not reported as unknown:  --also-dir ../Running-coach-/v0/supabase/migrations
  # optional exact name matching, from a read-only query run by Nadav:
  #   select version || '|' || name from supabase_migrations.schema_migrations;
  #   ... --remote-names /tmp/remote_names.txt

Exit code 0 = clean, 1 = errors found. Warnings never fail the run.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import subprocess
import sys

TS14 = re.compile(r"^(\d{14})_([A-Za-z0-9_]+)\.sql$")
ANY_VERSION = re.compile(r"^(\d+)_([A-Za-z0-9_]+)\.sql$")

# Files added after the fact for a migration that production already has. They keep their
# original (older) timestamp so the repo replays in the same order as production, so the
# "new file must be newer than main" rule does not apply to them. Each entry is recorded as
# applied in docs/migration-ledger.md. Add a file here only for an applied migration.
BACKFILLED_APPLIED = {
    # prod version 20261120094612, applied 2026-11-20 (ledger section 1)
    "20261120100000_athlete_display_name_placeholder.sql",
}

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)
    print(f"::error::{msg}")


def warn(msg: str) -> None:
    warnings.append(msg)
    print(f"::warning::{msg}")


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], check=True, capture_output=True, text=True
    ).stdout


def local_files(directory: str) -> list[str]:
    if not os.path.isdir(directory):
        return []
    return sorted(f for f in os.listdir(directory) if f.endswith(".sql"))


def valid_timestamp(ts: str) -> bool:
    try:
        dt.datetime.strptime(ts, "%Y%m%d%H%M%S")
        return True
    except ValueError:
        return False


def check_names(files: list[str], legacy: re.Pattern | None) -> dict[str, str]:
    """Return {version: filename}. Flags bad names, bad dates, duplicates."""
    by_version: dict[str, list[str]] = {}
    now = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
    limit = now + dt.timedelta(days=1)
    for f in files:
        m14 = TS14.match(f)
        if m14:
            ts = m14.group(1)
            if not valid_timestamp(ts):
                err(f"{f}: {ts} is not a real YYYYMMDDHHMMSS timestamp")
            elif dt.datetime.strptime(ts, "%Y%m%d%H%M%S") > limit:
                err(f"{f}: timestamp is more than 24h in the future (typo?)")
            by_version.setdefault(ts, []).append(f)
            continue
        many = ANY_VERSION.match(f)
        if many and legacy and legacy.search(f):
            by_version.setdefault(many.group(1), []).append(f)
            print(f"note: {f} is a grandfathered legacy name (not 14 digits)")
            continue
        err(f"{f}: name must be <14-digit UTC timestamp>_<snake_name>.sql")
    out: dict[str, str] = {}
    for version, names in by_version.items():
        if len(names) > 1:
            err(f"duplicate version {version}: {', '.join(names)}")
        out[version] = names[0]
    seen_names: dict[str, str] = {}
    for f in files:
        m = ANY_VERSION.match(f)
        if not m:
            continue
        if m.group(2) in seen_names:
            warn(f"same migration name twice: {seen_names[m.group(2)]} and {f}")
        seen_names[m.group(2)] = f
    return out


def check_against_base(directory: str, base: str, allow_edit: bool) -> None:
    try:
        base_files = {
            os.path.basename(p)
            for p in git("ls-tree", "-r", "--name-only", base, "--", directory).splitlines()
        }
    except subprocess.CalledProcessError:
        err(f"cannot read {base}; base comparison is required (fetch-depth: 0 needed)")
        return
    head_files = set(local_files(directory))
    base_ts = [m.group(1) for f in base_files if (m := TS14.match(f))]
    latest = max(base_ts) if base_ts else None
    for f in sorted(head_files - base_files):
        m = TS14.match(f)
        if f in BACKFILLED_APPLIED:
            print(f"note: {f} is a backfill of a migration production already has")
            continue
        if m and latest and m.group(1) <= latest:
            err(
                f"{f}: new migration is not newer than the latest on {base} "
                f"({latest}). Rename it to a newer timestamp."
            )
    changed = git(
        "diff", "--name-status", "--no-renames", f"{base}...HEAD", "--", directory
    ).splitlines()
    for line in changed:
        status, _, path = line.partition("\t")
        name = os.path.basename(path)
        if status in ("M", "D") and name in base_files:
            msg = (
                f"{name}: existing migration was {'edited' if status == 'M' else 'deleted/renamed'}. "
                "Applied migrations are immutable. Add a new migration instead, "
                "or Nadav adds the label 'migration-edit-ok' for a deliberate rename/mirror."
            )
            if allow_edit:
                warn(msg + " (allowed by label)")
            else:
                err(msg)


def parse_remote_list(path: str) -> set[str]:
    text = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
    remote: set[str] = set()
    for line in text.splitlines():
        cells = [c.strip() for c in re.split(r"[│|]", line)]
        if len(cells) >= 2 and re.fullmatch(r"\d+", cells[1] or "x"):
            remote.add(cells[1])
    return remote


def parse_remote_names(path: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in open(path, encoding="utf-8").read().splitlines():
        version, _, name = line.strip().partition("|")
        if version.isdigit() and name:
            out[version] = name
    return out


def check_drift(
    versions: dict[str, str],
    remote_list: str,
    remote_names: str | None,
    also_dirs: list[str],
) -> None:
    remote = parse_remote_list(remote_list)
    # Versions owned by a sibling repo that migrates the same Supabase project.
    other: set[str] = set()
    for d in also_dirs:
        for f in local_files(d):
            m = ANY_VERSION.match(f)
            if m:
                other.add(m.group(1))
    remote -= other - set(versions)
    if not remote:
        err("could not read any remote versions from the migration list output")
        return
    local = set(versions)
    local_only = sorted(local - remote)
    remote_only = sorted(remote - local)
    names = parse_remote_names(remote_names) if remote_names else {}
    local_name = {v: ANY_VERSION.match(f).group(2) for v, f in versions.items()}
    paired_local: set[str] = set()
    for r in remote_only:
        match = None
        if r in names:
            match = next((l for l in local_only if local_name[l] == names[r]), None)
        if match is None:
            match = next(
                (l for l in local_only if l[:8] == r[:8] and l not in paired_local), None
            )
            hint = "same UTC day (guess)"
        else:
            hint = "same migration name (exact)"
        if match:
            paired_local.add(match)
            err(
                f"VERSION MISMATCH: file {versions[match]} is recorded in prod as "
                f"{r} ({hint}). Fix in a reviewed PR: rename the file to "
                f"{r}_{local_name[match]}.sql (label 'migration-edit-ok')."
            )
        else:
            err(f"prod has version {r} that no file in the repo has (applied by hand?)")
    for l in local_only:
        if l not in paired_local:
            warn(f"pending: {versions[l]} is not applied to prod yet (expected until Nadav applies it)")
    if not remote_only and not local_only:
        print("drift check: local files and prod history match")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="supabase/migrations")
    ap.add_argument("--base", help="git ref of the target branch, e.g. origin/main")
    ap.add_argument("--legacy-regex", help="regex for grandfathered non-14-digit names")
    ap.add_argument("--remote-list", help="file (or -) with `supabase migration list` output")
    ap.add_argument("--remote-names", help="optional file of version|name lines from prod")
    ap.add_argument(
        "--also-dir",
        action="append",
        default=[],
        help="migrations dir of a sibling repo that shares the same Supabase project (repeatable)",
    )
    ap.add_argument("--allow-edit", action="store_true", default=os.environ.get("MIGRATION_EDIT_OK") == "1")
    args = ap.parse_args()

    legacy = re.compile(args.legacy_regex) if args.legacy_regex else None
    files = local_files(args.dir)
    versions = check_names(files, legacy)
    if args.base:
        check_against_base(args.dir, args.base, args.allow_edit)
    if args.remote_list:
        check_drift(versions, args.remote_list, args.remote_names, args.also_dir)
    print(f"checked {len(files)} files: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
