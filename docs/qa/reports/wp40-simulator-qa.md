# WP-40 S1 Simulator QA — 2026-07-10

## Story boundary

Validated only **S1 — Move HealthKit connect into the primary flow**. S2 auto-import, S3 value surfacing, and S4 live PostHog verification remain separate stories.

## Automated validation

- Focused XCTest: `testOnboardingHealthKitStepUsesExistingProviderAndRequiresConnectedState`
- Red state: failed to compile because `OnboardingHealthKitStep` did not exist.
- Green state: 1 test passed, 0 failed.
- Debug build-and-run succeeded on iPhone 17 simulator (iOS 26.3).
- Known warning only: deprecated `HKWorkout` initializer in the existing HealthKit service.

## S1 acceptance evidence

Launch arguments: `-RUNSMART_RECORD_ONBOARDING -RUNSMART_ONBOARDING_STEP 4`

1. **Prompt is in the primary onboarding flow** — PASS
   - Runtime snapshot exposed `Connect Apple Health` and `Continue without connecting` directly on onboarding step 5 of 6.
   - Evidence: `wp40-10-apple-health-step.png`.
2. **Skip does not block onboarding** — PASS
   - Tapping `Continue without connecting` advanced to the Ready screen with `Start RunSmart` available.
3. **Connect uses the real HealthKit permission path** — PASS
   - The action routes through `services.connect(provider: HealthKitSyncService.providerName)`, the same provider path used by the existing Profile connection flow.
   - The current simulator already had Health access, so the 2026-07-10 run advanced directly to Ready.
   - Preserved fresh-permission evidence from the partial branch work shows the system Health Access sheet: `wp40-18-after-wait.png`.

## Explicitly not completed

- S2 automatic first import was not implemented or validated as part of this story.
- S3 seeded Health data rendering was not validated.
- S4 production PostHog funnel counts were not queried for this story.
- Physical-device HealthKit QA remains required before release.
