# Apple Workout round trip — October 25, 2026

## Product brief and scope
A runner sends a saved planned run to Apple's Workout app, follows the same measurable steps on Watch, then imports one accurate run and completes the intended plan item. Founder authorized scoped implementation and draft PR in the Apple Watch chat. Base: origin/main 61b7cfb, including 1.2.0 build 37 currently submitted for review. Release checkout remains untouched.

Native iOS 17+, WorkoutKit, existing HealthKit. No watchOS app, live RunSmart coaching inside Apple Workout, background/instant sync claim, production configuration, upload or submission. Initial sync is the existing explicit Apple Health refresh. Outer May architecture documents are stale (describe ResumeBuilder); actual RunSmart source is authoritative.

## Story 1: Reliable import
As a runner I want repeat imports to enrich my run without duplicates.
- Read-only Health permission remains usable; request completion never claims read consent.
- Query errors do not become successful empty syncs. Empty reads explain missing permission/data.
- Repeated provider UUIDs update late routes/HR and preserve runner edits; hidden runs and locally exported runs stay protected.
- Every new run enters completion processing, oldest first. Enrichment does not reprocess completion.
Tests: mapper, late-data merge, hidden/own export existing regressions; query/error inspection; physical denied/read-only matrix.

## Story 2: Send one planned workout
As a runner I want to send a supported session from its detail screen.
- Reuse existing complete guide steps; reject incomplete/rest/nonrunning/completed/past sessions.
- Stable WorkoutPlan ID is the plan item's UUID; check support, separate authorization and scheduler limit.
- Confirm scheduling by reading it back, serialize actions, replace prior versions of the same item.
- Remove/update exports on successful plan edits and reconcile only known exported items against authoritative current plan data. Never infer cancellation from a failed plan fetch.
Tests: goals/interval order/pace conversion, unsupported data, scheduling seam for deny/limit/replace/cancel.

## Story 3: Exact return identity
As a runner I want the recorded workout to finish the intended session.
- Read HKWorkout.workoutPlan ID; retain locally across resync.
- Exact identity wins over date/distance heuristics. Missing/canceled/old-plan/completed IDs must not complete another session.
- Ordinary imported runs retain existing heuristic behavior.
Tests: exact ID, edited/date shifted, canceled/regenerated/completed, repeated import.

## Verification and device gate
Focused tests, full suite and simulator compilation; inspect unavailable Watch UI path. Physical paired iPhone/Watch required: send interval, verify steps/alerts, record phone-free, sync Health, import one run/one completion; repeat import; delayed route; deny scheduling; read-only/denied Health; edit/move/remove/regenerate. No simulator result proves this gate.

## API evidence
Retrieved Apple documentation October 25: https://developer.apple.com/documentation/workoutkit/workoutscheduler and https://developer.apple.com/documentation/healthkit/hkworkout/workoutplan . Signatures also checked against installed Xcode iOS 26.5 SDK swiftinterface. Uses current isSupported/requestAuthorization/maxAllowedScheduledWorkoutCount APIs, iOS 17 availability.
