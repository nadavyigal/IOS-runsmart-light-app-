# RunSmart App Store Readiness Deliverables

Date: 2026-05-10

## TestFlight Release Notes

Sign in with Apple, complete onboarding, then set a training goal to generate a plan. Test the Today and Plan tabs by reviewing the current workout, opening workout details, regenerating the plan, and using the no-plan recovery actions. Record or add workouts, amend/reschedule/remove planned workouts, and confirm the plan refreshes. Try route suggestions from the Run or route selector flow with location permission enabled.

## App Store Metadata Draft

App name: RunSmart

Subtitle: Adaptive running plans and coaching

Description:
RunSmart helps runners train with an adaptive plan, a daily coaching view, workout history, and route-aware run support. Set a goal, generate a plan, review today's workout, record runs, and keep your training history aligned across RunSmart and Health when you choose to connect it.

RunSmart is built for practical day-to-day training: see what to run today, adjust workouts when life changes, review completed efforts, and get route suggestions for nearby outdoor runs.

Keywords:
running,run coach,training plan,5K,10K,marathon,fitness,workouts,route planner,HealthKit

Support URL:
https://runsmart-ai.com/support

Marketing URL:
https://runsmart-ai.com

Privacy Policy URL:
https://runsmart-ai.com/privacy

Account deletion:
The app includes Profile -> Account -> Request Account Deletion, which opens https://runsmart-ai.com/account-deletion.

## Screenshot Inventory

Existing dark-mode iPhone screenshots/assets:

- `design-assets/today page .png`
- `design-assets/plan page .png`
- `design-assets/Run page .png`
- `design-assets/profile page .png`

Recommended final App Store screenshot set:

- Today tab with generated workout
- Plan tab monthly or weekly view
- Run tab pre-run/recording route experience
- Profile tab/account and training data
- Dark-mode no-plan state showing Set Goal and Regenerate Plan

Prepared screenshot package:

- `docs/app-store-assets/screenshots/iphone-6-9/01-today-generated-workout.png`
- `docs/app-store-assets/screenshots/iphone-6-9/02-plan-monthly-weekly.png`
- `docs/app-store-assets/screenshots/iphone-6-9/03-run-route.png`
- `docs/app-store-assets/screenshots/iphone-6-9/04-profile-account.png`

Still needed: capture `05-no-plan-empty-state.png` from the real app. The packaged files are cleanly named and padded to `1290 x 2796`, which Apple currently accepts for the 6.9-inch iPhone portrait slot.

## App Privacy Responses Draft

Data linked to the user:

- User ID: used for app functionality and account management.
- Email address: used for authentication/account management.
- Location: used for route suggestions and outdoor run route recording when permission is granted.
- Health and fitness: workouts and related fitness data are read or written only when Health access is granted.
- Diagnostics: include only if crash logs or diagnostic tooling is enabled for the submitted build.

Tracking:

- No third-party tracking declared unless analytics or advertising SDKs are added before submission.

## Build Readiness Checks

- Shared scheme archives with the Release configuration.
- Release build settings do not define `DEBUG` compilation conditions.
- App icon asset: `Assets.xcassets/AppIcon.appiconset`.
- Launch screen assets: `UILaunchScreen` uses `RunSmartLaunchLogo` and `LaunchBackground`.
- Accent color asset: `Assets.xcassets/AccentColor.colorset`.

## Final Pre-Flight QA

Completed on 2026-05-10:

- Account deletion: Profile -> Account includes "Request Account Deletion" and opens `https://runsmart-ai.com/account-deletion`.
- Info.plist: required location and Health usage descriptions are present in source and the archived app.
- HealthKit: enabled in entitlements, so Health usage descriptions remain required.
- Empty states: Today and Plan show "No plan yet" with "Set Goal", "Regenerate Plan", and retry messaging.
- Logging: service/repository `print(...)` calls are guarded with `#if DEBUG`.
- Test bundle: XCTest target compiles and the readiness suite passes.
- Swift Testing: no Swift Testing markers remain in app or test source.
- Garmin: disconnected states now explain that Garmin requires the secure connection gateway before activity sync is available.
- Release archive: local Release archive succeeded at `build/RunSmart.xcarchive`.
- Fresh Release archive: local Release archive succeeded at `build/RunSmart-AppStore-2026-05-10.xcarchive`.
- Screenshot package: four cleanly named 6.9-inch PNGs prepared under `docs/app-store-assets/screenshots/iphone-6-9`; fifth no-plan screenshot still needs a real capture.
- App Privacy: local privacy manifest declares User ID, Email Address, Health, Fitness, and Precise Location as linked to the user and not used for tracking; no crash/analytics SDK references were found in source.
- Accessibility: primary actions checked use visible text or `Label` controls, including Start Workout, Save, Set Goal, Regenerate Plan, and Request Account Deletion.
- Display mode: the app forces dark mode with `preferredColorScheme(.dark)`, so light-mode screenshots are not applicable unless light mode support is added.
- Production web source: `npm run build` passes in the local `RunSmart/Running-coach-/v0` app and generates `/support` and `/account-deletion` as static pages.

Blocked until App Store Connect access is available:

- Upload archived build to TestFlight.
- Create/confirm internal testing group and add internal tester.
- Attach release notes to the processed TestFlight build.
- Command-line export/upload is blocked locally by a distribution signing keychain error: `exportArchive codesign command failed ... errSecInternalComponent`. Use Xcode Organizer export/upload, or unlock/fix keychain access for the Apple Distribution private key before running CLI upload.

Blocked until production web deploy is available:

- Local web source now has pages for `https://runsmart-ai.com/support`, `/privacy`, and `/account-deletion`; deploy the web app before App Review so the currently missing production `/support` and `/account-deletion` routes resolve.
