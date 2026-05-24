# App Store Connect Closeout - 2026-05-24

## Status
Local pre-archive readiness can be completed in this repo. Final App Store Connect confirmation remains a release-owner portal task after the next merged build is archived, exported, uploaded, and processed.

## Portal Values
- App category: Health & Fitness.
- Age rating target: 4+.
- App name: RunSmart.
- Bundle identifier: `com.runsmart.lite`.
- Version: `1.0`.
- Support URL: `https://www.runsmart-ai.com/support`.
- Privacy Policy URL: `https://www.runsmart-ai.com/privacy`.
- Marketing URL: `https://www.runsmart-ai.com`.
- Terms URL: `https://www.runsmart-ai.com/terms`.

## Privacy Questionnaire Values
Use the app privacy manifest and shipped behavior as the source of truth.

- Data collected: User ID, Health, Fitness, Precise Location.
- Linked to user: yes for the collected categories above.
- Tracking: no.
- Tracking domains: none.
- Purposes: App Functionality.
- UserDefaults accessed API reason: `CA92.1`.
- Location use: GPS run recording, route history, route context, benchmark-route progress, and background location only during an active outdoor run.
- HealthKit use: optional workout, route, heart rate, HRV, sleep, steps, active energy, and completed-run writing when allowed.
- Garmin use: optional connected activity import. Deleting a RunSmart copy does not delete the original Garmin activity.

## Reviewer Notes
Use `docs/qa/app-review-notes-2026-05-19.md` as the reviewer-note source. Enter demo credentials directly in App Store Connect only.

Demo account requirements:
- Completed onboarding profile.
- Beginner-friendly active training plan.
- At least one recent completed run or sample activity.
- Coach reachable after sending a message.

Do not commit credentials, Apple account data, private device identifiers, exact battery logs, or personal reviewer notes to the repository.

## Screenshot Assets
Required local screenshot sets before archive:
- 6.9-inch iPhone: `fastlane/screenshots/en-US/iPhone_17_Pro_Max_01_today.png` through `iPhone_17_Pro_Max_05_profile.png`, each `1320 x 2868`.
- 6.1-inch iPhone: `fastlane/screenshots/en-US/iPhone_17e_01_today.png` through `iPhone_17e_05_profile.png`, each `1170 x 2532`.

The existing sign-in screenshot may remain as a supplemental asset, but the first five generated product screenshots should be the primary upload order.

## Post-Upload Portal Checklist
- Confirm the newly uploaded build finishes processing in App Store Connect.
- Select the processed build for TestFlight/App Store review.
- Upload or confirm the generated screenshot sets.
- Confirm privacy answers match this document and `PrivacyInfo.xcprivacy`.
- Set category to Health & Fitness.
- Confirm age rating resolves to 4+.
- Paste reviewer notes from `docs/qa/app-review-notes-2026-05-19.md`.
- Enter demo credentials directly in App Store Connect.
- Confirm no metadata claims medical diagnosis, live in-run AI coaching, guaranteed plan changes, or unsupported Garmin/HealthKit behavior.

## Archive Preflight Gate
Before archiving the merged build:
- `git status --short` reviewed; unrelated dirty files understood.
- No untracked Swift files under `IOS RunSmart app/`.
- App Store screenshots exist and pass exact dimension checks.
- `PrivacyInfo.xcprivacy` is present and matches the privacy questionnaire values above.
- Permission strings exist for location and HealthKit.
- Bundle id, display name, version, build number, support URL, privacy URL, and Garmin gateway URL are correct in the built app.
- Focused readiness tests pass or a release-owner waiver is recorded.
