# Spec: E7 — Garmin / Wearable Depth

*Priority: P3 (90+ days)*
*Retention link: Striver accuracy*
*Strategy source: `docs/product-strategy-2026-05.md`*

## Summary

E7 adds 7-day Garmin wellness depth for Striver users so daily coaching feels grounded in trend context, not single-point values. The first release includes:

- Real 7-day **HRV trend**
- Real 7-day **training readiness trend**
- Compact trend visibility in **Today**
- Full trend visibility in **Garmin Wellness / Recovery**

## Goals

1. Replace placeholder wellness sparklines with real 7-day values from Garmin data.
2. Show trend direction in plain language (rising/stable/dipping).
3. Gate richer trend surfaces to Striver-like users with wearable context.
4. Preserve current Rookie/no-wearable behavior.

## Non-Goals

- No medical diagnosis or injury prediction language.
- No full Apple Watch/HealthKit historical trend backfill in v1.
- No redesign of coaching logic for workout prescription in this story.
- No social/community or watch complication work.

## User Stories

1. As a Striver with Garmin sync, I want to see a real 7-day HRV trend so I can trust my recovery signal.
2. As a Striver with Garmin sync, I want to see a real 7-day training-readiness trend so I understand whether readiness is improving or slipping.
3. As a non-Striver or disconnected user, I want the current experience to remain stable with honest empty states instead of fake trend data.

## UX Requirements

### Today Surface

- Keep existing `TodayMiniStatCard` layout.
- Feed real `MetricBars` values for HRV and Recovery/Readiness mini-stats.
- Add a compact Striver-only trend card:
  - HRV 7-day row
  - Training readiness 7-day row
  - One-line trend summary copy

### Wellness / Recovery Surface

- Garmin wellness panel includes:
  - HRV chart (ms) for last 7 days
  - Training readiness chart (0-100) for last 7 days
- Recovery dashboard replaces static mock values with live trend-derived values.
- Tapping readiness area from Today routes to Recovery dashboard.

## Data and State

### Data Source

- Supabase `garmin_daily_metrics_deduped`
- Query by authenticated user, ordered by date, last 7 rows

### Models

- `DailyWellnessPoint`:
  - `date`
  - `hrvMilliseconds`
  - `trainingReadiness`
  - `bodyBattery`

- `WellnessTrendSeries`:
  - `days`
  - `hrvBars`
  - `readinessBars`
  - `hrvTrendSummary`
  - `readinessTrendSummary`
  - `latestHRVDisplay`
  - `latestReadinessDisplay`

### Readiness Source Rule

- Prefer Garmin `training_readiness` when present.
- Fallback to `body_battery` only for trend display when training readiness is missing.

### Striver Gate (v1 heuristic)

- True when wearable context exists (`garmin` source/device) and profile appears intermediate+.
- False for beginner flows and no wearable signals.

## Permissions

- No new permissions.
- Existing Health/Garmin privacy standards remain unchanged.

## Error, Empty, and Loading States

- No Garmin trend data: show "Need more synced days" state, no fake chart.
- Partial history (<3 days): show partial bars with "Building trend" copy.
- Data fetch failure: preserve existing surfaces and show subtle unavailable copy.

## Accessibility

- Chart summaries must have text equivalents (not color-only meaning).
- Dynamic Type support for trend summary text and labels.
- VoiceOver labels announce trend direction and latest values.

## Analytics or Observability

- Optional follow-up instrumentation:
  - `e7_trend_card_viewed`
  - `e7_recovery_dashboard_opened`
- Not required for first implementation slice.

## Acceptance Criteria

1. Striver + Garmin users see real 7-day HRV and readiness trends on Today and Wellness/Recovery.
2. Today no longer uses hardcoded sparkline arrays for HRV/recovery when trend data is available.
3. `training_readiness` is consumed when present; fallback behavior is tested.
4. Non-Striver/no-wearable users have no regression and no fabricated trend visuals.
5. Build passes and focused tests cover mapper, gating, and sparse-data behavior.

## QA Plan

1. Striver preview: 7 full days of Garmin data → both trend surfaces render.
2. Sparse preview: 2 days only → partial state + building-trend copy.
3. Missing `training_readiness`: fallback to `body_battery` for readiness bars.
4. No Garmin data: existing cards remain, trend card hidden or empty-state.
5. Route from Today readiness area to Recovery dashboard shows live values.

## TestFlight Notes

- Call out that trend depth is Garmin-first in this release.
- Avoid medical framing in release notes and in-app copy.
