# Clean-install telemetry integrity repair

Date: 2026-07-21
Status: Implemented and verified for 1.1.2 (26) release
Source: Public RunSmart 1.1.1 (25) physical App Store session, PostHog project 171597

## Story

As the RunSmart maintainer, I need the clean unauthenticated install path to preserve build identity and emit one lifecycle result per real user action, so activation rates can be trusted before the next activation experiment.

## Production evidence

The public physical session at `2026-07-21T07:27:24Z`–`07:29:10Z` showed:

1. SDK `$app_version = 1.1.1` / `$app_build = 25`, but the intended unprefixed `app_version` / `app_build` super properties were absent from every public unauthenticated-path event. The same properties were present on the prior authenticated sideload verification.
2. `onboarding_started` fired twice in one PostHog session/person (`07:27:34.982Z`, `07:28:58.681Z`) against one `onboarding_completed`, despite the 1.1.1 direct-call guard.
3. Notification permission emitted `permission_requested` twice, then `permission_denied` and `permission_granted` 39 ms apart. Multiple callers can concurrently observe `.notDetermined` and call the system authorization API.

## Scope

- Preserve/re-register the unprefixed build identity after analytics user reset without preserving user identity.
- Make `onboarding_started` once per onboarding lifecycle across the real SwiftUI completion/remount transition, while still allowing a genuinely new lifecycle when the user begins a distinct sign-in attempt.
- Serialize notification authorization through one in-flight request so concurrent callers share one system prompt result and analytics emits one request plus one terminal outcome.
- Add integration-level regression tests for all three production shapes.

## Out of scope

- No event-name changes, dashboard changes, backend changes, dependencies, production configuration, deployment, upload, or App Store submission.
- No onboarding redesign, authentication architecture change, S2 work, or Experiment E1.
- No attempt to treat founder/test traffic as a clean activation cohort.

## Acceptance criteria

1. After `Analytics.resetUser()`, the analytics SDK is anonymous but `app_version` / `app_build` are registered again before subsequent events.
2. Repeated onboarding appearance during one lifecycle emits one `onboarding_started`; a distinct sign-in-wall attempt permits one new start.
3. Two concurrent notification-authorization callers cause one underlying authorization request and receive the same result; analytics emits one `permission_requested` and exactly one matching granted/denied terminal.
4. Existing plan-generation terminal deduplication remains green.
5. Focused regression tests and the full iOS suite pass.

## S0 status

Founder confirmed the Apple ID used for the public 1.1.1 attempt had never authorized RunSmart. S0 is **PASS** based on the matching physical App Store `sign_in_completed` event at `2026-07-21T07:27:35.933Z`, correct SDK version/build attribution, no sign-in failure, and no app-supplied sensitive user data. The session remains excluded founder verification traffic for activation-rate decisions.
