# WP-40 S3 + S4 closeout — 2026-07-12

## S3 — HealthKit value surfaces on device

**Status: PASS (Today); Recovery path documented for one optional screenshot.**

### Today (captured)

Physical-device QA on the founder iPhone confirmed the post-sync Today card:

- Section: **Today's activity**
- Attribution: **Apple Health**
- **Steps 1.8k**, **Active kcal 46**, **Sleep `--`**

Evidence: `docs/qa/reports/assets-2026-07-12-wp40-s3/wp40-s3-today-apple-health-card.png`

Sleep `--` is expected when Apple Health has no `sleepAnalysis` samples in the import window; it does not block S3 because steps and active calories are populated from the same `HealthKitDailySnapshot` written during sync.

### Recovery (code + navigation)

`recoverySnapshot()` Apple Health fallback (`"Recovery data synced from Apple Health."`) was code-verified 2026-07-10. On device, open **Profile → Wellness Trends → Readiness** to see that recommendation when Garmin is not the active recovery source.

## S4 — PostHog funnel re-read (post PR #84 merge)

**Project:** [Running coach — 171597](https://us.posthog.com/project/171597)
**Window:** 2026-07-11 → 2026-07-12 (UTC)
**Filter:** `filterTestAccounts=true`

### Ordered funnel

| Step | Persons |
|---|---:|
| `healthkit_disclosure_viewed` | 1 |
| `healthkit_connect_tapped` | 0 |
| `healthkit_sync_completed` | 0 |

Ordered conversion is **not meaningful** at n=1 and this person did not complete the connect step in-sequence during the window (likely Profile disclosure view without a connect tap in the funnel path).

### Raw build-21 events (same window)

| Event | Events | People |
|---|---:|---:|
| `healthkit_disclosure_viewed` | 2 | 1 |
| `healthkit_sync_completed` | 3 | 1 |

Sync events are firing on **1.0.7 (21)** including activity on **2026-07-12 ~09:04 UTC** (today's device session). This confirms instrumentation still works post-merge.

### Decision-grade read (WP-42 alignment)

Per `docs/qa/reports/runsmart-wp40-healthkit-raw-hogql-funnel-autopsy-2026-07-11.md`, **0 clean disclosure viewers** remain after excluding TestFlight/sideload/emulator traffic. Founder's Xcode/sideload sessions should not be used for product funnel percentages.

**S4 re-read conclusion:** Mechanics verified; **no clean external cohort yet**. Re-run WP-42 when ≥1 native App Store/TestFlight user with no QA flags views disclosure, and wait for ≥10 clean viewers before product recommendations.

## WP-40 remaining open items

| Item | Status |
|---|---|
| S1 onboarding HealthKit | Shipped + device QA |
| S2 auto-import on connect | Shipped + device QA |
| S3 Today screenshot | **Done 2026-07-12** |
| S3 Recovery screenshot | Optional — Profile → Wellness Trends |
| S4 post-merge re-read | **Done 2026-07-12** (cohort still empty for decisions) |
| S2 periodic background re-sync | Founder decision — not built |
