# Current iOS Architecture

Last inspected: 2026-05-12.

## Xcode Structure
- GitHub repo root: `IOS RunSmart app/` from the outer workspace.
- Main detected project: `ResumeBuilder IOS APP.xcodeproj`
- Targets: `ResumeBuilder IOS APP`, `ResumeBuilder IOS APPTests`
- Scheme: `ResumeBuilder IOS APP`
- Build configurations: Debug, Release
- Deployment target: iOS 17.0
- Swift version: 6.0
- Generated Info.plist is enabled.
- Signing is automatic with team id `8VC4R5M425`.

## App Entry
- Entry point: `ResumeBuilder IOS APP/ResumeBuilder_IOS_APPApp.swift`
- Root chain: `ResumeBuilder_IOS_APPApp` -> `ContentView` -> `RootView` -> `MainTabViewV2`
- App uses SwiftUI and the Observation framework.
- App currently forces dark mode with `.preferredColorScheme(.dark)`.

## Main Screens Observed
- `ScoreView`
- `TailorView`
- `RedesignResumeView`
- `ApplicationsListView`
- `ProfileViewV2`
- Legacy/current resume-builder screens also exist under `Features/Home`, `Features/Onboarding`, `Features/Profile`, `Features/Score`, `Features/Tailor`, `Features/Track`, and `Features/V2`.

## State and Services
- `AppState` is `@Observable` and `@MainActor`.
- Auth, API, storage, push, payments, export, and resume services exist.
- View models are used for several feature areas.

## Dependencies
- No Swift Package Manager dependency references were detected in the inspected project file.
- No `Package.swift`, `Podfile`, or `Cartfile` was detected for the active app.

## Tests
- Unit test target exists: `ResumeBuilder IOS APPTests`.
- Test files include resume optimization and view model tests.
- No RunSmart-specific test target or UI test target was detected.

## Permissions and Integrations
- Entitlements currently show Sign in with Apple.
- Code search did not find active CoreLocation, HealthKit, Garmin, or Strava implementation in tracked Swift app files.
- Existing docs mention GPS background tracking, HealthKit, and Garmin, so the repo may contain stale or external planning docs.

## Build Assumptions
- Use `xcodebuild -list -project "ResumeBuilder IOS APP.xcodeproj"` from the GitHub repo root.
- For builds, prefer an explicit simulator destination and scheme.
- Signing, bundle id, and product naming need review before TestFlight.
