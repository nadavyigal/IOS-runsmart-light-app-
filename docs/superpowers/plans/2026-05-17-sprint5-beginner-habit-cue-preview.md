# Sprint 5: Beginner 5K Habit Track + Guided Cue Preview — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compact beginner habit card to Today for "First 5K" users and a collapsible cue-timeline preview to PreRunView using only existing data already loaded by those views.

**Architecture:** Approach A — pure derived models, no new service methods. `Beginner5KHabitTrack` is a value struct with a static `make` factory, computed in TodayTabView the same way `PlanExplanation` is. `PreRunCueTimeline` is a private SwiftUI struct in PreRunView that reads `StructuredWorkoutFactory.makeSteps(for:)` which already exists. Analytics are skipped (no wrapper found in previous sprints).

**Tech Stack:** Swift 5.9, SwiftUI, XCTest — no new dependencies.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift` | `Beginner5KHabitTrack` model + detection + `Beginner5KHabitCard` view |
| Modify | `IOS RunSmart app/Features/Today/TodayTabView.swift` | insert `Beginner5KHabitCard` guarded by `isBeginnerFirst5K` |
| Modify | `IOS RunSmart app/Features/Run/PreRunView.swift` | add `PreRunCueTimeline` private struct and wire it in |
| Modify | `IOS RunSmart appTests/RunSmartReadinessTests.swift` | add 5 Sprint 5 tests inside the existing class |
| Update | `tasks/todo.md` | append Sprint 5 section |
| Update | `tasks/session-log.md` | append Sprint 5 session entry |

---

## Task 1 — `Beginner5KHabitTrack` model and detection

**Files:**
- Create: `IOS RunSmart app/IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift`
- Modify: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

- [ ] **Step 1.1 — Write failing tests for detection and state**

Append inside `final class RunSmartReadinessTests: XCTestCase {` (before the closing `}`), before the closing brace at line 2053:

```swift
    // MARK: - Sprint 5: Beginner 5K Habit Track

    func testBeginnerHabitTrackDetectsFirst5KGoal() {
        var profile = OnboardingProfile.empty
        profile.goal = "First 5K"
        profile.experience = "Building base"
        XCTAssertTrue(Beginner5KHabitTrack.isBeginnerFirst5K(profile: profile))
    }

    func testBeginnerHabitTrackNonBeginnerIgnored() {
        var profile = OnboardingProfile.empty
        profile.goal = "10K PR"
        profile.experience = "Getting started"
        XCTAssertFalse(Beginner5KHabitTrack.isBeginnerFirst5K(profile: profile))
    }

    func testBeginnerHabitTrackRestDayState() {
        // Today has only a recovery workout → restDay
        let recovery = makeWorkout(date: "2026-05-17", kind: .recovery, title: "Recovery Jog")
        let track = Beginner5KHabitTrack.make(
            weekWorkouts: [recovery],
            activePlan: nil,
            now: makeDate("2026-05-17")
        )
        XCTAssertEqual(track.state, .restDay)
    }

    func testBeginnerHabitTrackMissedCopyIsNonShaming() {
        // Missed running workout yesterday → missedRecently
        var missed = makeWorkout(date: "2026-05-16", kind: .easy, title: "Easy Run")
        missed = WorkoutSummary(
            id: missed.id, scheduledDate: missed.scheduledDate, planID: nil,
            weekday: "", date: "", kind: .easy, title: "Easy Run",
            distance: "3.0 km", detail: "", isToday: false, isComplete: false,
            durationMinutes: nil, targetPaceSecondsPerKm: nil,
            intensity: nil, trainingPhase: nil, workoutStructure: nil
        )
        let track = Beginner5KHabitTrack.make(
            weekWorkouts: [missed],
            activePlan: nil,
            now: makeDate("2026-05-17")
        )
        XCTAssertEqual(track.state, .missedRecently)
        let shameWords = ["fail", "missed", "skip", "shame", "bad"]
        for word in shameWords {
            XCTAssertFalse(
                track.stateMessage.lowercased().contains(word),
                "Missed copy should not contain shame word: '\(word)'"
            )
        }
    }

    func testBeginnerHabitTrackWeekCompleteState() {
        let w1 = WorkoutSummary(
            id: UUID(), scheduledDate: makeDate("2026-05-13"), planID: nil,
            weekday: "", date: "", kind: .easy, title: "Easy Run",
            distance: "3.0 km", detail: "", isToday: false, isComplete: true,
            durationMinutes: nil, targetPaceSecondsPerKm: nil,
            intensity: nil, trainingPhase: nil, workoutStructure: nil
        )
        let w2 = WorkoutSummary(
            id: UUID(), scheduledDate: makeDate("2026-05-15"), planID: nil,
            weekday: "", date: "", kind: .easy, title: "Easy Run",
            distance: "5.0 km", detail: "", isToday: false, isComplete: true,
            durationMinutes: nil, targetPaceSecondsPerKm: nil,
            intensity: nil, trainingPhase: nil, workoutStructure: nil
        )
        let track = Beginner5KHabitTrack.make(
            weekWorkouts: [w1, w2],
            activePlan: nil,
            now: makeDate("2026-05-17")
        )
        XCTAssertEqual(track.state, .weekComplete)
    }
```

- [ ] **Step 1.2 — Run tests to confirm they fail (type not found)**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  build-for-testing 2>&1 | grep -E "error:|BUILD"
```

Expected: `error: cannot find type 'Beginner5KHabitTrack'` and `BUILD FAILED`.

- [ ] **Step 1.3 — Create `Beginner5KHabitCard.swift` with the model**

Create the file at `IOS RunSmart app/IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift`:

```swift
import SwiftUI

enum HabitState: Equatable {
    case onTrack
    case restDay
    case missedRecently
    case weekComplete
}

struct Beginner5KHabitTrack {
    var currentWeek: Int
    var totalWeeks: Int
    var completedThisWeek: Int
    var plannedThisWeek: Int
    var state: HabitState
    var progressLabel: String
    var confidenceLabel: String
    var nextActionTitle: String
    var nextActionDetail: String

    var stateMessage: String {
        switch state {
        case .onTrack:        return "Keep building. Every run counts."
        case .restDay:        return "Rest is training. Your body is adapting right now."
        case .missedRecently: return "Life happens. This week can still count."
        case .weekComplete:   return "Week done. You're making it real."
        }
    }

    // MARK: - Detection

    static func isBeginnerFirst5K(profile: OnboardingProfile) -> Bool {
        if profile.goal == "First 5K" { return true }
        let advancedGoals = ["10K PR", "Half Marathon", "Marathon"]
        if advancedGoals.contains(profile.goal) { return false }
        return profile.experience == "Getting started"
    }

    // MARK: - Factory

    static func make(
        weekWorkouts: [WorkoutSummary],
        activePlan: TrainingPlanSnapshot?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Beginner5KHabitTrack {
        let runningWorkouts = weekWorkouts.filter { isRunningWorkout($0) }
        let completedThisWeek = runningWorkouts.filter { $0.isComplete }.count
        let plannedThisWeek = runningWorkouts.count

        let totalWeeks = activePlan?.totalWeeks ?? 8
        let currentWeek: Int
        if let plan = activePlan {
            let components = calendar.dateComponents(
                [.weekOfYear],
                from: calendar.startOfDay(for: plan.startDate),
                to: calendar.startOfDay(for: now)
            )
            currentWeek = max(1, min((components.weekOfYear ?? 0) + 1, totalWeeks))
        } else {
            currentWeek = 1
        }

        let state = resolveState(
            runningWorkouts: runningWorkouts,
            completedThisWeek: completedThisWeek,
            plannedThisWeek: plannedThisWeek,
            weekWorkouts: weekWorkouts,
            now: now,
            calendar: calendar
        )

        let progressLabel = "Week \(currentWeek) of \(totalWeeks) · \(completedThisWeek) of \(plannedThisWeek) runs done"

        let confidenceLabel: String
        if plannedThisWeek > 0 && completedThisWeek == plannedThisWeek {
            confidenceLabel = "Great week"
        } else if completedThisWeek >= 2 {
            confidenceLabel = "Staying consistent"
        } else {
            confidenceLabel = "Building fitness"
        }

        let nextActionTitle: String
        let nextActionDetail: String
        switch state {
        case .restDay:
            nextActionTitle = "Rest today"
            nextActionDetail = "Recovery is part of the plan. Your next run is coming up."
        case .missedRecently:
            nextActionTitle = "Get back out there"
            nextActionDetail = "A gentle run today still counts toward your 5K."
        case .weekComplete:
            nextActionTitle = "Week complete"
            nextActionDetail = "Rest up and prepare for next week."
        case .onTrack:
            let upcoming = runningWorkouts
                .filter { !$0.isComplete && $0.scheduledDate >= calendar.startOfDay(for: now) }
                .sorted { $0.scheduledDate < $1.scheduledDate }
                .first
            if let next = upcoming {
                let dayLabel: String
                if calendar.isDateInToday(next.scheduledDate) {
                    dayLabel = "today"
                } else if calendar.isDateInTomorrow(next.scheduledDate) {
                    dayLabel = "tomorrow"
                } else {
                    let f = DateFormatter()
                    f.dateFormat = "EEEE"
                    dayLabel = f.string(from: next.scheduledDate)
                }
                nextActionTitle = "Run \(dayLabel)"
                nextActionDetail = "\(next.title) · \(next.distance)"
            } else {
                nextActionTitle = "Keep going"
                nextActionDetail = "Check your plan for the next session."
            }
        }

        return Beginner5KHabitTrack(
            currentWeek: currentWeek,
            totalWeeks: totalWeeks,
            completedThisWeek: completedThisWeek,
            plannedThisWeek: plannedThisWeek,
            state: state,
            progressLabel: progressLabel,
            confidenceLabel: confidenceLabel,
            nextActionTitle: nextActionTitle,
            nextActionDetail: nextActionDetail
        )
    }

    // MARK: - Private helpers

    private static func resolveState(
        runningWorkouts: [WorkoutSummary],
        completedThisWeek: Int,
        plannedThisWeek: Int,
        weekWorkouts: [WorkoutSummary],
        now: Date,
        calendar: Calendar
    ) -> HabitState {
        if plannedThisWeek > 0 && completedThisWeek == plannedThisWeek {
            return .weekComplete
        }
        let hasMissed = runningWorkouts.contains {
            !$0.isComplete &&
            calendar.startOfDay(for: $0.scheduledDate) < calendar.startOfDay(for: now)
        }
        if hasMissed { return .missedRecently }
        let hasTodayRun = runningWorkouts.contains {
            calendar.isDate($0.scheduledDate, inSameDayAs: now)
        }
        if !hasTodayRun { return .restDay }
        return .onTrack
    }

    private static func isRunningWorkout(_ workout: WorkoutSummary) -> Bool {
        switch workout.kind {
        case .strength: return false
        default: return true
        }
    }
}
```

> **Note:** Do NOT add any `import SwiftUI` or view code yet — that comes in Task 2. The file starts with `import SwiftUI` only because Task 2 will add the view.  
> Actually: since the model uses no SwiftUI types, use `import Foundation` for now. Task 2 will change it to `import SwiftUI`.

Corrected first line of the file should be `import Foundation` (not `import SwiftUI`) until Task 2 adds the view. When Task 2 adds the view, change the import to `import SwiftUI`.

- [ ] **Step 1.4 — Run build-for-testing to verify tests now compile and logic is correct**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  build-for-testing 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`. If any error: fix before proceeding.

- [ ] **Step 1.5 — Commit**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
git add "IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift" \
        "IOS RunSmart appTests/RunSmartReadinessTests.swift"
git commit -m "feat(sprint5): add Beginner5KHabitTrack model + detection + tests"
```

---

## Task 2 — `Beginner5KHabitCard` SwiftUI view

**Files:**
- Modify: `IOS RunSmart app/IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift` (add view, change import)

- [ ] **Step 2.1 — Change `import Foundation` → `import SwiftUI` at top of the file**

Replace the first line:
```swift
// Before:
import Foundation

// After:
import SwiftUI
```

- [ ] **Step 2.2 — Append the view struct at the bottom of `Beginner5KHabitCard.swift`**

Add after the closing `}` of `Beginner5KHabitTrack`:

```swift
struct Beginner5KHabitCard: View {
    var track: Beginner5KHabitTrack

    private var accentColor: Color {
        switch track.state {
        case .restDay:        return .accentRecovery
        case .missedRecently: return .accentAmber
        case .weekComplete:   return .accentSuccess
        case .onTrack:        return .accentPrimary
        }
    }

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 16, accent: accentColor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 34, height: 34)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FIRST 5K")
                            .font(.labelSM)
                            .tracking(1.6)
                            .foregroundStyle(Color.textSecondary)
                        Text(track.progressLabel)
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 0)

                    SessionDots(completed: track.completedThisWeek, total: track.plannedThisWeek, tint: accentColor)
                }

                Text(track.stateMessage)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.nextActionTitle)
                            .font(.bodyMD.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Text(track.nextActionDetail)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(track.confidenceLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(accentColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(accentColor.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }
}

private struct SessionDots: View {
    var completed: Int
    var total: Int
    var tint: Color

    var body: some View {
        let displayTotal = max(total, 1)
        HStack(spacing: 5) {
            ForEach(0..<displayTotal, id: \.self) { index in
                Circle()
                    .fill(index < completed ? tint : tint.opacity(0.22))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(tint.opacity(index < completed ? 0 : 0.5), lineWidth: 1))
            }
        }
    }
}
```

- [ ] **Step 2.3 — Build to verify the view compiles**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2.4 — Commit**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
git add "IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift"
git commit -m "feat(sprint5): add Beginner5KHabitCard SwiftUI view"
```

---

## Task 3 — Wire `Beginner5KHabitCard` into `TodayTabView`

**Files:**
- Modify: `IOS RunSmart app/IOS RunSmart app/Features/Today/TodayTabView.swift`

`TodayTabView` already loads `weekWorkouts`, `activePlan`, and has `@EnvironmentObject private var session: SupabaseSession`. The card is inserted after the existing `PlanExplanationCard`.

- [ ] **Step 3.1 — Add a computed property `habitTrack` to `TodayTabView`**

In `TodayTabView`, add this computed property after `todayExplanation` (around line 217):

```swift
    private var habitTrack: Beginner5KHabitTrack {
        Beginner5KHabitTrack.make(
            weekWorkouts: weekWorkouts,
            activePlan: activePlan
        )
    }
```

- [ ] **Step 3.2 — Add the card into the scroll view body**

In `TodayTabView.body`, the `VStack` currently has:

```swift
                PlanExplanationCard(
                    title: "Why this workout?",
                    explanation: todayExplanation,
                    onAction: { handleExplanationAction(todayExplanation) }
                )
                .runSmartStaggeredAppear(index: 3)

                TodayQuickActions(
```

Insert the beginner card block **between** `PlanExplanationCard` and `TodayQuickActions`:

```swift
                PlanExplanationCard(
                    title: "Why this workout?",
                    explanation: todayExplanation,
                    onAction: { handleExplanationAction(todayExplanation) }
                )
                .runSmartStaggeredAppear(index: 3)

                if Beginner5KHabitTrack.isBeginnerFirst5K(profile: session.onboardingProfile) {
                    Beginner5KHabitCard(track: habitTrack)
                        .runSmartStaggeredAppear(index: 4)
                }

                TodayQuickActions(
```

> **Important:** The stagger indices below will shift by one for existing cards (index 4 was QuickActions, it stays 4 but beginners see the habit card inserted, which is fine — stagger indices are not required to be unique or sequential, they just control animation delay).

- [ ] **Step 3.3 — Build to verify**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3.4 — Commit**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
git add "IOS RunSmart app/Features/Today/TodayTabView.swift"
git commit -m "feat(sprint5): show Beginner5KHabitCard on Today for First 5K users"
```

---

## Task 4 — `PreRunCueTimeline` in `PreRunView`

**Files:**
- Modify: `IOS RunSmart app/IOS RunSmart app/Features/Run/PreRunView.swift`
- Modify: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

- [ ] **Step 4.1 — Write the missing-structure test first**

Append inside `final class RunSmartReadinessTests: XCTestCase {` before the closing `}`:

```swift
    // MARK: - Sprint 5: Cue Preview

    func testPreRunCueMissingStructureHandledGracefully() {
        let workout = makeWorkout(date: "2026-05-17", kind: .tempo, title: "Tempo Run", distance: "6.0 km")
        // workoutStructure is nil by default from makeWorkout
        XCTAssertNil(workout.workoutStructure, "Fixture should have nil workoutStructure")
        // makeSteps falls back to derived steps for tempo — must not crash and must return non-empty
        let steps = StructuredWorkoutFactory.makeSteps(for: workout)
        // Derived steps exist for .tempo, so steps should be non-nil
        XCTAssertNotNil(steps)
        XCTAssertFalse(steps?.isEmpty ?? true, "Derived tempo steps should not be empty")
    }
```

> This test validates that `StructuredWorkoutFactory.makeSteps` never crashes on missing structure — which is the runtime guarantee needed by `PreRunCueTimeline`.

- [ ] **Step 4.2 — Build-for-testing to confirm test compiles**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  build-for-testing 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4.3 — Add `PreRunCueTimeline` to `PreRunView.swift`**

In `PreRunView.swift`, locate the main `RunSmartPanel` block which ends with `HStack(spacing: 10)` for Route/Audio buttons. That section currently closes its VStack like this:

```swift
                        HStack(spacing: 10) {
                            RunOptionButton(title: "Route", symbol: "map.fill", tint: .accentRecovery, action: onRoute)
                            RunOptionButton(title: "Audio", symbol: "speaker.wave.2.fill", tint: .accentPrimary, action: onAudio)
                        }
                    }
                }
```

Replace it with (adding `PreRunCueTimeline` inside the same `VStack`):

```swift
                        HStack(spacing: 10) {
                            RunOptionButton(title: "Route", symbol: "map.fill", tint: .accentRecovery, action: onRoute)
                            RunOptionButton(title: "Audio", symbol: "speaker.wave.2.fill", tint: .accentPrimary, action: onAudio)
                        }

                        PreRunCueTimeline(plannedWorkout: plannedWorkout)
                    }
                }
```

- [ ] **Step 4.4 — Add the `PreRunCueTimeline` private struct**

Append at the bottom of `PreRunView.swift` (after the existing `GPSStatusPill` struct, before the last line of the file):

```swift
private struct PreRunCueTimeline: View {
    var plannedWorkout: WorkoutSummary?
    @State private var isExpanded = false

    var body: some View {
        if let workout = plannedWorkout {
            plannedCues(for: workout)
        } else {
            freeRunIntent
        }
    }

    private var freeRunIntent: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 30, height: 30)
                .background(Color.accentPrimary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Pacing intent")
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Run by feel, no pressure. Listen to your body.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceBase.opacity(0.34), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.border, lineWidth: 1))
    }

    private func plannedCues(for workout: WorkoutSummary) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                    Text("See workout breakdown")
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(Color.surfaceBase.opacity(0.34), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    let steps = StructuredWorkoutFactory.makeSteps(for: workout)
                    if let steps, !steps.isEmpty {
                        ForEach(steps) { step in
                            CueStepRow(step: step)
                        }
                    } else {
                        Text("Workout details will appear once the structure loads.")
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct CueStepRow: View {
    var step: WorkoutStep

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(step.tint)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(step.duration) · \(step.target)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.surfaceCard.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
```

- [ ] **Step 4.5 — Build to verify**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`. If there are errors about `surfaceBase` or other color tokens, check the existing color definitions by running:

```bash
grep -rn "surfaceBase\|surfaceCard\|surfaceElevated" \
  "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/IOS RunSmart app/" \
  --include="*.swift" | head -5
```

Use whichever surface token is already used in the codebase.

- [ ] **Step 4.6 — Commit**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
git add "IOS RunSmart app/Features/Run/PreRunView.swift" \
        "IOS RunSmart appTests/RunSmartReadinessTests.swift"
git commit -m "feat(sprint5): add PreRunCueTimeline with collapsible workout steps"
```

---

## Task 5 — Final build validation and task memory update

**Files:**
- `tasks/todo.md`
- `tasks/session-log.md`

- [ ] **Step 5.1 — Full generic simulator build**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5.2 — build-for-testing (compile + link all 5 new tests)**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  build-for-testing 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5.3 — Update `tasks/todo.md`**

Append the Sprint 5 section to `IOS RunSmart app/tasks/todo.md`:

```markdown
---

## Sprint 5 - Beginner 5K Habit Track + Guided Cue Preview - 2026-05-17

As a beginner runner, I want to see a habit track on Today and a cue preview before planned runs so I know exactly what to do next.

### Expected Files
- `IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift`
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Run/PreRunView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Add `Beginner5KHabitTrack` model with detection, state resolution, and factory.
- [x] Add `Beginner5KHabitCard` view showing progress dots, state message, next action, confidence label.
- [x] Show card on Today only for First 5K / Getting started users.
- [x] Non-beginner never sees the card.
- [x] Missed workout copy is non-shaming.
- [x] Rest day explains recovery.
- [x] Add `PreRunCueTimeline` with collapsible workout steps for planned runs.
- [x] Free run shows pacing intent panel.
- [x] Missing workout structure handled gracefully.
- [x] App builds successfully.

### Scope Guard
- No plan rewrite, C25K engine, live audio coaching, route recommendation, notifications, or shame-based streaks.
- No new service protocol methods.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed and compiled 5 new Sprint 5 tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Manual QA required: First 5K beginner, intermediate user, missed workout, rest day, completed easy run, easy planned run, tempo run, free run, small iPhone.
- No analytics wrapper found; Sprint 5 did not add analytics events.
```

- [ ] **Step 5.4 — Update `tasks/session-log.md`**

Prepend a new session entry at the top of `IOS RunSmart app/tasks/session-log.md`:

```markdown
## 2026-05-17 - Beginner 5K Habit Track + Cue Preview Sprint 5

### Task Summary
Implemented Sprint 5 by adding a compact Beginner5KHabitCard for First 5K users on Today and a collapsible PreRunCueTimeline in PreRunView. Both features are purely derived from existing loaded data with no new service methods.

### Files Changed
- `IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift` (created)
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Run/PreRunView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Decisions Made
- Used Approach A (pure derived model) — no new service protocol methods. `Beginner5KHabitTrack.make` follows the same pattern as `PlanExplanation.make`.
- Detection: `profile.goal == "First 5K"` is primary; `experience == "Getting started"` with no advanced goal is secondary fallback.
- State resolution order: weekComplete → missedRecently → restDay → onTrack.
- Missed workout copy avoids shame keywords (fail, miss, skip, shame, bad).
- Rest day message focuses on recovery adaptation, not absence.
- PreRunCueTimeline uses `StructuredWorkoutFactory.makeSteps` which already exists; collapsed by default to keep small iPhone layout clean.
- Free run shows "Pacing intent" panel rather than claiming AI coaching.
- No analytics wrapper found; Sprint 5 did not add analytics events.

### Validation
- Generic simulator build passed.
- Generic simulator build-for-testing passed and compiled 5 new Sprint 5 tests.
- Manual QA required before TestFlight.

### Next Recommended Sprint
Sprint 6: Plan Adjustment Review Queue — persist one suggested adjustment from completed or imported runs, show apply/dismiss on Today and Plan, and route mutations through existing amend/reschedule flows without automatic plan adaptation.

```

- [ ] **Step 5.5 — Final commit**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
git add "tasks/todo.md" "tasks/session-log.md"
git commit -m "chore(sprint5): update task memory with Sprint 5 completion"
```

---

## Manual QA Checklist (after build)

Run through these scenarios in Simulator or on device:

- [ ] First 5K profile (goal = "First 5K") → habit card visible on Today
- [ ] Intermediate profile (goal = "10K PR") → no habit card on Today
- [ ] Missed workout scenario → card shows "Life happens" copy
- [ ] Rest day (no running workout today) → card shows "Rest is training" copy
- [ ] Week complete (all runs done) → card shows "Week done" copy
- [ ] Planned easy run → PreRunView shows "See workout breakdown" button; tap expands 3 step rows
- [ ] Tempo/interval run → cue preview shows warmup, main block, cooldown
- [ ] Free run (no planned workout) → PreRunView shows "Pacing intent" panel
- [ ] Small iPhone (SE size) → layout is readable without overflow
