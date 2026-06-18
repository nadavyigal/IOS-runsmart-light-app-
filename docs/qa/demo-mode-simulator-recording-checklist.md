# Demo Mode Simulator Recording Checklist

Use this only for DEBUG simulator recordings. Demo Mode is not App Review account-cycle evidence.

## Launch

- Build a Debug simulator app.
- Launch with one of:
  - Environment: `DEMO_MODE=true`
  - Environment: `RUNSMART_DEMO_MODE=1`
  - Argument: `-RUNSMART_DEMO_MODE`
- Optional initial tab:
  - Environment: `RUNSMART_INITIAL_TAB=Today`
  - Argument pair: `-INITIAL_TAB Today`

## Pre-Recording

- Confirm the app opens directly to RunSmart content, not Sign in with Apple.
- Confirm no Apple Account, Supabase, Garmin OAuth, HealthKit permission, purchase, or backend prompt appears.
- Set Simulator appearance and text size for the video.
- Turn off Simulator auto-lock and notification previews if needed.

## Screen Pass

- Today shows readiness, workout recommendation, plan strip, route, report, and recovery context.
- Plan shows current week, month/progress views, and plan explanation.
- Report shows recent runs and generated report summaries/details.
- Profile shows demo identity, stats, achievements, and connected Garmin/HealthKit state.
- Coach sheets open with demo-context responses.

## Safeguards

- Do not use Demo Mode for App Store review proof.
- Do not record screens that imply real account deletion, payment, Garmin authorization, or HealthKit permission was completed.
- If testing destructive buttons, verify they are disabled or demo-local only.
- Release/TestFlight builds must be validated separately without Demo Mode.
