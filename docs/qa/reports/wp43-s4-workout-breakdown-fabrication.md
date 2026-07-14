# WP-43 S4 — Fix the Workout Breakdown fabrication ("21000 × 400 m")

**Date:** 2026-07-14
**Branch:** `claude/bold-noyce-678ace`
**Audit ref:** §4 Risk 5, §10 B3/B4 — workout detail sheet showed "Repeats: 21000 × 400 m" while the card honestly showed "8 × 400m".

## Root cause

`StructuredWorkoutFactory.intervalSteps` derived the rep count from `distanceKm(from: workout.distance)`, which digit-strips the distance string. For an interval workout `workout.distance == "8 x 400m"`, `distanceKm` strips non-digits → `"8400"` → 8400 km, then `reps = max(4, Int((8400 / 0.4).rounded()))` = **21000**, rendered as "21000 × 400 m".

## Change (`StructuredWorkoutFactory.swift`)

- Added `parseIntervalReps(from:)` — parses interval notation (`"8 x 400m"`, `"8 × 400 m"`, `"10x200m"`) into `(reps, repDistance)` via `NSRegularExpression`. Returns nil for plain total distances (e.g. `"6.4 km"`) so callers never synthesize a rep count from a digit-stripped total.
- `intervalSteps` now builds the "Repeats" label from the parsed reps/distance. When the string isn't rep-notation, it shows the plan's own distance rather than fabricating a count.
- Estimated-pace labeling: when no `targetPaceSecondsPerKm`/duration is available and the hardcoded default is used, the target is labeled `"4:45 /km (est.)"` so the sheet doesn't assert a precise pace the card never showed (audit's pace-mismatch note).

## Validation

**Focused XCTest** (plan's required tests): `testIntervalBreakdownParsesRepsFromStructure` + `testBreakdownNeverExceedsPlausibleReps`.
- **Red confirmed:** reverted only `StructuredWorkoutFactory.swift` to the old digit-strip code (via `git stash push` of that one file), re-ran → `** TEST FAILED **` (old code yields "21000 × 400 m"). Restored the fix.
- **Green:** both tests pass. `testIntervalBreakdownParsesRepsFromStructure` asserts "8 x 400m" → `"8 × 400 m"`, "6 × 800m" → `"6 × 800 m"`, "10x200m" → `"10 × 200 m"`. `testBreakdownNeverExceedsPlausibleReps` asserts the leading rep count is `0 < n ≤ 40` across four interval notations.

**Full regression:** `RunSmartReadinessTests` — **166 tests, 0 failures** (`-parallel-testing-enabled NO`; the parallel run's failure was a CoreSimulator `cloneDevice` infra abort, not a test failure).

**Debug build:** app target compiled clean as part of the test build (the same build produces the installed `.app`).

**Simulator QA:** Plan tab renders the honest card value — `Intervals · 8 x 400m` (`assets-2026-07-14-wp43-s4/plan-tab.png`, iPhone 17, demo mode). The interval workout's detail-sheet breakdown itself could not be captured as a screenshot this session: `simctl` has no tap subcommand, `idb`/`cliclick` are not installed, and computer-use control of the Simulator was declined. The detail-sheet output ("8 × 400 m") is fully proven by the red→green unit test, which exercises the exact `makeSteps → intervalSteps` path that renders the sheet.

## Risks

Low. Change is confined to `intervalSteps` + a new pure parser; other workout kinds (easy/tempo/long/etc.) are untouched, and the existing `testPreRunCueMissingStructureHandledGracefully` (tempo) still passes. JSON-structured workouts (`workoutStructure` present) already used `reps_count`/`rep_distance` and were never affected.
