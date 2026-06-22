---
product: RunSmart iOS
artifact: pre-mortem
feature: HRV dual-source attribution
status: draft
founder-review-needed: yes
date: 2026-06-22
source-prd: tasks/prd-hrv-dual-source-attribution-2026-06-22.md
source-pr: "#55"
release-train: v1.0.4 build 17
---

# Pre-Mortem: HRV Dual-Source Attribution

Assume v1.0.4 build 17 ships in the next two weeks, the Garmin reply is sent, and the release fails the Garmin or user trust goal. This pre-mortem names what most likely went wrong.

## Tigers

| Risk | Urgency | Why It Matters | Mitigation | Owner | Due |
|---|---|---|---|---|---|
| HealthKit source detection does not actually identify Garmin Connect HRV on a real device. | Launch-blocking | The core plan depends on classifying Garmin-via-HealthKit. If this fails, Garmin attribution could still be wrong. | Validate sample source bundle identifiers on a real device before relying on screenshots. If unavailable, keep HealthKit HRV as unknown. | Engineering | Before Story 4 merge |
| Apple Watch HRV is mislabeled as Garmin. | Launch-blocking | This violates user trust and creates the opposite brand-compliance problem. | Unit-test Apple bundle classification and verify UI uses `HRVSource`, not Garmin connection state. | Engineering | Before Story 4 merge |
| Older saved HealthKit snapshots fail to decode after adding source fields. | Launch-blocking | Existing users could lose wellness data or hit recovery loading failures. | Add Codable back-compat tests and default missing source to unknown. | Engineering | Story 1 |
| Screenshots sent to Garmin do not match the submitted App Store build. | Launch-blocking | Garmin inspects the live app, so mismatched evidence wastes review cycles. | Archive/upload/submit v1.0.4 build 17 before replying, and record screenshot provenance. | Founder + Release | Before Garmin reply |
| Source attribution appears below the fold or only in screenshots, not the actual app. | Launch-blocking | Garmin requires attribution wherever device-sourced health data appears. | Visual check Today and Recovery on target devices after Story 4. | Engineering | Before Story 5 complete |

## Paper Tigers

| Concern | Why It Is Not Blocking |
|---|---|
| Device model is not shown in v1.0.4. | The plan already scopes this to later. `Garmin` attribution is a practical first release if device model is not surfaced. |
| Full multi-source HRV history is not built. | The release goal is correct current attribution, not a history product. |
| Unknown HRV may show no source label. | This is safer than false attribution. Unknown should remain conservative until provenance is proven. |

## Elephants

| Concern | Investigation |
|---|---|
| The plan names specific bundle patterns, but real HealthKit samples may vary by region, Garmin app version, or source revision. | Capture real-device sample source evidence without health values and record only non-sensitive source metadata. |
| HealthKit query design could double-read HRV or create inconsistent value/source pairs. | Keep value and source resolution together where possible, or document why the average and source sample rule can diverge safely. |
| Demo mode may prove visual placement but not real provenance. | Separate screenshot evidence from real-device source-detection evidence. |
| The brand-compliance PR also contains screenshot infrastructure and version bump changes. | Keep PM gate focused on HRV attribution, and avoid broad refactors inside the release branch. |

## Launch-Blocking Action Plans

1. **Real-device source proof**
   - Mitigation: Run a focused HealthKit source metadata validation with Garmin-synced HRV.
   - Owner: Engineering/founder device holder.
   - Due: Before Story 4 merge.

2. **Back-compat source model**
   - Mitigation: Add missing-field decode tests for `HealthKitDailySnapshot` and `RecoverySnapshot` defaults.
   - Owner: Engineering.
   - Due: Story 1.

3. **UI attribution correctness**
   - Mitigation: Add deterministic preview/demo states for Garmin, Apple Health, and unknown HRV attribution.
   - Owner: Engineering.
   - Due: Story 4.

4. **Garmin reply sequencing**
   - Mitigation: Do not reply to Garmin until v1.0.4 build 17 is submitted or live and screenshots match that build.
   - Owner: Founder/release.
   - Due: Before Garmin reply.

## PM Gate Outcome

PR #55 should not be treated as App Store resubmission-ready until the launch-blocking Tigers above are closed or explicitly accepted by the founder.
