# Production Error Sweep - 2026-06-19

## Summary

- Scope: RunSmart iOS live App Store build v1.0.3 build 16, report-only production error/risk sweep.
- Time window: PostHog last 7 days; Supabase MCP logs last 24 hours only; static Swift audit current working tree.
- Sources queried: `~/.claude/ERRORS.md`, `tasks/lessons.md`, `tasks/progress.md`, PostHog MCP, Supabase MCP `get_logs` for `api`, `postgres`, `auth`, `edge-function`, Supabase `get_advisors` security/performance, and targeted Swift scans.
- Known-source gaps: `tasks/ERRORS.md` does not exist in this repo. `tasks/progress.md` is stale and says v1.0.2 build 15; this report trusts v1.0.3 build 16 per production reality.
- Errors seen: PostHog Error Tracking returned 0 active/all issues for the last 7 days; direct `$exception` event query returned 0 rows. One custom failure-like PostHog event was present: `ats_checker_rate_limited` = 1 event / 1 user, likely stale/non-RunSmart taxonomy.
- Distinct clusters: 8 total risk/error clusters. Actionable: 6. High/Critical: 1 High, 0 Critical.

## Ranked Table

| Severity | Issue | Count(7d) | Users affected | Source | Root cause (file:line) | Suggested fix |
|---|---:|---:|---:|---|---|---|
| High | RunSmart activation/run funnel is effectively blind after launch/sign-in: `app_launched`=53/17 users and `sign_in_completed`=5/4 users, but no observed `onboarding_*`, `plan_generated`, `plan_viewed`, `run_started`, `run_completed`, or `tab_viewed` rows. | 0 observed for critical funnel events | Unknown; up to 17 launched users are unobservable past sign-in | PostHog + static | Events are defined in `IOS RunSmart app/Services/Analytics/AnalyticsEvents.swift:17`, `:28`, `:36`, `:45`, `:49`, `:121`, `:152`; setup at `IOS RunSmart app/App/RunSmartLiteAppShell.swift:401` | Verify production PostHog token/project and add a release smoke that confirms these events arrive for v1.0.3. |
| Medium | `coach_message` edge function had a 400 response; app falls back silently/near-silently for post-run debrief, weekly summary, and flex-week AI paths. | Supabase logs: 1 edge 400 in last 24h sample | Not exposed by Supabase log sample | Supabase edge logs + static | Shared endpoint calls at `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift:1191`, `:1313`, `:1400`; fallback logging only at `:1228`, `:1357`, `:1429` | Split typed coach endpoints or include explicit request kind/schema validation and track failure events. |
| Medium | Account deletion produced partial-success signal: `delete_account` returned 207 and auth `/logout` returned 403 after server-side user deletion. This may be expected but is noisy on an App Store-critical flow. | Supabase logs: 1 edge 207 + 1 auth 403 in last 24h sample | Not exposed by Supabase log sample | Supabase edge/auth logs + static | `deleteAccount()` checks `success == true`, reloads profile, and local sign-out can hit a deleted auth user at `IOS RunSmart app/Services/Supabase/SupabaseSession.swift:282`, `:288`, `:300` | Treat confirmed profile deletion as idempotent success and emit an aggregate deletion outcome event. |
| Medium | App can hard-crash at launch if Supabase config is missing, unsubstituted, or invalid; no crash reporter exists to quantify this from here. | Unknown | Unknown | Static | `fatalError` in `IOS RunSmart app/Services/Supabase/RunSmartSupabaseClient.swift:8`, `:12`, `:18` | Replace release `fatalError` with a controlled unavailable-state screen plus one-shot diagnostic event. |
| Medium | Supabase security advisors show exposed SECURITY DEFINER RPCs, including Garmin worker/job functions executable by anon/authenticated roles. | Advisor findings: multiple WARNs | Not user-counted | Supabase security advisors | Database grants/policies, no Swift line. Related app paths call Garmin/job surfaces through Supabase services. | Revoke public execute on worker/job RPCs; keep only service-role/cron access. |
| Low | Training plan/profile lookup errors are printed and converted to `nil` or empty arrays, so a backend/RLS outage can look like "no plan" instead of an error. | Static only | Unknown | Static | `IOS RunSmart app/Services/Supabase/TrainingPlanRepository.swift:184`, `:258`, `:290`, `:322`, `:350` | Return typed load states and track plan load failures by category. |
| Low | Route persistence and benchmark remote writes use `try?`; local state succeeds even if Supabase sync fails. | Static only | Unknown | Static | `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift:775`, `:784`, `:796`, `:825`, `:849` | Queue retryable route sync failures and show/signal unsynced state. |
| Low | Voice coach fetch/audio failures silently return, making voice guidance look disabled without telemetry. | Static only | Unknown | Static | `IOS RunSmart app/Services/VoiceCoachService.swift:102`, `:106`, `:113`, `:128` | Add non-PII voice cue failure counters and visible fallback state. |

## Static-Audit Findings

- Silent/print-only catch on auth profile load: `IOS RunSmart app/Services/Supabase/SupabaseSession.swift:131` sets `lastAuthError` but only prints backend detail. This is acceptable for UI privacy but leaves no aggregate production failure event.
- Onboarding save failure path: `IOS RunSmart app/Services/Supabase/SupabaseSession.swift:189` falls back to a legacy profile upsert; final failure at `:214` sets a generic error and prints only.
- Account deletion network/edge failures: `IOS RunSmart app/Services/Supabase/SupabaseSession.swift:265` and `:282` handle profile-gone success, but partial edge outcomes are not measured.
- Training plan reads swallow backend/RLS failures into empty product states: `IOS RunSmart app/Services/Supabase/TrainingPlanRepository.swift:258`, `:290`, `:322`, `:350`.
- Route sync remote failures are dropped after local success: `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift:778`, `:788`, `:801`, `:842`, `:853`.
- AI coach/post-run failures intentionally degrade to fallback but do not emit failure analytics: `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift:1141`, `:1228`, `:1357`, `:1429`.
- HealthKit/Garmin wellness reads return nil on errors: `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift:1820`, `:1833`, `:1902`.
- Generated route directions failures return nil silently: `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift:2206`.
- Voice coach network/audio failures are silent `try?`/guard exits: `IOS RunSmart app/Services/VoiceCoachService.swift:89`, `:90`, `:106`, `:113`, `:128`.
- Force/crash audit: no `try!` was found in the targeted paths. One force unwrap exists in a static fixture UUID, not a network/user path: `IOS RunSmart app/Services/Supabase/ChallengeRepository.swift:16`. Production-critical `fatalError` exists in Supabase config loading at `IOS RunSmart app/Services/Supabase/RunSmartSupabaseClient.swift:8`, `:12`, `:18`.

## Telemetry Gaps

- App Store Connect/Xcode Organizer crash data is not reachable from this environment. This sweep cannot report real crash counts, crash-free sessions, termination reasons, watchdog kills, or device/OS crash distribution.
- No Sentry/Crashlytics is installed. PostHog-ios analytics is present, but PostHog Error Tracking returned 0 issues and direct `$exception` queries returned 0 rows.
- PostHog appears mixed/stale for this project: last-7-day events include ResumeBuilder-era events (`resume_uploaded`, `job_added`, `optimization_*`, `ats_*`) and lack most RunSmart-defined funnel events. This blocks reliable onboarding -> plan -> run drop-off diagnosis.
- Supabase MCP `get_logs` returns only a recent sample/last 24 hours, not the requested full 7-day backend window. Counts from Supabase logs should be treated as observed samples, not full-period totals.
- Supabase logs include sensitive raw request details; this report intentionally uses aggregate counts only and omits raw identifiers, emails, IPs, tokens, and full URLs.
- There are no custom production failure events for plan load failures, AI fallback, route sync failures, HealthKit/Garmin import failures, or voice cue failures. Most static failures currently become `print`, fallback UI, `nil`, or empty arrays.

## Recommended Next Action

Fix production observability first: confirm v1.0.3 build 16 is sending RunSmart-specific PostHog events to the intended project, then add aggregate non-PII failure events for onboarding save, plan load, run save/sync, coach fallback, and account deletion outcomes. This should come before deep product fixes because the current telemetry cannot prove whether D7 retention risk is caused by crashes, onboarding drop-off, missing plans, or silent backend fallback.
