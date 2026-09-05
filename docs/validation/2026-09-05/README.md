# RunSmart continuity verification, September 5

## Reproduction

On iPhone 17 Pro / iOS 26.5 simulator, `testRunRecorderResumeExcludesMovementWhilePausedAndPersistsOnce` failed before the production fix: 110.888m became 1108.883m at the first post-pause fix; the saved total was 1219.771m instead of 221.776m. Synthetic locations only. Resetting `lastAcceptedLocation` on resume excludes that displacement.

The regression checks recording, ignored updates while paused, resumed distance, finish, decoding the persisted run, duplicate finish, ready-for-next-run state and completion-event deduplication through a reopened defaults suite. Existing tests cover transient location interruption and permission denial. This is a pause/resume test, not process-death recovery of an unfinished run.

## Commands

```
xcodebuild test -project 'IOS RunSmart app.xcodeproj' -scheme 'IOS RunSmart app' -destination 'platform=iOS Simulator,id=BEC1533B-1E20-4AD8-B86F-E321B9F9DC53' -derivedDataPath /tmp/runsmart-sept5-derived -parallel-testing-enabled NO
python3 scripts/measurement_contract.py
```

The contract was executed twice; outputs matched exactly. A separate all-events since-release query was also executed twice and returned zero events/persons/properties/install/screen counts both times. See measurement-contract.txt. No synthetic QA events were intentionally sent to PostHog; the isolated worktree has no production secrets configuration.

## Limits and handoff

- Guest preservation is tested through local restoration, upgrade state and the plan-request boundary. Native live Apple/email authentication and a generated backend workout were source-inspected, not exercised with a real account.
- The guest preview is introductory guidance; it has no durable full-plan workout identity. The generated workout is handed to the Run tab by existing code.
- Local defaults serialization and dedup flags are not a transaction or an exactly-once delivery guarantee to the analytics server. No claim about power-loss durability, public binary, physical GPS, locked-screen background recording, or recovery after process death.
- Raw route points still have no pause-segment metadata. Map polylines and derived kilometer splits can bridge a pause; this batch fixes recorded distance and its average pace, not those existing route-derived displays.
- WP-74 PR #149 remains a dependency. Its September 3 build-key rename is not a public-release boundary until a carrying binary ships. Shared contract/insight updates must preserve old app_build history and label the eventual release boundary. No vault/dashboard mutation was made here.

## Final suite result

416 passed, 0 failed: 413 XCTest cases plus 3 Swift Testing cases. Both ScreenAttributionTests passed; no simulator setup crash reproduced. Initial parallel runner startup stalled and was interrupted; serial testing worked. The first full run caught a new test's unpinned Date comparison; fixing only that fixture produced the final green suite. Result bundle: `/tmp/runsmart-sept5-derived/Logs/Test/Test-IOS RunSmart app-2026.09.05_15-00-47-+0300.xcresult`.

## Process relaunch smoke

Seeded synthetic First 5K / Getting started / Mon-Wed-Sat guest preview plus one saved-run fixture and its completion flag into the test simulator, launched, terminated and relaunched `com.runsmart.lite`. Verified the preview rendered with those answers and the corrected Garmin copy (guest-preview-relaunched.png); defaults still contained exactly one matching run and its dedup flag. These were seeded fixtures, not a run recorded through UI. Restored the three preference keys afterward. Combined with the recorder-to-storage regression, this proves the tested serialization and retention boundaries separately, not an uninterrupted end-to-end auth/GPS walk.
