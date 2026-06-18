# App Review Notes - 2026-05-19

## 1.0.1 Resubmission Response - 2026-06-08

Thank you for the review. In this build, we fixed the Sign in with Apple onboarding flow so RunSmart no longer asks users to provide their name or email address after authentication. The app requests the standard full name and email scopes through AuthenticationServices and uses Apple-provided account information when available, with an internal fallback display name if Apple does not return a name.

We also made HealthKit functionality explicit in the app UI. HealthKit is now identified on sign-in, onboarding Privacy, Profile Connected services, and the HealthKit detail screen. The UI explains that HealthKit access is optional, that RunSmart reads only approved workout and wellness data, and that completed GPS runs are written to Health only when the user allows write access. RunSmart does not use CareKit.

## Reviewer Access
Provide demo credentials directly in App Store Connect. Do not store credentials in this repository.

The demo account should have:
- A completed onboarding profile.
- A beginner-friendly training plan loaded.
- At least one recent completed run or sample activity.
- Coach history available after sending a message.

## Suggested Review Flow
1. Sign in with the provided demo account.
2. Open Today to view the next workout, readiness context, and Coach entry point.
3. Open Plan to inspect upcoming workouts.
4. Start a short run from Run, then stop before recording distance if testing indoors.
5. Open Report or Activity to view completed-run history.
6. Open Profile to review connected-service and reminder settings.
7. Optional: enable notifications to verify local reminder copy.

## Integration Notes
- Apple Health access is optional and used for fitness and recovery context.
- Location access is used for GPS run tracking and route context. Background location is used only during an active recorded run.
- Garmin connection is optional. Deleting a RunSmart activity does not delete the original Garmin activity.
- Coach responses are informational training guidance and are not medical advice.
- Share cards are private by default and do not include raw coordinates or exact route maps.

## Physical Device Evidence
The release owner reported an outdoor GPS run was recorded successfully and battery use was acceptable on May 19, 2026. Exact battery percentages were not stored in repo memory.
