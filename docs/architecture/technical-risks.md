# Technical Risks — RunSmart iOS (updated 2026-06-11)

## Resolved in code-review fix sprint

- Challenge enrollment no longer uses a hashed synthetic `user_id`; writes use `auth_user_id`.
- Garmin route points are scoped by `(auth_user_id, activity_id)` on the client; `garmin_activity_points` is a security-invoker view over `garmin_activities`, with owner RLS on `garmin_activities` and `runs`.
- Account deletion now wipes `user_saved_routes` and `user_benchmark_routes` and returns HTTP 207 when partial cleanup warnings exist.
- Supabase URL and publishable key are injected via xcconfig / Info.plist instead of hardcoded Swift constants.
- Garmin gateway fallback URL removed; missing config fails fast in `GarminBridge`.

## High (remaining)

- **Garmin gateway coordination:** UUID-only web profiles require the external gateway to accept `authUserId` when numeric `userId` is absent. iOS sends both when available.
- **Production RLS drift:** Local migrations must be applied to live Supabase; permissive legacy policies can still OR with new owner policies until removed in prod.
- **`runs.profile_id` constraints:** UUID-only upserts omit `profile_id`; confirm production schema allows null or backfill before wide rollout.

## Medium

- **Debrief latency:** Client timeout is 12s while edge `run_debrief` uses 10s; occasional fallback debriefs remain possible under load.
- **HealthKit authorization:** iOS cannot read per-type denial reliably; connected state reflects authorization prompt outcome, not guaranteed read access.
- **Large service files:** `SupabaseRunSmartServices.swift` and `SecondaryFlowView.swift` remain monolithic; split deferred to post-TestFlight cleanup.

## Low

- **Simulator CI fragility:** CoreSimulator install failures should be treated as infrastructure, not product regressions.
- **LiveRunSmartServices:** Legacy live stack remains in repo but is not wired into the production app shell (`SupabaseRunSmartServices.shared`).

## Mitigation rules

- Reconcile baseline audit against live Supabase before applying RLS/index migrations.
- TestFlight smoke: Sign in with Apple → Garmin connect → run sync → challenge enroll → delete account.
- After identity changes, verify both legacy bigint profiles and UUID-only web profiles.
