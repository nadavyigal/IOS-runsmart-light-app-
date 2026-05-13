# Task State

## Current Task
Story 5 complete: Run entry point added without changing GPS behavior.

## Goal
Add a distinct Run destination to the top-level app shell so the central runner action is visible without implementing GPS, manual logging, background tracking, or integrations.

## Story 1 - Bug Fix
As a developer, I want the existing test target to compile so validation can catch real regressions.

### Expected Files
- `ResumeBuilder IOS APPTests/ResumeOptimizationServiceSwiftTestingTests.swift`

### Checklist
- [x] Update stale test doubles to match `ResumeOptimizationServiceProtocol`.
- [x] Run the existing test target.
- [x] Keep fix scoped to tests only.

## Story 2 - Today Shell
As a runner, I want the first app tab to point me toward Today so the app starts moving toward daily runner jobs without losing current functionality.

### Expected Files
- `ResumeBuilder IOS APP/Core/DesignSystem/Components/ResumlyTabBar.swift`
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
- `ResumeBuilder IOS APP/App/MainTabViewV2.swift`
- `ResumeBuilder IOS APP/Features/V2/Today/TodayView.swift`
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
- `ResumeBuilder IOS APP/App/MainTabViewV2.swift`
- `ResumeBuilder IOS APP/Core/DesignSystem/Components/ResumlyTabBar.swift`
- `ResumeBuilder IOS APP/Features/V2/Plan/PlanView.swift`
- `ResumeBuilder IOS APP/Features/V2/Report/ReportView.swift`
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

## Story 5 - Run Entry Point
As a runner, I want a clear Run tab so I can see where GPS tracking and manual run logging will live.

### Expected Files
- `ResumeBuilder IOS APP/App/MainTabViewV2.swift`
- `ResumeBuilder IOS APP/Core/DesignSystem/Components/ResumlyTabBar.swift`
- `ResumeBuilder IOS APP/Features/V2/Run/RunView.swift`
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
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test` succeeded.
- Simulator install and launch succeeded on iPhone 17.
- Visual evidence captured at `build/qa/story2-today-tab-after-wait.png`.
- First screenshot was blank because it was captured before the app finished drawing; the follow-up screenshot showed the app UI and the active `Today` tab.
- Story 3 test run succeeded with the same `xcodebuild ... test` command on iPhone 17.
- Final Story 3 simulator build check succeeded with `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "generic/platform=iOS Simulator" build`.
- Story 3 simulator install and launch succeeded on iPhone 17.
- Story 3 visual evidence captured at `build/qa/story3-today-wrapper.png`.
- Story 4 simulator build check succeeded with `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "generic/platform=iOS Simulator" build`.
- Story 4 test run succeeded with `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test`.
- Story 5 simulator build check succeeded with `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "generic/platform=iOS Simulator" build`.
- Story 5 test run succeeded with `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test`.

## Review Notes
- Keep both changes small and reviewable.
- Existing unrelated app/resource changes remain untouched.
