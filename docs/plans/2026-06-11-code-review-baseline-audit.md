# Code Review Baseline Audit — 2026-06-11

Source: local `supabase/migrations/`, Swift client queries, and `docs/runsmart-ios-supabase-backend-plan.md`.  
Live Supabase export was not run in this session; reconcile against production before applying RLS migrations.

## Schema snapshot (inferred)

| Table | Owner column(s) | Notes |
| --- | --- | --- |
| `profiles` | `auth_user_id` | `id` is bigint (legacy) or UUID (web-created) |
| `challenge_enrollments` | `auth_user_id`, legacy `user_id` bigint | iOS enroll used hashed `user_id`; fix uses `auth_user_id,challenge_id` upsert |
| `garmin_activities` | `auth_user_id` | Deduped view `garmin_activities_deduped` used by iOS |
| `garmin_activity_points` | `auth_user_id`, `activity_id` | Route points queried by `activity_id` only before fix |
| `garmin_connections` | `auth_user_id` | OAuth polling target |
| `runs` | `profile_id` bigint + `auth_user_id` (target) | iOS upsert required numeric `profile_id` before fix |
| `user_saved_routes` | `user_id` uuid | Not wiped in `delete_account` before fix |
| `user_benchmark_routes` | `user_id` uuid | Not wiped in `delete_account` before fix |

## RLS audit (local migrations)

Existing migrations harden coach tables (`conversation_messages`, RPC grants, `run_debriefs`).  
**No migration in repo** enables owner-scoped RLS on:

- `garmin_activity_points`
- `garmin_activities`
- `runs`

**Risk:** Authenticated clients could read another user's GPS polyline if a global SELECT policy exists in production.  
**Mitigation:** Client scopes queries by `auth_user_id`; migration `20260611120000_garmin_activity_points_rls.sql` adds owner policies.

## Index recommendations (Phase 3.7)

| Table | Index | Purpose |
| --- | --- | --- |
| `garmin_activity_points` | `(auth_user_id, activity_id)` | Route fetch |
| `garmin_activities` | `(auth_user_id, start_time DESC)` | Recent activities |
| `challenge_enrollments` | `(auth_user_id, challenge_id)` | Enroll upsert |
| `runs` | `(auth_user_id, completed_at DESC)` | Recent runs by auth owner |
| `runs` | `(source_provider, source_activity_id)` | Idempotent upsert (existing unique) |

## Baseline validation

- Branch: `fix/code-review-p0-identity`
- Xcode build: **green** (2026-06-12, `-derivedDataPath /tmp/runsmart-dd`, iPhone 17 Pro Max iOS 26.5 simulator)
- Tests: **not executed** — simulator bootstrap SIGILL (`Early unexpected exit`); compile-only validation passed

## Open coordination

- Garmin gateway must accept `authUserId` when legacy numeric `profiles.id` is absent (UUID web profiles).
