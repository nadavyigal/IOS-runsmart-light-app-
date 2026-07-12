# WP-40 S3 physical-device evidence — 2026-07-12

## Device

- **Device:** Nadav.Yigal's iPhone (iPhone 13, iOS 26.x)
- **Build:** Debug from Xcode on `main` (1.0.7 / 21)
- **Account:** Founder production account (real HealthKit authorization)

## S3A — Today tab (PASS)

Screenshot: `wp40-s3-today-apple-health-card.png`

Observed on Today tab after HealthKit sync:

| Field | Value | Source label |
|---|---|---|
| Steps | 1.8k | Apple Health |
| Active kcal | 46 | Apple Health |
| Sleep | `--` | Apple Health (no sleep sample in window) |

**Pass criteria met:** `TodayHealthSummaryCard` renders with **"Today's activity"** + **"Apple Health"** attribution and real synced steps/calories. `hasAnyData` is true.

### Sleep `--` note (not a defect)

Sleep reads `sleepAnalysis` samples from **yesterday start → now** (`HealthKitSyncService.sleepDuration`). `--` means no asleep samples in that window or sleep permission/sample gap in Apple Health — steps and calories still prove the snapshot pipeline.

## S3B — Recovery / wellness (manual capture)

Deep link `-OPEN_SECONDARY recoveryDashboard` requires `-RUNSMART_DEMO_MODE` (preview data only).

On a **real signed-in account**, use:

1. **Profile** tab → **Connected** → **Wellness Trends**
2. Confirm **Readiness** panel shows recommendation **"Recovery data synced from Apple Health."** (when Garmin is not the recovery source)

Optional: if Striver persona is active, Today → wellness trend card → Recovery dashboard shows the same Apple Health fallback copy in `recovery.recommendation`.
