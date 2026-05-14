# Task State

## Current Task
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
