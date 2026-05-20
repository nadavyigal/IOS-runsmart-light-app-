# Sprint 9 Spec: Real Activity Today Data Flow UX

## Product Brief

### Idea
Make Today, Plan, Report, and post-run saving agree after a real run is completed or imported from Garmin/HealthKit.

### Runner Problem
A runner can finish today's run, see the run in Report, but still see a startable workout and route on Today. This makes RunSmart feel unaware of the most important thing the runner just did.

### Target User
Beta runners using RunSmart GPS, Garmin, HealthKit, or any combination of those sources on the same day.

### Daily Use Moment
After a morning run, the runner opens Today to check whether they are done, what changed, and what the next calm action should be.

### Desired Outcome
Today should first acknowledge the completed run, suppress start/route prompts for already-completed training, show the next future run as upcoming, and let suggested workout saves either succeed or explain exactly what needs review.

### Why iOS Native
This is a stateful, high-trust mobile moment: notifications, local run recording, Garmin sync, HealthKit sync, local cache, and Supabase plan updates all meet inside the native app.

### Non-Goals
- No redesign of the entire Today tab.
- No automatic insertion of every AI-suggested workout.
- No new social, route marketplace, or live in-run AI feature.
- No destructive cleanup of existing user runs.

### Success Signals
- Completed same-day runs make Today say the runner is done for now.
- Today does not show "Start Workout" for a completed same-day workout.
- Suggested-workout save succeeds when the payload is valid, or shows a specific review state instead of a vague failure.
- RunSmart and Garmin duplicates resolve to one user-visible activity and one stable report identity.

## Investigation Findings

1. Today falls forward to the next workout after completion.
   - `SupabaseRunSmartServices.todayRecommendation()` uses `activePlan?.uncompletedTodayWorkout ?? activePlan?.nextActionableWorkout`.
   - `TodayTabView.todayWorkout` uses `nextWorkouts.first(where: isToday) ?? nextWorkouts.first`.
   - Because `nextWorkouts` filters out completed workouts, the completed May 20 long run disappears and the May 25 easy run becomes the primary "Today's Workout" card.
   - Existing regression coverage (`testCompletedTodayWorkoutFallsThroughToNextActionableWorkout`) protects this behavior, but the UX outcome is wrong for Today.

2. Plan explanation prioritizes yesterday's miss over today's completed run.
   - `PlanExplanation.make()` checks `missedWorkout` before recent same-day run signals.
   - With May 19 incomplete and May 20 completed, the card still says "Missed workout" and offers "Reschedule" even though the current session should acknowledge today's run first.

3. Route recommendations render even when today's running is already complete.
   - `TodayRouteRecommendationCard` always renders from `routeRecommendation` and `todayWorkout`.
   - There is no "completed today" gate, so a future workout's route can appear as "Route for Today."

4. Workout completion only stores a boolean.
   - `TrainingPlanRepository.completeBestMatchingWorkout()` updates only `completed = true`.
   - Remote data confirms the May 20 workout is complete, but `completed_at`, `actual_distance_km`, `actual_duration_minutes`, and `actual_pace` are still null.
   - That prevents the UI from confidently saying which real activity completed the workout.

5. RunSmart plus Garmin duplicate identity is not fully stable across reports.
   - Remote data shows both a RunSmart GPS run and a Garmin run persisted for the same May 20 activity.
   - `ActivityConsolidationService` can merge them for user-visible activity lists, but the report cache can be generated before the Garmin duplicate arrives.
   - Result: one surface can show a Garmin activity while another still shows a RunSmart report for the same physical run.

6. Suggested workout saving sends schema-invalid plan data.
   - `saveSuggestedWorkout()` inserts `training_phase = "coach-recommendation"`, but the remote `workouts.training_phase` check only allows `base`, `build`, `peak`, and `taper`.
   - The no-active-plan fallback creates `plan_type = "recommendations"`, but the remote `plans.plan_type` check only allows `basic`, `advanced`, and `periodized`.
   - Some AI suggestions also have duration and target but no distance; those should become a reviewable workout draft, not a blind plan mutation.

7. Garmin post-run insight lookup is pointed at the wrong schema.
   - API/Postgres logs show repeated 400s for `ai_insights.activity_id`; the remote `ai_insights` table does not have that column.
   - iOS therefore cannot read stored Garmin post-run insight through the current path and falls back to local report generation/skeletons.

8. Remote route tables are missing.
   - API logs show 404s for `user_saved_routes` and `user_benchmark_routes`.
   - Route features degrade to local or Garmin-derived data, but the app still tries the missing remote tables.

## Summary
Create a completion-aware Today state and clean up the plan/report persistence contracts so real runs become the canonical source of truth across the app.

## Goals
- Treat same-day completed activity as the primary Today state.
- Separate "done today" from "next upcoming run."
- Persist workout completion actuals.
- Make suggested workout save payloads schema-valid and reviewable.
- Stabilize consolidated run/report identity when Garmin arrives after RunSmart GPS.
- Fix or safely degrade broken remote report and route lookups.

## Non-Goals
- Full training-plan regeneration.
- Manual database cleanup of existing user activity duplicates.
- New visual design system work.
- New Garmin webhook backend behavior beyond what the iOS app needs to consume correctly.

## User Stories

### Story 1: Today Completion State
**As a** runner who completed today's run
**I want** Today to acknowledge the completed run first
**So that** I do not feel pushed to run again by mistake.

Acceptance criteria:
- [ ] Same-day visible run changes the primary Today card into a completed/settled state.
- [ ] If the matching planned workout is complete, Today does not show a start button for that workout.
- [ ] The next future workout appears only in "Next runs" or a secondary "Up next" slot.
- [ ] Route for Today is hidden or converted to "Route from today" after completion.

Test plan:
- Unit test completion-state resolver with completed same-day workout plus future workout.
- Unit test same-day Garmin import without completed workout.
- Manual check with RunSmart-only, Garmin-only, and duplicate RunSmart+Garmin activity.

### Story 2: Plan Explanation Priority
**As a** runner with both a missed workout and a completed run today
**I want** Coach to acknowledge today's completed run before yesterday's miss
**So that** the app feels fair and current.

Acceptance criteria:
- [ ] Same-day completed/imported run outranks missed-workout copy.
- [ ] Missed workout still appears when there is no same-day completed activity.
- [ ] Copy remains calm and non-shaming.

Test plan:
- Unit test `PlanExplanation.make()` with missed May 19 and completed/imported May 20.
- Unit test existing missed-workout behavior remains unchanged without same-day run.

### Story 3: Workout Completion Actuals
**As a** runner reviewing my plan
**I want** completed workouts to store the actual run that completed them
**So that** Plan and Today can explain what really happened.

Acceptance criteria:
- [ ] Completing a matched workout writes `completed`, `completed_at`, `actual_distance_km`, `actual_duration_minutes`, and `actual_pace`.
- [ ] The update remains compatible with existing completed rows.
- [ ] Push reminder cancellation still occurs.

Test plan:
- Unit/contract test for completion update payload.
- Static schema check against current Supabase columns.
- Manual run/import smoke check verifies actuals in Supabase.

### Story 4: Suggested Workout Save Contract
**As a** runner reviewing a post-run suggestion
**I want** saving to either work or ask me to review missing details
**So that** I trust the plan update.

Acceptance criteria:
- [ ] Insert payload uses only valid `training_phase` and `plan_type` values.
- [ ] Duration-only suggestions become reviewable drafts or valid duration workouts without invalid distance assumptions.
- [ ] Failure copy distinguishes schema/network/auth from "needs review."
- [ ] A successful save posts `runSmartPlanDidChange`.

Test plan:
- Unit test "Moderate Run, 25-40 min" mapping.
- Unit test no-active-plan fallback uses valid plan type.
- Remote smoke insert with a safe test user or local Supabase contract if available.

### Story 5: Consolidated Report Identity
**As a** runner who records in RunSmart and Garmin
**I want** one activity and one report identity
**So that** Report, Today, and Recent Run Reports do not disagree.

Acceptance criteria:
- [ ] Consolidated activity ID remains stable when Garmin arrives after RunSmart GPS.
- [ ] Existing RunSmart report cache is discoverable after Garmin duplicate appears.
- [ ] The richer canonical source can display as Garmin without losing the already-generated report.

Test plan:
- Unit test RunSmart-first report lookup after Garmin duplicate arrives.
- Unit test Garmin-first then RunSmart duplicate.
- Manual check with same-day duplicate pair.

### Story 6: Broken Remote Lookup Cleanup
**As a** beta user
**I want** reports and routes to degrade quietly when backend tables differ
**So that** the app does not waste requests or show stale/confusing states.

Acceptance criteria:
- [ ] `ai_insights` query matches the deployed schema or is disabled behind a safe fallback.
- [ ] Missing route tables no longer spam 404s during normal Today/Report loads.
- [ ] Any unavailable remote route state still leaves local/saved routes visible.

Test plan:
- Supabase schema inspection test/documented check.
- API log check after smoke run shows no repeated `ai_insights.activity_id` 400s or route table 404s from the fixed path.

## UX Requirements
- Today headline after completion should be explicit: "Run complete today" or equivalent.
- The primary action after completion should be review/report/coach, not start.
- Future workouts should use "Up next" language, not "Today's Workout."
- Route recommendations should not invite route choice for a completed same-day run.
- Error copy should identify whether the run is saved, the report is saved, and only the plan mutation failed.

## Data and State
- Add a small resolver model for Today state rather than deriving state independently in multiple view properties.
- Inputs: `todayRecommendation`, `weekWorkouts`, `nextWorkouts`, `recentRuns`, `activePlan`, `runReports`, `routeRecommendation`.
- Outputs: primary state (`plannedToday`, `completedToday`, `upNext`, `restDay`, `noPlan`), primary workout, completed run, up-next workout, route visibility.
- Persist completion actuals on matched workout rows.
- Keep local run/report cache keys compatible with consolidated IDs.

## Permissions
- No new permissions.
- Existing Garmin, HealthKit, Location, and Supabase auth flows must keep working.

## Error, Empty, and Loading States
- If completion update succeeds but report generation fails, Today should still show run complete.
- If Garmin arrives later, refresh Today/Plan/Report once and avoid duplicate user-visible activities.
- If suggested workout lacks required plan fields, show review-needed copy instead of retry-only failure.

## Accessibility
- Completed-state labels must not rely only on color.
- Buttons should have clear labels: "Review Report", "Ask Coach", "View Next Run."

## Analytics or Observability
- Track Today completed-state viewed.
- Track suggested-workout save result with reason category, not raw error text.
- Track duplicate consolidation when Garmin and RunSmart merge.

## Acceptance Criteria
- [ ] Today no longer shows a startable workout or route for today after a same-day completed run.
- [ ] Plan explanation acknowledges today's run before missed-workout nudges.
- [ ] Matched workout completion stores actual run metrics.
- [ ] Suggested workout save works for schema-valid suggestions and handles review-needed suggestions gracefully.
- [ ] RunSmart/Garmin duplicate appears as one activity and one stable report across Today and Report.
- [ ] Remote logs no longer show repeated broken `ai_insights.activity_id` reads or missing route-table reads from the fixed path.

## QA Plan
- Xcode build-for-testing for focused regression tests.
- Xcode simulator build.
- Manual signed-in smoke:
  - Complete RunSmart GPS run.
  - Import matching Garmin run.
  - Open Today, Plan, Report, Profile.
  - Save suggested next run.
  - Reopen app and verify state persists.

## TestFlight Notes
- This is a beta trust fix. Do not call the app TestFlight-ready until same-day completion state is verified on a physical iPhone with Garmin connected.
