# Task State

## Current Task
Implement Story 1 for the RunSmart iOS improvement: confirm app shell and information architecture mapping.

## Goal
Create a concrete current-to-future IA mapping so the app can later move toward a cleaner, lighter, premium SwiftUI RunSmart structure without breaking existing flows.

## Exact Story
As a runner, I want the app organized by daily running jobs so I can find the right feature quickly.

## Scope
- Create the approved IA mapping artifact.
- Map current/known app areas to Today, Plan, Run, Report, Coach, and Profile.
- Identify preserve/move/rename decisions and risks.
- Keep implementation documentation-only for this first story.

## Out of Scope
- No SwiftUI navigation changes.
- No full redesign.
- No app code edits.
- No signing, certificates, or provisioning changes.
- No Garmin or Apple Health implementation.
- No paid services.
- No unrelated refactors.

## Plan
- [x] Read the requested Agent OS router, memory, task, implementation, QA, and TestFlight workflow files.
- [x] Confirm the first story and constraints.
- [x] Check worktree state and preserve existing uncommitted app changes.
- [x] Create `docs/specs/runsmart-ios-ia-mapping.md`.
- [x] Verify the mapping file exists and covers all six proposed app areas.
- [x] Run lightweight project validation with `xcodebuild -list`.
- [x] Update `tasks/session-log.md`.
- [x] Update `tasks/lessons.md` if a reusable lesson is learned.

## Risks
- The repo still has product identity mismatch around `ResumeBuilder IOS APP` versus RunSmart.
- Some existing RunSmart docs/features may be stale or outside the active Xcode project.
- A docs-only first story improves implementation safety but does not change runtime UI yet.
- Existing uncommitted Swift/resource changes are present and must not be staged or modified by this story.

## Validation
- `docs/specs/runsmart-ios-ia-mapping.md` exists.
- IA mapping coverage check passed for Today, Plan, Run, Report, Coach, Profile, Garmin, HealthKit, and TestFlight.
- `xcodebuild -list -project "ResumeBuilder IOS APP.xcodeproj"` succeeded.
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "generic/platform=iOS Simulator" build` succeeded.
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test` failed in the existing test target because `ResumeOptimizationServiceSwiftTestingTests.swift` test doubles still implement `optimize(resumeId:jobDescription:token:)` while `ResumeOptimizationServiceProtocol` requires `optimize(resumeId:jobDescriptionId:token:)`.
- Simulator smoke test skipped because this story did not edit runtime UI and no app launch was required.

## Review Notes
- Implementation should be small, reviewable, and limited to one story.
- Story 1 was implemented as a documentation/spec artifact, not runtime SwiftUI code, to preserve current navigation before a concrete mapping exists.
- Existing test target failure is unrelated to this docs-only story and should be handled in a separate bug-fix story.
