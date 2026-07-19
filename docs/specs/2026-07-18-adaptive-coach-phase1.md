# Adaptive Coach Phase 1 — Recovery- and Load-Aware Proactive Coaching

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a production, feature-flagged proactive Adaptive Coach card on Today that triggers from missed workouts, low recovery, or unsafe training-load ratio (ACWR), and enriches the existing Flex Week AI request with training-load metrics.

**Architecture:** Everything reuses the shipped Flex Week machinery (`FlexWeekEntryPresentation`, `DeterministicFlexWeekBuilder`, `coach_message` edge function with AI + deterministic fallback). Phase 1 adds three small pure units — `TrainingLoadCalculator` (session-RPE load + ACWR from `RecordedRun`), `AdaptiveCoachPolicy` (when/why to proactively surface the card), `RunSmartFeatureFlags` (Info.plist-driven kill switch, default OFF) — plus a production version of the preview card and load fields in the readiness DTO end to end.

**Tech Stack:** SwiftUI, XCTest, Supabase Edge Functions (Deno/TypeScript), PostHog via existing `RunSmartAnalytics`.

## Global Constraints

- Repo: `nadavyigal/IOS-runsmart-light-app-`, branch off `main`, one PR per task group.
- Production bundle stays `RunSmart` / `com.runsmart.lite`. No new build configurations.
- Feature flag `RUNSMART_ADAPTIVE_COACH_ENABLED` defaults to **false**; card must be invisible with flag off.
- No new third-party dependencies. No secrets in code.
- `typealias PlannedWorkout = WorkoutSummary` (FlexWeek.swift:5) — the two names are the same type.
- Existing passive link threshold is `readiness < 60` (FlexWeek.swift:216); the proactive card uses stricter `readiness < 45` so it never nags more than the passive link.
- All new logic units are pure static enums with injected `now:`/`calendar:` (house style: `TrainingMetrics`, `FlexWeekPresentation`).
- Tests live in `IOS RunSmart appTests/`, one file per unit, XCTest, no mocks.
- Simulator XCTest runner has a known stall (`waiting for workers to materialize`); if it stalls, fall back to `xcodebuild build-for-testing` compile proof + report the stall explicitly. Never claim a green run without one.

---

### Task 1: TrainingLoadCalculator

**Files:**
- Create: `IOS RunSmart app/Services/TrainingLoadCalculator.swift`
- Test: `IOS RunSmart appTests/TrainingLoadCalculatorTests.swift`

**Interfaces:**
- Consumes: `RecordedRun` (RunSmartModels.swift:878 — `startedAt: Date`, `movingTimeSeconds: TimeInterval`, `averageHeartRateBPM: Int?`, `rpe: Int?`).
- Produces:
  - `struct TrainingLoadMetrics: Hashable { let acuteLoad: Double; let chronicLoad: Double; let acwr: Double?; let status: TrainingLoadStatus }`
  - `enum TrainingLoadStatus: String { case insufficientData, detraining, optimal, elevated, highRisk }`
  - `TrainingLoadCalculator.snapshot(runs: [RecordedRun], now: Date, calendar: Calendar) -> TrainingLoadMetrics`
  - `TrainingLoadCalculator.sessionLoad(for run: RecordedRun) -> Double`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import IOS_RunSmart_app

final class TrainingLoadCalculatorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = ISO8601DateFormatter().date(from: "2026-07-18T08:00:00Z")!

    private func run(daysAgo: Int, minutes: Double, rpe: Int? = nil, hr: Int? = nil) -> RecordedRun {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .healthKit,
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            distanceMeters: minutes * 160,
            movingTimeSeconds: minutes * 60,
            averagePaceSecondsPerKm: 375,
            averageHeartRateBPM: hr,
            routePoints: [],
            rpe: rpe,
            syncedAt: nil
        )
    }

    func testSessionLoadUsesFosterSessionRPEWhenRPEPresent() {
        // Foster session-RPE: load = duration_minutes x RPE
        XCTAssertEqual(TrainingLoadCalculator.sessionLoad(for: run(daysAgo: 0, minutes: 40, rpe: 6)), 240, accuracy: 0.01)
    }

    func testSessionLoadFallsBackToModerateRPEWithoutSignals() {
        // No RPE, no HR: assume moderate effort (RPE 5)
        XCTAssertEqual(TrainingLoadCalculator.sessionLoad(for: run(daysAgo: 0, minutes: 30)), 150, accuracy: 0.01)
    }

    func testSessionLoadDerivesEffortFromHeartRateWhenNoRPE() {
        // HR 155 maps into the hard band -> derived RPE 7
        XCTAssertEqual(TrainingLoadCalculator.sessionLoad(for: run(daysAgo: 0, minutes: 30, hr: 155)), 210, accuracy: 0.01)
    }

    func testACWRBalancedLoadIsOptimal() {
        // Identical week x4: acute == chronic -> ACWR 1.0
        let runs = (0..<28).compactMap { day -> RecordedRun? in
            day % 2 == 0 ? run(daysAgo: day, minutes: 40, rpe: 5) : nil
        }
        let snapshot = TrainingLoadCalculator.snapshot(runs: runs, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.acwr ?? 0, 1.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.status, .optimal)
    }

    func testACWRSpikeFlagsHighRisk() {
        // Quiet month then a huge current week -> ACWR > 1.5
        var runs = (7..<28).compactMap { day -> RecordedRun? in
            day % 3 == 0 ? run(daysAgo: day, minutes: 30, rpe: 4) : nil
        }
        runs += (0..<7).map { run(daysAgo: $0, minutes: 60, rpe: 8) }
        let snapshot = TrainingLoadCalculator.snapshot(runs: runs, now: now, calendar: calendar)
        XCTAssertGreaterThan(snapshot.acwr ?? 0, 1.5)
        XCTAssertEqual(snapshot.status, .highRisk)
    }

    func testFewerThanFourRunsInMonthIsInsufficientData() {
        let snapshot = TrainingLoadCalculator.snapshot(
            runs: [run(daysAgo: 1, minutes: 40, rpe: 5), run(daysAgo: 9, minutes: 40, rpe: 5)],
            now: now, calendar: calendar
        )
        XCTAssertEqual(snapshot.status, .insufficientData)
        XCTAssertNil(snapshot.acwr)
    }

    func testRunsOlderThan28DaysAreIgnored() {
        var runs = (0..<28).compactMap { day -> RecordedRun? in
            day % 2 == 0 ? run(daysAgo: day, minutes: 40, rpe: 5) : nil
        }
        runs.append(run(daysAgo: 40, minutes: 300, rpe: 10)) // must not skew chronic
        let snapshot = TrainingLoadCalculator.snapshot(runs: runs, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.acwr ?? 0, 1.0, accuracy: 0.05)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from repo root):
```bash
xcodebuild test -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 16" -derivedDataPath .derivedDataFix \
  -only-testing:"IOS RunSmart appTests/TrainingLoadCalculatorTests" 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'TrainingLoadCalculator' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

enum TrainingLoadStatus: String, Hashable {
    case insufficientData
    case detraining
    case optimal
    case elevated
    case highRisk
}

struct TrainingLoadMetrics: Hashable {
    let acuteLoad: Double      // summed session load, last 7 days
    let chronicLoad: Double    // average weekly load, last 28 days
    let acwr: Double?          // acute / chronic; nil when chronic == 0 or insufficient data
    let status: TrainingLoadStatus
}

/// Session-RPE training load (Foster et al.): load = minutes x RPE.
/// Pure and deterministic; all callers inject now/calendar (house style,
/// see TrainingMetrics / FlexWeekPresentation).
enum TrainingLoadCalculator {
    static func sessionLoad(for run: RecordedRun) -> Double {
        (run.movingTimeSeconds / 60.0) * Double(effortRPE(for: run))
    }

    static func snapshot(
        runs: [RecordedRun],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrainingLoadMetrics {
        let windowStart = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let acuteStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let recent = runs.filter { $0.startedAt >= windowStart && $0.startedAt <= now }

        guard recent.count >= 4 else {
            return TrainingLoadMetrics(acuteLoad: 0, chronicLoad: 0, acwr: nil, status: .insufficientData)
        }

        let acute = recent.filter { $0.startedAt >= acuteStart }.map(sessionLoad(for:)).reduce(0, +)
        let chronic = recent.map(sessionLoad(for:)).reduce(0, +) / 4.0

        guard chronic > 0 else {
            return TrainingLoadMetrics(acuteLoad: acute, chronicLoad: 0, acwr: nil, status: .insufficientData)
        }

        let acwr = acute / chronic
        return TrainingLoadMetrics(acuteLoad: acute, chronicLoad: chronic, acwr: acwr, status: status(for: acwr))
    }

    private static func status(for acwr: Double) -> TrainingLoadStatus {
        switch acwr {
        case ..<0.8: return .detraining
        case ..<1.3: return .optimal
        case ..<1.5: return .elevated
        default: return .highRisk
        }
    }

    private static func effortRPE(for run: RecordedRun) -> Int {
        if let rpe = run.rpe, (1...10).contains(rpe) { return rpe }
        if let hr = run.averageHeartRateBPM {
            switch hr {
            case ..<120: return 3
            case ..<140: return 5
            case ..<160: return 7
            default: return 9
            }
        }
        return 5
    }
}
```

- [ ] **Step 4: Run tests to verify they pass** — same command as Step 2. Expected: PASS (7 tests). If the runner stalls at worker start, run `build-for-testing` for compile proof and report the stall.

- [ ] **Step 5: Commit**

```bash
git add "IOS RunSmart app/Services/TrainingLoadCalculator.swift" "IOS RunSmart appTests/TrainingLoadCalculatorTests.swift"
git commit -m "feat(adaptive): session-RPE training load + ACWR calculator"
```

---

### Task 2: RunSmartFeatureFlags

**Files:**
- Create: `IOS RunSmart app/App/RunSmartFeatureFlags.swift`
- Modify: `RunSmartInfo.plist` (add key after `RUNSMART_GARMIN_GATEWAY_URL`, line ~49)
- Test: `IOS RunSmart appTests/RunSmartFeatureFlagsTests.swift`

**Interfaces:**
- Produces: `RunSmartFeatureFlags.adaptiveCoachEnabled: Bool` and testable `RunSmartFeatureFlags.adaptiveCoachEnabled(infoDictionary:processArguments:) -> Bool`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import IOS_RunSmart_app

final class RunSmartFeatureFlagsTests: XCTestCase {
    func testDefaultIsOff() {
        XCTAssertFalse(RunSmartFeatureFlags.adaptiveCoachEnabled(infoDictionary: [:], processArguments: []))
    }

    func testPlistYESTurnsFlagOn() {
        XCTAssertTrue(RunSmartFeatureFlags.adaptiveCoachEnabled(
            infoDictionary: ["RUNSMART_ADAPTIVE_COACH_ENABLED": "YES"], processArguments: []))
    }

    func testPlistNOKeepsFlagOff() {
        XCTAssertFalse(RunSmartFeatureFlags.adaptiveCoachEnabled(
            infoDictionary: ["RUNSMART_ADAPTIVE_COACH_ENABLED": "NO"], processArguments: []))
    }

    func testLaunchArgumentOverridesForQA() {
        XCTAssertTrue(RunSmartFeatureFlags.adaptiveCoachEnabled(
            infoDictionary: [:], processArguments: ["-RUNSMART_ADAPTIVE_COACH"]))
    }
}
```

- [ ] **Step 2: Run to verify FAIL** (`cannot find 'RunSmartFeatureFlags' in scope`) — same xcodebuild pattern as Task 1 with `-only-testing:"IOS RunSmart appTests/RunSmartFeatureFlagsTests"`.

- [ ] **Step 3: Minimal implementation**

```swift
import Foundation

/// Local feature flags, Info.plist-driven (same pattern as RUNSMART_APP settings
/// and RunSmartDemoMode's launch-argument overrides). Default OFF.
enum RunSmartFeatureFlags {
    static var adaptiveCoachEnabled: Bool {
        adaptiveCoachEnabled(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            processArguments: ProcessInfo.processInfo.arguments
        )
    }

    static func adaptiveCoachEnabled(
        infoDictionary: [String: Any],
        processArguments: [String]
    ) -> Bool {
        if processArguments.contains("-RUNSMART_ADAPTIVE_COACH") { return true }
        let raw = (infoDictionary["RUNSMART_ADAPTIVE_COACH_ENABLED"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return raw == "YES" || raw == "TRUE" || raw == "1"
    }
}
```

Info.plist addition (inside the top-level dict, next to the other RUNSMART_ keys):

```xml
	<key>RUNSMART_ADAPTIVE_COACH_ENABLED</key>
	<string>NO</string>
```

- [ ] **Step 4: Run to verify PASS** (4 tests).
- [ ] **Step 5: Commit** — `git commit -m "feat(adaptive): RUNSMART_ADAPTIVE_COACH_ENABLED feature flag, default off"` (add the three files).

---

### Task 3: AdaptiveCoachPolicy

**Files:**
- Create: `IOS RunSmart app/Services/AdaptiveCoachPolicy.swift`
- Test: `IOS RunSmart appTests/AdaptiveCoachPolicyTests.swift`

**Interfaces:**
- Consumes: `TrainingLoadMetrics`/`TrainingLoadStatus` (Task 1), `FlexWeekPresentation.mostRecentMissedWorkout` (FlexWeek.swift:244), `FlexWeekReason` (`.missedWorkout(workoutID:)`, `.tired`), `PlannedWorkout`.
- Produces:
  - `struct AdaptiveCoachPrompt: Hashable { let trigger: AdaptiveCoachTrigger; let headline: String; let detail: String; let reason: FlexWeekReason }`
  - `enum AdaptiveCoachTrigger: String { case missedWorkout, lowRecovery, loadSpike }`
  - `AdaptiveCoachPolicy.prompt(weekWorkouts:readiness:loadSnapshot:lastDismissedAt:now:calendar:) -> AdaptiveCoachPrompt?`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import IOS_RunSmart_app

final class AdaptiveCoachPolicyTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = ISO8601DateFormatter().date(from: "2026-07-18T08:00:00Z")!

    private func workout(daysAgo: Int, complete: Bool) -> PlannedWorkout {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return PlannedWorkout(
            id: UUID(), scheduledDate: date, weekday: "MON",
            date: "1", kind: .tempo, title: "Tempo Run", distance: "8.0 km",
            detail: "", isToday: daysAgo == 0, isComplete: complete
        )
    }

    private let optimalLoad = TrainingLoadMetrics(acuteLoad: 900, chronicLoad: 900, acwr: 1.0, status: .optimal)
    private let spikedLoad = TrainingLoadMetrics(acuteLoad: 1800, chronicLoad: 1000, acwr: 1.8, status: .highRisk)

    func testMissedWorkoutWins() {
        let missed = workout(daysAgo: 1, complete: false)
        let prompt = AdaptiveCoachPolicy.prompt(
            weekWorkouts: [missed, workout(daysAgo: 0, complete: false)],
            readiness: 80, loadSnapshot: spikedLoad, lastDismissedAt: nil,
            now: now, calendar: calendar
        )
        XCTAssertEqual(prompt?.trigger, .missedWorkout)
        XCTAssertEqual(prompt?.reason, .missedWorkout(workoutID: missed.id))
    }

    func testLoadSpikeTriggersTiredReshape() {
        let prompt = AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 0, complete: false)],
            readiness: 80, loadSnapshot: spikedLoad, lastDismissedAt: nil,
            now: now, calendar: calendar
        )
        XCTAssertEqual(prompt?.trigger, .loadSpike)
        XCTAssertEqual(prompt?.reason, .tired)
    }

    func testLowRecoveryTriggersTiredReshape() {
        let prompt = AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 0, complete: false)],
            readiness: 38, loadSnapshot: optimalLoad, lastDismissedAt: nil,
            now: now, calendar: calendar
        )
        XCTAssertEqual(prompt?.trigger, .lowRecovery)
        XCTAssertEqual(prompt?.reason, .tired)
    }

    func testHealthySignalsProduceNoPrompt() {
        XCTAssertNil(AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 0, complete: false)],
            readiness: 72, loadSnapshot: optimalLoad, lastDismissedAt: nil,
            now: now, calendar: calendar
        ))
    }

    func testReadinessBetween45And60IsPassiveLinkTerritoryNotProactive() {
        // Existing passive link (readiness < 60) must stay the only surface here.
        XCTAssertNil(AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 0, complete: false)],
            readiness: 52, loadSnapshot: optimalLoad, lastDismissedAt: nil,
            now: now, calendar: calendar
        ))
    }

    func testDismissalSuppressesFor24Hours() {
        let dismissed = calendar.date(byAdding: .hour, value: -3, to: now)!
        XCTAssertNil(AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 1, complete: false)],
            readiness: 80, loadSnapshot: optimalLoad, lastDismissedAt: dismissed,
            now: now, calendar: calendar
        ))
    }

    func testDismissalExpiresAfter24Hours() {
        let dismissed = calendar.date(byAdding: .hour, value: -25, to: now)!
        XCTAssertNotNil(AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 1, complete: false)],
            readiness: 80, loadSnapshot: optimalLoad, lastDismissedAt: dismissed,
            now: now, calendar: calendar
        ))
    }

    func testInsufficientLoadDataNeverTriggersLoadSpike() {
        let insufficient = TrainingLoadMetrics(acuteLoad: 0, chronicLoad: 0, acwr: nil, status: .insufficientData)
        XCTAssertNil(AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 0, complete: false)],
            readiness: 80, loadSnapshot: insufficient, lastDismissedAt: nil,
            now: now, calendar: calendar
        ))
    }
}
```

- [ ] **Step 2: Run to verify FAIL** (`cannot find 'AdaptiveCoachPolicy' in scope`).

- [ ] **Step 3: Minimal implementation**

```swift
import Foundation

enum AdaptiveCoachTrigger: String, Hashable {
    case missedWorkout
    case lowRecovery
    case loadSpike
}

struct AdaptiveCoachPrompt: Hashable {
    let trigger: AdaptiveCoachTrigger
    let headline: String
    let detail: String
    let reason: FlexWeekReason
}

/// Decides when the coach proactively proposes a week reshape.
/// Priority: missed workout > load spike > low recovery. One prompt at a time,
/// suppressed for 24h after a dismissal. Thresholds are deliberately stricter
/// than the passive Flex Week link (readiness < 60) so the proactive card
/// stays rare and high-signal.
enum AdaptiveCoachPolicy {
    static let lowReadinessThreshold = 45
    static let dismissalCooldownHours = 24

    static func prompt(
        weekWorkouts: [PlannedWorkout],
        readiness: Int,
        loadSnapshot: TrainingLoadMetrics,
        lastDismissedAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AdaptiveCoachPrompt? {
        if let dismissed = lastDismissedAt,
           let expiry = calendar.date(byAdding: .hour, value: dismissalCooldownHours, to: dismissed),
           now < expiry {
            return nil
        }

        if let missed = FlexWeekPresentation.mostRecentMissedWorkout(in: weekWorkouts, now: now, calendar: calendar) {
            return AdaptiveCoachPrompt(
                trigger: .missedWorkout,
                headline: "Missed \(missed.title)?",
                detail: "I can reshape the rest of this week so you stay on track — nothing changes until you approve it.",
                reason: .missedWorkout(workoutID: missed.id)
            )
        }

        if loadSnapshot.status == .highRisk {
            return AdaptiveCoachPrompt(
                trigger: .loadSpike,
                headline: "Your training load jumped",
                detail: "This week is much bigger than your recent month. I can ease the next few days to lower injury risk.",
                reason: .tired
            )
        }

        if readiness > 0 && readiness < lowReadinessThreshold {
            return AdaptiveCoachPrompt(
                trigger: .lowRecovery,
                headline: "Recovery is running low",
                detail: "Readiness is \(readiness). I can soften this week so you rebuild before the next hard session.",
                reason: .tired
            )
        }

        return nil
    }
}
```

- [ ] **Step 4: Run to verify PASS** (8 tests).
- [ ] **Step 5: Commit** — `git commit -m "feat(adaptive): proactive coach trigger policy (missed/load/recovery)"`.

---

### Task 4: Production AdaptiveCoachCard on Today

**Files:**
- Create: `IOS RunSmart app/Features/Today/AdaptiveCoachCard.swift`
- Modify: `IOS RunSmart app/Features/Today/TodayTabView.swift` (card slot near the top of the scroll content, same position the preview branch used; state + handlers)
- Test: `IOS RunSmart appTests/AdaptiveCoachPolicyTests.swift` (visibility composition test added here)

**Interfaces:**
- Consumes: `AdaptiveCoachPrompt` (Task 3), `RunSmartFeatureFlags.adaptiveCoachEnabled` (Task 2), `router.openFlexWeek(preselectedReason:entryPoint:)` (RunSmartLiteAppShell.swift:58), design components `RunSmartPanel`, color/font tokens (as used by AdaptivePreviewCard on the preview branch).
- Produces: `AdaptiveCoachCard(prompt:onReview:onDismiss:)` view; `AdaptiveCoachPresentation.shouldShow(flagEnabled:prompt:) -> Bool`.

- [ ] **Step 1: Write the failing test** (append to `AdaptiveCoachPolicyTests.swift`)

```swift
    func testCardHiddenWhenFlagOffEvenWithPrompt() {
        let prompt = AdaptiveCoachPrompt(
            trigger: .missedWorkout, headline: "Missed Tempo Run?",
            detail: "detail", reason: .tired
        )
        XCTAssertFalse(AdaptiveCoachPresentation.shouldShow(flagEnabled: false, prompt: prompt))
        XCTAssertTrue(AdaptiveCoachPresentation.shouldShow(flagEnabled: true, prompt: prompt))
        XCTAssertFalse(AdaptiveCoachPresentation.shouldShow(flagEnabled: true, prompt: nil))
    }
```

- [ ] **Step 2: Run to verify FAIL** (`cannot find 'AdaptiveCoachPresentation' in scope`).

- [ ] **Step 3: Implement the card + wiring**

`AdaptiveCoachCard.swift` (production file — no `#if DEBUG`; visibility is the flag's job). Reuse the preview branch's visual design (`git show c920bbb -- "IOS RunSmart app/Features/Today/AdaptivePreviewCard.swift"` on branch `codex/runsmart-adaptive-preview`) with these changes:

```swift
import SwiftUI

enum AdaptiveCoachPresentation {
    static func shouldShow(flagEnabled: Bool, prompt: AdaptiveCoachPrompt?) -> Bool {
        flagEnabled && prompt != nil
    }
}

struct AdaptiveCoachCard: View {
    let prompt: AdaptiveCoachPrompt
    let onReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 18, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("ADAPTIVE COACH")
                        .font(.caption.weight(.black))
                        .tracking(0.8)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("adaptiveCoach.dismiss")
                }
                .foregroundStyle(Color.accentPrimary)

                Text(prompt.headline)
                    .font(.headingMD.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                Text(prompt.detail)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onReview) {
                    HStack {
                        Text("Review adjusted week")
                            .font(.bodyMD.weight(.bold))
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                            .font(.bodyMD.weight(.bold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(Color.accentPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("adaptiveCoach.review")

                Label("Nothing changes until you approve it", systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .accessibilityIdentifier("adaptiveCoach.card")
    }
}
```

`TodayTabView.swift` wiring (mirror the preview branch's insertion point, replacing its `#if DEBUG` block):

```swift
// near other @State/@AppStorage properties:
@AppStorage("runsmart.adaptiveCoach.lastDismissedAt") private var adaptiveCoachDismissedAt: Double = 0

// computed property alongside todayWorkout / adaptive helpers:
private var adaptiveCoachPrompt: AdaptiveCoachPrompt? {
    AdaptiveCoachPolicy.prompt(
        weekWorkouts: weekWorkouts,
        readiness: recovery.readiness,
        loadSnapshot: TrainingLoadCalculator.snapshot(runs: recentRuns),
        lastDismissedAt: adaptiveCoachDismissedAt > 0
            ? Date(timeIntervalSince1970: adaptiveCoachDismissedAt) : nil
    )
}

// in the scroll content, first card slot:
if RunSmartFeatureFlags.adaptiveCoachEnabled, let prompt = adaptiveCoachPrompt {
    AdaptiveCoachCard(
        prompt: prompt,
        onReview: {
            RunSmartAnalytics.adaptiveCoachAction(.review, trigger: prompt.trigger)
            router.openFlexWeek(preselectedReason: prompt.reason, entryPoint: .missedWorkoutReschedule)
        },
        onDismiss: {
            RunSmartAnalytics.adaptiveCoachAction(.dismiss, trigger: prompt.trigger)
            adaptiveCoachDismissedAt = Date().timeIntervalSince1970
        }
    )
    .runSmartStaggeredAppear(index: 0)
    .onAppear { RunSmartAnalytics.adaptiveCoachShown(trigger: prompt.trigger) }
}
```

Implementation notes for the wiring (resolve against the real file, do not guess):
- `recovery` and `recentRuns`: TodayTabView already loads recovery for the readiness ring; if `recentRuns` is not already held in state, load it in the existing `.task` via `services.recentRuns()` alongside the other awaits.
- The analytics calls compile only after Task 6; within this task stub them as `// TODO(Task 6)` comments is NOT allowed — instead add the two analytics functions in this task as no-ops that Task 6 fills in, or land Task 6 first. Preferred order if executing sequentially: Task 6's event enum may be folded into this task's commit if smaller. Executor: implement `RunSmartAnalytics.adaptiveCoachShown/adaptiveCoachAction` in this task with real PostHog capture calls following the existing pattern in `RunSmartAnalytics.swift` (see `flexWeekInterventionShown` / `flexWeekInterventionAction` for the exact shape), and Task 6 then only covers the funnel doc + rollout.

- [ ] **Step 4: Run to verify PASS** — policy tests + full `build-for-testing` compile.
- [ ] **Step 5: Manual QA on Simulator** — launch with `-RUNSMART_ADAPTIVE_COACH` launch argument (QA override from Task 2) plus demo mode; verify: card appears for the demo missed workout, Review opens Flex Week with reason preselected, diff + confirm works, X dismisses and card stays gone on refresh, relaunch without the argument shows no card.
- [ ] **Step 6: Commit** — `git commit -m "feat(adaptive): production Adaptive Coach card on Today behind flag"`.

---

### Task 5: Load-aware AI request (client DTO + edge function)

**Files:**
- Modify: `IOS RunSmart app/Models/FlexWeek.swift` (ReadinessContext: add load fields, extend `make()`)
- Modify: `IOS RunSmart app/Services/FlexWeekServiceSupport.swift` (`readinessDTO(from:)` — map new fields)
- Modify: DTO struct in `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift` (`FlexWeekRequestDTO` readiness payload: add `acwr`, `acute_load`, `chronic_load`, `load_status`)
- Modify: `supabase/functions/coach_message/flex_week.ts` (sanitize + type + prompt context)
- Test: `IOS RunSmart appTests/FlexWeekTests.swift` (DTO encoding), `supabase/functions/coach_message/index_test.ts` (sanitize)

**Interfaces:**
- Consumes: `TrainingLoadMetrics` (Task 1), existing `ReadinessContext` (FlexWeek.swift:50), `FlexWeekReadinessContextDTO` (flex_week.ts:26).
- Produces: readiness payload carrying `acwr: Double?`, `acuteLoad: Double?`, `chronicLoad: Double?`, `loadStatus: String?` end to end; edge-function prompt includes a "Training load" line when present.

- [ ] **Step 1: Write the failing Swift test** (append to FlexWeekTests.swift)

```swift
    func testFlexWeekRequestDTOEncodesTrainingLoadFields() throws {
        var context = ReadinessContext(
            readiness: 42, readinessLabel: "Low", bodyBattery: 30,
            hrv: "38 ms", sleep: "6h 10m", recommendation: "Take it easy"
        )
        context.acwr = 1.62
        context.acuteLoad = 1780
        context.chronicLoad = 1100
        context.loadStatus = "highRisk"

        let request = FlexWeekRequest(reason: .tired, currentWeek: [], readinessContext: context)
        let dto = FlexWeekServiceSupport.buildRequestDTO(from: request)
        let data = try JSONEncoder().encode(dto)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"acwr\":1.62"))
        XCTAssertTrue(json.contains("\"acute_load\":1780"))
        XCTAssertTrue(json.contains("\"chronic_load\":1100"))
        XCTAssertTrue(json.contains("\"load_status\":\"highRisk\""))
    }
```

- [ ] **Step 2: Run to verify FAIL** (no such properties on `ReadinessContext`).

- [ ] **Step 3: Implement Swift side**

`ReadinessContext` additions (FlexWeek.swift, keep existing fields untouched):

```swift
    // Training-load context (Phase 1 adaptive coach). Optional so existing
    // callers and cached requests stay valid.
    var acwr: Double?
    var acuteLoad: Double?
    var chronicLoad: Double?
    var loadStatus: String?

    static func make(
        recovery: RecoverySnapshot,
        recommendation: TodayRecommendation,
        load: TrainingLoadMetrics? = nil
    ) -> ReadinessContext {
        var context = ReadinessContext(
            readiness: recommendation.readiness > 0 ? recommendation.readiness : recovery.readiness,
            readinessLabel: recommendation.readinessLabel,
            bodyBattery: recovery.bodyBattery,
            hrv: recovery.hrv,
            sleep: recovery.sleep,
            recommendation: recovery.recommendation
        )
        if let load, load.status != .insufficientData {
            context.acwr = load.acwr
            context.acuteLoad = load.acuteLoad
            context.chronicLoad = load.chronicLoad
            context.loadStatus = load.status.rawValue
        }
        return context
    }
```

DTO: add the four optional fields to the readiness DTO struct with CodingKeys `acwr`, `acute_load`, `chronic_load`, `load_status`; map them in `FlexWeekServiceSupport.readinessDTO(from:)`. Callers: `FlexWeekEntryView.swift:93` and `FlexWeekFlowView.swift:219` pass `load: TrainingLoadCalculator.snapshot(runs: runs)` using the runs they already fetch (or fetch via `services.recentRuns()` in the same task group).

- [ ] **Step 4: Run Swift test to verify PASS.**

- [ ] **Step 5: Edge function (TDD with deno)** — add to `index_test.ts`:

```typescript
Deno.test("sanitizeFlexWeekRequest keeps training load fields", () => {
  const result = sanitizeFlexWeekRequest({
    reason: "tired",
    currentWeek: [],
    readinessContext: {
      readiness: 42, acwr: 1.62, acute_load: 1780, chronic_load: 1100, load_status: "highRisk",
    },
  });
  assertEquals(result?.readiness_context?.acwr, 1.62);
  assertEquals(result?.readiness_context?.load_status, "highRisk");
});
```

Run `deno test supabase/functions/coach_message/` → FAIL. Then in `flex_week.ts`: extend `FlexWeekReadinessContextDTO` with `acwr?: number | null; acute_load?: number | null; chronic_load?: number | null; load_status?: string | null;`, sanitize them (`numberValue(...)`, `limitString(..., 20)`), and where the AI prompt assembles readiness context add:

```typescript
  if (readiness_context?.acwr != null) {
    lines.push(`Training load: acute:chronic ratio ${readiness_context.acwr.toFixed(2)} (${readiness_context.load_status ?? "unknown"}). Above 1.5 means elevated injury risk — bias toward easing volume and protecting rest days.`);
  }
```

(Locate the exact prompt-assembly site in `generateFlexWeek` at flex_week.ts:196 and use its existing string-building variable; the fallback path ignores load by design.)

Run `deno test` → PASS.

- [ ] **Step 6: Commit** — `git commit -m "feat(adaptive): thread ACWR/load context through Flex Week AI request"`.
- **Deploy note:** edge-function deploy (`supabase functions deploy coach_message`) requires explicit founder "yes" per global rules — flag it, never auto-deploy.

---

### Task 6: Telemetry funnel + rollout gate

**Files:**
- Modify: `IOS RunSmart app/Services/RunSmartAnalytics.swift` (if not already landed in Task 4: `adaptiveCoachShown(trigger:)`, `adaptiveCoachAction(_:trigger:)` with action enum `.review`/`.dismiss`; follow the `flexWeekInterventionShown`/`flexWeekInterventionAction` capture pattern exactly — same client, same property naming style, event names `adaptive_coach_shown`, `adaptive_coach_action` with `trigger` and `action` properties)
- Modify: `tasks/progress.md`, `tasks/todo.md` (Phase 1 status)
- Create: `docs/specs/2026-07-18-adaptive-coach-phase1.md` (this plan, committed for traceability)

**Interfaces:**
- Consumes: PostHog client wrapper already inside `RunSmartAnalytics.swift`.
- Produces: funnel `adaptive_coach_shown → adaptive_coach_action(review) → flex week confirm` measurable in PostHog (confirm event already exists in the Flex Week flow).

- [ ] **Step 1:** If analytics functions were landed in Task 4, verify event names match this task's spec; otherwise implement them now (same code as Task 4 Step 3 notes).
- [ ] **Step 2:** Build compiles (`build-for-testing`), full focused suite green (or stall documented).
- [ ] **Step 3:** Update `tasks/progress.md` + `tasks/todo.md`; commit plan doc.
- [ ] **Step 4: Commit + push + PR** — `git commit -m "feat(adaptive): telemetry funnel + phase-1 docs"`, push branch, open PR titled "Adaptive Coach Phase 1: recovery- and load-aware proactive coaching (flag off)".
- **Rollout gate (founder decision, after merge):** flip `RUNSMART_ADAPTIVE_COACH_ENABLED` to `YES` in a release only after PostHog exclusions for founder/QA accounts are confirmed (see PostHog founder-account-exclusion rule); measure card show→review→confirm for 2 weeks before Phase 2.

---

## Explicitly deferred to Phase 2 (do not build now)

- Multi-day plan regeneration beyond the current week (full plan re-periodization).
- Garmin training-status ingestion as a load source (Garmin work is paused per 2026-07-02 decision; ACWR from RecordedRun covers both HealthKit and Garmin-synced runs already).
- Push notifications for proactive prompts (card-on-Today only in Phase 1).
- Server-side load computation (client-side is sufficient and offline-friendly).

## Implementation deviations log

- **Task 1 (2026-07-18):** the engine's result type is `TrainingLoadMetrics`, not `TrainingLoadSnapshot` — that name was already taken by the backend-fed Activity-tab display model (`RunSmartModels.swift:1724`, string-typed ACWR + recap copy). All later tasks' references updated accordingly. The display model and the engine stay separate types on purpose: one is presentation from the server, the other is client-computed signal for the coach policy.
- **Task 4 (2026-07-18):** analytics events (`adaptive_coach_shown`, `adaptive_coach_action`) landed in Task 4 per the plan's fold-in note; `AdaptiveCoachPresentation` lives in `AdaptiveCoachPolicy.swift` (pure logic), not the SwiftUI file. Manual QA: card verified live on sim via `-RUNSMART_ADAPTIVE_COACH -RUNSMART_DEMO_MODE` (screenshot in `docs/qa/reports/assets-2026-07-18-adaptive-phase1/`); tap-through of Review/dismiss is founder-smoke (no scriptable tap on this machine — same constraint as WP-43 sessions).
- **Task 5 (2026-07-18):** DTO load fields are **camelCase** (`acwr`, `acuteLoad`, `chronicLoad`, `loadStatus`), matching the existing `FlexWeekReadinessContextDTO` convention — not the plan's snake_case; the edge sanitizer accepts both spellings. The AI prompt change is a system-prompt rule (ACWR semantics) rather than line assembly — `generateFlexWeek` passes the whole sanitized request as JSON, so the sanitizer is the only data gate. Deno tests written but not run locally (deno not installed); they run wherever deno is available. Edge function NOT deployed — requires explicit founder approval.
