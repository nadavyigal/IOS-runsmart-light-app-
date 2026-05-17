# Sprint 5 Design — Beginner 5K Habit Track + Guided Cue Preview

**Date:** 2026-05-17  
**Status:** Approved  
**Approach:** Approach A — pure derived model, no new service methods

---

## Goal

Help beginner runners understand exactly what to do next, using existing plan/challenge data. Add a simple pre-run cue preview. Do not build live audio or live AI coaching.

---

## Part A — Beginner 5K Habit Track

### Detection

A user is treated as a beginner First 5K runner when:
- `OnboardingProfile.goal == "First 5K"` (primary)
- OR `OnboardingProfile.experience == "Getting started"` AND goal is not a longer race (secondary fallback)

Non-beginners must never see the beginner card.

### Model: `Beginner5KHabitTrack`

Pure value struct, derived from existing loaded data in `TodayTabView`:
- `weekWorkouts: [WorkoutSummary]` (already loaded)
- `nextWorkouts: [WorkoutSummary]` (already loaded)
- `activePlan: TrainingPlanSnapshot?` (already loaded)
- `recentRuns: [RecordedRun]` (already loaded)
- `onboardingProfile: OnboardingProfile` (from `SupabaseSession`)

Fields:
```
currentWeek: Int          // inferred from plan week count or workout dates
totalWeeks: Int           // from activePlan.totalWeeks (default 8 if unavailable)
completedThisWeek: Int    // weekWorkouts where isComplete == true and isWorkout
plannedThisWeek: Int      // weekWorkouts where isWorkout == true
progressLabel: String     // "Week 2 of 8 · 1 of 3 runs done"
confidenceLabel: String   // "Building fitness", "Staying consistent", "Great week"
state: HabitState         // .onTrack | .restDay | .missedRecently | .weekComplete
nextActionTitle: String   // "Your next run is tomorrow" / "Rest today"
nextActionDetail: String  // one-line detail
```

`HabitState` determines copy:
- `.onTrack` — "Keep building. Every run counts."
- `.restDay` — "Rest is training. Your body is adapting right now."
- `.missedRecently` — "Life happens. This week can still count."
- `.weekComplete` — "Week done. You're making it real."

State resolution order (first match wins):
1. If all planned running workouts this week are complete → `.weekComplete`
2. If today has no running workout and no missed workout → `.restDay`
3. If there is any uncompleted running workout whose scheduled date is before today → `.missedRecently`
4. Otherwise → `.onTrack`

### View: `Beginner5KHabitCard`

New file: `Features/Today/Beginner5KHabitCard.swift`

Compact card using `RunSmartPanel`. Contains:
- Progress row: week label (e.g., "Week 2 of 8") + session dots (3 circles, filled = complete)
- State-specific headline (e.g., "Rest today")
- Detail line (next action or recovery message)
- Confidence label chip (e.g., "Building fitness")
- No streak counter, no shame messaging

Inserted in `TodayTabView.body` after `PlanExplanationCard`, guarded by `isBeginnerFirst5K`.

---

## Part B — Guided Cue Preview

### Cue Timeline in PreRunView

Modified file: `Features/Run/PreRunView.swift`

New private struct `PreRunCueTimeline`:
- **Free run** (no `plannedWorkout`): shows a "Pacing intent" panel — "Run by feel, no pressure. Listen to your body."
- **Planned run with steps**: shows a collapsed "See workout breakdown" button. Tapping expands a list of `WorkoutStep` rows (same visual style as `TodayWorkoutStepRow` in TodayTabView, inlined to avoid private-access issues).
- **Planned run with no parseable steps**: shows "Workout details will appear once the structure loads." — no crash, no alarming copy.

Step derivation: `StructuredWorkoutFactory.makeSteps(for: workout)` — the same call already used by `TodayTabView`.

Placement: inside `PreRunView.body`, inside the main `RunSmartPanel`, below the Route/Audio buttons.

---

## Tests

New cases added to `RunSmartReadinessTests.swift`:

| Test | Assertion |
|------|-----------|
| `testBeginnerHabitTrackDetectsFirst5KGoal` | First 5K profile → `isBeginnerFirst5K` = true |
| `testBeginnerHabitTrackNonBeginnerIgnored` | 10K PR profile → false |
| `testBeginnerHabitTrackRestDayState` | Recovery workout today, no missed → `.restDay` |
| `testBeginnerHabitTrackMissedCopyIsNonShaming` | Missed workout → message has no shame keywords |
| `testPreRunCueMissingStructureHandled` | nil `workoutStructure` → makeSteps returns nil without crash |

---

## Files

| Action | File |
|--------|------|
| Create | `IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift` |
| Modify | `IOS RunSmart app/Features/Today/TodayTabView.swift` |
| Modify | `IOS RunSmart app/Features/Run/PreRunView.swift` |
| Modify | `IOS RunSmart appTests/RunSmartReadinessTests.swift` |
| Update | `tasks/todo.md`, `tasks/session-log.md` |

---

## Scope Guards (Do Not)

- Rewrite plan generation
- Build a full C25K engine
- Build live audio coaching
- Build route recommendation
- Build notifications
- Add shame-based streaks
- Add new service protocol methods

---

## Acceptance Criteria

1. First 5K beginner sees habit track on Today.
2. Non-beginner does not see irrelevant beginner framing.
3. Missed workout copy is non-shaming.
4. Rest day explains recovery.
5. Planned workout shows cue preview before run (collapsed by default).
6. Free run shows simple pacing intent.
7. Missing workout structure is handled gracefully.
8. App builds successfully.
