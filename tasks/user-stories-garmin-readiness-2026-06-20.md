---
product: RunSmart iOS
artifact: user-stories
feature: Garmin readiness
status: approved
founder-review-needed: no
date: 2026-06-20
source-prd: tasks/prd-garmin-readiness-2026-06-20.md
design: Existing RunSmart iOS screens and docs/specs/e7-garmin-wearable-depth.md
---

# User Stories: Garmin Readiness

These user stories break the approved Garmin readiness PRD into implementation-ready slices. They are pre-code PM artifacts. Pick one story, write an implementation plan, then execute only that story.

## Story 1: Physical TestFlight Garmin Readiness Smoke

**Description:** As the founder, I want one physical-device TestFlight smoke for build 16 or later, so that Garmin readiness is backed by real release evidence before production expansion.

**Design:** Existing Sign in, onboarding, Plan, Run, Profile, Connected Services, and PostHog evidence flow.

**Conversation:**
This is the first story because it proves the release path without changing product code. The smoke should confirm the current build can sign in, complete onboarding, generate a plan, start a run, and emit the required analytics to PostHog project 171597. Garmin connection is included when the test account and device state allow it. If Garmin cannot be tested in the same pass, the reason must be recorded and Story 2 becomes the next story.

**Acceptance Criteria:**
1. The smoke is run on a physical device using TestFlight build 16 or later.
2. Sign in with Apple completes without asking the user for name or email in onboarding.
3. Onboarding completes and a plan is generated.
4. A run is started, and a completed run is recorded when feasible.
5. PostHog project 171597 shows `app_launched`, `sign_in_completed`, `onboarding_completed`, `plan_generated`, and `run_started` for the tested build.
6. Results are documented in `tasks/todo.md` or a dated QA artifact without secrets, tokens, personal identifiers, or raw logs.

## Story 2: Garmin Connection Proof

**Description:** As a Garmin-connected runner, I want Garmin connection to complete inside RunSmart, so that I know the app can use my Garmin data reliably.

**Design:** Existing Profile connected-services flow and native Garmin OAuth callback.

**Conversation:**
This story verifies the production Garmin OAuth contract. It should prove that the app starts OAuth for an authenticated user, receives the `runsmart://garmin/callback`, completes the gateway callback exchange, then waits until `garmin_connections.status == connected`. The story is verification-first. It should not add a new Garmin UX unless the flow fails and a specific fix is needed.

**Acceptance Criteria:**
1. Tapping Garmin connect from iOS starts the Garmin OAuth flow for an authenticated user.
2. The callback returns through the registered `runsmart://garmin/callback` scheme.
3. The app completes the callback exchange with the Garmin gateway.
4. Supabase shows a production `garmin_connections` row for the test user with `status == connected`.
5. The app does not claim success until the connected status is observed.
6. Any failure is recorded with a concise user-facing symptom and a scoped follow-up, not broad speculation.

## Story 3: Garmin Import And Duplicate Safety

**Description:** As a runner with Garmin activities, I want imported Garmin runs to appear once and behave like normal RunSmart runs, so that my activity history stays trustworthy.

**Design:** Existing Activity, Report, route detail, and Garmin activity surfaces.

**Conversation:**
This story protects trust in the activity feed. Garmin activities should go through existing normalization, hidden-run, fragment, route, and report behavior. The goal is not to build new import features. The goal is to prove that Garmin data does not create duplicates, fake routes, or confusing delete behavior.

**Acceptance Criteria:**
1. Recent Garmin activities display newest-first through existing normalized activity behavior.
2. Duplicate Garmin rows do not create duplicate user-facing activities.
3. Route-less Garmin runs still show honest report behavior without fake map data.
4. Hiding or removing a Garmin activity in RunSmart does not imply deletion from Garmin.
5. Existing Garmin mapper/import tests or equivalent focused validation cover duplicate and route-less cases.
6. The story does not change unrelated HealthKit, GPS, or manual-run behavior.

## Story 4: Fresh Garmin Readiness Approval

**Description:** As a Garmin-connected runner, I want to approve Garmin readiness only when the data is fresh, so that RunSmart does not make today’s training decision from stale wellness data.

**Design:** Existing Morning Check-in, Recovery, Wellness, and Today readiness surfaces.

**Conversation:**
This story guards against stale or missing wellness data. If Garmin metrics are fresh, the app can offer an approval path. If the metrics are stale, missing, or disconnected, manual check-in remains the safe fallback. This keeps Garmin readiness useful without pretending it is always available.

**Acceptance Criteria:**
1. Fresh Garmin metrics can populate the recovery and wellness snapshots.
2. Garmin readiness approval saves a morning check-in only when metrics pass the freshness rule.
3. Stale or missing Garmin metrics show the manual check-in path instead of silently approving.
4. No wellness chart or readiness value is fabricated when Garmin data is sparse or unavailable.
5. Copy avoids medical diagnosis, injury prediction, and overconfident health claims.
6. Focused validation covers fresh, stale, missing, and disconnected Garmin states.

## Story 5: Garmin Readiness Analytics Proof

**Description:** As the founder, I want Garmin readiness events to appear in the correct PostHog project, so that launch decisions use real product evidence.

**Design:** Existing PostHog project 171597 and `AnalyticsEvents.swift`.

**Conversation:**
This story validates the analytics layer around the Garmin readiness gate. The correct project is 171597, "Running coach." The story should not add a new analytics provider or broad event taxonomy. It should prove the required activation, run, Garmin connect, and Garmin sync events for the tested build.

**Acceptance Criteria:**
1. Build 16 or later emits events to PostHog project 171597, not project 270848.
2. `garmin_connect_tapped` fires when the user attempts Garmin connection.
3. `garmin_sync_completed` fires when Garmin sync completes, with imported and skipped counts.
4. Activation events for sign-in, onboarding, plan generation, and run start are visible for the same tested build.
5. Event evidence is summarized without exposing tokens, direct personal identifiers, or raw secret-bearing logs.
6. Missing events produce one scoped follow-up story rather than a broad analytics rewrite.

## Story 6: Garmin Production Pre-Mortem

**Description:** As the founder, I want a pre-mortem before Garmin production expansion, so that launch-blocking risks are named before they hurt users.

**Design:** Use the PM `pre-mortem` skill against the approved Garmin readiness PRD and these user stories.

**Conversation:**
This story is mandatory before any high-stakes Garmin release decision. It should classify Tigers, Paper Tigers, and Elephants. Launch-blocking Tigers need owners and mitigations before approval. This story does not ship code by itself, but it can create follow-up implementation stories.

**Acceptance Criteria:**
1. A dated pre-mortem artifact is created under `tasks/`.
2. Risks are categorized as Tigers, Paper Tigers, and Elephants.
3. Each launch-blocking Tiger has a mitigation, owner, and completion or decision date.
4. The pre-mortem explicitly covers Garmin OAuth, data freshness, duplicate imports, privacy/security grants, App Review risk, and analytics proof.
5. Release approval is blocked until launch-blocking Tigers are closed or explicitly accepted by the founder.
6. Follow-up work is split into one story at a time.

## Recommended Execution Order

1. Story 1: Physical TestFlight Garmin Readiness Smoke.
2. Story 2: Garmin Connection Proof, if not fully covered by Story 1.
3. Story 5: Garmin Readiness Analytics Proof.
4. Story 4: Fresh Garmin Readiness Approval, if smoke exposes freshness confusion.
5. Story 3: Garmin Import And Duplicate Safety, if Garmin activity data is part of the release claim.
6. Story 6: Garmin Production Pre-Mortem before any high-stakes release approval.

## Approval Checklist

- [x] Founder reviews these user stories.
- [x] Founder changes `status` from `draft` to `reviewed` or `approved`.
- [x] One story is selected for execution.
- [ ] Implementation plan is written for the selected story only.
- [ ] Pre-mortem runs before Garmin production expansion.
