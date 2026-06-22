---
product: RunSmart iOS
artifact: story-execution
feature: Garmin readiness
story: 1
story-title: Physical TestFlight Garmin Readiness Smoke
status: awaiting-founder-smoke
founder-review-needed: yes
date: 2026-06-20
updated: 2026-06-21
source-user-stories: tasks/user-stories-garmin-readiness-2026-06-20.md
founder-run-sheet: tasks/story-1-garmin-readiness-smoke-FOUNDER-RUN.md
---

# Story 1 Execution: Physical TestFlight Garmin Readiness Smoke

## Objective

Run one physical-device TestFlight smoke for build 16 or later so Garmin readiness is backed by real release evidence before production expansion.

## Local Repo Checks Completed

- Source version/build is `1.0.3 (16)` in `IOS RunSmart app.xcodeproj/project.pbxproj`.
- Required analytics hooks exist in source:
  - `app_launched`
  - `sign_in_completed`
  - `onboarding_completed`
  - `plan_generated`
  - `run_started`
  - `run_completed`
  - `garmin_connect_tapped`
  - `garmin_sync_completed`
- Static scan did not find onboarding text fields for `Your name`, `Name`, `Email`, or `Your email`.
- Sign in with Apple requests `.fullName` and `.email` through AuthenticationServices and passes Apple-provided values into the session path.

## Physical TestFlight Smoke Checklist

- [ ] Install TestFlight build 16 or later on a physical iPhone.
- [ ] Launch the app fresh.
- [ ] Complete Sign in with Apple.
- [ ] Confirm onboarding does not ask for name or email.
- [ ] Finish onboarding.
- [ ] Generate a plan.
- [ ] Start a run.
- [ ] Complete a run if feasible.
- [ ] Attempt Garmin connect if the test account/device state allows it.
- [ ] Confirm PostHog project 171597 shows the tested build events:
  - [ ] `app_launched`
  - [ ] `sign_in_completed`
  - [ ] `onboarding_completed`
  - [ ] `plan_generated`
  - [ ] `run_started`
  - [ ] `run_completed`, if a run is completed
  - [ ] `garmin_connect_tapped`, if Garmin connect is attempted
  - [ ] `garmin_sync_completed`, if Garmin sync completes

## Result

**Awaiting founder physical-device smoke.** Local repo checks complete (see below). Founder run sheet: `tasks/story-1-garmin-readiness-smoke-FOUNDER-RUN.md`.

Agent cannot operate TestFlight UI, Apple sign-in on device, or live run flow. Share the "Share back" block from the run sheet after testing — agent will mark Story 1 complete and route to Story 2/5/6.

## Evidence Needed To Complete

Add a short dated note here or in `tasks/todo.md` with:

- Build number tested.
- Device type, without personal identifiers.
- Whether SIWA completed.
- Whether onboarding skipped name/email collection.
- Whether plan generation completed.
- Whether run start completed.
- Whether run completion was feasible.
- Whether Garmin connect/sync was attempted.
- PostHog project 171597 event summary.

Do not include tokens, raw secret-bearing logs, personal device identifiers, emails, or screenshots with personal account data.

## Next Story Routing

- If Garmin connect was not completed in Story 1, run Story 2 next.
- If Garmin connect was completed but analytics were missing, run Story 5 next.
- If all Story 1 acceptance criteria pass, run Story 6 pre-mortem before any high-stakes Garmin production expansion.
