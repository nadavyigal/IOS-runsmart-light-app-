# RunSmart iOS Readiness Status - 2026-05-05

## Current Status

This pass focused on the highest-risk release issue: the app must not present fake recent runs, fake Garmin wellness values, or undeletable test activity as real user truth.

## Completed In This Pass

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
xcodebuild -scheme "IOS RunSmart app" -project "IOS RunSmart app.xcodeproj" -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Still Not App Store Ready

- App icon asset catalog still needs real 1024x1024 PNG files.
- Deployment target is still iOS 26.2.
- No test target exists yet.
- No privacy manifest was found.
- iPad and landscape are enabled but not verified against the current UI.
- Garmin delete behavior is app-level hiding only. A server-side `ignored_provider_activities` table or RPC should replace this before a full production sync launch.
- Today screen still needs a deeper design pass to fully match the supplied "running coach 3" reference.

## Xcode Test Checklist For This Build

- Build and launch the app.
- Add a manual test run, confirm it appears in Activity/Profile/Today.
- Remove that run from Activity and confirm it disappears from Activity, Profile stats, Today summaries, and reports.
- Connect/sync Garmin or use an account with Garmin metrics, then open Morning Check-In and verify Garmin approval appears.
- Open Garmin Wellness and verify it shows live/empty data, not hardcoded Balanced/82/76 style values.
- Open Coach and verify it no longer starts with a fake seeded conversation.
