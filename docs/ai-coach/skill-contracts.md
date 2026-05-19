# AI Coach Skill Contracts

Date: 2026-05-19

## Purpose

This document defines iOS-native contract sketches for RunSmart AI coaching skills. It preserves the useful guardrails from the original RunSmart web/PWA skill docs while using this app's actual SwiftUI screens, service protocols, Supabase Edge Function boundary, and DTO style.

These contracts are planning contracts, not runtime code. Do not copy web/PWA `.codex`, `.cursor`, or `.claude` skill directories into the iOS repo unless a later story explicitly creates an iOS-specific skill bundle.

## Current iOS Boundaries

Use these local boundaries when turning any skill into code:

- Coach sheet: `IOS RunSmart app/Features/Coach/CoachFlowView.swift`
- Today flow: `IOS RunSmart app/Features/Today/TodayTabView.swift`
- Plan flow: `IOS RunSmart app/Features/Plan/PlanTabView.swift`
- Run flow: `IOS RunSmart app/Features/Run/PreRunView.swift` and `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- Route flow: `IOS RunSmart app/Features/Routes/RouteCreatorView.swift`
- Shared app models: `IOS RunSmart app/Models/RunSmartModels.swift`
- Service protocols: `IOS RunSmart app/Services/RunSmartServices.swift`
- Live DTO namespace: `RunSmartDTO` in `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift`
- Live Coach endpoint: `supabase/functions/coach_message/index.ts`
- Supabase iOS integration: `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`

## Shared Rules

- Responses must be conservative under uncertainty.
- Do not diagnose injuries or give medical advice.
- If the runner reports pain, dizziness, chest pain, fainting, severe symptoms, or clear injury signals, the recommendation must be to stop or skip activity, rest, and consult a qualified professional.
- Do not shame missed workouts or prescribe catch-up stacking.
- Do not claim the app changed a plan unless a real service action was applied.
- Do not send raw GPS coordinates, route points, polylines, or exact private route geometry to general Coach prompts.
- Prefer deterministic checks before model output where load, readiness, or safety decisions are involved.
- Persist or display safety flags where the UI or backend can act on them.

## Shared Types

Use this shape when adding Swift DTOs later. For the current docs-only story, this is the canonical shape to mirror manually.

```swift
struct SafetyFlagDTO: Codable, Equatable {
    enum Code: String, Codable {
        case loadSpike = "load_spike"
        case injurySignal = "injury_signal"
        case heatRisk = "heat_risk"
        case missingData = "missing_data"
        case uncertain
        case medicalCaution = "medical_caution"
        case routeSafety = "route_safety"
    }

    enum Severity: String, Codable {
        case low
        case medium
        case high
    }

    var code: Code
    var severity: Severity
    var message: String
}
```

Common supporting values:

```swift
enum CoachConfidenceDTO: String, Codable {
    case low
    case medium
    case high
}

enum CoachDecisionDTO: String, Codable {
    case proceed
    case modify
    case skip
}
```

## Skill Contract: Readiness Check

### iOS Use

- Screen or flow: Today readiness, Pre-run start decision, Coach prompt "Should I run today?"
- Future caller: `ReadinessProviding` or a Coach backend intent called by `SupabaseRunSmartServices`
- Current inputs available from: `TodayRecommendation`, `RecoverySnapshot`, `WellnessSnapshot`, `TrainingContextSnapshot`, `WorkoutSummary`, `RecordedRun`

### Request Sketch

```swift
struct ReadinessCheckRequestDTO: Codable {
    var entryPoint: String
    var generatedAt: String
    var profile: RunnerContextDTO
    var plannedWorkout: WorkoutContextDTO?
    var recentRuns: [RecentRunContextDTO]
    var recovery: RecoveryContextDTO
    var wellness: WellnessContextDTO
    var limitations: [String]
}
```

### Response Sketch

```swift
struct ReadinessCheckResponseDTO: Codable {
    var decision: CoachDecisionDTO
    var recommendation: String
    var modifications: [String]
    var confidence: CoachConfidenceDTO
    var safetyFlags: [SafetyFlagDTO]
}
```

### Required Behavior

- Pain, dizziness, chest pain, fainting, severe symptoms, or injury signals must return `decision = .skip` with a high-severity safety flag.
- Missing recovery or recent-run data should usually return `decision = .modify`, not a confident high-intensity recommendation.
- The app should not disable GPS start silently. If a future UI blocks start, it must show a clear safety reason and a recovery alternative.

## Skill Contract: Workout Explainer

### iOS Use

- Screen or flow: workout detail, Plan coach notes, Coach prompt "Explain today's workout"
- Future caller: Coach backend intent or `WorkoutExplaining` service
- Current inputs available from: `WorkoutSummary`, `TrainingContextRunnerSummary`, `TrainingContextActivitySummary`, `RecoverySnapshot`

### Request Sketch

```swift
struct WorkoutExplainerRequestDTO: Codable {
    var workout: WorkoutContextDTO
    var runner: RunnerContextDTO
    var recentRuns: [RecentRunContextDTO]
    var recovery: RecoveryContextDTO?
    var limitations: [String]
}
```

### Response Sketch

```swift
struct WorkoutExplainerResponseDTO: Codable {
    var purpose: String
    var executionCues: [String]
    var commonMistakes: [String]
    var substitutions: [String]
    var safetyFlags: [SafetyFlagDTO]
}
```

### Required Behavior

- Keep output concise enough for a compact iPhone workout detail surface.
- If intensity appears too high for level, recovery, or recent load, include an easier substitution and a safety flag.
- Never tell a runner to push through pain or dizziness.

## Skill Contract: Post-Run Debrief

### iOS Use

- Screen or flow: post-run summary, run report detail, Coach conversation insertion
- Current caller candidates: `generateRunReportIfMissing`, `processCompletedActivity`
- Current inputs available from: `RecordedRun`, `RunReportDetail`, `CoachRunNotes`, `StructuredNextWorkout`, RPE UI, route match result, benchmark comparison

### Request Sketch

```swift
struct PostRunDebriefRequestDTO: Codable {
    var run: RecentRunContextDTO
    var plannedWorkout: WorkoutContextDTO?
    var rpe: Int?
    var userNotes: String?
    var recentRuns: [RecentRunContextDTO]
    var upcomingWorkouts: [WorkoutContextDTO]
    var routeContext: RouteContextDTO?
    var limitations: [String]
}
```

### Response Sketch

```swift
struct PostRunDebriefResponseDTO: Codable {
    var reflection: [String]
    var confidenceScore: Double
    var effort: String
    var recovery: [String]
    var nextStepGuidance: String
    var suggestedNextWorkout: SuggestedWorkoutDTO?
    var safetyFlags: [SafetyFlagDTO]
}
```

### Required Behavior

- Pain, abnormal heart-rate concern, dizziness, nausea, or severe symptoms must prioritize rest and professional guidance over next-workout advice.
- Confidence score must describe how well the run matched plan and expectations, not the runner's worth or identity.
- Sharing surfaces must not include raw coordinates or exact route geometry.

## Skill Contract: Plan Generator

### iOS Use

- Screen or flow: onboarding goal wizard, Plan, Today
- Existing caller: `PlanProviding.saveTrainingGoal` and `SupabaseRunSmartServices.regenerateTrainingPlan(_:)`
- Existing DTOs: `RunSmartDTO.GeneratePlanRequest` and `RunSmartDTO.GeneratePlanResponse`

### Request Additions To Consider Later

```swift
struct PlanGenerationSafetyContextDTO: Codable {
    var injuryFlags: [String]
    var recentSafetyFlags: [SafetyFlagDTO]
    var maxWeeklyIncreasePercent: Int
    var uncertaintyPolicy: String
}
```

### Response Additions To Consider Later

```swift
struct PlanGenerationCoachMetadataDTO: Codable {
    var rationale: String
    var fallbackUsed: Bool
    var safetyFlags: [SafetyFlagDTO]
    var version: String?
}
```

### Required Behavior

- Never rewrite completed history.
- Cap load progression before persistence.
- If the model suggests unsafe volume or intensity, reject or clamp before saving.
- If schema validation fails, use deterministic fallback rather than saving malformed workouts.

## Skill Contract: Load Anomaly Guard

### iOS Use

- Screen or flow: Plan explanation, Today insight, future notification or weekly digest
- Future caller: `TrainingLoadGuarding` service or Supabase background job
- Current inputs available from: `TrainingLoadSnapshot`, `RecordedRun`, `WorkoutSummary`, `RecoverySnapshot`

### Request Sketch

```swift
struct LoadAnomalyGuardRequestDTO: Codable {
    var recentRuns: [RecentRunContextDTO]
    var planWindow: [WorkoutContextDTO]
    var recovery: RecoveryContextDTO?
    var injuryFlags: [String]
}
```

### Response Sketch

```swift
struct LoadAnomalyGuardResponseDTO: Codable {
    var flags: [SafetyFlagDTO]
    var recommendedAdjustments: [PlanAdjustmentSuggestionDTO]
    var confidence: CoachConfidenceDTO
}
```

### Required Behavior

- Flag week-over-week load spikes around 20 to 30 percent unless a deterministic policy changes that threshold.
- Bias toward rest or reduced volume when injury signals exist.
- Do not automatically apply changes until a real plan mutation service exists and confirms success.

## Skill Contract: Conversational Goal Discovery

### iOS Use

- Screen or flow: onboarding goal wizard, early Coach chat
- Future caller: onboarding view model or Coach backend intent
- Current inputs available from: `OnboardingProfile`, `CoachMessage`, `TrainingGoalRequest`

### Request Sketch

```swift
struct GoalDiscoveryRequestDTO: Codable {
    var conversation: [ConversationTurnDTO]
    var partialOnboarding: OnboardingProfileContextDTO
    var runner: RunnerContextDTO?
}
```

### Response Sketch

```swift
struct GoalDiscoveryResponseDTO: Codable {
    var goal: String
    var confidence: Double
    var blockers: [String]
    var weeklyCommitment: Int
    var preferredDays: [String]
    var starterPlanID: String?
    var summaryCard: String
    var coachMessage: String
    var safetyFlags: [SafetyFlagDTO]
}
```

### Required Behavior

- Ask one clarifying question when the goal is ambiguous.
- Do not push plan generation when pain or injury is the user's main blocker.
- Keep the summary short enough for onboarding UI.

## Skill Contract: Route Builder

### iOS Use

- Screen or flow: Route Creator, pre-run route selector, Today route recommendation
- Existing service boundary: `RouteProviding.nearbyLoopRoutes`, route ranking and recommendation helpers
- Current inputs available from: target distance, current or approximate start area, surface/elevation preferences, route library

### Request Sketch

```swift
struct RouteBuilderRequestDTO: Codable {
    var distanceKm: Double
    var targetTimeMinutes: Int?
    var startArea: String?
    var surfacePreference: String?
    var elevationPreference: String?
    var constraints: [String]
}
```

### Response Sketch

```swift
struct RouteBuilderResponseDTO: Codable {
    var routeID: String
    var distanceKm: Double
    var segments: [RouteSegmentDTO]
    var mapHints: [String]
    var safetyFlags: [SafetyFlagDTO]
}
```

### Required Behavior

- If location context is missing, ask for clarification or use an explicit unavailable state.
- Do not send exact private route geometry to a general AI prompt.
- Avoid unsafe surfaces, steep grades for beginners, and heat/injury risky suggestions.

## Skill Contract: Adherence Coach

### iOS Use

- Screen or flow: Plan, weekly recap, Coach prompt "get back on track"
- Future caller: plan adherence service or Coach backend intent
- Current inputs available from: `WorkoutSummary`, `RecordedRun`, `TrainingLoadSnapshot`, `RecoverySnapshot`

### Request Sketch

```swift
struct AdherenceCoachRequestDTO: Codable {
    var planWindow: [WorkoutContextDTO]
    var completedWorkouts: [WorkoutContextDTO]
    var missedWorkouts: [WorkoutContextDTO]
    var recentRuns: [RecentRunContextDTO]
    var availability: [String]
    var reasonNotes: [String]
}
```

### Response Sketch

```swift
struct AdherenceCoachResponseDTO: Codable {
    var reshuffle: [PlanAdjustmentSuggestionDTO]
    var focus: [String]
    var message: String
    var safetyFlags: [SafetyFlagDTO]
}
```

### Required Behavior

- Do not stack multiple missed intensity sessions as catch-up.
- Limit catch-up to one session per week unless a deterministic plan policy says otherwise.
- If missed sessions are due to pain or injury, recommend rest and professional guidance rather than a harder plan.

## Shared Context DTO Sketches

These are intentionally smaller than full domain models. Add only the fields needed by a specific endpoint.

```swift
struct RunnerContextDTO: Codable {
    var goal: String
    var level: String
    var streak: String?
    var totalRuns: Int?
    var averageWeeklyDistanceKm: Double?
}

struct WorkoutContextDTO: Codable {
    var id: String?
    var scheduledDate: String?
    var title: String
    var kind: String
    var distance: String?
    var durationMinutes: Int?
    var targetPace: String?
    var detail: String?
    var isComplete: Bool?
}

struct RecentRunContextDTO: Codable {
    var id: String
    var source: String
    var startedAt: String
    var distanceKm: Double
    var movingTimeSeconds: Int
    var paceLabel: String?
    var averageHeartRateBPM: Int?
    var rpe: Int?
    var hasRoute: Bool
}

struct RecoveryContextDTO: Codable {
    var readiness: Int?
    var bodyBattery: Int?
    var sleep: String?
    var hrv: String?
    var stress: String?
    var recommendation: String?
}

struct WellnessContextDTO: Codable {
    var soreness: String?
    var mood: String?
    var hydration: String?
    var checkInStatus: String?
}

struct RouteContextDTO: Codable {
    var id: String
    var name: String
    var distanceKm: Double
    var elevationGainMeters: Int?
    var kind: String
    var hasGeometry: Bool
}

struct RouteSegmentDTO: Codable {
    var instruction: String
    var distanceKm: Double
    var surface: String?
    var elevationNote: String?
}

struct SuggestedWorkoutDTO: Codable {
    var title: String
    var dateLabel: String?
    var distance: String?
    var target: String?
    var notes: String?
}

struct PlanAdjustmentSuggestionDTO: Codable {
    var date: String?
    var change: String
    var previousSession: String?
    var newSession: String
    var rationale: String
    var safetyFlags: [SafetyFlagDTO]
}

struct ConversationTurnDTO: Codable {
    var role: String
    var content: String
    var timestamp: String
}

struct OnboardingProfileContextDTO: Codable {
    var displayName: String?
    var goal: String?
    var experience: String?
    var weeklyRunDays: Int?
    var preferredDays: [String]
    var coachingTone: String?
}
```

## Validation Requirements For Future DTO Code

When any of these sketches become Swift code:

- Add fixture-based Codable tests before UI wiring.
- Assert key sets explicitly for safety flags and dates.
- Verify missing optional sections decode safely.
- Verify unknown enum strings either fail predictably or map through a documented fallback.
- Run `xcodebuild ... build-for-testing` for Swift changes.
- Keep any raw GPS/route-coordinate rejection tests at the backend boundary.

## First Code Slice Recommendation

Story 4 implemented this first code slice:

1. Add `SafetyFlagDTO`.
2. Add `ReadinessCheckRequestDTO` and `ReadinessCheckResponseDTO`.
3. Add Codable fixture tests for proceed, modify-with-missing-data, and skip-with-medical-caution cases.
4. Do not wire the Pre-run UI until those payloads pass tests and the endpoint/service boundary is approved.

The remaining implementation guard is unchanged: do not wire Pre-run UI behavior until build-for-testing passes and a readiness endpoint or local service boundary is approved.
