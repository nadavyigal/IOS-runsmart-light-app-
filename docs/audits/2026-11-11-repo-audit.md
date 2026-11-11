# Repo audit: RunSmart iOS, 2026-11-11

Branch `claude/2026-11-11-ios-repo-audit`, from `main` at 8f35e73.

## Secrets

No leaked credentials. The only key in tracked files is the PostHog client key in `RunSmartConfig.xcconfig`, which is public by design and committed on purpose (the file says why).

## Fixed in this branch

| What | Why it was safe |
|------|-----------------|
| Deleted 4 views no screen reaches: `PersonalRecordsCard`, `RouteCardView` (+ `RouteEmptyStateView`), `ReadinessHeroView`, `TodayWorkoutCard` | Reachability walk from `@main` plus `git grep -w` on every type: zero references, no tests. Last touched 2026-04-30 to 2026-07-15 |
| Moved `STATUS_REPORT.md` and `VS_AGENT_REPORT.md` out of the `.xcodeproj` bundle to `docs/archive/` | Project bundles are not a docs folder; Xcode ignores them |

## For your review (not changed)

1. **22 app-target concurrency warnings, 2 of them errors in Swift 6 mode**: `RunSessionCheckpoint.swift:95` (main-actor `Encodable` used off the main actor) and `StravaUploadCoordinator.swift:127`. The rest are main-actor statics called from nonisolated code (Strava, LocalRunCueService, Analytics, TrainingLoadView). Recommend: one focused PR; each fix is `nonisolated` on a pure helper or a hop to the main actor, and needs a test where it touches run recording.
2. **`Services/Live/LiveRunSmartServices.swift` + `RunSmartLiveMappers.swift` are unused stubs** ("Live endpoint not wired yet. This payload shape is the planned contract."). Someone still edited them on 2026-10-23 to keep them compiling. Recommend: delete unless the live API contract is coming back.
3. **`tasks/progress.md` 263 KB, `session-log.md` 250 KB, `todo.md` 193 KB.** Every session that reads them burns context. Recommend: archive history, keep the six-field top entry.
4. **377 files in `docs/`**, many dated 2026-05 (`runsmart-lite-*`, readiness status). Recommend: archive what describes a past state.
5. **This repo is a submodule of RunSmart web** (`apps/ios-native`, pinned to branch `runsmart-lite-build`). Recommend: confirm that pin is still wanted; it drifts silently.
