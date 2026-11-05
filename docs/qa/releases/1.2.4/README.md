# RunSmart 1.2.4 (42), release candidate

Founder approved "yes, merge + release" on 2026-11-05. Contents: T7 coaching tones (PR #176, merge a624885), nothing else in app code since 1.2.2. Version 1.2.3 skipped: build 41 is the 1.2.3 Apple Watch beta (PR #165).

## Validation
- Full `xcodebuild test`, iPhone 17 Pro simulator, iOS 26.5, at 1.2.4 (42): 825 passed, 0 failed, 1 skipped (`RunSharePosterRenderTests.testMapPostersRenderAtExportSize`).
- Release archive: app and Live Activity extension 1.2.4 (42), `codesign --verify --deep --strict` pass, both dSYMs present, no WorkoutKit.
- Exported IPA: both bundles Apple Distribution, get-task-allow false, entitlements as before (Sign in with Apple, associated domains, HealthKit).
- Upload to App Store Connect succeeded 2026-11-05 18:35 host time.
- Not checked on a device. The founder chose to listen to the tones in production.

## Not done at this entry
ASC processing check, TestFlight group, 1.2.4 version draft with build 42 selected, App Review submission (needs the founder's final OK).

Artifacts: `/private/tmp/runsmart-release-artifacts-2026-11-05` (archive, IPA, logs). Notes: `release-notes.txt`, `testflight-notes.txt`.
