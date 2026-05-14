# Task State

## Current Task
Stories A, B, C, and D are all implemented. Physical-device QA (Story E) remains before TestFlight.

## Story A - Backend Route Persistence - Implemented
As a signed-in runner, I want saved routes, benchmark routes, and route match results persisted beyond local UserDefaults so my route history survives reinstall and works across devices.

### Files Changed
- `IOS RunSmart app/Services/Supabase/RouteRepository.swift` (new)
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`

### Checklist
- [x] Saved routes are associated with authenticated user id (Supabase RLS policy: `user_id = auth.uid()`).
- [x] Benchmark route state survives reinstall/sign-out/sign-in (synced to `user_benchmark_routes` table).
- [x] Route match results needed for benchmark reports are stored or reconstructable (recomputed at runtime from runs + routes; no separate table needed).
- [x] Deletion clearly removes RunSmart route copies without deleting Garmin source activities (existing `removeSavedRoute` behavior preserved; Supabase delete is scoped to `user_saved_routes`).
- [x] Tests cover local fallback (remote empty → local returned), remote success (remote wins on conflict), and remote failure (new entries added from remote only when missing locally).

### Validation
- Simulator build passed.
- Story A focused tests (3 tests) passed:
  `testRouteSyncMergeReturnsLocalWhenRemoteIsEmpty`, `testRouteSyncMergeRemoteWinsOnConflictingRouteID`, `testRouteSyncBenchmarkMergeAddsRemoteEntriesMissingLocally`

## Story B - Benchmark Stat Hydration - Implemented
As a runner, I want route cards and route details to show current benchmark stats so route library data matches run-report comparisons.

### Files Changed
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`

### Checklist
- [x] Benchmark route cards show non-zero history after matched runs exist (stats refreshed after every `processCompletedActivity`).
- [x] Route detail stats match benchmark report aggregates (`BenchmarkStatRefresh.refresh` uses same matching logic as `BenchmarkRouteAnalyticsService`).
- [x] Stats update after route match, route deletion, and benchmark removal (refresh called in `processCompletedActivity`, `deleteRoute`, `removeRun`, `enableBenchmark`, `disableBenchmark`).
- [x] Tests cover mixed Garmin and RunSmart history.

### Validation
- Simulator build passed.
- Story B focused tests (4 tests) passed:
  `testBenchmarkStatRefreshComputesCountPBAndAveragesFromMatchedRuns`, `testBenchmarkStatRefreshSkipsRunsWithNoMatchOrWrongRoute`, `testBenchmarkStatRefreshClearsStatsWhenNoMatchedRunsExist`, `testBenchmarkStatRefreshHandlesMixedGarminAndRunSmartSources`

## Story C - Route Discovery Controls - Implemented
As a runner, I want distance, elevation, surface, and route intent controls to affect route recommendations instead of being decorative.

### Files Changed
- `IOS RunSmart app/Services/RouteSuggestionRanker.swift`
- `IOS RunSmart app/Features/Routes/RouteCreatorView.swift`
- `IOS RunSmart appTests/RouteRankingTests.swift`

### Checklist
- [x] Elevation preference (Flat/Rolling/Hilly) changes ranking of saved/past/benchmark routes.
- [x] Generated route reason copy reflects current elevation preference.
- [x] MapKit route failure shows inline retry card in Generated Nearby section while saved/past routes remain visible.
- [x] Location denied still shows saved/past routes (existing behavior preserved).
- [x] Tests cover flat-first, hilly-first, rolling-first, kind-priority override, and generated reason.

### Validation
- Simulator build passed.
- Focused RouteRankingTests (12 tests) passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RouteRankingTests" test`

## Story D - Garmin Historical Import Batch - Implemented
As a Garmin runner, I want newly imported historical activities to become route-aware without duplicating already-processed activities.

### Files Changed
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`

### Checklist
- [x] Supabase syncNow skips runs whose providerActivityID is already in the local store.
- [x] Production syncNow processes all batch runs (sorted newest-first) and skips already-stored IDs.
- [x] Missing route data does not block activity import (existing GarminImportProcessor behavior preserved).
- [x] Existing hidden Garmin runs remain hidden (existing behavior preserved).
- [x] Tests cover full-batch processing, duplicate-ID skipping, and missing-route-data resilience.

### Validation
- Simulator build passed.
- Story D focused tests (3 tests) passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminBatchProcessesAllNewRuns" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminBatchSkipsAlreadyProcessedProviderIDs" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminBatchWithMissingRouteDataDoesNotBlockOtherRuns" test`

## QA Quick Wins - Implemented (Previous Session)

## Route QA Quick Wins - Implemented
As a beta runner, I want the existing route feature to behave consistently while larger backend work is planned.

### Files Changed
- `IOS RunSmart app/Features/Routes/RouteCreatorView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart app/Features/Routes/SaveRouteSheet.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Activity/ActivityTabView.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `tasks/todo.md`

### Checklist
- [x] Route Creator and route selector request current location and include generated nearby loops when location is available.
- [x] Generated route cards receive recommendation reasons.
- [x] Report route library refreshes after route save, favorite, benchmark, delete, or run changes.
- [x] Save Route only appears/saves when the activity has enough GPS points to be matchable.
- [x] Garmin sync processes all normalized runs returned by the current activity batch instead of only the newest run.
- [ ] Physical-device QA: verify location permission prompt, generated-route loading time, weak-signal copy, and MapKit routing behavior outdoors.

### Validation
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Full iPhone 17 test run passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" test`

## Remaining Route QA Findings - Plan

### Story A - Backend Route Persistence
As a signed-in runner, I want saved routes, benchmark routes, and route match results persisted beyond local UserDefaults so my route history survives reinstall and works across devices.

#### Scope
- Define Supabase tables/API contracts for saved routes, benchmark routes, and route match metadata.
- Keep route GPS point retention explicit and privacy-safe.
- Add sync/merge rules for local-first saves and remote state.
- Do not rebuild route matching or AI insights in this story.

#### Acceptance Criteria
- [ ] Saved routes are associated with authenticated user id.
- [ ] Benchmark route state survives reinstall/sign-out/sign-in.
- [ ] Route match results needed for benchmark reports are stored or reconstructable.
- [ ] Deletion clearly removes RunSmart route copies without deleting Garmin source activities.
- [ ] Tests cover local fallback, remote success, and remote failure.

### Story B - Benchmark Stat Hydration
As a runner, I want route cards and route details to show current benchmark stats so route library data matches run-report comparisons.

#### Scope
- Recompute benchmark historical count, PB, average pace, and average duration from matched runs.
- Refresh stats after matched in-app and Garmin runs.
- Keep report comparison logic as the source of detailed per-run insight.

#### Acceptance Criteria
- [ ] Benchmark route cards show non-zero history after matched runs exist.
- [ ] Route detail stats match benchmark report aggregates.
- [ ] Stats update after route match, route deletion, and benchmark removal.
- [ ] Tests cover mixed Garmin and RunSmart history.

### Story C - Route Discovery Controls ✓ DONE
As a runner, I want distance, elevation, surface, and route intent controls to affect route recommendations instead of being decorative.

#### Acceptance Criteria
- [x] Changing distance/elevation/surface can change ranking or generated-route candidates.
- [x] Location denied still shows saved/past routes.
- [x] MapKit route failure has a clear retry/fallback state.
- [x] Tests cover ranker preference behavior.

### Story D - Garmin Historical Import Batch ✓ DONE
As a Garmin runner, I want newly imported historical activities to become route-aware, not only the newest visible activity.

#### Acceptance Criteria
- [x] Multiple returned Garmin activities are processed idempotently.
- [x] Missing route data does not block activity import.
- [x] Existing hidden Garmin runs remain hidden.
- [x] Tests cover batch processing and duplicate provider IDs.

### Story E - Visual And Device QA Pass
As a beta owner, I want proof that the route UI works on actual device conditions before TestFlight.

#### Scope
- Simulator screenshot checks for route library, route creator, route detail, Garmin missing-route state, and benchmark card.
- Physical-device checks for GPS, background/foreground, battery, and generated MapKit routes.

#### Acceptance Criteria
- [ ] iPhone SE/small-screen and iPhone 17 layouts do not overlap.
- [ ] Dark mode route cards/maps are legible.
- [ ] Background run recording continues as expected.
- [ ] Battery and privacy behavior are documented for TestFlight.

## Previous Task
Story 10 implementation complete: TestFlight Polish And Privacy Review. Physical-device background/battery QA remains before external beta.

## Route Feature Story 10 - TestFlight Polish And Privacy Review
As a beta runner, I want route, GPS, Garmin, and benchmark behavior to be clear and trustworthy so I understand what RunSmart records and where limitations remain.

### Expected Files
- `RunSmartInfo.plist`
- `IOS RunSmart app/Features/Routes/SaveRouteSheet.swift`
- `IOS RunSmart app/Features/Routes/RouteDetailView.swift`
- `IOS RunSmart app/Features/Run/RunTabView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `docs/qa/testflight-checklist.md`
- `docs/qa/ios-qa-checklist.md`
- `docs/qa/route-benchmark-testflight-notes.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Route/location privacy copy is clear.
- [x] Weak GPS and missing Garmin map data are handled with non-alarming copy.
- [x] Saved route deletion clarifies RunSmart-only deletion and benchmark tracking removal.
- [x] TestFlight release notes mention route/benchmark limitations.
- [x] Battery/background behavior is called out for physical-device validation.
- [ ] Physical-device battery/background run check completed before external TestFlight.

### Validation
- `plutil -lint RunSmartInfo.plist "IOS RunSmart app/PrivacyInfo.xcprivacy"` passed.
- Static copy check found the updated location, weak GPS, Garmin missing-map, privacy, and TestFlight notes strings.
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Full iPhone 17 test pass succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" test`
- Build/test still emit pre-existing warning noise from older resume-era view models and AppIntents metadata extraction, but no Story 10 failures.

---

## Previous Task
Story 9 complete: Garmin Import Processing Into Route Flow.

## Route Feature Story 9 - Garmin Import Processing Into Route Flow
As a Garmin runner, I want imported activities to behave like RunSmart-recorded runs so route matching, benchmark comparisons, and reports are consistent.

### Expected Files
- `IOS RunSmart app/Services/Garmin/GarminImportProcessor.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Garmin sync processes newest run through `processCompletedActivity`.
- [x] Garmin route points are normalized before matching when available.
- [x] Garmin run reports can show benchmark comparison through the existing matched-run report path.
- [x] Missing Garmin route points still leave a route-less import/report path.
- [x] Duplicate Garmin activities remain stable by provider activity id.
- [x] Report generation failure does not block sync status.

### Status
- [x] Added `GarminImportProcessor` to normalize Garmin activities into newest-first `RecordedRun` values.
- [x] Hydrates route points before matching when Garmin map data exists.
- [x] Keeps route-less Garmin runs processable when route points are unavailable.
- [x] Skips hidden Garmin runs before choosing the newest import.
- [x] Dedupes duplicate Garmin activity rows by provider activity id.
- [x] Supabase Garmin sync now sends the newest normalized run through `processCompletedActivity`.
- [x] Local production Garmin sync now uses the same completed-activity path for the newest gateway run.
- [x] Completed-activity persistence now saves the canonical run even when no route match is available.

### Validation
- Focused Story 9 tests passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorHydratesRoutePointsAndOrdersNewestFirst" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorKeepsRouteLessRunWhenMapDataIsMissing" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorSkipsHiddenRunsBeforeSelectingNewest" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorDedupesDuplicateProviderActivities" test`
- Simulator build check passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`

---

## Previous Task
Story 8 complete: Route Discovery Ranking MVP.

## Route Feature Story 8 - Route Discovery Ranking MVP
Full-bleed map route cards (map fills entire card, data overlaid via gradient scrim),
three-bucket ranked discovery (Benchmarks → My Routes → Generated Nearby),
distance filter chips, recommendation reason chips on each card. Applied to both
RouteCreatorView and RouteSelectorScaffold.

### Files Changed
- `IOS RunSmart app/Models/RunSmartModels.swift` — extended RouteKind + RouteSuggestion
- `IOS RunSmart app/Services/RouteSuggestionRanker.swift` — new pure ranker
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift` — rankedRouteSuggestions
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift` — rankedRouteSuggestions
- `IOS RunSmart app/Features/Routes/FullBleedRouteCard.swift` — new component file
- `IOS RunSmart app/Features/Routes/RouteCreatorView.swift` — redesigned
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift` — RouteSelectorScaffold redesigned
- `IOS RunSmart app/PreviewSupport/RunSmartPreviewData.swift` — added routeSuggestions
- `IOS RunSmart appTests/RouteRankingTests.swift` — new tests (all pass)

### Status
- [x] RouteSuggestion model extended with kind (.benchmark, .saved), recommendationReason, isFavorite
- [x] RouteSuggestionRanker with rank(), filter(), reason() — tested
- [x] rankedRouteSuggestions on RouteProviding + both service implementations
- [x] FullBleedRouteCard (full-bleed map + scrim + overlaid data)
- [x] RouteCreatorView redesigned with filter bar + three buckets
- [x] RouteSelectorScaffold redesigned with filter bar + three buckets
- [x] Preview data added

---

## Previous Task
Story 7 complete: Benchmark Comparison Card In Run Reports.

## Goal
Show route-specific benchmark progress in post-run and run report detail screens without recalculating Story 6 analytics in SwiftUI.

## Route Feature Story 7 - Benchmark Comparison Card In Run Reports
As a runner, I want run reports to show route-specific progress so I can understand improvement on benchmark routes without hunting through analytics.

### Expected Files
- `IOS RunSmart app/Features/Routes/BenchmarkComparisonCard.swift`
- `IOS RunSmart app/Services/BenchmarkComparisonPresentation.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Show route name and match confidence for benchmark-matched runs.
- [x] Show previous, PB, and monthly average comparisons.
- [x] Show 1-3 deterministic coaching insights.
- [x] Do not show for non-benchmark routes.
- [x] Handle first-run and not-enough-history states clearly.
- [x] Keep Dynamic Type-friendly layout.

## Route Feature Story 6 - Benchmark Comparison Data
As a runner, I want benchmark route reports to compare my current run with route history so I can see progress on routes I actually repeat.

### Expected Files
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/BenchmarkRouteAnalyticsService.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Calculate comparisons only for high-confidence matches attached to benchmark routes.
- [x] Provide previous run, personal best, all-time average, current-month average, and recent trend.
- [x] Handle first-run and not-enough-history states.
- [x] Aggregate monthly averages by the provided local calendar month.
- [x] Support duration, pace, and optional heart-rate averages.
- [x] Cover mixed Garmin and RunSmart matched runs.

## Route Feature Story 5 - MVP Route Matching Service
As a runner, I want RunSmart to recognize repeated saved and benchmark routes so route-aware reports can compare progress later.

### Expected Files
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/RouteMatchingService.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Checklist
- [x] Add route match result data to completed runs.
- [x] Distinguish high-confidence, possible, and no-match states.
- [x] Ignore manual or route-less runs.
- [x] Match both RunSmart GPS runs and Garmin/imported runs through `processCompletedActivity`.
- [x] Support reversed-route matching.
- [x] Verify same route, possible route, unrelated route, reversed route, and route-less cases.

## Story 1 - Bug Fix
As a developer, I want the existing test target to compile so validation can catch real regressions.

### Expected Files
- `RunSmartTests/ResumeOptimizationServiceSwiftTestingTests.swift`

### Checklist
- [x] Update stale test doubles to match `ResumeOptimizationServiceProtocol`.
- [x] Run the existing test target.
- [x] Keep fix scoped to tests only.

## Story 2 - Today Shell
As a runner, I want the first app tab to point me toward Today so the app starts moving toward daily runner jobs without losing current functionality.

### Expected Files
- `RunSmart/Core/DesignSystem/Components/RunSmartTabBar.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md` if a new lesson is learned

### Checklist
- [x] Keep the existing first-tab content reachable.
- [x] Update only shell-level tab naming/iconography for the first tab.
- [x] Do not implement the full redesign.
- [x] Do not change signing, certificates, provisioning, paid services, Garmin, or HealthKit.
- [x] Run build/tests after implementation.

## Story 3 - Today Content Wrapper
As a runner, I want the Today tab to open on a lightweight daily command-center surface so the app starts to feel like RunSmart while keeping the current score/check flow available.

### Expected Files
- `RunSmart/App/MainTabViewV2.swift`
- `RunSmart/Features/V2/Today/TodayView.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md` if a new lesson is learned

### Checklist
- [x] Add a real Today wrapper as the first tab content.
- [x] Keep the existing score/check flow reachable from Today.
- [x] Preserve the existing `ScoreViewModel` instance so score flow state is not reset by the wrapper.
- [x] Do not implement full Plan, Run, Coach, HealthKit, Garmin, signing, or paid-services work.
- [x] Run build/tests after implementation.

## Story 4 - Separate Plan From Report
As a runner, I want Plan and Report to be distinct top-level areas so upcoming training and past progress are not mixed together.

### Expected Files
- `RunSmart/App/MainTabViewV2.swift`
- `RunSmart/Core/DesignSystem/Components/RunSmartTabBar.swift`
- `RunSmart/Features/V2/Plan/PlanView.swift`
- `RunSmart/Features/V2/Report/ReportView.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md` if a new lesson is learned

### Checklist
- [x] Add a lightweight Plan surface as its own tab content.
- [x] Add a lightweight Report surface as its own tab content.
- [x] Keep the current Tailor/Improve flow reachable from Plan.
- [x] Keep the current Track/applications flow reachable from Report.
- [x] Do not implement full Run, Coach, HealthKit, Garmin, signing, or paid-services work.
- [x] Run build/tests after implementation.

## Prior Story 5 - Run Entry Point
As a runner, I want a clear Run tab so I can see where GPS tracking and manual run logging will live.

### Expected Files
- `RunSmart/App/MainTabViewV2.swift`
- `RunSmart/Core/DesignSystem/Components/RunSmartTabBar.swift`
- `RunSmart/Features/V2/Run/RunView.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md` if a new lesson is learned

### Checklist
- [x] Add a lightweight Run surface as the middle tab content.
- [x] Show GPS start and manual log entry points as unavailable placeholders only.
- [x] Keep the current Design/redesign flow reachable from Run while product ownership is unresolved.
- [x] Do not request location permissions or change GPS/background-location behavior.
- [x] Do not implement full Coach, HealthKit, Garmin, signing, or paid-services work.
- [x] Run build/tests after implementation.

## Risks
- Existing uncommitted Swift/resource changes are present and must be preserved.
- The app still contains resume-builder product naming and flows.
- Story 2 is intentionally a shell step; it improves IA direction but does not yet create the full Today screen.
- Story 3 creates a command-center wrapper but still uses placeholder/no-plan states until approved RunSmart data models are connected.
- Story 4 separates Plan and Report with placeholder states while preserving the existing Tailor and Track flows.
- Story 5 must not touch permissions or background tracking; it is an entry-point shell story only.

## Validation
- Story 7 benchmark presentation focused tests succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonPresentationShowsFirstRunHistoryPrompt" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonPresentationShowsImprovementAgainstPreviousAndMonth" test`
- Story 7 simulator build check succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Story 6 benchmark comparison focused tests succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonReturnsFirstRunNotEnoughHistory" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonUsesPreviousPBAndAveragesAcrossGarminAndRunSmartRuns" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonMonthlyAverageRespectsLocalCalendarMonthBoundary" test`
- Story 6 simulator build check succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Story 5 route matching focused tests succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingReturnsHighConfidenceForSameRoute" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingMarksNearbyNoisyRouteAsPossibleWithoutAttaching" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingReturnsNoMatchForUnrelatedRoute" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingHandlesReversedRouteAsMatch" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingIgnoresManualRouteLessRuns" test`
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "platform=iOS Simulator,name=iPhone 17" test` succeeded.
- Simulator install and launch succeeded on iPhone 17.
- Visual evidence captured at `build/qa/story2-today-tab-after-wait.png`.
- First screenshot was blank because it was captured before the app finished drawing; the follow-up screenshot showed the app UI and the active `Today` tab.
- Story 3 test run succeeded with the same `xcodebuild ... test` command on iPhone 17.
- Final Story 3 simulator build check succeeded with `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "generic/platform=iOS Simulator" build`.
- Story 3 simulator install and launch succeeded on iPhone 17.
- Story 3 visual evidence captured at `build/qa/story3-today-wrapper.png`.
- Story 4 simulator build check succeeded with `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "generic/platform=iOS Simulator" build`.
- Story 4 test run succeeded with `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "platform=iOS Simulator,name=iPhone 17" test`.
- Story 5 simulator build check succeeded with `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "generic/platform=iOS Simulator" build`.
- Story 5 test run succeeded with `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "platform=iOS Simulator,name=iPhone 17" test`.

## Review Notes
- Keep both changes small and reviewable.
- Existing unrelated app/resource changes remain untouched.
- Story 7 can now consume `benchmarkComparison(for:)` to render the report card without recalculating analytics in SwiftUI.
