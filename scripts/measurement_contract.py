#!/usr/bin/env python3
"""Run the pinned weekly measurement contract for one app, end to end.

The contract lives in Builder OS at
`02-Products/2026-08-15-weekly-measurement-contracts-and-gated-packets.md`.
It has seven mandatory steps and says a skipped step invalidates the read. This
script is that ritual as a command, because a ritual that depends on someone
remembering seven steps has now failed six releases running.

One query shape serves both apps. Everything that differs between them lives in
``APPS`` below, so the shape cannot drift apart again the way the property names
did (WP-74 S2).

Usage:
    python3 scripts/measurement_contract.py            # RunSmart, project 171597
    python3 scripts/measurement_contract.py --app resumely --build 28

Secrets: reads AGENTIC_OS_POSTHOG_API_KEY from the environment, falling back to
~/.config/agentic-os.env the way the Agentic OS CLI does. The key is never
printed, never written, and never passed as an argument. If it is absent this
script stops and says so; it does not carry a fallback.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

POSTHOG_BASE_URL = "https://us.posthog.com"
KEY_ENV = "AGENTIC_OS_POSTHOG_API_KEY"
LOCAL_ENV_FILE = Path.home() / ".config" / "agentic-os.env"
APP_STORE_LOOKUP_URL = "https://itunes.apple.com/lookup"
# Apple caches aggressively per exact URL: an identical lookup can keep returning
# the previous version for hours. Vary the query string on every call.
APP_STORE_STOREFRONTS = ("il", "us")
WINDOW_DAYS = 30
D7_HOURS = 168
MATURE_N = 10

REPO_ROOT = Path(__file__).resolve().parent.parent

APPS = {
    "runsmart": {
        "label": "RunSmart",
        "project_id": 171597,
        "app_store_id": 6768297840,
        "lib": "posthog-ios",
        # WP-74 S2 renamed app_build -> build_number on 2026-09-03. Historical
        # events keep the old key, so a query spanning the boundary reads both.
        # This is the documented discontinuity, not a second supported name.
        "build_keys": ["build_number", "app_build"],
        "build_key_boundary": "2026-09-03 (WP-74 S2): app_build -> build_number",
        # Ordered launch -> wall, per the 1.1.6 release plan.
        "funnel": ["app_launched", "activation_first_frame_rendered", "sign_in_wall_reached"],
        "gate": "n>=10 genuine users at every launch->wall step",
        # Marker events that prove the project is this app and not the other one.
        "fingerprint_events": ["app_launched", "sign_in_wall_reached"],
        # The repo is the build-number source, cross-checked against the store version.
        "version_source": "IOS RunSmart app.xcodeproj/project.pbxproj",
    },
    "resumely": {
        "label": "Resumely",
        "project_id": 270848,
        "app_store_id": 6776752349,
        "lib": "resumely-ios-urlsession",
        "build_keys": ["build_number"],
        "build_key_boundary": None,
        "funnel": ["resume_file_selected", "optimization_started", "optimization_completed"],
        "gate": ">=20 clean activations (EXD-022)",
        "fingerprint_events": ["optimization_completed"],
        "version_source": None,
    },
}


# --------------------------------------------------------------------------
# Secrets
# --------------------------------------------------------------------------

def load_key() -> str:
    """Read the PostHog personal API key. Never returns it to stdout."""
    key = os.environ.get(KEY_ENV, "").strip()
    if key:
        return key
    if LOCAL_ENV_FILE.is_file():
        for raw in LOCAL_ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].strip()
            if "=" not in line:
                continue
            name, _, value = line.partition("=")
            if name.strip() != KEY_ENV:
                continue
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            if value:
                return value
    print(f"STOP: {KEY_ENV} is not set and is not in {LOCAL_ENV_FILE}.", file=sys.stderr)
    print("This read cannot be taken. Not estimating.", file=sys.stderr)
    raise SystemExit(2)


# --------------------------------------------------------------------------
# PostHog
# --------------------------------------------------------------------------

def hogql(key: str, project_id: int, query: str) -> list[list]:
    body = json.dumps({"query": {"kind": "HogQLQuery", "query": query}}).encode()
    req = urllib.request.Request(
        f"{POSTHOG_BASE_URL}/api/projects/{project_id}/query/",
        data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:500]
        print(f"STOP: PostHog returned HTTP {exc.code}. {detail}", file=sys.stderr)
        raise SystemExit(1)
    return payload.get("results", [])


def sql_str(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def build_expr(build_keys: list[str]) -> str:
    """One expression for the build, spanning any documented key rename."""
    parts = [f"nullIf(toString(properties.{k}), '')" for k in build_keys]
    return f"coalesce({', '.join(parts)}, 'NULL')" if len(parts) > 1 else f"ifNull({parts[0]}, 'NULL')"


# --------------------------------------------------------------------------
# Step 1 - the anchor
# --------------------------------------------------------------------------

def apple_lookup(app_store_id: int) -> tuple[str, str]:
    """Cache-busted store lookup. Never a repo claim, never progress.md."""
    last_error = "no storefront answered"
    for storefront in APP_STORE_STOREFRONTS:
        bust = f"{int(datetime.now(timezone.utc).timestamp())}{random.randint(1000, 9999)}"
        url = f"{APP_STORE_LOOKUP_URL}?id={app_store_id}&country={storefront}&_cb={bust}"
        try:
            with urllib.request.urlopen(url, timeout=15) as response:
                data = json.load(response)
        except Exception as exc:  # noqa: BLE001 - any failure is the same failure here
            last_error = f"{type(exc).__name__} on storefront {storefront}"
            continue
        results = data.get("results") or []
        if not results:
            last_error = f"empty results on storefront {storefront}"
            continue
        entry = results[0]
        return entry["version"], entry["currentVersionReleaseDate"]
    print(f"STOP: could not read the live store version ({last_error}).", file=sys.stderr)
    print("The anchor is the store release timestamp; without it there is no read.", file=sys.stderr)
    raise SystemExit(2)


def repo_build(app: dict, store_version: str) -> str:
    """The build number, from the repo, only if the repo agrees with the store."""
    source = app.get("version_source")
    if not source:
        return ""
    text = (REPO_ROOT / source).read_text(encoding="utf-8")
    versions = sorted(set(re.findall(r"MARKETING_VERSION = ([^;]+);", text)))
    builds = sorted(set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", text)))
    if len(versions) != 1 or len(builds) != 1:
        print(f"STOP: {source} is not internally consistent: "
              f"versions={versions} builds={builds}.", file=sys.stderr)
        raise SystemExit(2)
    if versions[0].strip() != store_version:
        print(f"STOP: the repo says {versions[0].strip()} and the store serves "
              f"{store_version}. The repo cannot name the shipped build.", file=sys.stderr)
        raise SystemExit(2)
    return builds[0].strip()


# --------------------------------------------------------------------------
# The read
# --------------------------------------------------------------------------

def run(app_key: str, build_override: str | None) -> int:
    app = APPS[app_key]
    key = load_key()
    project_id = app["project_id"]
    lib = sql_str(app["lib"])
    builds = build_expr(app["build_keys"])

    # Deterministic window: whole UTC days, so two runs on the same day state the
    # same window. Non-determinism is the defect this contract exists to remove.
    today = datetime.now(timezone.utc).date()
    window_end = datetime(today.year, today.month, today.day, tzinfo=timezone.utc) + timedelta(days=1)
    window_start = window_end - timedelta(days=WINDOW_DAYS)
    win = (f"timestamp >= toDateTime('{window_start:%Y-%m-%d %H:%M:%S}') "
           f"AND timestamp < toDateTime('{window_end:%Y-%m-%d %H:%M:%S}')")
    lib_filter = f"properties.$lib = {lib}"

    print(f"# Measurement contract - {app['label']} (PostHog project {project_id})")
    print(f"# Window: trailing {WINDOW_DAYS} days, "
          f"{window_start:%Y-%m-%dT%H:%MZ} to {window_end:%Y-%m-%dT%H:%MZ} (whole UTC days)")
    print(f"# Gate: {app['gate']}")
    if app["build_key_boundary"]:
        print(f"# Build-key boundary: {app['build_key_boundary']}")
    print()

    # --- Step 1. Cache-busted Apple lookup -> version + release timestamp -----
    store_version, release_iso = apple_lookup(app["app_store_id"])
    release_dt = datetime.fromisoformat(release_iso.replace("Z", "+00:00"))
    build = (build_override or repo_build(app, store_version)).strip()
    print("## Step 1 - store anchor (cache-busted Apple lookup)")
    print(f"live version: {store_version}")
    print(f"release timestamp: {release_dt:%Y-%m-%dT%H:%M:%SZ}")
    if build:
        source = "--build argument" if build_override else f"repo {app['version_source']}, matching the store version"
        print(f"build number: {build} ({source})")
    else:
        print("build number: unknown - App Store Connect is the only source; pass --build")
    print()

    # --- Step 2. Fingerprint the project before trusting any query -----------
    print("## Step 2 - project fingerprint")
    rows = hogql(key, project_id, f"""
        SELECT ifNull(toString(properties.$lib), 'NULL') AS lib,
               count() AS events, uniq(person_id) AS persons
        FROM events WHERE {win}
        GROUP BY lib ORDER BY events DESC, lib ASC
    """)
    for lib_name, events, persons in rows:
        print(f"$lib={lib_name}: {events} events, {persons} persons")
    marker_rows = hogql(key, project_id, f"""
        SELECT event, count() AS events
        FROM events
        WHERE {win} AND event IN ({', '.join(sql_str(e) for e in app['fingerprint_events'])})
        GROUP BY event ORDER BY event ASC
    """)
    seen = {row[0] for row in marker_rows}
    for marker in app["fingerprint_events"]:
        print(f"marker {marker}: {'present' if marker in seen else 'ABSENT'}")
    if not seen:
        print("STOP: none of this app's marker events are in this project. "
              "The project id is wrong, or the app has never emitted.", file=sys.stderr)
        return 2
    print()

    # --- Step 3. Build split, with the pre-release integrity check -----------
    print("## Step 3 - build split and pre-release check")
    print("(a cohort whose last event predates its own public release contains no public users)")
    rows = hogql(key, project_id, f"""
        SELECT ifNull(toString(properties.app_version), 'NULL') AS app_version,
               {builds} AS build_number,
               count() AS events,
               uniq(person_id) AS persons,
               min(timestamp) AS first_seen,
               max(timestamp) AS last_seen
        FROM events WHERE {win} AND {lib_filter}
        GROUP BY app_version, build_number
        ORDER BY app_version DESC, build_number DESC
    """)
    target_rows = []
    for app_version, build_number, events, persons, first_seen, last_seen in rows:
        last_dt = datetime.fromisoformat(str(last_seen).replace("Z", "+00:00"))
        is_target = app_version == store_version and (not build or build_number == build)
        flag = ""
        if is_target:
            target_rows.append((build_number, events, persons))
            flag = " <- target cohort"
            if last_dt < release_dt:
                flag += " PRE-RELEASE: last event predates the store release"
        print(f"{app_version} ({build_number}): {events} events, {persons} persons, "
              f"{str(first_seen)[:19]}Z -> {str(last_seen)[:19]}Z{flag}")
    if not target_rows:
        print(f"target cohort {store_version} ({build or 'any build'}): 0 events, 0 persons")
    print()

    # --- Step 4. Person-level exclusion, reported separately -----------------
    print("## Step 4 - person-level exclusion (never event-level)")
    version_scope = f"properties.app_version = {sql_str(store_version)}"
    if build:
        version_scope += f" AND {builds} = {sql_str(build)}"
    since_release = f"timestamp >= toDateTime('{release_dt:%Y-%m-%d %H:%M:%S}')"
    rows = hogql(key, project_id, f"""
        WITH person_flags AS (
            SELECT person_id,
                   max(toString(properties.is_internal_tester) IN ('true', 'True')) AS is_internal
            FROM events WHERE {win}
            GROUP BY person_id
        )
        SELECT pf.is_internal AS is_internal,
               uniq(e.person_id) AS persons,
               count() AS events
        FROM events AS e
        INNER JOIN person_flags AS pf ON pf.person_id = e.person_id
        WHERE {win} AND {lib_filter} AND {version_scope} AND {since_release}
        GROUP BY is_internal ORDER BY is_internal ASC
    """)
    counts = {int(row[0]): (row[1], row[2]) for row in rows}
    ext_persons, ext_events = counts.get(0, (0, 0))
    int_persons, int_events = counts.get(1, (0, 0))
    print(f"scope: app_version={store_version}"
          f"{f', build={build}' if build else ''}, since the store release timestamp")
    print(f"external persons: {ext_persons} ({ext_events} events)")
    print(f"internal-tester persons: {int_persons} ({int_events} events)")
    print()

    # --- Step 5. Ordered funnel with n at every step -------------------------
    print("## Step 5 - ordered funnel, n at every step")
    steps = app["funnel"]
    print(" -> ".join(steps))
    if ext_persons == 0:
        for index, step in enumerate(steps, start=1):
            print(f"step {index} {step}: n=0")
        print("no external cohort: counts only, no rates. This is a real answer, not a gap.")
    else:
        conditions = ", ".join(f"event = {sql_str(step)}" for step in steps)
        rows = hogql(key, project_id, f"""
            WITH person_flags AS (
                SELECT person_id,
                       max(toString(properties.is_internal_tester) IN ('true', 'True')) AS is_internal
                FROM events WHERE {win}
                GROUP BY person_id
            ),
            reached AS (
                SELECT e.person_id AS person_id,
                       windowFunnel(86400)(toDateTime(e.timestamp), {conditions}) AS level
                FROM events AS e
                INNER JOIN person_flags AS pf ON pf.person_id = e.person_id
                WHERE {win} AND {lib_filter} AND {version_scope} AND {since_release}
                  AND pf.is_internal = 0
                GROUP BY e.person_id
            )
            SELECT level, count() AS persons FROM reached GROUP BY level ORDER BY level ASC
        """)
        at_level = {int(row[0]): row[1] for row in rows}
        reached_counts = []
        for index in range(1, len(steps) + 1):
            reached_counts.append(sum(count for level, count in at_level.items() if level >= index))
        for index, (step, n) in enumerate(zip(steps, reached_counts), start=1):
            line = f"step {index} {step}: n={n}"
            if index > 1 and reached_counts[0] >= MATURE_N and n >= MATURE_N:
                line += f" ({n} of {reached_counts[0]} who reached step 1)"
            print(line)
        if min(reached_counts) < MATURE_N:
            print(f"immature: below n={MATURE_N} at some step. Counts only, no rates.")
    print()

    # --- Step 6. Age check against the metric's own window -------------------
    print("## Step 6 - cohort age")
    earliest_valid = release_dt + timedelta(hours=D7_HOURS)
    now = datetime.now(timezone.utc)
    if now < earliest_valid:
        print(f"D7 not yet measurable. Earliest valid read: {earliest_valid:%Y-%m-%dT%H:%MZ} "
              f"({D7_HOURS}h after the store release). No partial figure is reported.")
    else:
        print(f"D7 measurable: the cohort passed {D7_HOURS}h at {earliest_valid:%Y-%m-%dT%H:%MZ}.")
    print()

    # --- Step 7. Where the result goes --------------------------------------
    print("## Step 7 - record the result")
    print("Write the above into tasks/progress.md and the living page's Current State.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", choices=sorted(APPS), default="runsmart")
    parser.add_argument("--build", default=None,
                        help="App Store Connect-confirmed build number, when the repo cannot name it")
    args = parser.parse_args()
    return run(args.app, args.build)


if __name__ == "__main__":
    raise SystemExit(main())
