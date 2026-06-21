---
product: RunSmart iOS
artifact: PRD
feature: Garmin readiness
status: approved
founder-review-needed: no
date: 2026-06-20
owner: Nadav Yigal
source-repo: /Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app
---

# PRD: Garmin Readiness

## 1. Summary

RunSmart needs a production readiness gate for Garmin before any hard-to-reverse Garmin-facing release is treated as safe. This PRD defines the minimum user, data, privacy, analytics, and release evidence required for Garmin connection, import, wellness readiness, and PostHog proof.

This is a pre-code PM artifact. It should feed one implementation or QA story at a time. It does not replace the planning protocol, tests, physical-device smoke, or release pre-mortem.

## 2. Contacts

| Name | Role | Comment |
|---|---|---|
| Nadav Yigal | Founder, product owner | Reviews and approves scope, release gate, and final go/no-go. |
| Codex | PM drafting agent | Drafted this PRD from repo evidence and existing RunSmart operating rules. |
| Future implementation agent | Engineering executor | Uses the approved PRD as input to a scoped implementation or QA plan. |

## 3. Background

RunSmart is live on the App Store. Current repo state says v1.0.2 build 15 is live, and v1.0.3 build 16 is ready for archive/TestFlight upload. Garmin already appears in multiple production paths:

- Native Garmin OAuth uses `runsmart://garmin/callback` through `ASWebAuthenticationSession`.
- The app polls `garmin_connections` until the connection is marked connected.
- Garmin activities feed recent activities, route details, reports, route saving, and run analytics.
- Garmin daily metrics feed recovery, wellness, morning check-in approval, and 7-day HRV/readiness trend surfaces.
- Supabase grants for Garmin worker/job RPCs were tightened live and documented in a migration.
- PostHog project 171597, "Running coach", has live activation and run events, but no build 16 events yet.

Why now: Garmin is a trust-heavy integration. A broken connection, stale wellness data, duplicate imports, exposed worker functions, or missing analytics can make the app feel unsafe or unreliable. The current production gate still needs physical TestFlight confirmation that build 16 can sign in, onboard, generate a plan, connect or sync Garmin where applicable, start a run, and emit the expected analytics.

## 4. Objective

The objective is to make Garmin readiness a clear release gate, not a vague "seems okay" check.

This matters because runners will trust Garmin data only if RunSmart handles it consistently, privately, and honestly. The company benefit is lower App Review risk, fewer post-launch support surprises, and better evidence before investing more in Garmin-first coaching.

### Key Results

1. By the next Garmin-facing release decision, one physical-device TestFlight smoke on build 16 or later confirms sign-in, onboarding, plan generation, run start, and the expected PostHog events in project 171597.
2. Before Garmin production expansion, one authenticated iOS Garmin connection flow confirms `garmin_connections.status == connected` and token records are created without requiring public/authenticated access to worker RPCs.
3. Before using Garmin readiness as a coaching signal, the app shows fresh Garmin data only when available and falls back to manual check-in or Apple Health without fake readiness values.
4. Before release approval, a pre-mortem exists for Garmin readiness and every launch-blocking Tiger has an owner and mitigation.
5. Within the first 7 days after release, PostHog shows at least one full successful Garmin-adjacent activation path for build 16 or later, or the release is treated as needing investigation.

## 5. Market Segments

### Primary segment

Runners who use Garmin and want RunSmart to turn training history and wellness signals into simple daily guidance.

Their job: "Help me know whether I should run today, how hard to go, and whether my recent training is on track."

### Secondary segment

Runners without Garmin, or with only Apple Health/HealthKit data.

Their job: "Let me use RunSmart without being punished for not connecting Garmin."

### Constraints

- RunSmart must not use medical diagnosis, injury prediction, or overconfident health language.
- Garmin data can be missing, stale, sparse, or route-less.
- Sign in with Apple and HealthKit App Review rules remain active risks.
- Physical-device smoke is required because local simulator SIWA has previously failed with `ASAuthorizationError 1000`.
- No new dependencies or service changes should be introduced by this PRD.

## 6. Value Propositions

### For Garmin-connected runners

- They can connect Garmin and see RunSmart use real activity and wellness context.
- They can trust that RunSmart imports supported runs without duplicate or fragment clutter.
- They can approve fresh Garmin readiness for morning check-in instead of manually entering the same signal.
- They can see HRV and readiness trends without fake placeholder charts.

### For non-Garmin runners

- They still get a working RunSmart experience through manual check-in, Apple Health, GPS runs, and plan behavior.
- They do not see false Garmin claims or empty promises.

### For the business

- Garmin becomes a credible differentiation layer instead of a fragile integration.
- Release decisions become evidence-backed.
- The team avoids overbuilding Garmin coaching before connection, import, and analytics proof are stable.

## 7. Solution

### 7.1 UX and user flow

The readiness gate covers these user-visible flows:

1. Sign in with Apple.
2. Finish onboarding without asking for name or email.
3. Generate a plan.
4. Open Profile or connected services.
5. Connect Garmin from iOS.
6. Return to RunSmart through the `runsmart://garmin/callback` app callback.
7. See Garmin connection status become connected.
8. Sync or view Garmin activity/wellness data.
9. Approve Garmin readiness only if metrics are fresh enough.
10. Fall back to manual check-in when Garmin data is missing or stale.

No new UI build is required unless the smoke finds a blocking gap. If a gap is found, it must become one scoped story.

### 7.2 Key features and requirements

#### Connection readiness

- Garmin OAuth starts only for an authenticated user.
- iOS uses the registered `runsmart://` callback scheme.
- The callback POSTs the returned `code` and `state` to the gateway callback endpoint.
- The app waits for `garmin_connections.status == connected` before claiming success.
- Failed or canceled connection returns clear non-scary copy.

#### Import readiness

- Supported Garmin activities import or display through the same normalization, hidden-run, fragment, and route handling rules as existing run flows.
- Duplicate Garmin rows do not create duplicate user-facing activities.
- Route-less Garmin activities still allow run reports where possible, with honest route limitations.
- Garmin activities are hidden in RunSmart when removed from RunSmart, not deleted from Garmin.

#### Wellness and readiness readiness

- Latest Garmin metrics can populate recovery and wellness snapshots.
- Garmin readiness approval saves a morning check-in only when Garmin metrics are fresh enough.
- Manual check-in remains available when Garmin metrics are stale, missing, or disconnected.
- 7-day HRV and readiness trends use real Garmin daily metrics.
- Readiness trend display prefers Garmin `training_readiness` when present and falls back to `body_battery` only for trend display.
- No fake wellness charts are shown for sparse or missing Garmin data.

#### Security and privacy readiness

- Garmin worker/job RPCs remain executable only by intended privileged roles.
- App-facing views enforce owner-scoped access.
- No API keys, bearer tokens, demo credentials, or personal identifiers are written to repo docs.
- User-facing copy avoids medical diagnosis and overconfident claims.

#### Analytics readiness

PostHog project 171597 must be the source of truth for launch evidence. Required events for build 16 or later:

- `app_launched`
- `sign_in_completed`
- `onboarding_started`
- `onboarding_completed`
- `plan_generated`
- `run_started`
- `run_completed`, when a run is completed
- `garmin_connect_tapped`, when Garmin connect is attempted
- `garmin_sync_completed`, when Garmin sync completes

Build-specific verification should confirm the current version/build is present in event properties or available event context.

### 7.3 Technology

Current implementation surfaces to preserve:

- `GarminBridge.swift` handles native OAuth, callback completion, connection polling, recent activities, latest daily metrics, and 7-day metrics.
- `SupabaseRunSmartServices.swift` maps Garmin data into recovery, wellness, morning check-in approval, training load, and recent activity behavior.
- `AnalyticsEvents.swift` contains activation, run, Garmin connect, and Garmin sync events.
- Supabase migrations document Garmin activity RLS and restricted worker/job RPC grants.
- `docs/specs/e7-garmin-wearable-depth.md` defines existing 7-day HRV/readiness trend behavior.

### 7.4 Assumptions

- Build 16 uses RunSmart PostHog project 171597, not ResumeBuilder project 270848.
- The Garmin gateway production deployment still matches the native callback contract.
- Existing Garmin token records and `garmin_connections` rows are enough to prove connection success without exposing secrets.
- Garmin wellness data freshness can be validated with the existing `isFreshMorningMetricDate` behavior.
- No new Garmin backend schema is required for this readiness pass.
- The current dirty local files belong to another in-progress production gate and should not be changed by this PRD.

## 8. Release

### First version of this readiness gate

The first version is a QA and release-readiness story, not a new feature build. It should produce:

1. Physical-device TestFlight smoke evidence for build 16 or later.
2. PostHog event proof from project 171597.
3. Garmin connection proof from production records.
4. Confirmation that Garmin readiness gracefully falls back when stale or unavailable.
5. A Garmin readiness pre-mortem before release approval.

### Future versions

Future work can add richer Garmin-specific coaching only after the gate passes. Possible later stories:

- Better user-facing Garmin sync diagnostics.
- More explicit freshness labels for wellness metrics.
- Garmin readiness analytics for trend-card views and approval attempts.
- Stronger support tooling for failed Garmin connection states.

### Out of scope

- New paid plans, subscriptions, or StoreKit changes.
- New Garmin API scopes.
- New analytics providers.
- Broad UI redesign.
- Production migrations beyond already documented Garmin grant/RLS fixes.
- App Store submission without founder approval.

## Approval Checklist

- [x] Founder reviews and edits this PRD.
- [x] Founder changes `status` from `draft` to `reviewed` or `approved`.
- [ ] User stories are created from this PRD before implementation.
- [ ] Pre-mortem is completed before any high-stakes Garmin release.
- [ ] One story is selected for execution.
