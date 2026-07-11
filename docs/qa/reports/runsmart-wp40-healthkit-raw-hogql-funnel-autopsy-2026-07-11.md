# RunSmart WP-40 HealthKit Raw HogQL Funnel Autopsy — 2026-07-11

## Result

**No readable first cohort yet.** Through **2026-07-11 14:57:58 UTC**, build `1.0.7 (21)` had one production-looking Apple Health disclosure viewer, but that same PostHog person also emitted TestFlight and sideloaded events. The person-stable exclusion therefore removes the only viewer, leaving **0 clean build users and 0 clean disclosure viewers**. A funnel percentage or largest-loss step would be fabricated, so neither is reported.

Earliest re-read condition: rerun after at least one `1.0.7 (21)` `healthkit_disclosure_viewed` person appears on native RunSmart traffic with `$is_emulator = false`, `$is_testflight = false`, and `$is_sideloaded = false`, and that person has no emulator/TestFlight/sideloaded evidence anywhere in their event history. A decision-grade product recommendation still requires at least 10 clean disclosure viewers.

PostHog project: [Running coach — project 171597](https://us.posthog.com/project/171597)

## Release and cohort anchor

- WP-40 S1/S2 merged as commit `236dde09cb1020002b7c31337094b9ff3313ab70` on 2026-07-11 at 05:34:50 UTC.
- That commit's Xcode project records `MARKETING_VERSION = 1.0.7` and `CURRENT_PROJECT_VERSION = 21`.
- PostHog project timezone: `UTC`.
- First production-looking `1.0.7 (21)` disclosure: `2026-07-11 05:48:24.950 UTC`.
- Frozen query bounds: `[2026-07-11 05:48:24 UTC, 2026-07-11 14:57:58 UTC]`. The millisecond timestamp above is retained as the evidence anchor; the reproducible aggregate uses the containing second so it cannot omit that event.
- Native build dimensions verified from raw disclosure events: `$app_name = 'RunSmart'`, `$app_namespace = 'com.runsmart.lite'`, `$lib = 'posthog-ios'`, `$os_name IN ('iOS', 'iPadOS')`, `$app_version = '1.0.7'`, `$app_build = 21`.
- Production-looking event flags: `$is_emulator = false`, `$is_testflight = false`, `$is_sideloaded = false`.

The source schema verifies only `healthkit_disclosure_viewed`, `healthkit_connect_tapped`, and `healthkit_sync_completed`. No HealthKit skip, permission-denied, connect-succeeded, sync-started, or sync-failed event exists in the live project schema, so side exits cannot currently be separated from silent disappearance.

## Test-account and exclusion audit

The project has one configured test-account filter: event `$host` `not_regex` `^(localhost|127\\.0\\.0\\.1)($|:)`. Native iOS HealthKit events do not expose `$host`, so this filter does not provide a reproducible native QA/founder exclusion. Project-level `filter_test_accounts` is currently false; the earlier WP-40 insight explicitly enabled `filterTestAccounts=true`, but its 9/7/5 result contained pre-ship QA bursts and is not a post-WP-40 cohort.

The reproducible raw-event exclusion is therefore person-stable: any production-looking build person is excluded from every step if any event in that person's full history has an evidenced emulator, TestFlight, or sideloaded flag. No email, full identifier, device name, location, token, HealthKit payload, or workout property was selected.

| Exclusion reason | People removed | Overlap note |
|---|---:|---|
| Ever emulator | 0 | None |
| Ever TestFlight | 1 | Same person as sideloaded |
| Ever sideloaded | 1 | Same person as TestFlight |
| Union removed | 1 | One unique person |
| Final clean people | 0 | No readable cohort |

The packet asks to locate founder/QA signals in `$identify`/alias history. The live taxonomy contains `$identify` but no alias event, and the app calls `identify` with empty traits. Consequently, no safe role/email/account flag exists to label the person as founder specifically. The exclusion is supported only by ingestion-time TestFlight/sideload evidence and is intentionally described as QA/test traffic, not as a named individual.

## Exposure context

| Context | Clean people | Production-looking before exclusion |
|---|---:|---:|
| Users on WP-40 build during the cohort window | 0 | 1 |
| Disclosure viewers | 0 | 1 |
| Share who saw disclosure | Not computable | 100% (1/1), QA/test traffic |

A verified `onboarding_completed` event exists, but there is no clean person to support onboarding → disclosure analysis.

## Ordered clean funnel

No funnel table is emitted because eligible clean entrants are zero. In particular, independent event totals are not substituted for ordered person conversion.

| Step | Eligible entrants | Reached step | Lost at step | Step conversion | Cumulative conversion | Side-exit count |
|---|---:|---:|---:|---:|---:|---:|
| `healthkit_disclosure_viewed` | — | 0 | — | — | — | Unknown / uninstrumented |
| `healthkit_connect_tapped` | 0 | 0 | — | — | — | Unknown / uninstrumented |
| `healthkit_sync_completed` | 0 | 0 | — | — | — | Unknown / uninstrumented |

There is no ranked loss and no single bottleneck. The current result is a cohort-readiness finding, not a product-friction finding.

## Exact HogQL

### Release/build discovery

```sql
SELECT
    properties.$app_version AS app_version,
    properties.$app_build AS app_build,
    properties.$app_name AS app_name,
    properties.$app_namespace AS app_namespace,
    properties.$lib AS lib,
    properties.$os_name AS os_name,
    properties.$is_emulator AS is_emulator,
    properties.$is_testflight AS is_testflight,
    properties.$is_sideloaded AS is_sideloaded,
    min(timestamp) AS first_seen_utc,
    max(timestamp) AS last_seen_utc,
    count() AS events,
    uniq(person_id) AS people
FROM events
WHERE event = 'healthkit_disclosure_viewed'
GROUP BY
    app_version, app_build, app_name, app_namespace, lib, os_name,
    is_emulator, is_testflight, is_sideloaded
ORDER BY first_seen_utc
```

### Frozen exclusion and readiness query

```sql
WITH production_people AS (
    SELECT DISTINCT person_id
    FROM events
    WHERE timestamp >= toDateTime('2026-07-11 05:48:24', 'UTC')
      AND timestamp <= toDateTime('2026-07-11 14:57:58', 'UTC')
      AND properties.$app_namespace = 'com.runsmart.lite'
      AND properties.$app_name = 'RunSmart'
      AND properties.$lib = 'posthog-ios'
      AND properties.$os_name IN ('iOS', 'iPadOS')
      AND properties.$app_version = '1.0.7'
      AND toFloat(properties.$app_build) = 21
      AND coalesce(toBool(properties.$is_emulator), false) = false
      AND coalesce(toBool(properties.$is_testflight), false) = false
      AND coalesce(toBool(properties.$is_sideloaded), false) = false
), flags AS (
    SELECT
        person_id,
        countIf(coalesce(toBool(properties.$is_emulator), false)) > 0 AS ever_emulator,
        countIf(coalesce(toBool(properties.$is_testflight), false)) > 0 AS ever_testflight,
        countIf(coalesce(toBool(properties.$is_sideloaded), false)) > 0 AS ever_sideloaded,
        countIf(
            event = 'healthkit_disclosure_viewed'
            AND timestamp >= toDateTime('2026-07-11 05:48:24', 'UTC')
            AND timestamp <= toDateTime('2026-07-11 14:57:58', 'UTC')
            AND properties.$app_version = '1.0.7'
            AND toFloat(properties.$app_build) = 21
            AND coalesce(toBool(properties.$is_emulator), false) = false
            AND coalesce(toBool(properties.$is_testflight), false) = false
            AND coalesce(toBool(properties.$is_sideloaded), false) = false
        ) > 0 AS saw_disclosure
    FROM events
    WHERE person_id IN (SELECT person_id FROM production_people)
    GROUP BY person_id
)
SELECT
    count() AS production_looking_build_people,
    countIf(saw_disclosure) AS production_looking_disclosure_people,
    countIf(ever_emulator) AS excluded_emulator_people,
    countIf(ever_testflight) AS excluded_testflight_people,
    countIf(ever_sideloaded) AS excluded_sideloaded_people,
    countIf(ever_emulator OR ever_testflight OR ever_sideloaded) AS excluded_union_people,
    countIf(NOT (ever_emulator OR ever_testflight OR ever_sideloaded)) AS clean_build_people,
    countIf(saw_disclosure AND NOT (ever_emulator OR ever_testflight OR ever_sideloaded)) AS clean_disclosure_people
FROM flags
```

Result: `1 | 1 | 0 | 1 | 1 | 1 | 0 | 0` in the selected-column order.

### Privacy-safe raw path query for the next re-read

Run only after the readiness query returns at least one clean disclosure person. Keep identifiers inside PostHog; export only a locally generated stable hash or aggregate path label. Select no full `properties` object.

```sql
SELECT
    person_id,
    distinct_id,
    event,
    timestamp,
    uuid,
    properties.$session_id AS session_id,
    properties.$app_version AS app_version,
    properties.$app_build AS app_build,
    properties.$app_namespace AS app_namespace,
    properties.$lib AS lib,
    properties.$os_name AS os_name,
    properties.$is_emulator AS is_emulator,
    properties.$is_testflight AS is_testflight,
    properties.$is_sideloaded AS is_sideloaded,
    properties.connection_state AS connection_state,
    properties.imported_count AS imported_count
FROM events
WHERE person_id IN (/* clean person set from the frozen exclusion CTE */)
  AND event IN (
      'healthkit_disclosure_viewed',
      'healthkit_connect_tapped',
      'healthkit_sync_completed',
      'app_launched',
      'onboarding_completed'
  )
  AND timestamp >= /* frozen cohort start */
  AND timestamp <= /* frozen query end */
ORDER BY person_id, timestamp, uuid
```

## Validation and caveats

- The frozen readiness query was run twice and returned the same `1 production-looking / 1 excluded / 0 clean` result.
- Exclusion overlap reconciles arithmetically: TestFlight 1 + sideloaded 1 − overlap 1 = union 1.
- No excluded person can appear in a clean raw set because the clean set is defined after the lifetime person-level union exclusion.
- Version/build filters exclude all pre-WP-40 events.
- Session-ID coverage, 24-hour ordered conversion, 1-hour sensitivity, path groups, and pre-existing-user sync paths are not computable until a clean disclosure viewer exists.
- The connected warehouse-schema helper was unavailable during execution, so event/property discovery used the live event taxonomy, per-event property schema, and successful narrow HogQL queries. No schema or project configuration was changed.
- Read-only only: no dashboards, cohorts, insights, filters, app code, instrumentation, backend, release, or HealthKit behavior changed.

## Privacy-safe appendix

There are no ordered clean-person rows to append. Aggregate path group: **QA/test-only disclosure path — 1 person; clean path groups — 0 people**. Reproduction is the frozen readiness query followed by the raw path template once the re-read condition is met.
