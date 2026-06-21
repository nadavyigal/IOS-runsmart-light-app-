# Apple and Garmin Sync and Adapt Backlog

Date: 2026-06-21
Status: implementation-ready planning backlog, no code implemented

## Epic 1: Data Model Foundation

### Ticket 1.1: Define Canonical Sync and Adapt Models

- Problem: Current `WorkoutSummary` and `StructuredWorkoutFactory.WorkoutStep` are UI-oriented and not safe as Apple/Garmin export contracts or no-wearable execution contracts.
- Proposed solution: Add provider-neutral model definitions for planned workouts, workout steps, targets, execution modes, completed activities, recovery context, plan-vs-actual results, coach adjustments, and publish statuses.
- Files/areas likely affected: `IOS RunSmart app/Models/RunSmartModels.swift`, possible new `IOS RunSmart app/Models/RunSmartSyncModels.swift`.
- Dependencies: Existing `WorkoutKind`, `RecordedRun`, `RunRoutePoint`.
- Acceptance criteria: Models compile, use user-local schedule dates, and do not import WorkoutKit or Garmin-specific SDK concepts.
- Risk level: Medium.

### Ticket 1.1A: Define Runner Execution Modes

- Problem: The strategy should not assume one user uses both Apple Watch and Garmin, and no-wearable must not appear as a failed watch-sync state.
- Proposed solution: Add `WorkoutExecutionMode` concept for `inAppPhoneGPS`, `manualOrTreadmill`, `appleWatchWorkoutKit`, and `garminTrainingApi`.
- Files/areas likely affected: `RunSmartModels.swift`, Today/PreRun view models, future publisher services.
- Dependencies: Ticket 1.1.
- Acceptance criteria: A planned workout can declare available execution modes and preferred mode without requiring Apple or Garmin.
- Risk level: Medium.

### Ticket 1.2: Map Existing Plans Into Canonical PlannedWorkout

- Problem: Existing plan persistence returns `DBWorkout` and `WorkoutSummary`, but publishers need structured duration/target/step semantics.
- Proposed solution: Add mapper from `DBWorkout` and `WorkoutSummary` into canonical `PlannedWorkout`.
- Files/areas likely affected: `TrainingPlanRepository.swift`, `RunSmartModels.swift`, `StructuredWorkoutFactory.swift`.
- Dependencies: Ticket 1.1.
- Acceptance criteria: Easy, long, tempo, intervals, hills, recovery, race, and strength map deterministically with readable in-app/manual execution labels.
- Risk level: Medium.

### Ticket 1.3: Map RecordedRun Into CompletedActivity

- Problem: `RecordedRun` is good for current UI but does not include richer provider detail like laps, zones, elapsed time, source quality, or raw metadata.
- Proposed solution: Add mapper from `RecordedRun` into canonical `CompletedActivity`, preserving existing IDs and source behavior.
- Files/areas likely affected: `RunSmartModels.swift`, `ActivityConsolidationService.swift`, `SupabaseRunSmartServices.swift`.
- Dependencies: Ticket 1.1.
- Acceptance criteria: Phone GPS, HealthKit, Garmin, and manual runs map without losing provider activity IDs or route points.
- Risk level: Low-Medium.

## Epic 2: Apple Health Import

### Ticket 2.1: Preserve HealthKit Import As Canonical Activity

- Problem: HealthKit imports currently become `RecordedRun`; future analysis should consume `CompletedActivity`.
- Proposed solution: Keep the existing HealthKit import path, then map imported runs into `CompletedActivity` before plan-vs-actual analysis.
- Files/areas likely affected: `HealthKitSyncService.swift`, `SupabaseRunSmartServices.swift`.
- Dependencies: Epic 1.
- Acceptance criteria: HealthKit sync still imports workouts, route points, average HR, and wellness snapshot, then calls the post-run pipeline once.
- Risk level: Medium.

### Ticket 2.2: Add HealthKit Route Write Spike

- Problem: RunSmart saves phone GPS runs to HealthKit as workouts, but does not appear to write route series.
- Proposed solution: Spike `HKWorkoutRouteBuilder` support for phone-recorded route writes.
- Files/areas likely affected: `HealthKitSyncService.swift`, `RunTabView.swift`.
- Dependencies: HealthKit permission review.
- Acceptance criteria: Spike doc says whether route write is feasible, what permissions/copy change, and whether App Review risk changes.
- Risk level: Medium.

## Epic 3: Garmin Activity Import

### Ticket 3.1: Document Current Garmin Activity Contract

- Problem: Current Garmin data arrives through Supabase tables, but the official Activity API contract is not captured in engineering docs.
- Proposed solution: Add implementation note mapping Activity API/FIT concepts to current `DBGarminActivity`, route points, and future `CompletedActivity`.
- Files/areas likely affected: `docs/engineering/`, `GarminBridge.swift`, `GarminImportProcessor.swift`.
- Dependencies: None.
- Acceptance criteria: Official Activity API, FIT, route, and duplicate behavior are documented with current table fields.
- Risk level: Low.

### Ticket 3.2: Add Garmin Import PlanVsActual Test Fixtures

- Problem: Garmin import can complete workouts, but plan-vs-actual behavior needs fixture coverage.
- Proposed solution: Add focused fixtures for exact match, same-day partial, route-less run, duplicate rows, and wrong-day run.
- Files/areas likely affected: `IOS RunSmart appTests/RunSmartReadinessTests.swift`, Garmin test helpers.
- Dependencies: PlanVsActual analyzer.
- Acceptance criteria: Tests prove no duplicate user-facing activities and correct matching classification.
- Risk level: Medium.

## Epic 4: Workout Publisher Abstraction

### Ticket 4.0: Make Manual and Phone GPS Execution First-Class

- Problem: A runner without a wearable needs the same coached workout loop, not a lesser fallback.
- Proposed solution: Add execution-mode handling for phone GPS and manual/treadmill runs before watch publishing UI is added.
- Files/areas likely affected: `TodayTabView.swift`, `PreRunView.swift`, `RunTabView.swift`, manual run flow in `SecondaryFlowView.swift`.
- Dependencies: Epic 1.
- Acceptance criteria: Today and PreRun can show "Run with phone GPS" and "Log manually/treadmill" as valid execution choices for a planned workout.
- Risk level: Medium.

### Ticket 4.1: Add WorkoutPublishingService Protocol

- Problem: Apple and Garmin publishing should not be called directly from views or plan repository methods, and publishing should not be confused with execution for no-wearable runners.
- Proposed solution: Add protocol with `publish`, `unpublish`, `publishUpcoming`, and `refreshStatus`.
- Files/areas likely affected: `RunSmartServices.swift`, new publisher service files.
- Dependencies: Epic 1.
- Acceptance criteria: Protocol supports Apple and Garmin publish states while preserving in-app/manual execution without provider imports in the core interface.
- Risk level: Medium.

### Ticket 4.2: Add WorkoutPublishStatus Persistence

- Problem: Users and adaptation logic need to know whether a workout was published, failed, or is stale.
- Proposed solution: Add local and backend persistence for per-provider publish status.
- Files/areas likely affected: `RunSmartLocalStore`, Supabase migration, `SupabaseRunSmartServices`.
- Dependencies: Ticket 4.1.
- Acceptance criteria: Publish status tracks provider, external ID, last published revision, state, last attempt, and user-facing message.
- Risk level: High.

## Epic 5: Apple WorkoutKit Publishing

### Ticket 5.1: WorkoutKit Feasibility Spike

- Problem: RunSmart needs to confirm target OS, entitlement/capability requirements, authorization copy, and supported workout target mapping.
- Proposed solution: Create a spike doc with sample payload mapping for easy, tempo, intervals, and long run.
- Files/areas likely affected: `docs/engineering/`, no Swift implementation.
- Dependencies: Epic 1.
- Acceptance criteria: Decision on supported OS floor, model mapping gaps, and MVP workout types.
- Risk level: Medium.

### Ticket 5.2: Implement AppleWorkoutKitPublisher

- Problem: RunSmart cannot publish structured workouts to Apple Watch yet.
- Proposed solution: Implement WorkoutKit authorization and scheduled workout publishing behind `WorkoutPublishingService`.
- Files/areas likely affected: new Apple publisher service, `SupabaseRunSmartServices`, Plan/Today publish UI.
- Dependencies: Ticket 5.1, WorkoutPublishStatus, and first-class manual/phone execution.
- Acceptance criteria: A supported planned workout can be published and status updates to published or failed with clear copy.
- Risk level: High.

### Ticket 5.3: Apple Watch Publish QA

- Problem: Publish success must be verified on real Apple Watch, not just source.
- Proposed solution: Add QA checklist for authorization, scheduled appearance, workout completion, HealthKit import, and stale update.
- Files/areas likely affected: `docs/qa/`, `tasks/`.
- Dependencies: Ticket 5.2.
- Acceptance criteria: Physical device/watch evidence captured without secrets or personal identifiers.
- Risk level: High.

## Epic 6: Garmin Training API Publishing

### Ticket 6.1: Garmin Training API Approval Check

- Problem: Garmin Training API is approval-gated and server-owned.
- Proposed solution: Confirm current Garmin Developer access, scopes, throttled production testing, and commercial constraints.
- Files/areas likely affected: `tasks/`, `docs/engineering/`.
- Dependencies: Founder/Garmin account access.
- Acceptance criteria: Approval state and next action are documented without secrets.
- Risk level: High.

### Ticket 6.2: Design Garmin Training API Backend Contract

- Problem: iOS should not call Garmin Training API directly with secrets.
- Proposed solution: Define Supabase or web backend endpoint for publishing workouts to Garmin Connect calendar.
- Files/areas likely affected: iOS docs, RunSmart web/Supabase docs, backend endpoint contract.
- Dependencies: Ticket 6.1, Epic 1.
- Acceptance criteria: Request/response schema includes planned workout ID, revision, provider payload, external ID, and error handling.
- Risk level: High.

### Ticket 6.3: Implement GarminTrainingPublisher

- Problem: RunSmart cannot publish structured workouts to Garmin yet.
- Proposed solution: Implement iOS adapter that calls the backend contract and stores publish status.
- Files/areas likely affected: new Garmin publisher service, `GarminBridge.swift` or sibling, `SupabaseRunSmartServices`.
- Dependencies: Ticket 6.2, backend availability, and first-class manual/phone execution.
- Acceptance criteria: Test user workout appears in Garmin Connect calendar after publish.
- Risk level: High.

## Epic 7: Post-run Analysis

### Ticket 7.1: Implement PlanVsActualAnalyzer

- Problem: RunSmart completes matching workouts, but does not store a structured plan-vs-actual result.
- Proposed solution: Add analyzer for match confidence, completion status, distance/duration/pace deltas, effort classification, route and zone summary.
- Files/areas likely affected: new service, `SupabaseRunSmartServices.processCompletedActivity`.
- Dependencies: Epic 1.
- Acceptance criteria: Analyzer returns deterministic results for matched, partial, overdone, skipped, wrong-day, and no-plan runs.
- Risk level: Medium.

### Ticket 7.2: Add Post-run Adaptive Review UI

- Problem: Users need to see what the run means for the next workout.
- Proposed solution: Extend post-run summary/report to show plan-vs-actual, next-session impact, and explain/no-change copy.
- Files/areas likely affected: `PostRunSummaryView.swift`, `SecondaryFlowView.swift`, report views.
- Dependencies: Ticket 7.1.
- Acceptance criteria: After a completed run, user sees match result and next-session explanation without medical claims.
- Risk level: Medium.

## Epic 8: Adaptive Plan Adjustment

### Ticket 8.1: Add CoachAdjustment Audit Model

- Problem: AI or rule-based plan changes need durable reasons and evidence.
- Proposed solution: Persist adjustment trigger, evidence, before/after, affected workouts, status, and publish-stale impact.
- Files/areas likely affected: models, Supabase migration, Flex Week services.
- Dependencies: Epic 1.
- Acceptance criteria: Any automatic adjustment produces an auditable record.
- Risk level: High.

### Ticket 8.2: Mark Published Workouts Stale After Adaptation

- Problem: If a future workout changes, Apple/Garmin watch copies may be stale.
- Proposed solution: When a workout is moved/amended/replaced, mark provider statuses stale and prompt republish.
- Files/areas likely affected: `TrainingPlanRepository.swift`, publisher status service.
- Dependencies: Epic 4.
- Acceptance criteria: Existing plan mutation actions update publish state consistently.
- Risk level: High.

## Epic 9: App Intents

### Ticket 9.1: App Intents Design Spike

- Problem: App Intents can bypass UI safety if scoped poorly.
- Proposed solution: Define the first safe intents: Start Today's Run, Explain Today's Workout, Move Workout Tomorrow, Make This Week Easier, Sync Devices.
- Files/areas likely affected: `docs/engineering/`, future App Intents target/files.
- Dependencies: None.
- Acceptance criteria: Each intent has auth/onboarding behavior, confirmation rules, parameters, and fallback copy.
- Risk level: Medium.

### Ticket 9.2: Implement Core App Intents

- Problem: RunSmart is not exposed to Siri, Shortcuts, Spotlight, or Action Button.
- Proposed solution: Add App Intents and route them through existing service boundaries.
- Files/areas likely affected: new App Intents files, project settings, possibly metadata warnings cleanup.
- Dependencies: Ticket 9.1.
- Acceptance criteria: Intents work for authenticated/onboarded users and fail gracefully otherwise.
- Risk level: Medium-High.

## Epic 10: Live Activity

### Ticket 10.1: Live Activity Design and Privacy Spec

- Problem: Live Activities are useful for phone runs but can expose sensitive fitness/location data.
- Proposed solution: Define Lock Screen/Dynamic Island content, privacy states, and update cadence.
- Files/areas likely affected: `docs/product/`, `docs/engineering/`.
- Dependencies: Current phone GPS run flow.
- Acceptance criteria: Spec includes elapsed time, distance, pace, GPS status, and privacy-safe fallback.
- Risk level: Medium.

### Ticket 10.2: Implement Phone Run Live Activity

- Problem: Phone-recorded runs have no Lock Screen/Dynamic Island surface.
- Proposed solution: Add ActivityKit/Widget extension for active run metrics.
- Files/areas likely affected: new widget extension, `RunRecorder`, `RunTabView`.
- Dependencies: Ticket 10.1.
- Acceptance criteria: Live Activity starts, updates, pauses/resumes, ends, and does not outlive discarded runs.
- Risk level: High.

## Epic 11: Recovery and Beginner Guardrails

### Ticket 11.1: RecoveryContext Freshness Gate

- Problem: Garmin or HealthKit recovery data can be stale, sparse, or missing.
- Proposed solution: Add canonical `RecoveryContext` with freshness, confidence, and limitations.
- Files/areas likely affected: `SupabaseRunSmartServices.recoverySnapshot`, `GarminMappers.swift`, `HealthKitSyncService.swift`.
- Dependencies: Epic 1.
- Acceptance criteria: Fresh, stale, missing, disconnected, and manual-check-in states produce distinct context.
- Risk level: Medium.

### Ticket 11.2: Beginner Protection Adjustment Rule

- Problem: Beginner safety should not depend only on AI wording.
- Proposed solution: Add deterministic rules for lowering/moving workouts when recovery, recent load, or missed sessions indicate risk.
- Files/areas likely affected: Flex Week services, adjustment service.
- Dependencies: Ticket 11.1 and CoachAdjustment.
- Acceptance criteria: Rule explains action, evidence, and user confirmation when needed.
- Risk level: High.

### Ticket 11.3: No-wearable Readiness Check-in Loop

- Problem: No-wearable runners lack HRV, sleep, Body Battery, and training readiness signals, but still need a confident daily recommendation.
- Proposed solution: Use a simple check-in for energy, soreness, fatigue, stress, and notes, then combine it with completion history and progression rules.
- Files/areas likely affected: `MorningCheckinView.swift`, `SupabaseRunSmartServices.swift`, Today readiness surfaces.
- Dependencies: RecoveryContext model.
- Acceptance criteria: A no-wearable user gets a clear readiness/recommendation state without fake health metrics.
- Risk level: Medium.

## Epic 12: Research Spikes and API Approval Checks

### Ticket 12.1: Garmin API Approval and Commercial Terms Packet

- Problem: Garmin Training, Activity, Health, and Courses APIs have approval and possible commercial constraints.
- Proposed solution: Create a decision packet covering current access, requested APIs, scopes, use cases, licensing, and rollout order.
- Files/areas likely affected: `tasks/`, `docs/research/`.
- Dependencies: Founder account access.
- Acceptance criteria: Clear go/no-go and next action for each Garmin API.
- Risk level: High.

### Ticket 12.2: HealthKit Workout Zones OS Availability Spike

- Problem: HealthKit workout zones are new in iOS/watchOS 27 and may not support all target users immediately.
- Proposed solution: Verify API availability, authorization requirements, and fallback behavior.
- Files/areas likely affected: `docs/engineering/`.
- Dependencies: Xcode/SDK availability.
- Acceptance criteria: Recommendation for when to adopt source-native zone data versus internal computed zones.
- Risk level: Medium.

### Ticket 12.3: Foundation Models Coaching Spike

- Problem: Foundation Models may help explanations but should not replace cloud AI prematurely.
- Proposed solution: Evaluate on-device explanation use cases, supported devices, privacy, cost, and fallback.
- Files/areas likely affected: `docs/engineering/`, future AI service abstraction.
- Dependencies: Xcode/SDK availability and target OS decision.
- Acceptance criteria: Decision on whether Phase 4 uses Foundation Models, cloud AI, or hybrid.
- Risk level: Medium.
