---
product: RunSmart iOS
artifact: user-stories
feature: HRV dual-source attribution
status: draft
founder-review-needed: yes
date: 2026-06-22
source-prd: tasks/prd-hrv-dual-source-attribution-2026-06-22.md
source-assumptions: tasks/assumptions-hrv-dual-source-attribution-2026-06-22.md
source-pr: "#55"
---

# User Stories: HRV Dual-Source Attribution

These stories convert PR #55's HRV attribution plan into implementation slices. Execute one story at a time.

## Story 1: HRV Provenance Model And Back-Compat

**Description:** As a RunSmart engineer, I want HRV source to be modeled explicitly, so that existing and future recovery data can carry source attribution safely.

**Design:** `HealthKitDailySnapshot`, `RecoverySnapshot`, and pure `HRVSource` attribution mapping.

**Conversation:**
This is the first story because it creates the source contract without changing user-facing behavior. It should prove older stored snapshots still decode and that attribution labels are deterministic.

**Acceptance Criteria:**
1. `HRVSource` supports Garmin, Apple Health, and unknown.
2. `HRVSource` exposes attribution labels for Garmin and Apple Health only.
3. `HealthKitDailySnapshot` can decode old payloads without an HRV source field.
4. `RecoverySnapshot` can carry HRV source without breaking previews and service defaults.
5. Unit tests cover Codable back-compat and label mapping.
6. No UI attribution changes ship in this story.

## Story 2: HealthKit HRV Source Classification

**Description:** As a Garmin or Apple Health runner, I want RunSmart to detect where HealthKit HRV came from, so that HRV attribution is honest.

**Design:** Pure bundle classifier plus HealthKit sample-source read path.

**Conversation:**
This story tests the riskiest assumption. HealthKit HRV is currently read as a plain average. The new path must inspect sample source metadata and classify Garmin Connect, Apple, or unknown sources.

**Acceptance Criteria:**
1. A pure classifier maps Garmin Connect bundle identifiers to Garmin.
2. A pure classifier maps Apple bundle identifiers to Apple Health.
3. Unknown and nil bundle identifiers map to unknown.
4. The daily HealthKit HRV read stores both value and source.
5. Tests cover Garmin, Apple, third-party, and nil bundle inputs.
6. A real-device validation note is added before relying on Garmin-via-HealthKit screenshots.

## Story 3: HRV Source Precedence Resolver

**Description:** As a runner with multiple HRV sources, I want RunSmart to pick the right source, so that it does not mislabel mixed recovery data.

**Design:** Pure resolver used by recovery assembly and trend display paths.

**Conversation:**
This story handles the case where direct Garmin data and HealthKit data both exist. It should not guess from connection state. It should resolve from actual data source and document the precedence rule.

**Acceptance Criteria:**
1. Direct Garmin HRV wins when present.
2. Garmin-via-HealthKit wins over Apple Health.
3. Apple Health is used when no Garmin HRV exists.
4. Unknown HRV can show value without source-specific attribution.
5. Unit tests cover the full precedence matrix.
6. Recovery assembly uses the resolver rather than ad hoc source checks.

## Story 4: Source-Aware HRV Attribution In UI

**Description:** As a runner, I want HRV cards to name the source only when known, so that I can trust the recovery signal.

**Design:** Today wearable trend card, Recovery dashboard HRV tile, Garmin Wellness attribution.

**Conversation:**
This story is the first visible behavior change. Today and Recovery should show Garmin only for Garmin-sourced HRV, Apple Health only for Apple-sourced HRV, and no source label for unknown.

**Acceptance Criteria:**
1. Today HRV attribution comes from `HRVSource`, not Garmin connection state.
2. Recovery HRV attribution comes from `HRVSource`, not Garmin connection state.
3. Garmin Wellness keeps Garmin attribution because that screen is Garmin-only.
4. Unknown source shows no source-specific label.
5. Visual checks cover Garmin, Apple Health, and unknown states.
6. Copy remains plain, visible, and not medical.

## Story 5: Evidence, Screenshots, And Garmin Reply Readiness

**Description:** As the founder, I want screenshots and status docs to match the submitted app, so that the Garmin reply is backed by production-ready evidence.

**Design:** Demo screenshot infrastructure, affected iOS screens, web repo Garmin application docs.

**Conversation:**
This story is release evidence, not product logic. It should run after Stories 1-4 are green. It should refresh screenshots and status docs, then leave a clear archive/upload/reply sequence.

**Acceptance Criteria:**
1. Build succeeds for v1.0.4 build 17.
2. Unit tests for HRV source logic pass.
3. Today and Recovery screenshots show correct source attribution.
4. Garmin screenshots are refreshed in the web repo docs package.
5. `tasks/progress.md` and Garmin status docs are updated.
6. The Garmin reply is not sent until the App Store build matches the screenshots.

## Recommended Execution Order

1. Story 1: HRV Provenance Model And Back-Compat.
2. Story 2: HealthKit HRV Source Classification.
3. Story 3: HRV Source Precedence Resolver.
4. Story 4: Source-Aware HRV Attribution In UI.
5. Story 5: Evidence, Screenshots, And Garmin Reply Readiness.

## Approval Checklist

- [ ] Founder reviews these user stories.
- [ ] Founder changes `status` from `draft` to `reviewed` or `approved`.
- [ ] One story is selected for execution.
- [ ] Implementation plan is written for the selected story only.
- [ ] Pre-mortem launch-blocking Tigers are closed or accepted before App Store resubmission.
