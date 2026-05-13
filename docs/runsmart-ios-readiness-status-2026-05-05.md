# RunSmart iOS Readiness Status - 2026-05-05

## Current Status

The latest pass completed the launch UI polish for goal creation, tab safe areas, Plan, and Today. The previous data-truth pass also removed misleading fake recent runs, fake Garmin wellness values, and undeletable test activity from user-facing flows.

## Completed In This Pass

- Moved the custom tab bar into a real bottom safe-area inset so tab content can scroll above navigation.
- Rebuilt the goal wizard as a self-owned scroll layout with a pinned, bottom-safe "Create Goal & Training Plan" CTA.
- Replaced the duplicate Plan month overview strip with a RunSmart-branded weekly plan list and kept the full monthly calendar below it.
- Fixed weekly workout cards so top icons and bottom status icons are not clipped.
- Replaced the Today command center with a launch-quality workout recommendation card showing workout type, distance, target pace, intensity, duration, and expandable breakdown.
- Added tests for weekly plan grouping, current-week highlighting inputs, distance totals, and Today recommendation fallback/derived labels.
- Added a real `removeRun(_:)` service contract.
- Added local removal for RunSmart/manual/GPS runs.
- Added local tombstones for provider-backed runs so hidden Garmin activities do not reappear after sync.
- Filtered hidden runs from Activity, Profile totals, route suggestions, run reports, and current run metrics.
- Added remove controls and confirmation copy in the Activity recent-runs list.
- Added refresh notifications so Today, Run, Activity, and Profile reload when runs change.
- Removed misleading fake fallbacks from share and post-run summary views.
- Replaced static Garmin wellness panels with values loaded from `recoverySnapshot()` and `wellnessSnapshot()`.
- Changed coach chat to start from verified service messages instead of seeded sample conversation text.
- Added Garmin morning approval flow: connected users can approve fresh Garmin-derived readiness; non-wearable or stale-data users can still use manual sliders.

## Build Verification

Passed:

```sh
xcodebuild -scheme "IOS RunSmart app" -project "IOS RunSmart app/IOS RunSmart app.xcodeproj" -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -scheme "IOS RunSmart app" -project "IOS RunSmart app.xcodeproj" -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Note: the requested `iPhone 16` simulator was not installed locally, so the simulator test run used the available `iPhone 17` device.

## Launch Readiness Notes

- App icon assets are present as 1024x1024 PNGs.
- Deployment target is `iOS 17.0`.
- The `IOS RunSmart appTests` target exists and passes on the available phone simulator.
- `PrivacyInfo.xcprivacy` exists and declares User ID, Health, Fitness, Precise Location, and UserDefaults access.
- iPhone and iPad orientations are portrait-only, and the target device family is iPhone-only.
- Garmin delete behavior is app-level hiding only. A server-side `ignored_provider_activities` table or RPC should replace this before a full production sync launch.

## Xcode Test Checklist For This Build

- Build and launch the app.
- Open Goal Wizard and confirm the create-plan CTA is visible and tappable on small and large phones.
- Open Today and confirm the workout recommendation card, expand/collapse breakdown, start, modify, route, and skip actions are usable.
- Open Plan and confirm weekly list cards appear above the full month calendar.
- Swipe the This Week row and confirm workout icons/status markers are not clipped.
- Scroll Today, Plan, Run, and Profile to their last controls and confirm the tab bar does not cover content.
- Add a manual test run, confirm it appears in Activity/Profile/Today.
- Remove that run from Activity and confirm it disappears from Activity, Profile stats, Today summaries, and reports.
- Connect/sync Garmin or use an account with Garmin metrics, then open Morning Check-In and verify Garmin approval appears.
- Open Garmin Wellness and verify it shows live/empty data, not hardcoded Balanced/82/76 style values.
- Open Coach and verify it no longer starts with a fake seeded conversation.
