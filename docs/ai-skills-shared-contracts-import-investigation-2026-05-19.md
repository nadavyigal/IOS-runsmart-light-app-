# AI Skills And Shared Contracts Import Investigation

Date: 2026-05-19

## Scope

Investigate how selected AI coaching skills and shared TypeScript contracts from the original RunSmart web/PWA repo can fit into this native iOS app before implementation.

Source inspected:
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/docs/ai-skills/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/.codex/skills/_index/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/.codex/skills/plan-generator/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/.codex/skills/readiness-check/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/.codex/skills/workout-explainer/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/.codex/skills/conversational-goal-discovery/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/.codex/skills/load-anomaly-guard/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/.codex/skills/route-builder/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/.cursor/skills/post-run-debrief/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/.claude/skills/adherence-coach/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/packages/shared/src/models/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/packages/shared/src/api/`
- `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/packages/shared/scripts/generate-swift-types.ts`

Explicitly not imported:
- Source Agent OS files, workflows, product docs, root instructions, and task-board files.
- Source `.codex`, `.cursor`, or `.claude` skill directories.
- Bulk TypeScript model files.
- Generated Swift models.
- Secrets or local env values.

## Local iOS Fit

The iOS repo already has useful integration points:

- Coach chat UI: `IOS RunSmart app/Features/Coach/CoachFlowView.swift`
- Context collection: `TrainingContextProviding.trainingContext(for:)` in `IOS RunSmart app/Services/RunSmartServices.swift`
- Live Coach DTOs: `RunSmartDTO.SendCoachMessageRequest`, `TrainingContextSnapshotDTO`, and `SendCoachMessageResponse` in `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift`
- Live Coach service: `SupabaseRunSmartServices.send(message:context:)`
- Backend guardrail layer: `supabase/functions/coach_message/index.ts`
- Plan generation DTOs: `RunSmartDTO.GeneratePlanRequest` and `GeneratePlanResponse`
- Plan persistence: `TrainingPlanRepository` through `SupabaseRunSmartServices.regenerateTrainingPlan(_:)`
- Run report DTOs: `RunSmartDTO.RunReportRequest` and `RunReportResponse`
- Route models/services: `RouteSuggestion`, `SavedRoute`, `RouteRecommendation`, `RouteSuggestionRanker`, `RouteCreatorView`
- Recovery/load surfaces: `RecoverySnapshot`, `WellnessSnapshot`, `TrainingLoadSnapshot`, Today, Plan, and Run screens

The first safe representation should be docs and contracts. The app is already live enough that copying source skill folders or regenerating all models would create naming, date, id, optionality, and Codable risk without improving current behavior.

## Skill Mapping

| Source skill | iOS home | Screen or flow | Caller | Inputs needed | Outputs stored or displayed | Guardrails to preserve | Recommendation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Plan generator | `RunSmartDTO.GeneratePlanRequest/Response`, `SupabaseRunSmartServices.regenerateTrainingPlan`, `TrainingPlanRepository` | Onboarding goal wizard, Plan tab, Today recommendation | `PlanProviding.saveTrainingGoal` and `regenerateTrainingPlan` | `TrainingGoalRequest`, recent runs, weekly volume, preferred days, challenge context | Persisted plan/workouts, plan rationale or coach notes later | Cap weekly load deltas, reduce load for pain/dizziness/injury, fallback if invalid | Do not copy skill. Add a future skill contract doc and tests around request/response payloads. |
| Readiness check | New contract beside Coach/Run DTOs, plus existing `RecoverySnapshot` and `TodayRecommendation` | Today readiness card, Pre-run start gate, Coach "Should I run today?" | Future `ReadinessProviding` service or Coach backend intent | Profile, recent runs, recovery, wellness check-in, planned workout | `proceed/modify/skip`, modifications, `SafetyFlag[]`, confidence | Pain/dizziness/injury must become skip/stop/rest/professional guidance; missing data should modify | Best next DTO slice after docs because it is narrow and safety-heavy. |
| Workout explainer | Contract DTO and prompt intent, not a full Codex skill yet | Workout detail, Plan coach notes, Coach prompt "Explain today's workout" | Coach backend intent through `send(message:context:)`, later `WorkoutExplaining` service | `WorkoutSummary`, profile level, recent runs, recovery | Purpose, cues, mistakes, substitutions, flags | Easier substitution when intensity mismatches user level; stop on pain/dizziness | Keep as docs first; add DTO tests before UI wiring. |
| Conversational goal discovery | Onboarding/Coach contract | Onboarding goal wizard and early Coach session | Future onboarding view model or Coach backend intent | Conversation turns, partial onboarding, current profile | Goal classification, confidence, blockers, weekly commitment, starter plan id, summary card | Injury mentions should pause plan push and advise professional guidance | Do not copy source skill. Fold into onboarding spec before behavior change. |
| Load anomaly guard | Contract plus deterministic service tests | Plan, Today, notifications later | Future `TrainingLoadGuarding` service or backend job | Recent run history, plan window, injury flags | `SafetyFlag[]`, recommended adjustments | Flag 20-30 percent week-over-week spikes, no catch-up stacking, conservative under uncertainty | Add manual Swift DTO only when a backend endpoint exists. |
| Route builder | Route contract and route generation service boundary | Route Creator, pre-run route selector, Today route recommendation | `RouteProviding.nearbyLoopRoutes`, future backend route builder | Target distance/time, start area/location, surface/elevation preferences, constraints | Route spec/segments, map hints, safety flags | Missing location requires clarification; avoid unsafe surfaces, steep grades, heat/injury risk | Do not import as skill. Current route UI has native models and ranking. |
| Post-run debrief | Run report contract extension | Post-run summary, Report detail, Coach insertion | `generateRunReportIfMissing`, `processCompletedActivity` | `RecordedRun`, derived metrics, RPE, notes, upcoming workout | Reflection bullets, confidence score, next-step guidance, safety flags | Pain/abnormal HR/dizziness triggers rest/professional guidance | Current `RunReportDetail` is close; add `safetyFlags` and `confidenceScore` later. |
| Adherence coach | Plan adjustment contract | Weekly digest, Plan tab, Coach "get back on track" | Future plan adherence service | Current plan, completed/missed workouts, availability, reason notes | Reshuffle suggestions, focus, coach message, safety flags | Limit catch-up to one session/week; no stacking intensity; pain means rest | Docs first. Implement after readiness/load guard. |

## Shared Contract Comparison

### Existing iOS equivalents

| Source area | iOS equivalent | Notes |
| --- | --- | --- |
| `user.ts User` | `OnboardingProfile`, `RunnerProfile`, `TrainingGoalRequest`, `TrainingContextRunnerSummary` | iOS stores display strings and UUID/auth identity. Source uses numeric `userId` and richer preference fields. |
| `plan.ts Plan/Workout` | `TrainingPlanSnapshot`, `WorkoutSummary`, `RunSmartDTO.GeneratePlan*`, `TrainingPlanRepository` DB rows | iOS uses UUIDs and display labels; source uses numeric ids, `Date`, and richer periodization fields. |
| `run.ts Run/GPSPoint` | `RecordedRun`, `RunRoutePoint`, `RunSmartDTO.RunLogRequest`, `RunReportRequest.WebRun` | iOS uses meters/seconds and UUIDs. Source uses km-ish `distance`, seconds/minutes depending on endpoint, and serialized GPS strings. |
| `route.ts Route/RouteRecommendation/UserRoutePreferences` | `SavedRoute`, `RouteSuggestion`, `RouteRecommendation`, `RouteMatchResult` | iOS has geometry and benchmark-specific models. Source has safety/popularity/scenic/lighting preferences. |
| `recovery.ts RecoveryScore/SubjectiveWellness` | `RecoverySnapshot`, `WellnessSnapshot`, HealthKit/Garmin snapshots | iOS has display snapshots, not full raw wellness contract. |
| `device.ts WearableDevice/SyncJob` | `ConnectedDeviceStatus`, HealthKit/Garmin services, first sync review models | iOS names providers as strings and local enums; source has numeric device ids and token fields that should not be copied. |
| `coaching.ts ChatMessage/Coaching*` | `CoachMessage`, persisted `conversation_messages`, `RunSmartDTO.SendCoachMessage*` | iOS has live Supabase conversation storage and sanitized context. Source has richer feedback/effectiveness models. |
| `goal.ts Goal*` | `GoalSummary`, `TrainingGoalRequest`, Goal wizard | iOS is summary-first and not a direct SMART goal mirror. |
| `challenge.ts Challenge*` | `ChallengeSummary`, `TrainingChallengeContext`, `ChallengeRepository` | iOS already carries challenge context into plan generation. |
| `metrics.ts Performance*`, `Shoe`, `Badge` | `TrainingLoadSnapshot`, `ShoeSummary`, `Achievement`, benchmark models | iOS uses presentation summaries; source is persistence-heavy. |
| `api/types.ts` | `RunSmartDTO` nested DTOs | iOS has custom DTOs for live Coach, generate plan, run report, route points, device sync. |

### Gaps and mismatches

- IDs: source contracts often use numeric `userId`, `planId`, `runId`, and optional numeric `id`. iOS uses Supabase auth UUIDs, local UUIDs, and backend numeric identity only inside plan generation.
- Dates: source model files use TypeScript `Date`; API types often use strings. iOS uses `Date` internally and ISO8601 strings in DTOs. Any generated Swift must define date decoding deliberately.
- Naming: source workout types include `race-pace`, `time-trial`, and `fartlek`; iOS `WorkoutKind` uses `.race`, `.parkrun`, `.hills`, `.strength`, `.recovery`, and display raw values.
- Units: iOS domain uses meters/seconds for recorded runs and labels for UI. Source models mix km, duration, pace, and labels depending on file.
- Optionality: source persistence models require many fields that iOS does not own yet. Blind generation would create unusable required properties.
- Codable: source contracts include `any`, `Record<string, unknown>`, nested object literals, function-valued endpoints, and union literals. The existing generator cannot safely handle these.
- Safety flags: iOS live Coach response currently decodes `safetyFlags: [String]?`, while source skill contracts define structured `SafetyFlag { code, severity, message }`.
- Coordinates: iOS Coach context intentionally sends route summaries without points. The backend rejects coordinate-like keys. Any shared contract must preserve that privacy boundary.

### Generator assessment

`packages/shared/scripts/generate-swift-types.ts` is not safe to run into this repo as-is.

Reasons:
- It writes to `../../../apps/ios/App/App/Generated/SharedModels.swift`, which does not match this repository layout.
- It parses TypeScript interfaces with regex and will miss nested structures, unions, imported types, arrays of inline objects, and `Record` values.
- It maps all `number` values to `Double`, which is wrong for many ids, durations, counts, scores, and enum-like values.
- It does not emit `CodingKeys`, enum types, custom date strategies, access-control choices that match this app, or test fixtures.

Recommended future workflow:
1. Keep the TypeScript source repo as reference, not vendored code.
2. Manually mirror only endpoint DTOs that iOS actually calls.
3. Add fixture-based Codable tests for every mirrored DTO.
4. If generation becomes necessary, replace the regex generator with schema-driven generation that targets this app's actual output path and date/id rules.

## Best Representation Decisions

- AI skill source docs: keep as reference only for now.
- `.codex/skills/` in this repo: do not copy in this slice. If added later, create one iOS-native index skill that points to app contracts and guardrails, not the web app's `v0` paths.
- Swift service contracts: add only after a story selects a real caller and endpoint. `ReadinessChecking` is the best first candidate.
- API DTOs: manually mirror selected skill payloads near `RunSmartDTO`, starting with structured `SafetyFlagDTO` and readiness payloads.
- Tests: add fixture-based Codable tests before behavior wiring. Prioritize safety flags, readiness decisions, and run report safety payloads.

## Implementation Plan

## Story 1: AI Skill Inventory And iOS Mapping

**As a** RunSmart maintainer
**I want** a repo-local map of source AI skills to iOS screens, services, inputs, outputs, and guardrails
**So that** we can import only the useful coaching logic without pulling web-era operating files.

### Acceptance Criteria
- [x] Source AI skill areas are inspected.
- [x] Each skill is mapped to an iOS home, flow, caller, inputs, outputs, and safety guardrails.
- [x] The report states what is intentionally not imported.

### Test Plan
- Unit test: not applicable for docs.
- Integration test: confirm referenced iOS files exist.
- Manual check: verify no source Agent OS/task-board files were copied.

### Out of Scope
- Swift behavior changes.
- New backend endpoints.
- Copying source skill folders.

### Dependencies
- None.

## Story 2: Shared Contract Comparison

**As a** RunSmart iOS developer
**I want** source TypeScript models compared to current Swift models and DTOs
**So that** future API work avoids id/date/optionality/Codable regressions.

### Acceptance Criteria
- [x] Source `models/` and `api/` contracts are compared to iOS equivalents.
- [x] Naming, date, id, optionality, unit, and Codable risks are documented.
- [x] The existing generator is assessed for this repo.

### Test Plan
- Unit test: not applicable for docs.
- Integration test: confirm source and destination files exist.
- Manual check: verify no generated Swift was added.

### Out of Scope
- Bulk generated model import.
- Replacing existing iOS models.

### Dependencies
- Story 1 context.

## Story 3: Add/Adapt Selected Skill Docs Or Codex Skills

**As a** RunSmart maintainer
**I want** iOS-native skill contract docs
**So that** future Coach work keeps source guardrails without web path assumptions.

### Acceptance Criteria
- [x] Add an iOS-native `docs/ai-coach/skill-contracts.md` or equivalent.
- [x] Include structured `SafetyFlag` definitions and per-skill request/response sketches.
- [x] Reference iOS services/screens instead of web `v0` paths.

### Test Plan
- Unit test: not applicable.
- Integration test: markdown/path existence check.
- Manual check: no app behavior change.

### Out of Scope
- Adding `.codex/skills/` directories until the iOS contract doc settles.

### Dependencies
- Stories 1 and 2.

## Story 4: Add/Adapt Selected Shared DTOs Or Generation Workflow

**As a** RunSmart iOS developer
**I want** minimal DTOs for the first AI skill endpoint
**So that** payloads are type-safe without importing the full web model layer.

### Acceptance Criteria
- [x] Pick one first DTO slice, preferably readiness or structured safety flags.
- [x] Add Codable request/response DTOs near `RunSmartDTO`.
- [x] Add fixture-based tests for key decoding/encoding, date/id formats, and safety flags.
- [x] Leave existing domain models intact.

### Test Plan
- Unit test: focused Codable tests.
- Integration test: build-for-testing.
- Manual check: no UI behavior change unless separately approved.

### Out of Scope
- Full TypeScript-to-Swift generation.
- Renaming existing domain models.

### Dependencies
- Story 3.

## Story 5: Validation And QA

**As a** release owner
**I want** validation evidence for every import slice
**So that** TestFlight readiness is not weakened by AI contract work.

### Acceptance Criteria
- [x] Run the smallest useful verification for each slice.
- [x] For DTO/code slices, run focused tests or build-for-testing.
- [x] For docs-only slices, run path existence and targeted content checks.
- [x] Record what passed, what was not run, and the next story.

### Test Plan
- Unit test: depends on slice.
- Integration test: build-for-testing for Swift changes.
- Manual check: inspect docs for no source operating files or secrets.

### Out of Scope
- App Store Connect portal work.

### Dependencies
- Each implementation story.

## First Safe Slice Implemented

Implemented Story 1 and Story 2 as this investigation report only.

No Swift behavior changed. No source repo files were copied. No shared TypeScript contracts were vendored. No generated Swift was added.

## Story 3 Implementation

Story 3 is implemented in `docs/ai-coach/skill-contracts.md`. The contract doc defines structured `SafetyFlag`, readiness, workout explainer, post-run debrief, plan generation metadata, load anomaly guard, conversational goal discovery, route builder, and adherence payload sketches in terms of current iOS services and Supabase Edge Function boundaries.

## Story 4 Implementation

Story 4 is implemented in `RunSmartDTO` and `RunSmartReadinessTests`. The first code slice adds manual `SafetyFlagDTO`, readiness request/response DTOs, small readiness context DTOs, and focused Codable tests for proceed, modify-with-missing-data, skip-with-medical-caution, and request privacy.

No Pre-run UI behavior, backend endpoint, or current live Coach `safetyFlags: [String]?` behavior was changed.

## Story 5 Implementation

Story 5 is implemented in `docs/qa/ai-coach-story-5-validation-2026-05-19.md`. Validation was rerun from a clean worktree based on merged `origin/main` after PR #18 and PR #19. Documentation checks, source import guards, Swift parse validation, Xcode project listing, generic simulator build, and generic simulator build-for-testing passed.

Focused `RunSmartReadinessTests` XCTest execution built the app and test bundle, then stalled during simulator launch/test execution and was stopped. Treat the DTO slice as build-validated, but rerun focused XCTest from a healthy simulator before wiring readiness behavior.

## Recommended Next Story

Plan the readiness service/backend boundary. Do not wire Pre-run UI behavior until the endpoint/service boundary is approved and the focused readiness XCTest run completes on a healthy simulator.
