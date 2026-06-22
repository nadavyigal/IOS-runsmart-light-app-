# Apple and Garmin Developer Trends for RunSmart iOS

Date: 2026-06-21
Scope: research, repo analysis, product strategy, and technical planning. No code implementation.

## Executive Finding

The product hypothesis is partly validated and needs a sharper framing.

RunSmart should not start with a custom Garmin Connect IQ watch app. The stronger near-term opportunity is to make RunSmart the adaptive coaching layer that creates provider-neutral workouts, supports the runner's chosen execution mode, imports or logs completed activity, analyzes plan versus actual, adapts the next workout, and explains the change clearly.

Important correction: users usually do not use both Garmin and Apple Watch. They usually choose one wearable ecosystem, or they have no wearable. Apple and Garmin also have clear native advantages because they own the wearable, native app, device sync, and first-party data layer. RunSmart's differentiation is not "we support both at once." It is "we give you the same safety-first coaching loop whether you run with Apple Watch, Garmin, phone GPS, or manual logging."

The highest-leverage loop is:

Plan -> run through the best available path -> import or log completed activity -> analyze -> adapt next session -> explain.

## Repo-Read Summary

Current repo state:

- Native SwiftUI iOS app, live on the App Store since 2026-06-19 as v1.0.3 build 16 according to `tasks/progress.md`.
- Current local branch is `main`; existing unrelated task-file changes are present and were not touched.
- No Apple Watch target, Widget extension, App Intents target, ActivityKit/Live Activity implementation, or WorkoutKit implementation is visible in the source scan.
- Core app tabs are Today, Plan, Run, Report, and Profile in `RunSmartTab`.
- HealthKit capability is enabled in `RunSmart.entitlements`.
- `RunSmartInfo.plist` includes HealthKit read/write copy, location copy, background location mode, `runsmart://` URL scheme, Supabase config keys, PostHog keys, and Garmin gateway URL.
- Privacy manifest declares linked Health, Fitness, Precise Location, Email, User ID, plus unlinked Product Interaction and Crash Data.

Existing app architecture:

- `RunSmartServiceProviding` composes service protocols for Today, Plan, Coach, Profile, Run logging, route, device sync, Health sync, and training context.
- `SupabaseRunSmartServices` is the production service boundary. It handles device connection, HealthKit import, Garmin import, completed-activity processing, recovery, wellness, plan completion, reports, and AI debriefs.
- `RunSmartLocalStore` caches runs, reports, device statuses, first-sync reviews, HealthKit daily snapshots, saved routes, and benchmark routes.
- `TrainingPlanRepository` owns active plan lookup, generated plan persistence, workout mutation, suggested workout persistence, and best-match completion.

Existing Apple integration:

- `HealthKitSyncService` can request HealthKit access, read running workouts, workout routes, average heart rate, steps, resting heart rate, HRV, sleep, and active energy.
- HealthKit imported workouts map into `RecordedRun` with stable provider IDs.
- Phone GPS recording exists through `RunRecorder`, using Core Location background updates while a run is in progress.
- RunSmart can save completed phone GPS runs back to HealthKit as `HKWorkout`, but current save path does not write route series or detailed heart-rate samples.

Existing Garmin integration:

- `GarminBridge` uses `ASWebAuthenticationSession`, `runsmart://garmin/callback`, gateway callback POST, and connection polling until `garmin_connections.status == connected`.
- Garmin activities are read from Supabase `garmin_activities_deduped` with fallback to `garmin_activities`.
- Garmin route points are read from owner-scoped `garmin_activity_points`.
- Garmin daily metrics are read from `garmin_daily_metrics_deduped`.
- Garmin readiness and wellness currently use Body Battery, HRV, sleep duration, stress, and training readiness when present.

Current plan, workout, and activity models:

- `WorkoutSummary` is the main planned workout presentation model. It has scheduled date, plan ID, kind, title, distance, detail, completion state, duration, target pace, intensity, training phase, workout structure JSON, and adjustment metadata.
- `StructuredWorkoutFactory` turns `WorkoutSummary.workoutStructure` or inferred workout type into display steps. These steps are UI-oriented and not yet an export-safe model.
- `RecordedRun` is the completed activity model. It stores provider activity ID, consolidated activity ID, source, start/end, distance, moving time, average pace, average HR, route points, route match, and sync timestamp.
- `PostActivityOutcome` already captures the bridge between completed activity and plan/report behavior: canonical run, report, completed matching workout, planned-workout completion flag, and AI debrief.

Existing AI coaching logic:

- `SupabaseRunSmartServices` calls AI-backed endpoints for coach messages, run reports, run debriefs, weekly summaries, and Flex Week adaptation, with deterministic fallbacks.
- `processCompletedActivity` already runs the important post-run loop: canonicalize, upsert, generate report, complete matching workout, fetch debrief, emit analytics, and notify plan/report/run surfaces.
- Flex Week exists as a user-triggered adaptive plan mechanism.

Current screens related to the requested loop:

- Today: readiness, workout card, weekly progress, latest run/report entry points.
- Plan: weekly plan, workout mutation, Flex Week, explanation surfaces.
- Run: pre-run, live phone GPS run, post-run summary.
- Report/Activity: recent runs, reports, progress, zone analysis placeholder, Garmin activity report details.
- Profile/Secondary: connected services, HealthKit details, Garmin wellness, recovery dashboard, route creation/saving.

Main repo constraint:

RunSmart has import and analysis foundations, but not provider-neutral planned-workout, execution-mode, or publish-status models. The next architecture move should add internal contracts before adding Apple WorkoutKit or Garmin Training API payload mapping.

## Differentiation Reframe

Apple and Garmin can beat RunSmart on native device execution. RunSmart must win on coaching interpretation and safety:

- Apple Watch mode: use WorkoutKit and HealthKit when available, but differentiate through adaptive explanations, plan-vs-actual review, and beginner-safe changes.
- Garmin mode: use Garmin activity/wellness/training APIs when approved, but differentiate through plain-language interpretation, safety-first adjustments, and a softer alternative to performance-heavy plans.
- No-wearable mode: provide the same Today -> Run/Log -> Review -> Adjust loop through phone GPS, manual/treadmill logging, and check-ins.

This changes priority. Manual/no-wearable execution is not a fallback after watch sync. It is a core wedge for beginners and returning runners.

## Apple Developer Trends

### HealthKit

Apple describes HealthKit as the central repository for health and fitness data across iPhone, iPad, Apple Watch, and Apple Vision Pro, with user permission required for read/write access. Source: [Apple Health and fitness apps](https://developer.apple.com/health-fitness/), [HealthKit documentation](https://developer.apple.com/documentation/healthkit).

RunSmart relevance:

- Current HealthKit import already reads running workouts, routes, average heart rate, HRV, sleep, steps, and active energy.
- HealthKit remains the best Apple-side source for completed workouts and wellness context.
- The app should keep HealthKit permissions tightly tied to clear product value because Apple calls out privacy, purpose strings, and avoiding nonessential data collection in health apps. Source: [Apple Health and fitness apps](https://developer.apple.com/health-fitness/).

### WorkoutKit

Apple says WorkoutKit can create and preview interval workouts, including single-goal, pace-based, triathlete, and custom interval workouts. It can also create and maintain a workout schedule and, with permission, sync scheduled compositions to Apple Watch. These appear in the Workout app on Apple Watch and the Fitness app on iPhone with the app icon and name. Source: [Apple Health and fitness apps](https://developer.apple.com/health-fitness/), [WorkoutKit](https://developer.apple.com/documentation/workoutkit/), [Customizing workouts with WorkoutKit](https://developer.apple.com/documentation/WorkoutKit/customizing-workouts-with-workoutkit).

RunSmart relevance:

- This is the Apple-native path for "Plan -> Sync to Apple Watch."
- It lets RunSmart avoid building a custom Apple Watch app for the MVP.
- RunSmart needs a provider-neutral `PlannedWorkout` and `WorkoutStep` model before mapping to WorkoutKit custom workouts.
- WorkoutKit should not become the only MVP execution path because no-wearable runners need the same workout guidance inside RunSmart.

### Scheduled workouts on Apple Watch

WorkoutKit scheduled workouts appear in a dedicated space in the Workout app on Apple Watch and in Fitness on iPhone. Source: [Apple Health and fitness apps](https://developer.apple.com/health-fitness/), [ScheduledWorkoutPlan](https://developer.apple.com/documentation/workoutkit/scheduledworkoutplan), [WorkoutScheduler](https://developer.apple.com/documentation/workoutkit/workoutscheduler).

RunSmart relevance:

- The minimum Apple publisher should send today plus the next 6 to 14 days.
- RunSmart should track per-workout publish status, provider IDs, revision numbers, and stale/update states.

### Workout zones and heart-rate zones

Apple's WWDC26 HealthKit workout zones session says iOS 27 and watchOS 27 add HealthKit workout zones for heart rate and cycling power. Completed workouts expose zone data through `zoneGroupsByType`, and live workouts can receive zone changes through `HKLiveWorkoutDelegate`. Source: [Deliver workout insights with HealthKit workout zones](https://developer.apple.com/videos/play/wwdc2026/207/), [Accessing workout zone data](https://developer.apple.com/documentation/healthkit/accessing-workout-zone-data/).

RunSmart relevance:

- This is important but should be phased after OS availability and compatibility checks.
- Current RunSmart zone analysis appears static or derived, not source-backed by HealthKit zone APIs.
- Future RunSmart should store a neutral `HeartRateZoneSummary` so Apple HealthKit zones, Garmin zones, and internally computed zones can coexist.

### App Intents, Siri, Shortcuts, Spotlight, widgets, Action Button

Apple says App Intents make app actions and content available in Siri, Shortcuts, Spotlight, widgets, controls, and Action Button surfaces. Source: [App Intents](https://developer.apple.com/documentation/appintents), [Apple Health and fitness apps](https://developer.apple.com/health-fitness/), [What's new in iOS 27](https://developer.apple.com/ios/whats-new/).

RunSmart relevance:

- Best first intents: Start Today's Run, Explain Today's Workout, Move Workout to Tomorrow, Make This Week Easier, Log Treadmill Run, Sync Devices.
- Intents should call existing service boundaries, not duplicate plan or run logic.
- App Intents also prepare RunSmart for Apple Intelligence and Siri semantic actions.

### Live Activities and Widgets

Apple says widgets can show relevant health and fitness data such as daily steps, calories, or streaks, and Live Activities can show real-time workout progress such as elapsed time, distance, pace, or heart rate. Source: [Apple Health and fitness apps](https://developer.apple.com/health-fitness/), [ActivityKit](https://developer.apple.com/documentation/ActivityKit/), [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

RunSmart relevance:

- A Live Activity is useful for phone-recorded runs and glanceable lock-screen progress.
- It is not the primary path for Apple Watch workout execution.
- The MVP should publish workouts first, then add Live Activity polish for phone GPS runs.

### Core Location and route tracking

Apple says Core Location can record outdoor activities, map routes, measure distance, and provide location-based coaching or challenges, while keeping users in control of location data. Source: [Apple Health and fitness apps](https://developer.apple.com/health-fitness/), [Core Location](https://developer.apple.com/documentation/corelocation).

RunSmart relevance:

- RunSmart already records phone GPS routes.
- Next Apple-side improvement is not more route recording, it is route persistence to HealthKit and provider-neutral route summaries for plan-vs-actual and course export.

### Foundation Models and Apple Intelligence

Apple's iOS 27 developer page says the Foundation Models framework is a native Swift API that can access the on-device model behind Apple Intelligence and can work with Apple Foundation Models, cloud models, or other Language Model providers. Source: [What's new in iOS 27](https://developer.apple.com/ios/whats-new/), [Foundation Models](https://developer.apple.com/documentation/foundationmodels).

RunSmart relevance:

- Useful later for on-device explanations, pre-run briefs, and lightweight summaries.
- Not a near-term replacement for existing cloud AI because availability depends on OS/device/model support and because RunSmart already depends on Supabase and server-side coaching.
- Use when it improves privacy, latency, and cost for supported users, with cloud fallback.

### Apple Workout Buddy signal

Apple's watchOS 26 announcement introduced Workout Buddy, an Apple Intelligence-powered workout experience for Apple Watch. Source: [Apple watchOS 26 announcement](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/).

RunSmart relevance:

- Apple is validating AI workout coaching and raising user expectations.
- RunSmart should not compete on generic motivational audio first.
- RunSmart should compete on cross-device adaptation, beginner safety, plan-vs-actual explanations, and Garmin plus Apple data synthesis.

## Garmin Developer Trends

### Activity API

Garmin says Activity API provides access to detailed fitness data captured during activities on Garmin wearable devices or cycling computers. It supports push or ping/pull integration, custom data feeds, backfill tools, and full activity detail files in FIT, GPX, and TCX. Source: [Garmin Activity API](https://developer.garmin.com/gc-developer-program/activity-api/).

RunSmart relevance:

- This is the official source for completed Garmin runs.
- RunSmart already has Garmin activity ingestion through Supabase-backed tables, but should document the Activity API as the long-term contract.
- FIT access matters for richer heart-rate series, laps, splits, zones, and route detail beyond the current summary model.

### Health API

Garmin says Health API provides all-day health metrics such as steps, heart rate, sleep, stress, Pulse Ox, Body Battery, respiration, and related summaries. Commercial use requires license fee payment. Source: [Garmin Health API](https://developer.garmin.com/gc-developer-program/health-api/).

RunSmart relevance:

- This is the Garmin path for recovery/readiness context.
- Current RunSmart already uses Garmin daily metrics, but Garmin Health API approval/licensing is a business dependency.
- Do not overbuild a proprietary readiness score until Garmin Health API access and data freshness are proven.

### Training API

Garmin says Training API publishes workouts and training plans to Garmin Connect calendar, where users can sync compatible devices and follow steps on wearables or cycling computers. Source: [Garmin Training API](https://developer.garmin.com/gc-developer-program/training-api/).

RunSmart relevance:

- This is the correct Garmin path for structured workout sync.
- It directly supports the product hypothesis and reduces need for a Connect IQ app.
- RunSmart needs publish-status tracking and exportable workout steps before building this integration.
- Garmin Training API is for Garmin users, not evidence that the average runner needs both Garmin and Apple support.

### Courses API

Garmin says Courses API publishes courses and course points to Garmin Connect, then compatible devices can sync and follow them from the Courses menu. Source: [Garmin Courses API](https://developer.garmin.com/gc-developer-program/courses-api/).

RunSmart relevance:

- Useful after route suggestions and saved routes are reliable.
- Not Phase 1 because workout publishing and completed-activity import are more central to adaptation.

### FIT files

Garmin FIT SDK defines file templates for activities, courses, and workouts. Activity files can include sport type, date/time, laps/splits, GPS track, sensor data, and events. Sources: [FIT SDK](https://developer.garmin.com/fit/), [Activity file type](https://developer.garmin.com/fit/file-types/activity/), [Workout file type](https://developer.garmin.com/fit/file-types/workout/), [FIT Cookbook](https://developer.garmin.com/fit/cookbook/).

RunSmart relevance:

- FIT parsing is a depth feature for better analysis when Activity API summaries are insufficient.
- Avoid adding FIT parsing until the MVP needs fields that the current Garmin summary tables do not provide.

### Connect IQ

Garmin Connect IQ is the platform for watch faces, data fields, widgets, and apps. Data fields plug into the Garmin activity experience. Sources: [Connect IQ](https://developer.garmin.com/connect-iq/), [Connect IQ app types](https://developer.garmin.com/connect-iq/connect-iq-basics/app-types/), [Data fields UX guidelines](https://developer.garmin.com/connect-iq/user-experience-guidelines/data-fields/).

RunSmart relevance:

- Connect IQ is not the first priority.
- It adds Garmin-specific app runtime, device compatibility, store submission, and Monkey C work.
- It becomes relevant only if RunSmart needs custom on-watch guidance that Garmin Training API steps cannot provide.

### Garmin Coach, Connect Plus, and AI direction

Garmin markets Garmin Coach as adaptive and prebuilt plans for running, cycling, strength, triathlon, and fitness. Garmin Connect+ adds Active Intelligence, AI-powered insights, expert training guidance, performance dashboards, and expanded LiveTrack features. Sources: [Garmin Coach](https://www.garmin.com/en-US/garmin-coach/overview/), [Garmin Connect+ press release](https://www.garmin.com/en-US/newsroom/press-release/wearables-health/elevate-your-health-and-fitness-goals-with-garmin-connect/), [Garmin Connect+ support](https://support.garmin.com/en-US/?faq=kWi5DoaMPZ4VCJBA0lFWP7).

RunSmart relevance:

- Garmin is moving toward AI explanations and adaptive training.
- RunSmart must be sharper than generic AI summaries: what changed, why it changed, and what the runner should do next.

## Competitive and Market Signals

- Runna supports Garmin and Apple Watch workout syncing. Its Garmin docs say Premium users sync the next two full weeks and updates can reflect plan changes. Sources: [Runna Garmin support](https://support.runna.com/en/articles/6169639-using-your-garmin-watch-with-runna), [Runna Apple Watch support](https://support.runna.com/en/articles/6306200-using-your-apple-watch-with-runna-and-getting-the-most-out-of-it).
- TrainingPeaks supports structured workouts on the Apple Watch Workout app and Garmin sync flows. Source: [TrainingPeaks Apple Watch](https://help.trainingpeaks.com/hc/en-us/articles/360039727152-TrainingPeaks-and-Apple-Watch), [TrainingPeaks structured workout sync](https://help.trainingpeaks.com/hc/en-us/articles/115000325647-Structured-Workout-sync-and-Manual-Export).
- Strava acquired Runna in April 2025, validating running coaching as strategic for large fitness platforms. Source: [Strava acquisition release](https://press.strava.com/articles/strava-to-acquire-runna-a-leading-running-training-app).
- Strava launched an MCP connector on June 1, 2026 so subscribers can query their own activity data through Claude, including stream data, GPS, pace, heart rate, and power. Source: [Strava MCP connector release](https://press.strava.com/articles/strava-launches-mcp-connector), [Strava MCP Help Center](https://support.strava.com/en-us/articles/15401531-strava-mcp-connector).
- Strava Athlete Intelligence uses generative AI to analyze activity, health, and location data into activity summaries. Source: [Strava Athlete Intelligence help](https://support.strava.com/en-us/articles/15401629-athlete-intelligence-on-strava).
- COROS is pushing app-native plans and training data analysis tools. Sources: [COROS App 4.0 feature update](https://coros.com/stories/coros-metrics/c/app-4-feature-update), [COROS Training Hub](https://coros.com/traininghub).

## Apple vs Garmin Capability Matrix

| Capability | Apple path | Garmin path | Product value for RunSmart | Technical complexity | Dependency / approval requirement | Recommended phase |
|---|---|---|---|---|---|---|
| Import completed run | HealthKit `HKWorkout` read | Activity API summaries/FIT via backend | Core adaptation input | Medium | HealthKit permission, Garmin approval | Phase 1 Apple, Phase 3 Garmin |
| Import GPS route | `HKWorkoutRoute`, Core Location | Activity API GPX/TCX/FIT or route points | Route matching, course learning | Medium | HealthKit route permission, Garmin Activity API | Phase 1 Apple import, Phase 3 Garmin depth |
| Import heart-rate series | HealthKit heart-rate samples | Activity API FIT detail | Better zones and effort scoring | Medium-High | HealthKit heart rate, Garmin FIT/detail access | Phase 3 |
| Import heart-rate zones | HealthKit workout zones in iOS/watchOS 27 | Garmin-derived zones or FIT/lap data | Zone Intelligence Layer | Medium | OS availability, Garmin data depth | Phase 4 |
| Import sleep/recovery data | HealthKit sleep, HRV, resting HR | Health API sleep, stress, Body Battery, HRV, readiness | Recovery-aware adjustment | Medium | HealthKit permission, Garmin Health API license | Phase 2 Apple, Phase 3 Garmin |
| Publish structured workout | WorkoutKit | Training API | Watch-sync promise for the runner's chosen ecosystem | High | WorkoutKit auth, Garmin Training API approval | Phase 2 Apple, Phase 3 Garmin |
| Schedule workout | WorkoutKit scheduler | Garmin Connect calendar via Training API | Plan becomes watch-ready when the runner owns a watch | Medium-High | User consent, Garmin approval | Phase 2 Apple, Phase 3 Garmin |
| Push workout changes | Update scheduled WorkoutKit plan | Update Garmin workout/plan calendar payload | Adaptation reaches watch | High | Provider update semantics | Phase 2/3 |
| Publish route/course | Apple route UX likely app-owned, not WorkoutKit course export | Courses API | Route-aware planning | High | Garmin Courses API approval | Phase 3/4 |
| Live workout guidance | Phone GPS + Live Activity, future watch app | Garmin standard workout step prompts, later Connect IQ | Confidence during session | Medium to High | ActivityKit, WorkoutKit, Garmin device support | Phase 2 Apple, Not Now for Connect IQ |
| Post-run analysis | HealthKit import plus local/Supabase analysis | Activity API import plus Supabase analysis | Retention loop | Medium | Existing app path | Phase 1 |
| Plan adaptation | Existing Flex Week and plan mutation | Provider-neutral adaptation, then republish | Product core | Medium-High | Internal model first | Phase 1 |
| No-wearable execution | Phone GPS, Live Activity later, manual log | Not applicable | Beginner wedge and non-device parity | Medium | Location permission for GPS only | Phase 1 |
| Voice/Siri/App Intent action | App Intents | No direct Garmin equivalent | Faster actions, Apple Intelligence readiness | Medium | iOS target/entitlements, test coverage | Phase 2 |
| Watch-native custom experience | watchOS app target | Connect IQ app/data field | Deep control, high polish | High | New targets, review, device QA | Not Now |
| AI explanation/coaching | Existing cloud AI, later Foundation Models | Existing cloud AI, Garmin data as context | Differentiation | Medium | AI safety, privacy, availability | Phase 1 cloud, Phase 4 on-device |

## Critical Dependencies and Approval Gates

**Garmin API approval is a critical-path blocker for Phase 3.** Several capabilities in the matrix below depend on Garmin Connect Partner Services granting production access to specific API scopes. Until approval lands, Phase 3 deliverables (import heart-rate series, import sleep/recovery depth, publish structured workout, schedule workout, push workout changes, publish route/course) cannot ship.

Capabilities blocked on Garmin approval:

- Import completed run (Phase 3 Garmin path)
- Import heart-rate series
- Import sleep/recovery data (Garmin Health API)
- Publish structured workout (Training API)
- Schedule workout (Training API calendar)
- Push workout changes
- Publish route/course (Courses API)

**Epic 6 (Garmin Training API Publishing) is the highest-risk gate.** Ticket 6.1 must confirm current approval state, OAuth scopes, and throttled production testing before any Training API engineering begins. If approval is delayed, Phase 2 (Apple WorkoutKit) and Phase 1 (provider-neutral foundation + no-wearable execution) proceed independently.

## Recommendation

Prioritize the provider-neutral Sync & Adapt foundation before adding any new watch-specific app surface.

The near-term roadmap should make one RunSmart workout usable in three ways: Apple WorkoutKit for Apple Watch users, Garmin Training API for Garmin users once approved, and a first-class in-app/manual path for no-wearable runners. One completed activity should import from Apple HealthKit, Garmin Activity API, phone GPS, or manual entry into the same canonical analysis pipeline.
