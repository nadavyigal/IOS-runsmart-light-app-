# RunSmart Lite Audit

## Reference Inputs

- Web reference: `/Users/nadavyigal/Documents/RunSmart/v0/`
- Native app target: `IOS RunSmart app/`
- Visual direction: `design-assets/today page .png`, `plan page .png`, `Run page .png`, and `profile page .png`

## Screen Inventory

- Primary tabs: Today, Plan, Run, Profile.
- Coach flow: launched from primary surfaces as a sheet or full-screen flow, not as a fifth tab.
- Secondary flows: onboarding, workout detail, reschedule, add activity, route selection, reminders, coaching preferences, connected services, and empty/error states.

## Flow Inventory

- Onboarding captures runner goal, schedule, current ability, preferences, and readiness signals.
- Today explains the current recommendation, gives the fastest Start Workout path, and keeps the coach one tap away.
- Plan exposes the current week first, then month/block context.
- Run moves from pre-run guidance to live tracking and post-run reflection.
- Profile groups identity, progress, coaching preferences, achievements, and connected services.

## API And Domain Concepts To Preserve

- User profile, goal, training plan, workout, run, route, coach chat message, recovery/readiness, reminders, device sync, and preferences.
- AI chat and plan generation remain backend-owned contracts; the native app should call services instead of encoding model prompts in views.
- Local mock data is acceptable for previews and scaffolding only.

## Dense Surfaces To Hide Or Defer

- Full analytics dashboards, long historical tables, deep recovery math, raw device data, and admin/debug controls.
- Advanced settings should live behind Profile or detail screens, not in the first viewport.

## Visual Preservation List

- Dark premium athletic base.
- Neon lime coaching accent.
- Frosted cards with subtle borders.
- Coach portrait/persona as a trust anchor.
- Custom bottom navigation with prominent Run tab.
- Compact metric cards that keep first actions above the fold.
