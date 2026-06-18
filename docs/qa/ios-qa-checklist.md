# iOS QA Checklist

Use this for simulator and device QA before calling work done.

## Build and Tests
- [ ] Xcode build succeeds for the active scheme.
- [ ] Unit tests pass if the target is available.
- [ ] New or changed behavior has appropriate test coverage or a documented manual check.

## Simulator Smoke Test
- [ ] App launches.
- [ ] No obvious console crash loop.
- [ ] Main navigation works.
- [ ] Small iPhone layout is usable.
- [ ] Dark mode is usable if dark styling is forced or supported.
- [ ] Text does not truncate badly or overlap.

## RunSmart Core Screens
- [ ] Onboarding is clear and recoverable.
- [ ] Today screen shows next action, readiness/recovery, and next workout when available.
- [ ] Plan screen explains the week and upcoming sessions.
- [ ] Run tracking starts, pauses, resumes, and finishes if present.
- [ ] Run review is understandable.
- [ ] Profile is useful but not overloaded.

## Permissions and Data
- [ ] Location permission copy is clear if location is used.
- [ ] HealthKit permission copy is clear if HealthKit is used.
- [ ] Permission denial states are handled.
- [ ] Empty, loading, error, and offline states are handled.
- [ ] Weak GPS and sparse route-point states are handled without overclaiming route matching.
- [ ] Garmin runs without map data still show reports and explain why route actions are unavailable.
- [ ] Saved route deletion removes only the RunSmart copy and benchmark tracking.

## E7 Wearable Depth
- [ ] Striver + Garmin user sees real 7-day HRV bars on Today mini-stats (not placeholder bars).
- [ ] Striver + Garmin user sees real 7-day readiness bars on Today mini-stats (not placeholder bars).
- [ ] Today Striver trend card shows latest HRV/readiness values and trend summaries.
- [ ] Garmin Wellness shows both 7-day HRV and 7-day training-readiness trend panels.
- [ ] Recovery dashboard shows live readiness + trend bars (no static mock values).
- [ ] Missing or sparse Garmin trend data shows honest fallback copy and does not fabricate values.
- [ ] Non-Striver / no-wearable flow does not regress.

## Accessibility
- [ ] Dynamic Type does not break primary flows.
- [ ] Tap targets are large enough.
- [ ] VoiceOver labels exist for non-text controls where needed.
- [ ] Color is not the only way to understand status.
