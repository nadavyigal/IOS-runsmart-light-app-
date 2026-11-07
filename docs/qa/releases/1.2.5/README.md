# RunSmart 1.2.5 (43), Apple Watch release candidate

Founder said "Yes, start 1.2.5" on 2026-11-07 after PR #165 merged (`8f35e73`). Contents since live 1.2.4 (42): the Apple Watch workout round trip (WorkoutKit scheduling, Health import, deferred plan completion) and its review fixes `a4bab42` and `acc8e59`. This branch also carries the 1.2.4 release records from PR #177.

## Validation
- Full `xcodebuild test` at the release source, iPhone 17 Pro simulator: 863 tests, 862 passed, 0 failed, 1 skipped (existing opt-in `RunSharePosterRenderTests.testMapPostersRenderAtExportSize`). `TEST SUCCEEDED`.
- Release archive from `f43ba8d`: app `com.runsmart.lite` and extension `com.runsmart.lite.runliveactivity` both 1.2.5 (43). `codesign --verify --deep --strict` passes. Both dSYMs present. WorkoutKit and HealthKit linked. PostHog key present (47 characters). Built without `RunSmartSecrets.xcconfig`, so committed defaults apply, as in 1.2.4.
- `scripts/verify-release-backend.py` on the archived app and on the exported IPA's app: passed, auth settings HTTP 200, Apple and email sign-in enabled.
- Exported IPA (13.4 MB): both bundles signed `Apple Distribution: Nadav Yigal (8VC4R5M425)`, `get-task-allow` false on both, HealthKit entitlement on the app.
- Not yet done: TestFlight upload (needs founder yes), the external tester's paired-Watch round trip on build 43, App Store submission (needs founder yes).

## Why a new Watch check
Build 41's Watch pass (2026-11-07) came from `4f20bc0`, before `a4bab42` and `acc8e59` changed how a Watch run completes the plan. Build 43 needs its own pass. Steps are in `testflight-notes.txt`.

Notes: `release-notes.txt` (What's New), `testflight-notes.txt` (What to Test), `review-notes.txt` (App Review). Local artifacts (archive, IPA, logs) are in the session scratchpad, not in git.
