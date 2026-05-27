# RunSmart iOS TestFlight Readiness Audit - 2026-05-23

## Summary
RunSmart is closer to TestFlight-ready after this pass. The audit fixed one functional route-discovery gap, replaced placeholder release links with live RunSmart URLs, made the sign-in legal links tappable, and removed low-risk HealthKit warning noise. Local build-for-testing and simulator install/launch smoke passed. Final TestFlight submission is still blocked on authenticated QA, physical-device GPS/background/HealthKit checks, App Store Connect owner tasks, and a healthy simulator XCTest execution pass.

## Implemented
- Route surface preference now participates in `RouteSuggestionRanker.rank`, so Road and Trail controls influence route ordering instead of acting as inert UI.
- Generated route reasons now include the selected surface preference and elevation fit.
- Sign-in legal copy now links to Terms of Service and Privacy Policy.
- External release URLs now point to live RunSmart pages instead of `example.com`.
- HealthKit optional read types now use explicit insertion instead of side-effect-only `map` calls.

## Validation Passed
- Swift parse passed for the route ranking implementation and tests:
  `xcrun swiftc -parse "IOS RunSmart app/Services/RouteSuggestionRanker.swift" "IOS RunSmart appTests/RouteRankingTests.swift"`
- Whitespace validation passed for route-ranking files:
  `git diff --check -- "IOS RunSmart app/Services/RouteSuggestionRanker.swift" "IOS RunSmart app/Features/Routes/RouteCreatorView.swift" "IOS RunSmart appTests/RouteRankingTests.swift"`
- Generic simulator build-for-testing passed with DerivedData outside synced storage:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-audit-derived-data build-for-testing`
- iPhone 17 Pro simulator install and launch passed for bundle id `com.runsmart.lite`.
- Launch smoke reached the RunSmart sign-in screen with Sign in with Apple visible.
- Public release URLs responded successfully:
  - `https://www.runsmart-ai.com`
  - `https://www.runsmart-ai.com/support`
  - `https://www.runsmart-ai.com/privacy`
  - `https://www.runsmart-ai.com/terms`
  - `https://www.runsmart-ai.com/account-deletion`

## Blocked Or Inconclusive
- Focused `RouteRankingTests` simulator execution was attempted with `test-without-building`, but produced no output during simulator launch/test execution for roughly 90 seconds and was stopped. Do not treat this as a pass.
- XcodeBuildMCP UI snapshot failed with: `No translation object returned for simulator`.
- Authenticated Today, Coach, route-save, post-run, Garmin, and account-management smokes remain blocked without a signed-in test account or release-owner credentials.
- Physical-device GPS, background run tracking, HealthKit permission/write/read, and battery checks remain blocked without a device QA pass.
- App Store Connect build selection, screenshots, demo credentials, privacy questionnaire, category, age rating, and submission notes remain release-owner portal tasks.

## Build Warnings To Track
- `HealthKitSyncService.swift`: `HKWorkout(...)` initializer is deprecated on iOS 17 and should move to `HKWorkoutBuilder` in a follow-up.
- `RunSmartAPIModels.swift`: main actor-isolated initializer calls were observed in an earlier audit build and should be tracked if they recur in a clean build.
- AppIntents metadata extraction is skipped because the target has no AppIntents dependency.

## Go/No-Go
No-go for external TestFlight submission today. Local build and launch smoke are good enough to continue QA, but the release still needs a clean simulator XCTest run, authenticated manual smoke, physical-device GPS/background/HealthKit validation, and App Store Connect completion.
