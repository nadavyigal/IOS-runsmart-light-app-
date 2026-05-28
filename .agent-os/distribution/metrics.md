# RunSmart — Metrics

Project-level snapshot. Update during the weekly cycle.
Last synced from: `RunSmart iOS/docs/product-strategy-2026-05.md` (2026-05-24)

## North Star Metrics

- **D7 retention** (primary): percentage of users who return and log a run by day 7
- **D14 retention** (primary): percentage of users who return and log a run by day 14
- **First plan generated** (activation): user generates their first AI training plan within first session

Tracking status: `not tracked` — rs-analytics-001 spec is ready; execute in a product-code session.

## Current Snapshot (week of YYYY-MM-DD)

| Metric (canonical) | This week | Prior week | Delta | Status | Note |
|---|---|---|---|---|---|
| `runsmart.acquisition.app_store_impressions` | | | | not tracked | App Store Connect — pull manually |
| `runsmart.acquisition.app_store_install_rate` | | | | not tracked | App Store Connect — pull manually |
| `runsmart.activation.first_open_to_onboarding_complete` | | | | not tracked | needs PostHog event |
| `runsmart.activation.first_plan_generated` | | | | not tracked | needs PostHog event |
| `runsmart.activation.first_run_logged` | | | | not tracked | needs PostHog event |
| `runsmart.retention.d7` | | | | not tracked | primary north star |
| `runsmart.retention.d14` | | | | not tracked | primary north star |
| `runsmart.retention.readiness_check_to_session_completed` | | | | not tracked | safety confidence signal |
| `runsmart.retention.week1_adherence` | | | | not tracked | |
| `runsmart.retention.weekly_active_runners` | | | | not tracked | |
| `runsmart.revenue.paid_users` | | | | not tracked | v1.0 is free; activate when paid tier ships |
| `runsmart.revenue.mrr` | | | | not tracked | v1.0 is free; activate when paid tier ships |

## Key Conversion Events (to instrument in rs-analytics-001)

1. `app_opened` — first open
2. `onboarding_completed` — completed onboarding flow
3. `plan_generated` — first AI training plan generated
4. `run_logged` — first run recorded
5. `readiness_check_completed` — readiness check completed (trust signal)
6. `debrief_viewed` — post-run debrief opened
7. `reactivation` — return after 7+ day gap

## Tracked Keywords (App Store)

| Keyword | Rank | Trend |
|---|---|---|
| ai running coach | | |
| adaptive training plan | | |
| beginner 5k | | |
| marathon training app | | |
| garmin running | | |
| strava plan | | |
| run coach app | | |
| beginner marathon plan | | |

## Anomalies This Week

- (none) / list
