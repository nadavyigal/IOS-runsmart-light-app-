# RunSmart Lite Integration Gaps

## Current State

The native app is scaffolded with mock services and deterministic sample data. No live backend, HealthKit, Core Location, push notification, or device sync code is wired yet.

## Service Mapping

| Native Service | Reference Concept | Known Gap |
| --- | --- | --- |
| `TodayProviding` | Today screen, readiness, workout recommendation | Needs native endpoint or mapper from plan/workout/recovery data. |
| `PlanProviding` | Generated plan and workout schedule | Needs contract for weekly and monthly plan payloads. |
| `CoachChatting` | `app/api/chat/route.ts` | Needs auth/session strategy and streaming response handling. |
| `ProfileProviding` | User, preferences, badges, shoes/devices | Needs native profile API and local persistence decision. |
| `RunLogging` | Run recording and persistence | Needs Core Location tracking, pause/resume state, and save contract. |
| Route service | Route selection/generation | Needs route payload, map provider, and offline behavior. |
| Reminder service | Local/push reminders | Needs notification permission UX and scheduling policy. |
| Device sync | Garmin/HealthKit/Strava hooks | Needs OAuth/permissions, sync lifecycle, and privacy strings. |

## Backend Questions

- Which auth strategy should the native app use for the existing web backend?
- Should coach chat stream tokens to the app or return complete responses?
- Which service owns readiness and recovery calculations for iOS V1?
- Are run records persisted locally first, remotely first, or both?
- Which connected-service provider is first: Apple Health, Garmin, or Strava?

## Exact Contracts Needed

The native app now has DTO boundaries prepared in `Services/Live/RunSmartAPIModels.swift`.
To wire real networking, these backend contracts must be finalized:

### 1) Auth + Profile
- `POST /v1/auth/session`
  - **Request**: provider token/code payload (provider-specific)
  - **Response**: `accessToken`, `refreshToken?`, `expiresAtISO8601`, `tokenType`, `user`
- `GET /v1/profile/me`
  - **Response user**: `userID`, `displayName`, `email?`, `goal`, `level`, `streakLabel`, `stats`
  - **Stats**: `totalRuns`, `totalDistanceKm`, `totalTimeLabel`

### 2) Today
- `GET /v1/today`
  - **Response**: `readinessScore`, `readinessLabel`, `workoutTitle`, `plannedDistanceLabel`, `targetPaceLabel`, `elevationLabel`, `coachMessage`

### 3) Plan + Workouts
- `GET /v1/plan/week?start=YYYY-MM-DD`
  - **Response**: `weekStartISO8601`, `weekEndISO8601`, `workouts[]`
  - **Workout item**: `workoutID`, `weekday`, `dateLabel`, `kind`, `title`, `distanceLabel`, `detailLabel`, `isToday`, `isComplete`
- `GET /v1/workouts/{workoutID}`
  - Needed to support workout detail screens once added.

### 4) Coach Chat
- `GET /v1/coach/threads/current`
  - **Response**: `threadID`, `messages[]`
  - **Message**: `messageID`, `text`, `timeLabel`, `role` (`user|assistant|system`)
- `POST /v1/coach/messages`
  - **Request**: `threadID?`, `text`
  - **Response (non-streaming fallback)**: `messageID`, `text`, `timeLabel`, `role`
- Streaming decision still required:
  - SSE token stream vs full-response payload.

### 5) Run Logging
- `POST /v1/runs`
  - **Request**: `startedAtISO8601`, `endedAtISO8601`, `distanceMeters`, `movingTimeSeconds`, `averagePaceSecondsPerKm`, `averageHeartRateBPM?`, `routePoints[]`
  - **Route point**: `latitude`, `longitude`, `sequence`
  - **Response**: `runID`, `savedAtISO8601`
- `GET /v1/runs/live-metrics` (optional if backend-calculated)
  - If omitted, app computes live metrics locally.

### 6) Routes
- `GET /v1/routes/suggestions?distanceKm=&surface=&elevation=`
  - **Response[]**: `routeID`, `name`, `distanceKm`, `elevationGainMeters`, `estimatedDurationMinutes`, `points[]`

### 7) Preferences
- `GET /v1/preferences`
  - **Response**: `units`, `weekStartsOn`, `defaultCoachTone`, `trainingDays[]`, `notificationEnabled`
- `PUT /v1/preferences`
  - **Request** matches response payload.

### 8) Reminders
- `GET /v1/reminders`
  - **Response[]**: `reminderID`, `type`, `title`, `body`, `localTime`, `enabled`
- `PUT /v1/reminders/{reminderID}`
  - **Request**: `enabled`, `localTime`, `type`

### 9) Device Sync
- `GET /v1/device-sync/status`
  - **Response[]**: `provider`, `connectionState`, `lastSuccessfulSyncISO8601?`, `permissions[]`
- `POST /v1/device-sync/{provider}/connect`
- `POST /v1/device-sync/{provider}/disconnect`
- `POST /v1/device-sync/{provider}/sync-now`

## iOS Mapping Boundary Rule (Now Enforced)

- DTOs are backend-facing only.
- Views/screens consume domain/UI models only (`RunnerProfile`, `TodayRecommendation`, `WorkoutSummary`, `CoachMessage`, `MetricTile`).
- Mapping happens in `RunSmartDTOMapper` and nowhere in views.

## Implementation Rule

Views should keep depending on protocols. Replace `MockRunSmartServices` with live clients only after payload contracts are stable.
