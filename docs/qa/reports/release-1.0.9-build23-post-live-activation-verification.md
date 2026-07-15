# RunSmart 1.0.9 (23) post-live activation verification

**Status:** ready after approval and confirmed public App Store availability

**Mode:** Grower

**Decision metric:** founder-excluded physical install → `run_completed` within mature D7

**PostHog:** Running coach (`171597`, UTC)

**Release:** `1.0.9` (`23`)

**Scope:** documentation and read-only analytics only

This package separates **event verification** from **product interpretation**. The first proves the reviewed App Store binary emits expected names/properties on a physical path. The second begins only after a clean founder/QA-excluded cohort fully matures through D7.

Do not start E1 while 1.0.9 is under review. Do not alter PostHog dashboards, insights, cohorts, definitions, test filters, flags, experiments, or production configuration.

## Source contract

Checked against `main` at reviewed-build commit `6cb4094`, not inferred from the proposal.

- [Definitions](<../../../IOS RunSmart app/Services/Analytics/AnalyticsEvents.swift>), [PostHog setup](<../../../IOS RunSmart app/Services/Analytics/AnalyticsService.swift>), [app shell](<../../../IOS RunSmart app/App/RunSmartLiteAppShell.swift>)
- [Sign-in](<../../../IOS RunSmart app/Features/Auth/SignInView.swift>), [onboarding](<../../../IOS RunSmart app/Features/Onboarding/OnboardingView.swift>), [plan lifecycle](<../../../IOS RunSmart app/Services/PlanGenerationStore.swift>)
- [Supabase services](<../../../IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift>), [production run/permission services](<../../../IOS RunSmart app/Services/Production/RunSmartProductionServices.swift>), [notifications](<../../../IOS RunSmart app/Core/Push/PushService.swift>)
- [Today](<../../../IOS RunSmart app/Features/Today/TodayTabView.swift>), [run start](<../../../IOS RunSmart app/Features/Run/RunTabView.swift>), [reports](<../../../IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift>), [sharing](<../../../IOS RunSmart app/Features/Sharing/ProgressShareCard.swift>)

The source proposal remains on `claude/runsmart-ftux-audit-240648` at `docs/plans/2026-07-13-ftux-upgrade-plan.md`; E1 evidence is in that branch's journey audit, section 13.

## Canonical mature-D7 cohort

An entrant is one PostHog person whose first qualifying `Application Installed`:

- has `$app_namespace = 'com.runsmart.lite'`, `$lib = 'posthog-ios'`, `$os_name IN ('iOS', 'iPadOS')`;
- has `$app_version = '1.0.9'`, `$app_build = 23`;
- has `$is_emulator = false`, `$is_testflight = false`, `$is_sideloaded = false`; and
- occurred no later than `snapshot_end_utc - 7 days`.

`Application Installed` is PostHog iOS lifecycle autocapture, not a custom event. The SDK initializes at `AnalyticsService.swift:31-43` and `RunSmartLiteAppShell.swift:486-493`; the exact event exists in the live schema.

Apply exclusions **person-stably before every count**:

- exclude a person if any event in their full available history has emulator, TestFlight, or sideloaded true;
- exclude established redacted RunSmart founder prefixes `82f3c85c…` and `aa28b5c7…`;
- do not substitute the project test-account filter; it is insufficient for native RunSmart traffic;
- do not invent a bot filter: Portfolio HQ's 2026-07-12 read says the RunSmart bot property was unavailable.

The headline numerator is any `run_completed` at/after install and by `install_at + 7 days`, whether or not every diagnostic intermediate event was observed. Count each person once. The fully ordered eight-step path is reported separately so missing telemetry or a valid alternate route cannot silently erase a real activation. Upgrades without a qualifying install are not entrants. Freeze `snapshot_end_utc`; a moving dashboard is not a saved snapshot.

## Ordered activation funnel

| Step | Event | Required properties | Code evidence |
|---:|---|---|---|
| 1 | `Application Installed` | lifecycle/build/physical flags above | SDK setup and live schema |
| 2 | `sign_in_completed` | `method = 'apple'` | `AnalyticsEvents.swift:13-15`; `SignInView.swift:143-149` |
| 3 | `onboarding_started` | none | `AnalyticsEvents.swift:25-27`; `OnboardingView.swift:95-99` |
| 4 | `onboarding_completed` | `goal`, `experience`, `days_per_week`, `$set.onboarding_completed_at` | `AnalyticsEvents.swift:36-44`; `OnboardingView.swift:294-306` |
| 5 | `plan_generated` | `plan_type`, `duration_weeks` | `AnalyticsEvents.swift:76-81`; `SupabaseRunSmartServices.swift:273-281` |
| 6 | `first_workout_viewed` | `workout_type` | `AnalyticsEvents.swift:234-242`; `TodayTabView.swift:80-86,351-354` |
| 7 | `run_started` | `source` (`planned`/`free`) | `AnalyticsEvents.swift:108-110`; `RunTabView.swift:250-254` |
| 8 | `run_completed` | `distance_km`, `duration_s`, `pace_min_km`, `run_type`, `is_first_run` | `AnalyticsEvents.swift:112-137`; `RunSmartProductionServices.swift:943-949`; `SupabaseRunSmartServices.swift:1509-1521` |

`onboarding_step_completed` is diagnostic, with `step_number`/`step_name` (`AnalyticsEvents.swift:29-34`). Values are `goal`, `experience`, `schedule`, `privacy`, `healthkit`, `ready` (`OnboardingView.swift:32-34`). Legacy `privacy` intentionally names the current Coaching UI step.

## WP-43/WP-45 event contract

| Event | Required properties / actual values | Definition and call site |
|---|---|---|
| `sign_in_failed` | `error_domain` string, `error_code` integer | `AnalyticsEvents.swift:17-22`; `SignInView.swift:150-156`; cancel emits nothing |
| `onboarding_step_abandoned` | `last_step`, `dwell_seconds` integer | `AnalyticsEvents.swift:48-53`; `OnboardingView.swift:104-116` |
| `permission_requested` | `kind` = `location`/`notifications` | `AnalyticsEvents.swift:60-62`; `RunSmartProductionServices.swift:350-355`; `PushService.swift:209-217` |
| `permission_granted` | same `kind` | `AnalyticsEvents.swift:64-66`; `RunSmartProductionServices.swift:455-480`; `PushService.swift:218-225` |
| `permission_denied` | same `kind` | `AnalyticsEvents.swift:68-70`; same outcome sites |
| `healthkit_connect_failed` | `reason` = `disconnected`, `connecting`, or `error` on failed path | `AnalyticsEvents.swift:72-74`; states `RunSmartModels.swift:1228-1233`; `OnboardingView.swift:321-340` |
| `plan_generation_started` | none | `AnalyticsEvents.swift:85-87`; `PlanGenerationStore.swift:78-87` |
| `plan_generation_succeeded` | `duration_ms` on normal path | `AnalyticsEvents.swift:89-91,101-104`; `PlanGenerationStore.swift:87-89` |
| `plan_generation_failed` | `duration_ms` on normal path | `AnalyticsEvents.swift:93-95,101-104`; `PlanGenerationStore.swift:90-92` |
| `plan_generation_timed_out` | `duration_ms`, about 45,000 | `AnalyticsEvents.swift:97-104`; `RunSmartLiteAppShell.swift:429-445` |
| `first_workout_viewed` | `workout_type = WorkoutKind.rawValue` | `AnalyticsEvents.swift:234-242`; `TodayTabView.swift:80-86,351-354`; values `RunSmartModels.swift:35-44` |
| `first_run_cta_viewed` | `workout_type`, `scheduled_today` boolean | `AnalyticsEvents.swift:214-219`; `FirstRunActivationSheet.swift:82-86` |
| `run_report_generate_tapped` | `source` = `garmin_activity`/`run_report_detail` | `AnalyticsEvents.swift:246-248`; `SecondaryFlowView.swift:1188,1314` |
| `run_report_generate_succeeded` | same `source` | `AnalyticsEvents.swift:250-252`; `SecondaryFlowView.swift:1192,1321` |
| `run_report_generate_failed` | same `source`; no reason/code | `AnalyticsEvents.swift:254-256`; `SecondaryFlowView.swift:1195,1324` |
| `insight_expanded` | `surface = 'workout_breakdown'` | `AnalyticsEvents.swift:258-264`; only call `TodayTabView.swift:849-857` |
| `share_progress_tapped` | `payload_kind` = `Run Report`, `Benchmark`, `Milestone` | `AnalyticsEvents.swift:266-270`; `ProgressShareCard.swift:3-7,148-154` |
| `onboarding_completed` person update | `$set.onboarding_completed_at` ISO-8601 | `AnalyticsEvents.swift:36-44`; `OnboardingView.swift:301-306` |

### Proposal gaps

- `share_progress_completed` has **no definition/call site** because `ShareLink` has no completion callback (`AnalyticsEvents.swift:272-274`; `ProgressShareCard.swift:148-151`). Do not search for it or call absence an outage.
- `insight_expanded` is only `workout_breakdown`. Proposed why-this-workout, week-in-review, and coach-learned surfaces lack call sites.
- Every other proposed event above has a definition and call site.

## Semantic caveats

### `onboarding_step_abandoned`

Means the app entered background during onboarding. It does not prove permanent abandonment, deletion, or no return. One person may emit repeatedly. `dwell_seconds` is time since current-step entry, truncated to integer. `last_step = 'privacy'` means Coaching. Use only diagnostically.

### `plan_generation_timed_out`

Means the activation poll found no runnable workout within 45 seconds. It is not backend lifecycle failure. Generation continues and may later emit `plan_generated` plus `plan_generation_succeeded`; timeout and success are not mutually exclusive.

## Post-approval verification

### Release and mechanics

- [ ] Apple approved 1.0.9 (23), and the public listing offers it; approval alone is insufficient.
- [ ] Install public 1.0.9 (23) on a physical device, not Xcode/TestFlight/sideload/emulator; record UTC bounds.
- [ ] Exercise fresh install → sign-in → onboarding → plan → first workout → physical run start/completion.
- [ ] If safe, background once on a known onboarding step.
- [ ] Exercise permission prompts only when genuinely `notDetermined`; do not reset production permissions to manufacture events.
- [ ] Exercise report generation, workout-breakdown expansion, share tap when naturally available.
- [ ] Background and wait ≥60 seconds; SDK flush is 20 events or 30 seconds (`AnalyticsService.swift:38-42`).

An excluded founder/QA path may prove mechanics, never product performance.

### Property query

Privacy-safe: no identifiers, email, device, location, route, HealthKit payload, full properties object, or full `$set` object.

```sql
SELECT event, timestamp,
    properties.$app_version AS app_version, properties.$app_build AS app_build,
    properties.$is_emulator AS is_emulator,
    properties.$is_testflight AS is_testflight,
    properties.$is_sideloaded AS is_sideloaded,
    properties.error_domain AS error_domain, properties.error_code AS error_code,
    properties.last_step AS last_step, properties.dwell_seconds AS dwell_seconds,
    properties.kind AS permission_kind, properties.reason AS failure_reason,
    properties.duration_ms AS duration_ms, properties.workout_type AS workout_type,
    properties.scheduled_today AS scheduled_today,
    properties.source AS source, properties.surface AS surface,
    properties.payload_kind AS payload_kind, properties.goal AS goal,
    properties.experience AS experience, properties.days_per_week AS days_per_week,
    properties.$set.onboarding_completed_at AS onboarding_completed_at
FROM events
WHERE timestamp >= toDateTime('REPLACE_VERIFICATION_START_UTC', 'UTC')
  AND timestamp <= toDateTime('REPLACE_VERIFICATION_END_UTC', 'UTC')
  AND properties.$app_namespace = 'com.runsmart.lite'
  AND properties.$app_version = '1.0.9'
  AND toFloat(properties.$app_build) = 23
  AND event IN (
      'sign_in_failed', 'onboarding_step_abandoned',
      'permission_requested', 'permission_granted', 'permission_denied',
      'healthkit_connect_failed', 'plan_generation_started',
      'plan_generation_succeeded', 'plan_generation_failed',
      'plan_generation_timed_out', 'first_workout_viewed', 'first_run_cta_viewed',
      'run_report_generate_tapped', 'run_report_generate_succeeded',
      'run_report_generate_failed', 'insight_expanded',
      'share_progress_tapped', 'onboarding_completed',
      'run_started', 'run_completed')
ORDER BY timestamp, event
```

Pass mechanics when naturally exercised events have exact names/properties, build 23, and physical flags false. Mark conditional failures/denials/timeouts **not exercised**, rather than forcing them. Absence alone does not prove a broken feature.

Pre-approval read-only baseline (2026-07-15): build-23 QA telemetry already observed `first_workout_viewed`, `permission_requested`, `permission_granted`, `plan_generation_started`, `plan_generation_succeeded`, `plan_generation_failed`, and `sign_in_failed`. These prove mechanics only and are excluded from decisions.

## Mature-D7 ordered query

Replace only `REPLACE_SNAPSHOT_END_UTC`; save it with output. The exact query was executed successfully against live HogQL on 2026-07-15 using a fixed pre-live snapshot and returned the expected zero build-23 mature cohort. `toDateTime(e.timestamp)` is required because `windowFunnel` rejects native `DateTime64`.

```sql
WITH
    toDateTime('REPLACE_SNAPSHOT_END_UTC', 'UTC') AS snapshot_end,
    candidate AS (
        SELECT person_id, min(timestamp) AS install_at
        FROM events
        WHERE event = 'Application Installed'
          AND properties.$app_namespace = 'com.runsmart.lite'
          AND properties.$lib = 'posthog-ios'
          AND properties.$os_name IN ('iOS', 'iPadOS')
          AND properties.$app_version = '1.0.9'
          AND toFloat(properties.$app_build) = 23
          AND coalesce(toBool(properties.$is_emulator), false) = false
          AND coalesce(toBool(properties.$is_testflight), false) = false
          AND coalesce(toBool(properties.$is_sideloaded), false) = false
          AND timestamp <= snapshot_end - INTERVAL 7 DAY
        GROUP BY person_id),
    lifetime_flags AS (
        SELECT person_id,
            countIf(coalesce(toBool(properties.$is_emulator), false)) > 0 AS ever_emulator,
            countIf(coalesce(toBool(properties.$is_testflight), false)) > 0 AS ever_testflight,
            countIf(coalesce(toBool(properties.$is_sideloaded), false)) > 0 AS ever_sideloaded
        FROM events WHERE person_id IN (SELECT person_id FROM candidate)
        GROUP BY person_id),
    clean_installs AS (
        SELECT c.person_id, c.install_at FROM candidate c
        INNER JOIN lifetime_flags f ON c.person_id = f.person_id
        WHERE NOT (f.ever_emulator OR f.ever_testflight OR f.ever_sideloaded)
          AND NOT startsWith(toString(c.person_id), '82f3c85c')
          AND NOT startsWith(toString(c.person_id), 'aa28b5c7')),
    paths AS (
        SELECT c.person_id,
            countIf(e.event = 'run_completed') > 0 AS activated_within_d7,
            windowFunnel(604800)(toDateTime(e.timestamp),
                e.event = 'Application Installed', e.event = 'sign_in_completed',
                e.event = 'onboarding_started', e.event = 'onboarding_completed',
                e.event = 'plan_generated', e.event = 'first_workout_viewed',
                e.event = 'run_started', e.event = 'run_completed') AS max_step
        FROM clean_installs c INNER JOIN events e ON e.person_id = c.person_id
        WHERE e.timestamp >= c.install_at
          AND e.timestamp <= c.install_at + INTERVAL 7 DAY
        GROUP BY c.person_id)
SELECT count() AS mature_physical_installs,
    countIf(activated_within_d7) AS run_completed_within_d7,
    countIf(max_step >= 2) AS signed_in,
    countIf(max_step >= 3) AS onboarding_started,
    countIf(max_step >= 4) AS onboarding_completed,
    countIf(max_step >= 5) AS plan_generated,
    countIf(max_step >= 6) AS first_workout_viewed,
    countIf(max_step >= 7) AS run_started,
    countIf(max_step >= 8) AS ordered_run_completed
FROM paths
```

Report `run_completed_within_d7 / mature_physical_installs` as the decision metric. Report `ordered_run_completed` only as the end of the diagnostic path. A difference between them is an instrumentation/alternate-path investigation, not permission to discard the direct completion. Include snapshot end, build, exclusions, and denominator. Keep identifiers in PostHog.

## Minimum interpretation cohort

- Mechanics: one excluded physical App Store path.
- Descriptive read: at least **10 clean founder/QA-excluded build-23 physical installs, each D7-mature**. Below 10, report readiness/counts only; do not name bottleneck or recommend change.
- This matches WP-42's existing 10-clean-entrant minimum. It is not a power claim.

## Experiment E1 gate

E1 is the deterministic coach preview while the real plan generates.

**Start remains NO-GO** until:

1. 1.0.9 (23) is publicly live.
2. Public physical flow verifies `onboarding_completed` + `$set.onboarding_completed_at`, `plan_generation_started`, a normal lifecycle terminal, `first_workout_viewed`, `first_run_cta_viewed`, `run_started`, `run_completed`.
3. The semantic caveats are accepted in the analysis plan.
4. Random assignment and an E1 exposure event/variant property are defined before enrollment. `main` has no E1 exposure/variant/assignment, so E1 cannot start from current instrumentation alone.

**Decision gate:** ≥200 D7-mature new users per arm; primary is share with `first_workout_viewed` within 10 minutes of `onboarding_completed`; supporting latency is `onboarding_completed` → `first_run_cta_viewed`; treatment week-1 `flex_week` usage must be no higher than control; treatment D7 retention must be no lower.

**GO:** ≥200 mature users/arm, treatment primary ≥ `control × 1.10`, neither guardrail worsens.

**NO-GO:** any condition false. The hypothesis expects ≥15%, but decision evidence is ≥10% relative.

## Operational dashboard is different

Portfolio HQ links dashboard `1841362`. Read-only inspection on 2026-07-15 found rolling 30-day trends, a 14-day exception chart, 8-week retention, independent totals, and ordered funnels with 14-day windows; several tiles use `filterTestAccounts = false`.

Operating dashboard `1775590` also defaults to last 30 days UTC; onboarding/plan-to-run funnels use 14-day windows and lack Portfolio HQ person-stable exclusions. Both are event-health drill-downs, not substitutes for the frozen build-23 mature-D7 query.

## Closeout checklist

### Event verification

- [ ] Public physical version/build and UTC bounds confirmed.
- [ ] Naturally exercised events match code names/properties.
- [ ] Conditional events marked observed/not exercised/missing.
- [ ] `share_progress_completed` marked not implemented.
- [ ] `insight_expanded` marked workout-breakdown-only.
- [ ] Founder/QA verification person excluded from every product count.

### Product conclusion

- [ ] Snapshot frozen; entrants are build 23, physical-looking, D7-mature.
- [ ] Lifetime flags and founder prefixes excluded before every step.
- [ ] Clean denominator ≥10 before bottleneck/recommendation language.
- [ ] Numerator, denominator, steps, exclusions, uncertainty, re-read condition reported.
- [ ] Operational dashboards used only for drill-down.
- [ ] E1 off until start gate; decision waits for ≥200 mature users/arm.

## Verification sequence

`approval` → `public availability` → `physical build-23 mechanics` → `60-second flush` → `property query` → `record gaps` → `exclude QA path` → `wait for ≥10 clean mature-D7 installs` → `freeze snapshot` → `ordered query` → `report` → `evaluate E1 start gate`.
