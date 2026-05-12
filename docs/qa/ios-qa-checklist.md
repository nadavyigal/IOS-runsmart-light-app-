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

## Accessibility
- [ ] Dynamic Type does not break primary flows.
- [ ] Tap targets are large enough.
- [ ] VoiceOver labels exist for non-text controls where needed.
- [ ] Color is not the only way to understand status.

