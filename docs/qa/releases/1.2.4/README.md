# RunSmart 1.2.4 (42), release candidate

Founder approved "yes, merge + release" on 2026-11-05. Contents: T7 coaching tones (PR #176, merge a624885), nothing else in app code since 1.2.2. Version 1.2.3 skipped: build 41 is the 1.2.3 Apple Watch beta (PR #165).

## Validation
- Full `xcodebuild test`, iPhone 17 Pro simulator, iOS 26.5, at 1.2.4 (42): 825 passed, 0 failed, 1 skipped (`RunSharePosterRenderTests.testMapPostersRenderAtExportSize`).
- Release archive: app and Live Activity extension 1.2.4 (42), `codesign --verify --deep --strict` pass, both dSYMs present, no WorkoutKit.
- Exported IPA: both bundles Apple Distribution, get-task-allow false, entitlements as before (Sign in with Apple, associated domains, HealthKit).
- Upload to App Store Connect succeeded 2026-11-05 18:35 host time.
- Not checked on a device. The founder chose to listen to the tones in production.

## Status 2026-11-05 evening
ASC processed build 42 (Ready to Submit). Added to RunSmart Internal (1 tester), What to Test saved. Version 1.2.4 created (Prepare for Submission), build 42 selected, What's New saved and confirmed after reload. Release option carried over: automatic after approval, all users immediately. App Review notes still describe 1.2.2: Chrome froze while typing them; new text in `review-notes.txt`.

## Submitted 2026-11-05
Founder pasted the 1.2.4 review notes and said "Notes saved, submit". Notes confirmed after reload. Version 1.2.4 with build 42 submitted: ASC shows "1 Item Submitted" and 1.2.4 Waiting for Review (`submitted-waiting-for-review.jpg`). Release: automatic after approval, all users immediately.

Artifacts: `/private/tmp/runsmart-release-artifacts-2026-11-05` (archive, IPA, logs). Notes: `release-notes.txt`, `testflight-notes.txt`.
