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

## Implementation Rule

Views should keep depending on protocols. Replace `MockRunSmartServices` with live clients only after payload contracts are stable.
