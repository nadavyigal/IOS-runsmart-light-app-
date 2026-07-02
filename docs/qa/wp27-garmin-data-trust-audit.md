# WP-27: Garmin Data Trust Audit

*Track:* Garmin Production Gate + Garmin-powered product depth
*Status:* Implemented
*Started:* 2026-07-02
*Branch:* `codex/wp27-garmin-data-trust-audit`

## Objective

Audit Garmin-derived labels, fallback behavior, and source attribution across Today, Report/Activity, Recovery, Wellness Trends, and Profile. Fix only product-critical trust issues that can affect Garmin evidence or user-visible source clarity.

## Readiness Check

WP-27 is ready to execute as a code/data-trust audit because:

- Canonical Garmin work-packet specs live in Agentic OS executive-os/work-packets/WP-25 through WP-28.
- PR #71 was mislabeled WP-26, but its Gate-4 evidence package is canonically WP-27.
- Founder-owned live-device evidence actions remain pending, but they do not block a local audit of Garmin data attribution paths.

WP-27 data-trust fixes are not a replacement for WP-27 live-device evidence. This repo should not send Garmin replies or claim Gate-4 readiness.

## Audit Results

| Surface | Status | Notes |
| --- | --- | --- |
| Today route suggestion | Pass | Garmin route suggestions use `sourceAttribution` from `RunSmartAttribution.garminDeviceLabel(...)`, with activity device name first and connected fallback second. |
| Activity / Report rows | Pass | `ActivityRow` uses `RunSmartAttribution.sourceLabel(...)`; Garmin rows prefer row `sourceDeviceName`, then connected fallback, then `Garmin`. |
| Run Report detail | Pass | `RunReportDetail.withGarminDeviceFallback(...)` rewrites Garmin report title/source with the same attribution helper. |
| Profile Garmin Connect tile | Pass | Uses Garmin Connect tile only for the connection entry. Wellness entry is RunSmart-owned `Wellness Trends`. |
| Garmin recent activity rows | Pass | `RecentActivityRow` uses `RunSmartAttribution.garminDeviceLabel(...)`. |
| Recovery dashboard | Fixed | Previously showed Garmin attribution whenever Garmin was connected, even if the loaded recovery snapshot was HealthKit-only. Now it requires `RecoverySnapshot.includesGarminDeviceSourcedData`. |
| Wellness Trends | Fixed | Previously showed `Garmin` attribution and derived-data footer unconditionally. Now it requires connected Garmin plus Garmin-backed recovery/trend data. |
| Morning Check-In | Fixed | Previously could show a Garmin proposal when Garmin was connected but recovery values came from HealthKit/manual fallback. Now it requires Garmin-backed recovery data. |
| Cached device model fallback | Fixed | Wellness surfaces now pass cached device names through `RunSmartAttribution.garminDeviceLabel(...)`, so bare values such as `Forerunner 965` render as `Garmin Forerunner 965`. |

## Code Changes

- Added `RecoverySnapshot.includesGarminDeviceSourcedData`, defaulting to `false`.
- Marked Supabase Garmin recovery snapshots with `includesGarminDeviceSourcedData: true`.
- Gated Recovery dashboard, Wellness Trends, and Morning Check-In Garmin attribution on actual Garmin-backed recovery/trend data.
- Normalized cached Garmin connection device names through `RunSmartAttribution.garminDeviceLabel(...)`.
- Kept HealthKit-only recovery from displaying Garmin attribution even when Garmin is connected.

## Verification Plan

- Focused attribution tests:
  - `testBareConnectedGarminDeviceFallbackGetsBrandPrefix`
  - `testRecoverySnapshotDefaultsToNonGarminUntilExplicitlyMarked`
  - existing Garmin attribution tests
- Static checks:
  - `git diff --check`
  - app-source search for removed legacy `Garmin Wellness` strings

## Verification Result

- `git diff --check` passed.
- App-source search found no `Garmin Wellness` / `garminWellness` strings.
- Full `xcodebuild test` passed on `iPhone 17 Pro, OS=26.5` with `-parallel-testing-enabled NO`: 234 XCTest tests and 3 Swift Testing tests passed.
- Confirmed `testBareConnectedGarminDeviceFallbackGetsBrandPrefix` and `testRecoverySnapshotDefaultsToNonGarminUntilExplicitlyMarked` executed and passed.
- Earlier iPhone 17 full-suite attempt built and launched but stalled before test-case output; interrupted after 224.522 seconds and retried on iPhone 17 Pro.
- Known warning remains: `HealthKitSyncService.swift` uses deprecated `HKWorkout` initializer.

## Remaining Founder/Live Checks

- WP-27 founder-owned real-device screenshot capture still must verify the actual `1.0.7 (20)` screenshots on a real device.
- Official Garmin Connect tile provenance is now verified in repo; founder still needs to verify captured screenshots render the asset correctly.
- If Garmin responds with new instructions about "start all over," update this audit before starting WP-28.
