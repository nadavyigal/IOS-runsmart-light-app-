# Task State

## Current Task
Story complete: Unified Training Context + AI Coach Context Integration.

Base branch run-save/Garmin merge fix is merged into `routes`; PR conflict resolution is in progress.

Physical-device build and install passed on connected iPhone; app launch/manual outdoor background/battery QA is still blocked until the device is unlocked and a real outdoor run is recorded.

## Story - Unified Training Context + AI Coach Context Integration - 2026-05-16

As a runner, I want Coach to understand my current training state so its answers can be specific without exposing raw GPS route data.

### Expected Files
- `docs/specs/training-context-coach.md`
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Live/LiveRunSmartServices.swift`
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `IOS RunSmart app/Features/Coach/CoachFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Add typed Coach entry points and training context summary models.
- [x] Add a `TrainingContextProviding` service API and integrate it into `RunSmartServiceProviding`.
- [x] Build context from existing Today, Plan, Run, Report, Route, Recovery, Wellness, and Profile services.
- [x] Limit context to summarized data and omit raw GPS coordinates.
- [x] Wire Coach UI to load/show context and send messages with context.
- [x] Keep compatibility fallback for `send(message:)`.
- [x] Add focused XCTest coverage for context completeness, limits, omissions, limitations, and fallback responses.
- [x] Run targeted XCTest and generic simulator build.

### Scope Guard
- No backend endpoint, Supabase schema, live AI call, permissions, TestFlight, or Coach redesign work in this story.

### Validation
- Focused training context tests passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testTrainingContextIncludesSummariesAndLimitsPrivateRouteData" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testTrainingContextReportsMissingDataLimitations" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testCoachFallbackResponseUsesEntryPointSpecificContext" test`
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- PR rebuild passed after commit:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Simulator launch passed on booted iPhone 17 Pro:
  `xcrun simctl install booted ".../IOS RunSmart app.app" && xcrun simctl launch booted com.runsmart.lite`
- First focused test attempt failed during compile because an async context load was placed inside a `??` expression; fixed by branching before awaiting.
- Build/test still emit pre-existing AppIcon unassigned-child warnings and older resume-era actor-isolation warning noise.

## Critical Bug - Run Save And Garmin Merge Investigation - Merged From Base
As a TestFlight runner, I want a real completed run to save once, display real metrics, merge with Garmin when it is the same workout, and produce a useful coach report so RunSmart activity history stays trustworthy.

### Status
- [x] Post-run summary shows actual distance, time, and pace for a valid recorded run.
- [x] Done closes the post-run summary/sheet and the run remains visible.
- [x] Garmin mapping rejects invalid/non-running records.
- [x] Garmin fragments overlapping or adjacent to a longer real run do not appear as separate activities.
- [x] Garmin + RunSmart versions of the same workout merge into one canonical activity.
- [x] Run reports have useful deterministic coach notes if backend AI generation is unavailable.
- [x] Save failure path has safer copy and debug diagnostics.
- [x] Focused tests and simulator build pass.

### Validation
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Focused run-save/Garmin merge regression tests passed on iPhone 17 simulator.
- Nearby Garmin import, batch, and consolidation tests passed on iPhone 17 simulator.
- Full test pass succeeded:
  `xcodebuild -quiet -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,id=A24FA1E8-AD0C-46DB-85B7-651A24B1BB38" test`
- Manual physical-device GPS/Garmin TestFlight QA still required.

## Physical Device Outdoor Background Battery QA - 2026-05-15

### Device
- `<REDACTED_DEVICE_NAME>` / iPhone 13 (`iPhone14,5`) / iOS 26.4.2.
- Device UDID: `<REDACTED_UDID>`.
- CoreDevice identifier: `<REDACTED_COREDEVICE_ID>`.
- Full device identifiers are kept out of git-tracked task memory and should remain in private/local QA notes only.

### Status
- [x] Connected physical iPhone discovered by `xcrun xctrace list devices`.
- [x] Connected physical iPhone discovered by `xcrun devicectl list devices`.
- [x] Active scheme listed for `IOS RunSmart app.xcodeproj`.
- [x] Physical-device Debug build succeeded for `com.runsmart.lite`.
- [x] Debug app installed on the connected iPhone.
- [ ] App launch on the device completed.
- [ ] Outdoor GPS run recording started.
- [ ] Location permission prompt/denial/approval behavior verified on device.
- [ ] Run continued correctly with the phone locked/backgrounded.
- [ ] Battery start/end percentage and duration recorded.
- [ ] Weak GPS, sparse points, or permission issues documented from the real run.
- [ ] Route/benchmark/Garmin limitations rechecked after a saved/finished run.

### Validation Evidence
- `xcrun xctrace list devices` showed `<REDACTED_DEVICE_NAME> (26.4.2) (<REDACTED_UDID>)`.
- `xcrun devicectl list devices` showed `<REDACTED_DEVICE_NAME>`, identifier `<REDACTED_COREDEVICE_ID>`, state `available (paired)`, model `iPhone 13 (iPhone14,5)`.
- `xcodebuild -list -project "IOS RunSmart app.xcodeproj"` succeeded and listed scheme `IOS RunSmart app`.
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS,id=<REDACTED_UDID>" build` succeeded.
- Build evidence: `** BUILD SUCCEEDED **`; signing identity `Apple Development: <REDACTED_EMAIL> (<REDACTED_TEAM_ID>)`; provisioning profile `iOS Team Provisioning Profile: com.runsmart.lite`; bundle id `com.runsmart.lite`; HealthKit, associated domains, and background location entitlements were present.
- `xcrun devicectl device install app --device <REDACTED_COREDEVICE_ID> ".../IOS RunSmart app.app"` succeeded for bundle id `com.runsmart.lite`.
- `xcrun devicectl device process launch --device <REDACTED_COREDEVICE_ID> com.runsmart.lite` failed because the device was locked: `Unable to launch com.runsmart.lite because the device was not, or could not be, unlocked`.

### Manual QA Steps Still Required
- Unlock the connected iPhone and launch `RunSmart`.
- Record starting battery percentage before tapping `Start Run`.
- From the Run tab, tap `Start Run`; approve location permission if prompted and capture whether the app copy is clear.
- Wait for `Recording` or `Finding GPS` to resolve under open sky; note GPS accuracy text and any weak-GPS copy.
- Walk/run outdoors for at least 10 minutes, lock the phone for at least 5 minutes, then unlock and confirm time/distance/route continued.
- Finish the run, save it, and confirm the post-run route/benchmark/Garmin limitation copy remains accurate.
- Record ending battery percentage, duration, distance, GPS notes, and whether background continuation passed.

### Blocker
- External TestFlight archive/upload readiness should not start until the locked-device launch blocker is cleared and the outdoor/background/battery evidence above is captured.

## Agent OS Source Of Truth - 2026-05-15

### Status
- [x] Canonical app repo is `<LOCAL_APP_REPO_PATH>`.
- [x] Canonical status files are `tasks/todo.md`, `tasks/lessons.md`, and `tasks/session-log.md` in the app repo.
- [x] Outer wrapper `tasks/*.md` files are pointer stubs only.
- [x] Removed duplicate loose task files `tasks/todo 2.md` and `tasks/todo 3.md`.
- [x] No app feature code changed.

### Validation
- File discovery after cleanup showed exactly these app-repo status files: `tasks/todo.md`, `tasks/lessons.md`, and `tasks/session-log.md`.
- Outer wrapper discovery showed only pointer stubs: `tasks/todo.md`, `tasks/lessons.md`, and `tasks/session-log.md`.

## Open Task Triage - 2026-05-15

### What Was Checked
- Re-read `tasks/todo.md`, `tasks/session-log.md`, `tasks/lessons.md`, the Agent OS implementation and bug-fix workflows, and the active RunSmart project files.
- Checked the historical open questions for `RunSmartTab` ambiguity and `GlassCard` redeclaration.
- Verified the active `IOS RunSmart app.xcodeproj` simulator build no longer reproduces those compile blockers.

### Status
- [x] `RunSmartTab` ambiguity is not present in the active simulator build.
- [x] `GlassCard` redeclaration is not present in the active simulator build.
- [x] Active simulator build succeeds for `IOS RunSmart app`.
- [x] Connected physical device is visible: `<REDACTED_DEVICE_NAME>` / iPhone 13 / iOS 26.4.2.
- [x] Physical-device Debug build succeeds for bundle id `com.runsmart.lite`.
- [ ] Manual outdoor/background recording and battery-delta check completed before external TestFlight.

### Validation
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Full iPhone 17 XCTest run was attempted but did not complete because the simulator launch worker stalled and ended with `NSMachErrorDomain Code=-308` after interruption.
- Device discovery passed:
  `xcrun xctrace list devices`
  Evidence: `<REDACTED_DEVICE_NAME> (26.4.2) (<REDACTED_UDID>)`.
- Device list passed:
  `xcrun devicectl list devices`
  Evidence: `<REDACTED_DEVICE_NAME>`, identifier `<REDACTED_COREDEVICE_ID>`, state `connected`, model `iPhone 13 (iPhone14,5)`.
- Physical-device build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS,id=<REDACTED_UDID>" build`
  Evidence: `** BUILD SUCCEEDED **`; signing identity `Apple Development: <REDACTED_EMAIL> (<REDACTED_TEAM_ID>)`; provisioning profile `iOS Team Provisioning Profile: com.runsmart.lite`; bundle id `com.runsmart.lite`.
- Build still reports pre-existing AppIcon unassigned-child warnings and older resume-era actor-isolation warning noise.

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
