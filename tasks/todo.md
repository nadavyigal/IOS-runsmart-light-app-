# Task State

## Current Feature
Routes, Benchmark Routes, and Route-Based Run Reports (10 stories total)

## Story Progress
- [x] Story 1: Define Saved Route And Benchmark Route Foundation
- [x] Story 2: Route Library And Benchmark Skeleton In Report
- [x] Story 3: Save Route From Post-Run Summary
- [x] Story 4: Save Route From Garmin Imported Run
- [ ] Story 5: MVP Route Matching Service
- [ ] Story 6: Benchmark Comparison Data
- [ ] Story 7: Benchmark Comparison Card In Run Reports
- [ ] Story 8: Route Discovery Ranking MVP
- [ ] Story 9: Garmin Import Processing Into Route Flow
- [ ] Story 10: TestFlight Polish And Privacy Review

## Story 3 Details

### What Was Done
- Added route CRUD implementations to `SupabaseRunSmartServices` (the default service was relying on protocol extension defaults that returned empty/false).
- Created `SaveRouteSheet` view with name, tags, notes, favorite toggle, and benchmark toggle.
- Added "Save Route" button to `PostRunSummaryView` (visible only when GPS route points exist).
- No save action appears for route-less manual runs.

### Files Changed
- `Services/Supabase/SupabaseRunSmartServices.swift`: Added `savedRoutes()`, `saveRoute()`, `deleteRoute()`, `updateRoute()`, `benchmarkRoutes()`, `enableBenchmark()`, `disableBenchmark()` using `RunSmartLocalStore`.
- `Features/Routes/SaveRouteSheet.swift`: New file — save route sheet with map preview, stats, name field, tag picker, notes, favorite/benchmark toggles, and success/error feedback.
- `Features/Run/PostRunSummaryView.swift`: Added `showSaveRouteSheet` state, "Save Route" button (conditionally shown), and `.sheet` modifier.

### Acceptance Criteria Met
- [x] Post-run summary offers Save Route when GPS points exist.
- [x] User can name route, add tags/notes, and favorite it.
- [x] User can optionally mark as benchmark.
- [x] No save action appears for route-less manual runs.

### Verification
- Build succeeds for all changed/new files (no new compile errors).
- Pre-existing build errors in `RunSmartTabBar.swift` are unrelated.

## Story 4 Details

### What Was Done
- Added "Save Route" button to `RunReportScaffold` (Garmin run review screen), visible only when route points exist.
- Reuses `SaveRouteSheet` from Story 3 — passes a `RecordedRun` with Garmin route points injected.
- Added empty state message when Garmin GPS data is unavailable for an activity.
- Added `isLoadingRoutePoints` state to prevent flash of empty state during route point fetch.

### Files Changed
- `Features/Secondary/SecondaryFlowView.swift`: Added `showSaveRouteSheet`, `isLoadingRoutePoints` state vars, Save Route button (conditional on route points), empty state message, `.sheet` presenting `SaveRouteSheet`, `garminRunWithRoutePoints` computed property, and loading state tracking in `.task`.

### Acceptance Criteria Met
- [x] Garmin route points are fetched and displayed (pre-existing).
- [x] Save Route and Make Benchmark actions available when points exist.
- [x] Saved route source is Garmin (`SavedRoute.from(run:)` already handles `.garmin`).
- [x] Missing route points show clear empty state message.

### Verification
- Build succeeds for `SecondaryFlowView.swift` (no new compile errors).
- Pre-existing build errors in `RunSmartTabBar.swift` / `GlassCard.swift` are unrelated (duplicate type definitions from app shell migration).

## Next Story
Story 5: MVP Route Matching Service — depends on Stories 1-2 (complete).

## Open Questions
- Pre-existing `RunSmartTab` ambiguity error in `RunSmartTabBar.swift` should be fixed before TestFlight.
- Pre-existing `GlassCard` redeclaration error in `GlassCard.swift` should be resolved.
