# Code Review Fix Plan — 2026-06-11

Source: full static code review of `IOS RunSmart app/` (SwiftUI + Supabase edge functions).  
Scope: bugs, security/data integrity, performance, cleanup. No React/Capacitor in this repo.

## Goal

Fix data-integrity and auth/security issues first, then user-visible correctness and performance, then cleanup — without broad refactors until P0–P2 are stable.

## Phase 0 — Baseline (before code changes)

**Duration:** ~0.5 day

| Step | Action | Why |
|------|--------|-----|
| 0.1 | Export live schema for `profiles`, `challenge_enrollments`, `garmin_*`, `runs`, `user_saved_routes`, `user_benchmark_routes` | Fixes depend on actual column types and FKs |
| 0.2 | Audit RLS on `garmin_activity_points`, `garmin_activities`, `runs` | Confirms whether route-point query is exploitable today |
| 0.3 | List indexes on hot columns (see Phase 3) | Avoid guessing in migrations |
| 0.4 | Run Xcode build + core unit tests on current branch | Establishes green baseline |
| 0.5 | Create branch `fix/code-review-p0-identity` | Keeps fixes reviewable in small PRs |

**Exit criteria:** Schema/RLS snapshot documented; build green.

---

## Phase 1 — P0: Identity, auth, and data deletion (ship blockers)

**Duration:** ~3–5 days  
**PR strategy:** 2–3 small PRs

### 1.1 Unify profile identity (Garmin + runs + challenges)

**Problem:** UUID profiles break Garmin connect and cloud run sync; challenge enrollment uses a hashed fake `user_id`.

| Task | Files | Acceptance criteria |
|------|-------|---------------------|
| **1.1a** Decide identity model: (A) backfill numeric `profiles.id`, (B) migrate gateway + `runs` to `auth_user_id`, or (C) hybrid mapping table | Product + backend decision doc | Written decision in `docs/decisions/` |
| **1.1b** Replace `userIdInt64(from: authUUID)` in challenge enrollment with real identity | `ChallengeRepository.swift`, `RunSmartSupabaseClient.swift` | Enroll works for web-created users; no hash collisions |
| **1.1c** Fix Garmin connect for UUID profiles | `GarminBridge.swift`, gateway if needed | Connect works for web + iOS accounts |
| **1.1d** Fix `upsertCompletedRunIfPossible` for UUID profiles | `SupabaseRunSmartServices.swift` | Runs sync to Supabase, not local-only |
| **1.1e** Integration test: web-profile user → Garmin mock → run upsert → challenge enroll | Tests | All paths pass |

**Dependencies:** 1.1a blocks 1.1b–1.1d.

### 1.2 Security hardening

| Task | Files | Acceptance criteria |
|------|-------|---------------------|
| **1.2a** Scope `activityRoutePoints` by `auth_user_id` | `GarminBridge.swift`, call sites | Query never returns another user's GPS points |
| **1.2b** Add/verify RLS migration for `garmin_activity_points` | `supabase/migrations/` | User A cannot read user B's activity_id |
| **1.2c** Restrict CORS on `delete_account` and `coach_message` | Edge functions | Random web origin cannot POST with stolen JWT |
| **1.2d** Cap `coach_message` `message` length (~2000 chars) | `coach_message/index.ts` | Oversized payload returns 400 |
| **1.2e** Move Supabase URL/key out of committed Swift source | `RunSmartSupabaseClient.swift`, xcconfig | No secrets in VCS Swift files |
| **1.2f** Complete `delete_account` wipe: `user_saved_routes`, `user_benchmark_routes` | `delete_account/index.ts` | Deleted user has zero rows in user tables |
| **1.2g** Surface partial deletion failures (207 or `warnings` in response) | `delete_account/index.ts` | Ops/client can detect incomplete wipe |

### Phase 1 PR order

```
PR-1: Identity (1.1b–1.1d) + tests
PR-2: Security (1.2a–1.2d, 1.2g)
PR-3: Account deletion completeness (1.2f) + config externalization (1.2e)
```

**Phase 1 exit criteria:** TestFlight smoke — sign in, connect Garmin, run sync, challenge enroll, delete account; no orphaned route rows.

---

## Phase 2 — P1: User-visible correctness

**Duration:** ~2–3 days

| ID | Task | Files | Verify |
|----|------|-------|--------|
| 2.1 | Real device disconnect | `SupabaseRunSmartServices.swift`, `GarminBridge` | Disconnect → reconnect works; tokens cleared |
| 2.2 | HealthKit authorization truth | `HealthKitSyncService.swift` | Deny permission → UI not connected |
| 2.3 | Garmin OAuth reliability | `GarminBridge.swift` | Bad callback fails; ephemeral session |
| 2.4 | Debrief timeout alignment | `SupabaseRunSmartServices.swift` | Client timeout ≥ server or async debrief |
| 2.5 | Stable run IDs from Garmin | `GarminMappers.swift` | Re-import → same report key |
| 2.6 | Surface Garmin/RLS errors | `SupabaseRunSmartServices.swift` | RLS failure visible in Settings |
| 2.7 | Remove hardcoded production Garmin gateway fallback | `GarminBridge.swift` | Missing config fails fast |

**Phase 2 exit criteria:** Settings Garmin/HealthKit flows honest; post-run debrief not always fallback.

---

## Phase 3 — P2: Performance

**Duration:** ~2 days

| ID | Task | Impact |
|----|------|--------|
| 3.1 | Deduplicate `planRepo.activePlan()` on Today load | High — 4× same query |
| 3.2 | Parallelize `latestRunReports` | High on Activity tab |
| 3.3 | Bulk HealthKit run upsert | Medium on first sync |
| 3.4 | Parallel Garmin route points | Medium on sync |
| 3.5 | Debounce Activity tab refresh | Medium — double fetch |
| 3.6 | Parallel `nearbyLoopRoutes` | Medium |
| 3.7 | DB indexes after EXPLAIN on prod | Medium at scale |

**Phase 3 exit criteria:** Today load uses one plan fetch; Activity refresh does not double-fetch.

---

## Phase 4 — P3: Cleanup

**Duration:** ~2–3 days

| ID | Task |
|----|------|
| 4.1 | Delete dead code: `fetchPostRunInsight`, `remotePostRunInsightLookupEnabled`, stub `finishRun` |
| 4.2 | Extract shared Garmin bucket logic |
| 4.3 | Split `SupabaseRunSmartServices.swift` by protocol |
| 4.4 | Split `SecondaryFlowView.swift` by scaffold |
| 4.5 | Gate/remove `LiveRunSmartServices` from release |
| 4.6 | Update `docs/architecture/technical-risks.md` |
| 4.7 | Harden `AhaMomentStore` (LIKE escape, error propagation) |

---

## Timeline

| Week | Focus |
|------|-------|
| W1 | Phase 0 + Phase 1 |
| W2 | Phase 2 + TestFlight smoke |
| W3 | Phase 3 |
| W4 | Phase 4 |

---

## Risk register

| Risk | Mitigation |
|------|------------|
| Identity migration breaks existing users | Feature flag; SQL backfill; test bigint + UUID accounts |
| Garmin gateway owned externally | Schedule backend change with 1.1c |
| RLS migration breaks client | Test without service role; rollback script |
| Large file splits cause conflicts | Do Phase 4 after feature freeze |

---

## Definition of done

- [ ] No critical review findings remain open
- [ ] Account deletion passes App Store / GDPR checklist
- [ ] Garmin + HealthKit connect/disconnect/sync behave honestly
- [ ] Today screen does not fan out redundant plan queries
- [ ] Xcode build + targeted tests green
- [ ] `tasks/lessons.md` updated with identity decision

---

## Recommended first PR

**Title:** `fix: scope Garmin route points by auth_user_id and fix challenge enrollment identity`

**Scope:** 1.2a + 1.1b only (no full gateway migration yet).

---

## Key file references

| Area | Path |
|------|------|
| Garmin OAuth / routes | `IOS RunSmart app/Services/Garmin/GarminBridge.swift` |
| Challenge enroll | `IOS RunSmart app/Services/Supabase/ChallengeRepository.swift` |
| Supabase client | `IOS RunSmart app/Services/Supabase/RunSmartSupabaseClient.swift` |
| Main services | `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift` |
| HealthKit | `IOS RunSmart app/Services/HealthKit/HealthKitSyncService.swift` |
| Account delete | `supabase/functions/delete_account/index.ts` |
| Coach AI | `supabase/functions/coach_message/index.ts` |
| Today perf | `IOS RunSmart app/Features/Today/TodayTabView.swift` |
| Activity perf | `IOS RunSmart app/Features/Activity/ActivityTabView.swift` |
