# RunSmart Sync and Adapt Strategy

Date: 2026-06-21
Status: planning, no implementation yet

## Strategy

RunSmart should become the adaptive coaching layer for three runner modes:

- Apple Watch runner: RunSmart works with Apple Health, WorkoutKit, and Apple Watch workout execution.
- Garmin runner: RunSmart works with Garmin Connect, Garmin activity history, wellness signals, and Garmin workout publishing where approved.
- No-wearable runner: RunSmart gives a similar coaching experience through phone GPS, manual/treadmill logging, simple check-ins, and clear plan adaptation.

The product should focus on the loop runners already understand:

Plan -> run through the best available path -> import or log completed activity -> analyze -> adapt next workout -> explain.

The strongest near-term bet is not asking users to use both Apple Watch and Garmin. Most runners choose one ecosystem, and Apple/Garmin both have structural advantages because they own the wearable, the native app, and the data layer. RunSmart's job is to add the coaching layer they do not consistently provide:

- Safer beginner progression.
- Clear "why" behind each workout and adjustment.
- Plan-vs-actual interpretation in plain language.
- Life-aware adaptation when the runner is tired, traveling, missed a session, or overdid a run.
- A no-wearable experience that still feels coached, not second-class.

Workout publishing still matters, but it should be framed as provider choice:

- If the runner uses Apple Watch, publish through WorkoutKit and import through HealthKit.
- If the runner uses Garmin, publish through Garmin Training API and import through Garmin Activity API.
- If the runner has no wearable, show the same workout steps in RunSmart, record phone GPS when possible, support treadmill/manual logs, and use check-ins plus completed-run history for adaptation.

## Positioning Implication

Runna, TrainingPeaks, Garmin Coach, Apple Workout Buddy, Strava Athlete Intelligence, and Garmin Connect+ all point in the same direction: workouts, activity history, recovery signals, and AI summaries are becoming table stakes.

RunSmart should not compete by pretending to out-platform Apple or Garmin inside their own ecosystems. It should compete as the safety-first coaching layer:

- "Here is today's workout."
- "Use it on your watch, with phone GPS, or manually."
- "Here is what actually happened."
- "Here is what changed next."
- "Here is why that protects progress."

## Differentiation By Runner Mode

### Apple Watch Runner

Apple advantage:

- Apple owns the watch, Workout app, Health app, Activity rings, HealthKit, WorkoutKit, Workout Buddy, Siri, widgets, and Live Activities.

What RunSmart adds:

- A beginner-safe plan that changes when the runner misses, struggles, or overdoes a session.
- Coach explanations that connect HealthKit data, recent runs, and the next workout.
- A clearer "what should I do today?" decision than browsing Fitness/Health data.
- Plan-vs-actual review after the workout, not just a completed workout record.

### Garmin Runner

Garmin advantage:

- Garmin owns the watch, Garmin Connect, Garmin Coach, Body Battery, training readiness, activity history, routes, and device sync.

What RunSmart adds:

- Cross-session adaptation that explains how Garmin data changes the next RunSmart workout.
- A softer, safety-first coaching layer for runners who do not want a performance-maximizing plan every week.
- Plain-language interpretation of readiness, HRV, and completed runs.
- A product focused on "protect consistency" rather than "optimize every metric."

### No-wearable Runner

Platform gap:

- No watch means no automatic recovery metrics, no watch-based structured workout, and often less confidence that the plan is calibrated.

What RunSmart adds:

- The same Today, Plan, Run, Report, and Coach loop without requiring a device.
- Phone GPS recording for outdoor runs.
- Manual/treadmill logging for indoor or watchless sessions.
- Simple readiness check-ins that stand in for wearable recovery data.
- Beginner protection rules based on completion history, missed sessions, soreness, energy, and progression limits.

This path is strategically important. If RunSmart only feels valuable with Apple Watch or Garmin, it enters a fight where the platform owners have the advantage. If RunSmart makes no-wearable runners feel similarly coached, it owns a wider beginner wedge.

## Ranked Feature Recommendations

### 1. No-wearable Coaching Loop

- User promise: You can get coached even without a watch.
- Why it matters: This is where RunSmart can differentiate instead of fighting Apple/Garmin on their strongest terrain.
- Apple dependency: none for MVP; optional HealthKit later if the user has Apple Health data.
- Garmin dependency: none.
- Backend dependency: existing runs, manual logs, check-ins, plan mutation, debrief/report tables.
- Implementation complexity: Medium.
- Commercial value: High.
- Suggested MVP version: Today workout, phone GPS start, manual/treadmill log, post-run review, simple readiness check-in, beginner protection adjustment.
- Risks / unknowns: Must feel first-class, not like a fallback for users without expensive hardware.

### 2. Unified Activity Import

- User promise: Whether you use Apple Watch, Garmin, phone GPS, or manual logging, your runs count once.
- Why it matters: Adaptation is only credible if the activity history is complete and deduplicated for the runner's chosen mode.
- Apple dependency: HealthKit workout, route, heart rate, wellness permissions.
- Garmin dependency: Activity API and current Supabase Garmin ingestion.
- Backend dependency: Existing `runs`, `garmin_activities`, route points, debrief/report tables.
- Implementation complexity: Medium.
- Commercial value: High.
- Suggested MVP version: Import source badges, duplicate safety, canonical completed activity pipeline, freshness/error states.
- Risks / unknowns: Garmin API approval, sparse route/HR data, and duplicate records when users record on phone plus watch.

### 3. Plan vs Actual Analyzer

- User promise: RunSmart tells you whether the workout matched the plan.
- Why it matters: It is the missing reasoning layer between import and adaptation.
- Apple dependency: Completed workout details from HealthKit.
- Garmin dependency: Completed activity summaries and ideally FIT/lap/zone data later.
- Backend dependency: `workouts`, `runs`, reports, plan matching.
- Implementation complexity: Medium.
- Commercial value: High.
- Suggested MVP version: distance, duration, pace, completion, effort, route availability, manual confidence, and simple result classification.
- Risks / unknowns: Current `WorkoutSummary` is presentation-oriented and needs a canonical planned-workout model.

### 4. Post-run Adaptive Review

- User promise: After every run, you get a useful "what this means for the next session."
- Why it matters: This is the retention moment after effort.
- Apple dependency: HealthKit import and phone GPS save where available.
- Garmin dependency: Activity API import where connected.
- Backend dependency: Existing run debrief/report path.
- Implementation complexity: Medium.
- Commercial value: High.
- Suggested MVP version: show plan-vs-actual, coach explanation, and next-workout impact.
- Risks / unknowns: Avoid overconfident medical or injury language.

### 5. Provider-choice Workout Publisher

- User promise: Today's RunSmart workout appears where you actually run: Apple Watch, Garmin, or RunSmart itself.
- Why it matters: Watch sync turns RunSmart from advice into execution.
- Apple dependency: WorkoutKit authorization, scheduled workouts.
- Garmin dependency: Garmin Training API approval.
- Backend dependency: publish status table/fields, provider payload records, retry/error tracking.
- Implementation complexity: High.
- Commercial value: High.
- Suggested MVP version: in-app/manual execution first-class, Apple WorkoutKit first for watch publishing, Garmin Training API once approved.
- Risks / unknowns: Workout target mapping, schedule update semantics, Garmin approval.

### 6. "Make This Week Easier" / Beginner Protection Mode

- User promise: One tap makes the plan safer this week.
- Why it matters: This is more differentiated than generic AI Q&A and more defensible than watch sync alone.
- Apple dependency: none beyond existing app surface.
- Garmin dependency: none for MVP.
- Backend dependency: Flex Week and plan mutation.
- Implementation complexity: Medium.
- Commercial value: High.
- Suggested MVP version: App UI action first, App Intent later.
- Risks / unknowns: Must preserve progressive overload without feeling punitive.

### 7. Recovery-aware Adjustment

- User promise: RunSmart protects you when recovery signals say to back off, whether those signals come from a wearable or a check-in.
- Why it matters: This is core to RunSmart's safety-first wedge.
- Apple dependency: sleep, HRV, resting HR when available.
- Garmin dependency: Body Battery, sleep, stress, HRV, training readiness when available.
- Backend dependency: wellness check-ins, existing readiness logic.
- Implementation complexity: Medium.
- Commercial value: High.
- Suggested MVP version: freshness-gated recovery context plus manual check-in, no complex black-box score.
- Risks / unknowns: Garmin Health API commercial terms, HealthKit sparsity, and manual check-in compliance.

### 8. Zone Intelligence Layer

- User promise: RunSmart explains easy, steady, and hard effort using zones instead of vague pace alone.
- Why it matters: Beginner protection and Striver trust both improve when effort is concrete.
- Apple dependency: HealthKit heart rate now, HealthKit workout zones in iOS/watchOS 27 later.
- Garmin dependency: Health/Activity/FIT data for HR and zones.
- Backend dependency: zone summary storage and effort classifier.
- Implementation complexity: Medium.
- Commercial value: Medium-High.
- Suggested MVP version: derive zones from average HR and known thresholds, then upgrade to source-native zones.
- Risks / unknowns: Zone availability varies by OS, watch, permissions, and provider.

### 9. Pre-run Brief

- User promise: Before you run, you know the goal, target effort, and why it is safe today.
- Why it matters: Bridges plan and execution.
- Apple dependency: WorkoutKit publish state and HealthKit recovery when available.
- Garmin dependency: Training API publish state and wellness metrics when available.
- Backend dependency: training context snapshot.
- Implementation complexity: Low-Medium.
- Commercial value: Medium.
- Suggested MVP version: card on Today and PreRun surfaces, with no-wearable version based on plan goal, recent completion, and check-in.
- Risks / unknowns: Avoid duplicating existing workout card copy.

### 10. App Intents for Core Actions

- User promise: RunSmart works from Siri, Shortcuts, Spotlight, and Action Button.
- Why it matters: Apple-native polish and acquisition through system surfaces.
- Apple dependency: App Intents.
- Garmin dependency: none.
- Backend dependency: existing service methods.
- Implementation complexity: Medium.
- Commercial value: Medium.
- Suggested MVP version: Start Today's Run, Explain Today's Workout, Move Workout Tomorrow, Sync Devices.
- Risks / unknowns: Must not bypass auth, onboarding, or safety confirmation rules.

### 11. Live Activity for Active Run

- User promise: Phone-recorded runs stay visible on Lock Screen and Dynamic Island.
- Why it matters: Makes the no-wearable and phone GPS path feel more native.
- Apple dependency: ActivityKit and Widget extension.
- Garmin dependency: none.
- Backend dependency: none for local live run.
- Implementation complexity: Medium.
- Commercial value: Medium.
- Suggested MVP version: elapsed time, distance, pace, GPS status.
- Risks / unknowns: Sensitive data display and battery behavior.

### 12. AI Training Q&A

- User promise: Ask RunSmart about your own training history.
- Why it matters: Strava's June 2026 MCP launch validates conversational data analysis.
- Apple dependency: Foundation Models later, App Intents later.
- Garmin dependency: imported training history.
- Backend dependency: training context, retrieval, permissions, guardrails.
- Implementation complexity: Medium-High.
- Commercial value: Medium-High.
- Suggested MVP version: scoped questions in Coach using existing `TrainingContextSnapshot`.
- Risks / unknowns: Cost, hallucination, and safety claims.

### 13. Route/course Suggestions

- User promise: RunSmart recommends where to run based on workout distance and past routes.
- Why it matters: Useful, but secondary to workout sync and adaptation.
- Apple dependency: Core Location and existing route recording.
- Garmin dependency: route points from activities.
- Backend dependency: saved routes and route matching.
- Implementation complexity: Medium.
- Commercial value: Medium.
- Suggested MVP version: improve existing route recommendation and saved-route fit.
- Risks / unknowns: Requires enough route history.

### 14. Garmin Courses API Export

- User promise: Send a route/course to Garmin.
- Why it matters: Strong Striver feature after route library is trusted.
- Apple dependency: none.
- Garmin dependency: Courses API approval.
- Backend dependency: course payload records.
- Implementation complexity: High.
- Commercial value: Medium.
- Suggested MVP version: export saved routes only.
- Risks / unknowns: Course compatibility, route quality, approval.

### 15. Connect IQ Watch App or Data Field

- User promise: A custom RunSmart Garmin watch experience.
- Why it matters: Only matters if standard Training API execution cannot express RunSmart guidance.
- Apple dependency: none.
- Garmin dependency: Connect IQ SDK, store review, device QA.
- Backend dependency: auth and mobile/device communication.
- Implementation complexity: High.
- Commercial value: Low-Medium near term.
- Suggested MVP version: not in MVP.
- Risks / unknowns: Device fragmentation and high maintenance.

## Phased Roadmap

### Phase 0: Repo Readiness

Goals:

- Make RunSmart's internal workout and activity models export/import safe.
- Avoid adding provider-specific code on top of UI models.
- Treat no-wearable as a primary mode, not a fallback after Apple/Garmin fail.

User-facing outcome:

- No major new user-facing feature yet, but existing import, reports, and plan screens become safer to extend.

Engineering tasks:

- Add canonical model definitions for `RunSmartPlan`, `PlannedWorkout`, `WorkoutStep`, `WorkoutTarget`, `CompletedActivity`, `PlanVsActualResult`, `CoachAdjustment`, and `WorkoutPublishStatus`.
- Add mapping from existing `DBWorkout` and `WorkoutSummary` into canonical planned workouts.
- Add mapping from `RecordedRun` into canonical completed activities.
- Add provider publish-status persistence.
- Document HealthKit/Garmin permissions and stale/fallback behavior.
- Define mode-specific UX contracts for Apple, Garmin, and no-wearable users.

Risks:

- Scope creep into UI redesign.
- Existing presentation structs get reused as export contracts.

Acceptance criteria:

- One planned workout can be represented without Apple or Garmin fields.
- One completed activity can be represented without provider-specific assumptions.
- Existing `processCompletedActivity` remains the single post-run pipeline.

### Phase 1: Sync & Adapt MVP

Goals:

- Deliver the minimum Plan -> run/log/import -> analyze -> adjust next session loop for no-wearable and one connected provider.

User-facing outcome:

- A runner can see today's planned workout, complete it through phone GPS/manual logging or one connected provider, and get a clear adaptive review.

Engineering tasks:

- Make manual/no-wearable execution first-class in Today, PreRun, and PostRun.
- Implement `PlanVsActualAnalyzer`.
- Extend post-run summary/report to show what changed next.
- Preserve HealthKit and Garmin import dedupe.
- Add Apple WorkoutKit publishing only after the internal manual loop is stable.

Risks:

- No-wearable path can feel inferior if copy and UX are not deliberate.
- Garmin Training API access may not be ready.

Acceptance criteria:

- Manual, phone GPS, or imported completed run produces plan-vs-actual result.
- Next workout adjustment is shown with a reason, or explicitly says no change was needed.
- Apple Watch publishing is ready to layer on without changing the analysis contract.

### Phase 2: Native iOS Experience

Goals:

- Make RunSmart feel first-party on iPhone and Apple Watch without building a watch app.

User-facing outcome:

- Start/explain/sync actions work from Siri, Shortcuts, Spotlight, and widgets; phone-recorded runs get Live Activity support.

Engineering tasks:

- Add App Intents for core safe actions.
- Add widget for today's workout/readiness.
- Add Live Activity for phone GPS runs.
- Improve HealthKit route/write behavior.
- Prepare for HealthKit zone APIs once OS availability supports it.

Risks:

- App Intents can bypass safety or auth if not carefully routed.
- Live Activities can leak sensitive workout data if copy is too detailed.

Acceptance criteria:

- App Intents call existing service boundaries and respect auth/onboarding state.
- Widget and Live Activity show only appropriate glanceable data.
- No HealthKit App Review disclosure regression.

### Phase 3: Garmin Depth

Goals:

- Make Garmin a credible execution and recovery source, not just an import badge.

User-facing outcome:

- Garmin users can publish workouts to their Garmin calendar/watch, import completed runs, and see recovery-aware adaptation.

Engineering tasks:

- Complete Garmin Training API approval and server integration.
- Add Garmin publish status, payload mapper, and retry handling.
- Improve Activity API ingestion for route, HR series, laps/splits, and FIT where useful.
- Add Garmin Health API readiness metrics only after approval/licensing clarity.
- Add Courses API export only for saved routes with sufficient quality.

Risks:

- Garmin approval, commercial terms, and data freshness.
- More provider data can increase privacy and support burden.

Acceptance criteria:

- Garmin published workouts appear in Garmin Connect calendar for a test user.
- Completed Garmin run returns through the same post-run analysis pipeline.
- Stale/missing wellness data never silently adjusts a plan.

### Phase 4: AI Coach Layer

Goals:

- Turn synced workouts and completed activities into a differentiated adaptive coach.

User-facing outcome:

- RunSmart can answer "why did you change this?" and "what should I do this week?" with grounded, safety-aware explanations.

Engineering tasks:

- Expand `TrainingContextSnapshot` for plan-vs-actual, publish state, recovery freshness, zones, and recent adjustments.
- Add coach adjustment audit trail.
- Add beginner protection rules and guardrails.
- Evaluate Foundation Models for local summaries and plan rationale on supported devices.
- Add eval tests for coaching safety and consistency.

Risks:

- Overconfident coaching, medical claims, and vague AI summaries.
- Cost if every post-run action becomes an expensive cloud call.

Acceptance criteria:

- Every adjustment has evidence, user-facing reason, and rollback/review path.
- AI explanations are bounded by deterministic safety rules.
- Unsupported Apple Intelligence devices keep cloud/fallback behavior.

## Not Now

### Custom Garmin Connect IQ app

Defer. Garmin Training API already publishes structured workouts to compatible devices, Activity API imports completed runs, and Courses API handles courses. Connect IQ adds a separate SDK, Monkey C, store review, and device fragmentation before RunSmart has proven the official Garmin loop.

### Custom Apple Watch app

Defer. WorkoutKit gives RunSmart a native Apple Watch execution path inside the system Workout app. A custom watch app becomes useful only when RunSmart needs live custom guidance beyond WorkoutKit and HealthKit.

### Real-time AI voice coach

Defer as a core bet. Voice cues already exist in the repo, but real-time AI voice during runs competes with Apple Workout Buddy and adds safety, latency, audio, and cost concerns. Use structured workout prompts and post-run explanations first.

### Advanced route generation

Defer. Route suggestions exist, but watch workout publishing and post-run adaptation are more important. Route/course generation should wait until saved routes and route-quality checks are reliable.

### Full TrainingPeaks-like analytics

Defer. RunSmart's wedge is safe adaptation, not pro analytics breadth. Build plan-vs-actual and zones before charts, power curves, chronic load, and coach dashboards.

### Medical or injury diagnosis

Do not build. RunSmart can use conservative training guardrails and advise rest, but should not diagnose injury, predict medical conditions, or imply clinical authority.

### Overly complex readiness score

Defer. Use transparent freshness-gated recovery context from Garmin, HealthKit, and manual check-ins. Avoid a black-box score until data reliability and user trust are strong.
