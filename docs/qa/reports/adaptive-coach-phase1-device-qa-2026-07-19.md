# Adaptive Coach Phase 1 Physical-Device QA

**Date:** 2026-07-19

**Build:** Debug from `codex/adaptive-coach-device-qa-fixture`

**Device class:** Physical iPhone, iOS 26.5.x

**QA mode:** `-RUNSMART_ADAPTIVE_COACH -RUNSMART_DEMO_MODE`

## Outcome

The safe deterministic fallback path passes the required Review → diff → confirm and dismiss-persistence device gate after two device-discovered fixes. The live AI path is not claimed because the updated `coach_message` function remains undeployed.

## Findings Resolved

1. **Card absent after local week rollover.** The demo fixture only produced a missed-workout trigger on some weekdays. Adaptive Coach QA now injects low readiness through demo data only when the dedicated QA flag is active.
2. **Contradictory easy workout.** The fallback proposed `Intervals · 8 x 400m → Easy Run · 8 x 400m`. Downgrades now clear target pace and workout structure, set easy-effort detail, and map repetition prescriptions to `5.0 km`.

## Physical QA Matrix

| Check | Result |
|---|---|
| Card renders on Today | Pass — `Recovery is running low`, readiness 38 |
| Review action opens Flex Week | Pass |
| Proposed change is coherent | Pass — `Intervals · 8 x 400m → Easy Run · 5.0 km` |
| Rationale and safety disclosure visible | Pass |
| Confirm and Keep Original actions visible | Pass |
| Confirm applies and closes normally | Pass |
| Dismiss hides card immediately | Pass |
| Dismiss persists across process relaunch | Pass |
| Today reloads after relaunch | Pass |
| Crash or console error | None observed |

An intermediate automated relaunch encountered the device lock screen and left a black launch surface. A subsequent unlocked console relaunch loaded Today normally with no crash/error; this was device-state tooling behavior, not an app failure.

## Automated Validation

- Adaptive Coach + Flex Week focused suites: **44 passed, 0 failed**.
- Full iOS suite: **306 passed, 0 failed, 0 skipped**.
- Physical Debug build and install passed.
- `git diff --check` and plist lint passed.

## Still Not Done

- Deno sanitizer tests were not run because Deno is unavailable locally.
- `coach_message` was not deployed.
- Live AI response behavior was not device-smoke-tested.
- Release flag remains a founder decision and is not remotely flippable.
