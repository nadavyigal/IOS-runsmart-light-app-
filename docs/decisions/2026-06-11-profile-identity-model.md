# Decision: Profile identity model (hybrid C)

**Date:** 2026-06-11  
**Status:** Accepted for iOS code-review fix sprint  
**Options considered:** (A) backfill numeric `profiles.id`, (B) migrate all tables to `auth_user_id`, (C) hybrid

## Decision

Use **hybrid identity (C)**:

1. **`auth.users.id` / `profiles.auth_user_id` is canonical** for enrollments, RLS, Garmin row ownership, and new writes.
2. **Legacy numeric `profiles.id`** remains for Garmin gateway connect and `runs.profile_id` where the row still uses bigint.
3. **Stop synthesizing identity** via `userIdInt64(from:)` hash for `challenge_enrollments`.
4. **UUID-only profiles** must work without numeric id: send `authUserId` to Garmin gateway; upsert runs with `auth_user_id`.

## iOS implementation rules

- Resolve identity through `TrainingPlanRepository.identity(authUserID:)` / `RunSmartIdentity`.
- Upsert conflicts: `challenge_enrollments` on `(auth_user_id, challenge_id)`; runs on `(source_provider, source_activity_id)`.
- Scope Garmin route-point reads by `(auth_user_id, activity_id)`.

## Backend follow-up

- Garmin connect API: accept `authUserId` when `userId` is omitted.
- Optional SQL backfill: populate `runs.auth_user_id` for legacy rows (out of scope for this iOS PR set).

## Risks

- Gateway deployed without `authUserId` support blocks Garmin for UUID-only accounts until backend ships.
- `runs.profile_id` NOT NULL constraints in production may require migration before UUID-only upserts succeed.
