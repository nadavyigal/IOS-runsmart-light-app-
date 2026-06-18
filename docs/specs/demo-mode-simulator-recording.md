# Demo Mode for Simulator Recording

## Product Brief

RunSmart needs a safe way to record realistic iOS simulator demo videos when Apple Account validation blocks Sign in with Apple in Simulator. Demo Mode is a DEBUG-only local presentation path for showing app pages and flows. It must not authenticate with Apple, Supabase, Garmin, HealthKit, purchases, or production analytics.

## Scope

- Enable Demo Mode only in DEBUG builds through `DEMO_MODE=true`, `RUNSMART_DEMO_MODE=1`, `-RUNSMART_DEMO_MODE`, or the existing screenshot-mode alias.
- Skip real authentication and onboarding by creating a local demo session/user.
- Inject local no-network demo services.
- Show realistic data for Today, weekly plan, run reports, Garmin connected state, profile stats, recent runs, and recovery/insight recommendations.
- Prevent production analytics events, backend writes, purchases, real Garmin auth, HealthKit sync, and destructive account actions.

## Non-Goals

- Do not change production auth, onboarding, Supabase, Garmin, HealthKit, or App Store behavior.
- Do not make Demo Mode available in Release builds.
- Do not use Demo Mode as App Review account-cycle evidence.

## Development Stories

### Story 1: DEBUG Demo Flag and Local Session

As a demo recorder, I want to launch RunSmart directly into an authenticated local demo user so I can record app pages without Apple Account.

Acceptance:
- Demo Mode is DEBUG-only.
- Demo Mode can be enabled from launch args or environment variables.
- The app opens past Sign in with Apple and onboarding.
- Release builds cannot enable Demo Mode.

### Story 2: Complete No-Network Demo Data

As a demo recorder, I want realistic app state across Today, Plan, Report, Profile, and connected devices so videos look production-like.

Acceptance:
- Demo services return coherent local data for core screens.
- Garmin and HealthKit show demo connected/synced states.
- Run reports can open without backend generation.
- Write/destructive service calls do not touch production.

### Story 3: Safeguards and Recording QA

As the release owner, I want clear safeguards and a QA checklist so Demo Mode cannot pollute production or be mistaken for release evidence.

Acceptance:
- Analytics remains null in Demo Mode.
- Account deletion/sign-out/destructive flows are disabled or local-only.
- A QA checklist documents launch and recording steps.

