# Project Progress

Project: RunSmart iOS Light
Repository: https://github.com/nadavyigal/IOS-runsmart-light-app-
Status: In Progress

Current Phase: RunSmart iOS shell migration
Active Story: Story 5 - Run Entry Point
Last Completed Story: Story 5 - Run Entry Point
Next Recommended Story: Story 6 - Place Coach contextually without adding a sixth tab
Estimated Completion: 55%

Blockers:
- Product identity still contains ResumeBuilder naming in project files and some preserved flows.
- `gh` CLI is not installed in this local environment, so GitHub PR automation is unavailable.

Risks:
- Existing uncommitted work includes app-store assets, docs, and preserved migration artifacts outside Story 5.
- Run tab intentionally shows placeholders; no GPS, manual logging, HealthKit, or Garmin behavior is implemented yet.
- Signing, bundle id, permissions, and privacy strings still need explicit TestFlight validation before release claims.

Last Validation:
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "generic/platform=iOS Simulator" build` succeeded on 2026-05-13.
- `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination "platform=iOS Simulator,name=iPhone 17" test` succeeded on 2026-05-13.

Last Updated: 2026-05-13
Current Branch: runsmart-lite-build
Latest Commit: This commit (`git log -1` on `runsmart-lite-build`)

Active Spec: `docs/specs/runsmart-ios-ia-mapping.md`
Latest QA Report: `docs/qa/ios-qa-checklist.md`
Latest PR / Deployment: Not created from this environment

Notes:
- Stories 1-5 move the shell toward Today, Plan, Run, Report, and Profile while preserving existing ResumeBuilder-era flows behind wrapper cards.
- Story 5 adds the visible Run destination only; location permissions and tracking behavior remain unchanged.
