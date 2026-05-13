# RunSmart iOS Supabase Backend Plan

## Outcome

Move RunSmart user data from browser-only persistence into Supabase so the iOS app can read and write the same user profile, training plan, activity, coach, and preference data across devices.

## What Done Looks Like

- The web app and iOS app use the same Supabase user identity.
- Training plans, workouts, goals, runs, coach messages, recovery data, and preferences are server-owned.
- iOS keeps only session tokens, short-lived cache, unsynced run drafts, and device-local permission state locally.
- Local/browser data has a migration path into Supabase.
- Row Level Security protects every user-owned table by `auth.uid()`.

## Investigated Sources

- Web app local checkout: `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-`
- GitHub remote: `https://github.com/nadavyigal/Running-coach-.git`
- GitHub `main` and local checkout both resolve to commit `79a85f51fcf8492bb1fe7fa3a552f33a08d5e216`.
- Also found `/Users/nadavyigal/Documents/RunSmart`, but that checkout is on a different local commit with local changes. The GitHub-matching project path above is the source of truth for this audit.

## Current Repo Findings

The web app is local-first. The primary browser database is Dexie/IndexedDB, not `localStorage`. Supabase is already used for auth, profiles, Garmin/backend features, user-memory snapshots, and partial sync of runs/goals/shoes, but the main product state still lives in browser storage.

| Data area | Current iOS behavior | Backend status |
| --- | --- | --- |
| Auth session | Supabase auth session with Apple sign-in | Supabase-owned |
| Onboarding/profile | `profiles` upsert through `auth_user_id`; older production store still saves `runsmart.onboarding.*` in `UserDefaults` | Partly Supabase-owned |
| Training goals | Saves goal fields to `profiles`; web has local `goals` table and partial sync to Supabase `goals` | Partly Supabase-owned |
| Plans/workouts | iOS reads/writes Supabase `plans` and `workouts`; web keeps plans/workouts in Dexie | Split source of truth |
| Manual/GPS runs | Saved to `UserDefaults` as `runsmart.runs`; Garmin runs read from Supabase | Needs Supabase table for native/manual runs |
| Run reports | Saved locally as `runsmart.runReports`; Garmin post-run insights read from `ai_insights` | Needs Supabase persistence for native reports |
| Device status | Some status cached locally as `runsmart.device.statuses`; Garmin connection read from Supabase | Split; should be server-owned except iOS permissions |
| Coach chat | Reads conversation history from Supabase; send path is not implemented | Needs native send endpoint or table write + Edge Function |
| Recovery/wellness | Garmin metrics from Supabase; wellness check-ins currently empty | Needs wellness table |
| Preferences/reminders | Profile UI displays units, notifications, coaching tone; reminders return empty | Needs tables/contracts |

## Confirmed Browser Storage Inventory

### IndexedDB

Primary database:

- `RunSmartDB`

Legacy/reset-only database names:

- `running-coach-db`
- `RunningCoachDB`

Dexie object stores in `RunSmartDB`:

| Store | Current role | Backend action |
| --- | --- | --- |
| `users` | Profile, onboarding, consents, preferences, physiological data, reminders, subscription, race baselines | Migrate to `profiles`, `user_preferences`, `user_consents`, `physiology_profiles`, `subscriptions` |
| `plans` | Training plan metadata | Migrate to Supabase `plans`; add/standardize `auth_user_id` |
| `workouts` | Scheduled plan workouts, completion, structure, dates | Migrate to Supabase `workouts`; add workout event history |
| `runs` | Manual/GPS/Garmin-mirrored runs, GPS JSON, run reports | Migrate to `runs`, `run_route_points`, `run_reports` |
| `activeRecordingSessions` | In-progress recording recovery | Keep local draft; sync only when finalized |
| `locationQuality` | GPS/location quality summaries | Optional server analytics; can stay local cache for V1 |
| `shoes` | Shoe inventory/mileage | Migrate to `shoes`; already partially synced |
| `chatMessages` | Coach/chat history | Migrate to `conversations`, `conversation_messages` |
| `badges` | Achievements | Migrate to `achievements` or derive from runs/goals |
| `planFeedback` | Feedback on plan difficulty/enjoyment | Migrate to `plan_feedback` |
| `cohorts`, `cohortMembers` | Group/cohort data | Server-owned tables |
| `performanceMetrics`, `personalRecords`, `performanceInsights` | Derived performance analytics | Prefer server-derived or materialized snapshots |
| `raceGoals` | Race targets | Migrate to `goals` or `race_goals` |
| `workoutTemplates` | Template catalog | Server/catalog table or bundled static seed |
| `coachingProfiles`, `coachingFeedback`, `coachingInteractions`, `userBehaviorPatterns` | Adaptive coaching memory | Server-owned coaching tables |
| `goals`, `goalMilestones`, `goalProgressHistory`, `goalRecommendations` | SMART goals and progress | Migrate to normalized goal tables; `goals` already partially synced |
| `wearableDevices`, `heartRateData`, `heartRateZones`, `heartRateZoneSettings`, `zoneDistributions`, `advancedMetrics`, `runningDynamicsData`, `syncJobs`, `garminSummaryRecords` | Device state and physiology metrics | Server-owned except device permission/cache state |
| `onboardingSessions`, `conversationMessages` | AI onboarding session + messages | Migrate to onboarding/conversation tables |
| `sleepData`, `hrvMeasurements`, `recoveryScores`, `subjectiveWellness` | Recovery/readiness/wellness | Migrate to wellness/recovery tables |
| `dataFusionRules`, `fusedDataPoints`, `dataConflicts`, `dataSources` | Multi-source data fusion | Server-owned for cross-device consistency |
| `habitAnalyticsSnapshots`, `habitInsights`, `habitPatterns` | Habit analytics | Server-derived or synced snapshots |
| `routes`, `routeRecommendations`, `userRoutePreferences` | Route data/preferences | Server-owned routes/preferences |
| `challengeTemplates`, `challengeProgress` | Challenge catalog and user progress | Catalog server-owned; progress user-owned |

### localStorage Keys

| Key or pattern | Current use | Backend action |
| --- | --- | --- |
| `sb-${projectRef}-auth-token` | Supabase client auth session | Keep managed by Supabase clients |
| `runsmart_auth_user_id`, `runsmart_auth_email`, `runsmart_auth_at` | Local auth hints for web UI | Replace with Supabase session/profile reads; cache-only if retained |
| `onboarding-complete` | Boolean navigation gate mirrored from Dexie `users.onboardingComplete` | Cache-only; source should be `profiles.onboarding_complete` |
| `user-data` | Small onboarding/profile snapshot used for fallback navigation | Remove as source of truth; migrate once to profile/preferences if needed |
| `user-profile`, `user-preferences` | Legacy diagnostic cleanup keys | Legacy cleanup only |
| `beta_signup_email`, `beta_signup_name`, `beta_signup_complete` | Landing/beta signup flow | Keep only for pre-auth landing recovery; server should own signup |
| `preselectedChallenge` | Challenge slug chosen before onboarding | Draft-only; write to challenge enrollment after onboarding |
| `landing_lang`, `beta_landing_lang`, `challenge_lang` | Landing/challenge language preference | Local UI preference or `user_preferences.locale` after auth |
| `audioCoachEnabled`, `vibrationEnabled` | Device/audio coaching toggles | `user_preferences` plus device-local fallback |
| `running-shoes` | Demo shoe list in add-shoes/profile screens | Migrate to `shoes`; remove demo local source |
| `active_recording_checkpoint` | Fast in-progress GPS recording checkpoint | Keep local draft; upload finalized run |
| `morning-checkin:auto-prompt:${userId}:${YYYY-MM-DD}` | Prevent repeated morning check-in prompt | Local UI gate; check-in data goes to `subjectiveWellness`/Supabase |
| `weeklyRecap_${userId}_${weekStartISO}` | Weekly recap cache | Cache-only; regenerate from server data |
| `lastRecapNotificationDate` | Weekly recap reminder gate | Local notification state or `reminders` metadata |
| `runsmart_device_id` | Device ID for `user_memory_snapshots` | Keep device-local; link to authenticated user server-side |
| `device_id` | Welcome modal checks for an existing device id | Normalize to `runsmart_device_id` or remove |
| `has_seen_welcome_modal`, `welcome_dismissed_at` | Welcome modal UX | Local UI state |
| `last_sync_timestamp` | Incremental sync watermark for runs/goals/shoes | Replace with per-table sync cursors or server `updated_at` checks |
| `initial_sync_complete`, `initial_sync_timestamp` | One-time local-to-Supabase sync flag | Migration-only; reset after durable server migration |
| `plan_workout_sync_complete_v1` | One-time browser backfill flag for plans/workouts added in the web sync implementation | Migration-only; prevents existing authenticated users from being skipped |
| `device_migration_complete`, `linked_profile_id`, `migration_timestamp` | Device data migration flag | Migration-only |
| `migration_fix_multiple_active_plans_v2` | One-time local plan cleanup | Migration-only |
| `migration_clear_tel_aviv_routes_v1`, `migration_clear_tel_aviv_routes_v1_timestamp` | One-time local route cleanup | Migration-only |
| `db-version-change` | Cross-tab DB version notification | Local cache/control |
| `app-version` | App version cache invalidation | Local cache/control |
| `offline_data`, `offline_mode` | Generic offline fallback | Replace with typed sync queue; not source of truth |
| `error_logs`, `critical_errors` | Client diagnostics | Local diagnostics or server telemetry with consent |
| `chat-persistence-test`, `integration-test` | Debug/testing keys | Test-only; ignore for migration |

### sessionStorage Keys

| Key | Current use | Backend action |
| --- | --- | --- |
| `last-screen` | Restore last selected screen | Local UI state |
| `force-onboarding` | Reset flow flag | Local reset/debug state |
| `recording_recovery` | Temporary payload to resume an interrupted recording in `RecordScreen` | Keep local draft only |
| `chunk_reload_count` | Chunk error reload protection | Local UI/runtime state |
| `user-id`, `timezone` | Preserved by version cleanup if present | Cache only; timezone can also live in `user_preferences` |

### Cache Storage

The web app uses the browser Cache API during version changes to clear all service-worker/cache entries. No stable user-data cache key was found. Treat Cache Storage as rebuildable application cache, not migration input.

Likely browser-owned user data to expect:

| Browser/local item | Supabase destination |
| --- | --- |
| User profile and onboarding answers | `profiles`, `user_preferences` |
| Current goal | `goals` or profile summary fields plus goal history |
| Generated training plan | `plans` |
| Scheduled workouts | `workouts` |
| Workout edits/reschedules/completion | `workouts`, `workout_events` |
| Run history/manual logs | `runs`, `run_route_points` |
| Coach messages | `conversations`, `conversation_messages` |
| Readiness/recovery/wellness check-ins | `wellness_checkins`, `recovery_snapshots` |
| Reminders/notification settings | `reminders`, `user_preferences` |
| Shoes/devices/challenges | `shoes`, `device_connections`, `challenge_enrollments` |
| AI reports/insights | `ai_insights`, or `run_reports` if reports need structured fields |

## Existing Web Sync/Backend Behavior

- Auth uses Supabase client/session and `profiles.id` lookup by `auth_user_id`.
- `SyncService` performs incremental sync from Dexie to Supabase for only `runs`, `goals`, and `shoes`, using `profile_id + local_id` upserts and `last_sync_timestamp`.
- `performInitialSync` does a one-time upload of local runs/goals/shoes and writes `initial_sync_complete`.
- `user_memory_snapshots` stores a device-level JSON snapshot containing user, active plan, workouts, goals, runs, routes, and summary. This is useful for backup/restore, but it is not a normalized backend model.
- `plans` and `workouts` remain local-first in the web app, while iOS already expects Supabase `plans` and `workouts`.

## Implementation Update - 2026-05-03

Implemented the first backend bridge for the iOS app by updating the GitHub-matching web project at `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-`.

| Area | Implemented change |
| --- | --- |
| Supabase schema | Added migration `v0/supabase/migrations/20260503000000_web_plan_workout_sync.sql` to add `local_id`, `auth_user_id`, workout completion/actual fields, and unique upsert indexes for `plans` and `workouts`. |
| Browser-to-Supabase plan sync | Added `v0/lib/sync/plan-workout-sync.ts` to map Dexie `plans`/`workouts` into normalized Supabase rows using stable local IDs. |
| Initial sync | Updated `v0/lib/sync/initial-sync.ts` so first-time authenticated users upload existing plans and workouts before runs/goals/shoes. |
| Incremental sync | Updated `v0/lib/sync/sync-service.ts` so authenticated web users sync plans and workout changes, with a one-time backfill for users who already had `last_sync_timestamp`. |
| Browser mutation triggers | Updated `v0/lib/dbUtils.ts` so creating plans/workouts and completing/updating workouts triggers the background sync path. |
| iOS writes | Updated `IOS RunSmart app/Services/Supabase/TrainingPlanRepository.swift` so iOS-created plans/workouts populate `auth_user_id` alongside `profile_id`. |

Operational caveat: remote deletion/tombstones for browser-deleted workouts are not implemented yet. The current implementation covers creation, update, completion, and first backfill, which are the required paths for iOS to read the active plan and workout schedule from Supabase.

## Supabase Data Model

Use `auth.users.id` as the stable cross-platform owner. Keep `profiles.auth_user_id` as the primary user join. Existing web tables use numeric `profiles.id` in some places and iOS already has compatibility for numeric `profile_id`; keep this short-term, but new tables should include `auth_user_id uuid not null`.

Core tables:

| Table | Purpose | Owner column |
| --- | --- | --- |
| `profiles` | Display name, email, onboarding complete, coarse goal/experience summary | `auth_user_id` |
| `user_preferences` | Units, coaching tone, notification defaults, week start, training days | `auth_user_id` |
| `user_consents` | Data/GDPR/push consent history | `auth_user_id` |
| `physiology_profiles` | VDOT, HRV baseline, max/resting HR, lactate threshold, historical baseline runs | `auth_user_id` |
| `goals` | Goal history, target date, target distance/time, status | `auth_user_id` |
| `plans` | Active/generated training plan metadata | `profile_id` now; migrate/add `auth_user_id` |
| `workouts` | Scheduled workout rows with structure, date, intensity, completion | via `plan_id`, ideally plus denormalized `auth_user_id` |
| `workout_events` | Rescheduled, amended, skipped, completed audit trail | `auth_user_id` |
| `runs` | Manual, GPS, HealthKit, Garmin-normalized run records | `auth_user_id` |
| `run_route_points` | GPS/polyline points for app-recorded runs | via `run_id` |
| `run_reports` | Structured post-run report generated for native/manual runs | `auth_user_id` |
| `conversations` | Coach thread ownership | `auth_user_id` or compatible profile UUID |
| `conversation_messages` | Coach messages | via `conversation_id` |
| `wellness_checkins` | Mood, soreness, hydration, RPE, subjective recovery | `auth_user_id` |
| `recovery_snapshots` | Computed readiness from Garmin/HealthKit/check-ins | `auth_user_id` |
| `device_connections` | Garmin/HealthKit/Strava connection status and sync metadata | `auth_user_id` |
| `reminders` | Reminder schedules and enabled state | `auth_user_id` |
| `shoes` | Shoe tracking and mileage | `auth_user_id` |
| `challenge_enrollments` | User challenge progress | `auth_user_id` |
| `user_memory_snapshots` | Optional compatibility backup of legacy browser state by device | `auth_user_id` plus `device_id` |

## iOS Persistence Rule

iOS should not treat `UserDefaults` as the source of truth for user training data.

Keep local:

- Supabase auth/session state managed by `supabase-swift`.
- Unsynced run recording drafts while a run is in progress.
- Last successful read cache for offline display.
- Device-only permission state, such as HealthKit authorization.
- Ephemeral UI state.

Sync to Supabase:

- Onboarding/profile completion.
- Training goals and plan generation results.
- Workout edits, reschedules, removals, and completions.
- Manual runs, GPS runs, HealthKit imports, Garmin imports.
- Run reports and AI insights.
- Coach messages.
- Wellness check-ins, reminders, shoes, device sync status.

## Backend API Plan

Prefer direct Supabase table reads for simple read models and Supabase Edge Functions or existing web API routes for operations that need business logic or AI generation.

Required contracts:

| Capability | Contract |
| --- | --- |
| Profile | `GET/UPSERT profiles`, `GET/PUT user_preferences` |
| Goal save | `POST /goals` or RPC `save_training_goal` |
| Plan generation | Edge Function/API `generate-plan`, then persist `plans` + `workouts` transactionally |
| Today | DB/RPC `get_today_summary(auth_user_id)` combining plan, workout, recovery, streak |
| Workout changes | RPCs for `move_workout`, `amend_workout`, `complete_workout`, `remove_workout` |
| Run logging | `POST runs`, `POST run_route_points`, optional RPC `complete_run_and_update_stats` |
| Coach | `POST coach_message` Edge Function that stores user message, calls model, stores assistant message |
| Recovery | RPC or materialized view combining Garmin, HealthKit, check-ins, run load |
| Reminders | CRUD `reminders`; iOS schedules local notifications from server state |
| Migration | `POST /migrate-browser-state` or admin script to import Dexie export / `user_memory_snapshots` |

## Migration Stories

### Story 1: Browser Storage Migration Map

**As a** developer
**I want** the confirmed Dexie/localStorage/sessionStorage inventory mapped to Supabase
**So that** no training data is lost when iOS becomes server-backed.

Acceptance criteria:

- Every `RunSmartDB` object store has a server-owned/cache/draft/ephemeral classification.
- Every known `localStorage` and `sessionStorage` key has a migration action.
- The app can export a signed-in user's Dexie tables and local migration metadata for import testing.

Test plan:

- Create a web user, complete onboarding, generate a plan, edit a workout, log a run, send coach chat, then export `RunSmartDB`, `localStorage`, and `sessionStorage`.
- Verify all server-owned records map to a target Supabase table.

### Story 2: Supabase Ownership Schema

**As a** backend
**I want** normalized user-owned tables with RLS
**So that** web and iOS can safely share data.

Acceptance criteria:

- New/updated tables exist for preferences, consents, physiology profiles, goals, plans/workouts ownership, native runs, route points, run reports, wellness, reminders, shoes, challenges, and workout events.
- All user data tables have RLS policies scoped to `auth.uid()`.
- Existing `plans`, `workouts`, `runs`, `goals`, and `shoes` support current numeric `profile_id/local_id` sync while moving toward `auth_user_id`.

Test plan:

- SQL migration tests with two users.
- Verify user A cannot read/write user B rows.

### Story 3: Profile And Plan Parity

**As an** iOS user
**I want** onboarding, profile, goals, plans, and workouts saved in Supabase
**So that** my plan appears on every device.

Acceptance criteria:

- Web and iOS onboarding write profile/preferences to Supabase.
- Existing web `onboarding-complete` and `user-data` are cache/migration-only.
- Web and iOS Plan/Today screens load active plan/workouts from Supabase.
- Goal changes regenerate and persist a new active plan transactionally.

Test plan:

- Unit tests for DTO mappers.
- Integration test: sign in on web, complete onboarding, save goal, verify `profiles`, `goals`, `plans`, `workouts`, then sign in on iOS and verify same next workout.

### Story 4: Run Logging Sync

**As an** iOS runner
**I want** web/iOS manual/GPS/HealthKit runs synced to Supabase
**So that** training load, streak, plans, and reports use real activity.

Acceptance criteria:

- `runs` table stores source, provider activity ID, start/end, distance, duration, pace, HR, sync status.
- GPS route points are saved separately and batched.
- Local unsynced web/iOS run drafts retry after network failure.
- Duplicate imports are prevented by `provider + provider_activity_id`.
- Existing web `runs` Dexie rows and iOS `runsmart.runs` rows can migrate idempotently.

Test plan:

- Offline save then online retry.
- Duplicate HealthKit/Garmin import does not create duplicates.
- Runs appear in profile totals and training load.

### Story 5: Coach, Recovery, And Preferences

**As an** iOS user
**I want** coach chat, recovery, reminders, and preferences persisted
**So that** the native app behaves like the web app.

Acceptance criteria:

- Coach send path stores both user and assistant messages.
- Recovery summary uses server data and falls back gracefully when no wearable is connected.
- Preferences/reminders are editable on iOS and visible on web.

Test plan:

- Coach message integration test.
- Preference update round-trip test from iOS to Supabase to web.
- Recovery empty-state and Garmin-backed-state tests.

### Story 6: Legacy Browser Data Migration

**As an** existing web user
**I want** Dexie/browser-only data copied into Supabase
**So that** installing iOS does not reset my training history.

Acceptance criteria:

- Migration imports `RunSmartDB` export or existing `user_memory_snapshots` once per user.
- Imported rows preserve original IDs where safe, or store legacy IDs for dedupe.
- Migration is idempotent.
- User can confirm data appears on iOS after sign-in.

Test plan:

- Run migration twice with same browser export.
- Verify row counts do not duplicate.
- Verify active plan and next workout match pre-migration browser state.

## Recommended Order

1. Add/export a web migration payload from `RunSmartDB`, `localStorage`, and existing `user_memory_snapshots`.
2. Add Supabase migrations/RLS for missing server-owned data and `auth_user_id` ownership.
3. Backfill existing web data into normalized Supabase tables, preserving `local_id` for dedupe.
4. Update web app to read/write server-first for profile, goals, plans, workouts, runs, shoes, coach, recovery, and reminders.
5. Update iOS service repositories to use the same Supabase tables for runs, reports, preferences, reminders, and coach send.
6. Keep local draft/cache systems for active recording checkpoints, offline queue, and UI state.
7. Run one-user migration tests, then two-user RLS tests, then web/iOS cross-device QA.

## Open Decisions

- Whether to keep using direct Supabase table access from iOS or route all writes through Edge Functions/RPCs.
- Whether `plans.profile_id` should remain numeric/profile-based or be migrated to `auth_user_id`.
- Whether coach chat should stream to iOS or return complete assistant responses.
- Whether HealthKit records should be stored as first-class `runs` rows or only aggregated into metrics.
- Whether AI run reports belong in current `ai_insights` or a dedicated `run_reports` table.
- Whether `user_memory_snapshots` remains a compatibility backup or is removed after normalized migration.
