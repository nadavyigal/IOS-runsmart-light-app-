# RunSmart iOS Activation Cliff: Evidence and Fix Plan

Date: 2026-07-19 (amended same day after the 1.1.0 submission; see Status below)
Source: live PostHog reads, project 171597 ("Running coach"), 90-day window, read 2026-07-19. All numbers below are founder/QA-excluded unless labeled RAW. Investigation only; no code changed in this session.

## Status vs the submitted build (added 2026-07-19, post-submission)

**1.1.0 (24) is in App Store review (public: 1.0.9 build 23) and contains NONE of this plan.** It ships Adaptive Coach Phase 1 flag-ON (`c6e75c1`, PR #102). Verified against `origin/main` (last commit `0365816`, 2026-07-19 13:49): no `sign_in_wall_*` events exist, `SignInView.swift` and `RunSmartLiteAppShell.swift` are unchanged, no guest path. Consequence: **Adaptive Coach Phase 2's own gate (2 weeks live + >=20 real `adaptive_coach_shown` users) cannot fill while ~96% of installs die on the wall before the Today tab exists for them.** S1 below should be the first content of the next build (1.1.1), not queued behind other work.

## The headline number

**22 of 23 real App Store users (95.7%) produced zero events after app open and never started onboarding.** The sign-in wall is the leading explanation, not yet a directly measured one: it is provably the first screen every unauthenticated user sees (code path below) and it is uninstrumented, so "refused to sign in", "sign-in attempt failed silently", and "app hung" cannot be separated until S1 ships. 1 of 23 started and completed onboarding; 0 of 23 ever started a run. D7 activation for the mature clean cohort (first seen 2026-06-19 to 2026-07-12, n=19): **0%**.

## Cohort construction (measured)

Raw 90d: 76 installs / 78 opened / 12 onboarding-completed people / 9 plan people / 3 run-started people. These raw counts match the 2026-07-19 dashboard read but are dominated by founder and QA traffic.

Excluded, per the standing exclusion rules (memory: posthog-founder-account-exclusion):

- Founder/dogfood devices (>=6 sessions or >=3 app versions): `3e1b84b3` (911 events, 56 sessions, 1.0 to 1.0.2), `535caef6` (1,099 events, 58 sessions, 7 versions, 1.0.2 to 1.0.9), `0efa0d1b` (42 sessions, 6 versions), `f40fc161` (11 sessions, 5 versions).
- 2026-06-24 QA cluster on 1.0.4, 10-15 sessions each, zero onboarding: `edec8f9a`, `9dc02c76`, `3772ba89`, `d08f2cbb`.
- 2026-07-15 09:21-09:27 sign-in-debug pair (`03766171`, `26140ca4`, all 5 `sign_in_failed` events in the project belong to this window).
- `a7cd39a2` (1.0.9, 07-16): completed onboarding + plan same evening founder devices were verifying 1.0.9. Labeled founder-verification-suspect. If it is a real user, see "first-run CTA" below; conclusion does not change.
- `7b6c448e` (1.0.7, 07-09): 13 sessions, 4 rageclicks, `onboarding_step_completed` x6 with no `onboarding_started`. Excluded by the >=6-session rule but flagged: could be a real frustrated user.
- Install burst pair `ee0b105d`/`273b83ad` (07-12, 35 seconds apart).
- All pre-App-Store traffic (first version 1.0/1.0.1/1.0.2 or first seen before 2026-06-19; first live App Store build was 1.0.3 on 2026-06-19).

Remaining organic App Store cohort: **23 users** (2026-06-19 to 2026-07-19).

## Funnel (clean, measured)

| Step | People | % of cohort |
|---|---|---|
| Installed + opened | 23 | 100% |
| onboarding_started | 1 | 4.3% |
| onboarding_completed | 1 | 4.3% |
| plan_generated | 1 | 4.3% |
| run_started | 0 | 0% |
| run_completed | 0 | 0% |

The 22 drop-offs share one signature: `Application Installed` + `Application Opened` + `app_launched` + one generic `$screen`, all within ~1-5 seconds, then silence forever. One user (`008226a2`) came back over 2 days, 10 opens across 5 sessions, and still never fired a single non-lifecycle event.

## Why they die there (code path)

- The first screen for every unauthenticated user is a hard Sign-in-with-Apple wall: `RunSmartLiteAppShell.swift:184-186` renders `SignInView()` whenever `!session.isAuthenticated`. There is no guest mode, no browse-first path, no product preview beyond three static feature pills (`SignInView.swift:15-19`).
- **We are analytically blind at exactly this screen.** `SignInView` fires no event on appear; the first instrumented user action after launch is `sign_in_completed`/`sign_in_failed` (`SignInView.swift:149,156`). SwiftUI `$screen` autocapture emits the same generic `UIHostingController<...>` name for every screen, and mobile session replay is off (recordings list is empty). So "bounced in 2 seconds" and "stared at the wall for 5 minutes" are indistinguishable today.

## We know vs we suspect

We KNOW (measured):
1. 95.7% of organic users produce zero events past app-open; the wall is the first screen (code-confirmed).
2. Zero organic `run_started` in the entire App Store era. Every run event in 90d belongs to founder devices.
3. The one engaged organic user (`6e6797d3`, 06-20, 1.0.3) completed onboarding, generated 3 plans in 6 minutes, rage-tapped 10 times during the day, never started a run, and churned that same day.
4. Onboarding steps for those who start hold up well (goal 14, experience 14, schedule 13, privacy 11 people, 90d incl. pre-App-Store), so onboarding itself is not the first-order problem.

We SUSPECT (inferred, needs instrumentation to confirm):
1. Users bounce because they are asked to create an account before seeing any product value. Cannot yet separate "unwilling to sign in" from "sign-in attempted and failed silently" or "app hung".
2. The `6e6797d3` triple plan-regeneration + rageclicks suggests plan output or post-plan next-step is unconvincing even for the rare user who gets there.
3. Instrumentation bug: on founder device `0efa0d1b`, `plan_generation_failed` and `plan_generation_succeeded` fire in pairs 19ms apart (6 of each, 07-14/07-15). One of them is lying; verify the call sites.

## Open question resolved: did the build-21 first-run-sheet fix move plan-to-run?

**Unverifiable in live data: the denominator is zero.** No organic user has generated a plan on 1.0.9+. The only 1.0.9 plan-generator (`a7cd39a2`, founder-suspect) saw the first-run CTA and chose "Remind me" (event pair `first_run_cta_tapped` + `first_run_reminder_scheduled` 129ms apart matches `handleFirstRunRemindMe`, `RunSmartLiteAppShell.swift:460-474`), so no `run_started` was expected. The sheet works mechanically; whether it converts cannot be known until users reach it.

## Fix backlog (ranked by expected D7-activation lift per unit effort)

Top 2 (do these, in this order):

1. **S1. Instrument the black hole (S, 1 day; target: next build, 1.1.1).** Add `sign_in_wall_viewed`, `sign_in_tapped`, and `sign_in_wall_abandoned` with defined semantics: fires at most once per session, only when the app backgrounds (or terminates) after >=5 seconds on the wall with no sign-in attempt; returning to foreground and then attempting sign-in does not retro-emit. Add explicit screen names. Fix the `plan_generation_failed`/`succeeded` double-fire. Session replay is desirable but **gated on privacy guardrails first**: documented consent/opt-out, masking of text input and any health-adjacent surfaces, retention limit, and access control; if that takes longer than a day, ship the events without replay rather than delaying. Metric moved: none directly; it converts every later fix from faith to measurement.
2. **S2. Let users see the product before the account wall (M, 2-3 days).** Options in ascending effort: (a) value-preview carousel with sample plan before the SIWA button, (b) full guest mode: run onboarding + plan preview anonymously, ask for sign-in only to save the plan (Supabase anonymous auth exists; Resumely already ships guest mode). Hypothesis: the wall, not the product, kills ~96% of installs. Metric moved: install -> onboarding_started (currently 1/23, 4.3%). **Predeclared decision rule** (version-over-version, no A/B infra at this volume): evaluate at >=30 clean post-release App Store installs on the new build (roughly 4-6 weeks at ~25 organic installs/month); call it a win if >=6/30 (20%) fire `onboarding_started` (baseline 4.3%; at n=30 a 20% observed rate is inconsistent with the old rate at ~95% confidence); call it inconclusive below 30 installs regardless of rate; rollback triggers: sign-in completion at the plan-save gate under 50%, or any onboarding-crash signal in the new flow. The 30% figure stays the aspiration, not the success threshold.

Then, only after S1+S2 data exists:

3. S3. Post-plan conviction (M). The one user who saw a plan regenerated it 3x and left. Add plan-explainer + "why this plan" content and track `plan_regenerated` as a dissatisfaction signal. Metric: plan_generated -> run_started within 48h.
4. S4. Onboarding healthkit step audit (S). `privacy` 11 people -> `healthkit` 3 people step events; verify the step is genuinely optional-skippable and the skip is not a silent dead end. Metric: onboarding_started -> completed.
5. S5. Add `is_internal_tester` property to this app (S). Resumely already has it; RunSmart exclusions currently rely on behavioral heuristics. Metric: analysis hygiene.

Explicitly NOT prioritized: more acquisition. At a 95.7% first-screen loss, new installs are being poured into a broken funnel.

## Instrumentation gaps found (fix as part of S1)

- No event between `app_launched` and `onboarding_started`.
- `$screen` names are useless (generic hosting-controller strings).
- No mobile session replay.
- `plan_generation_failed`/`succeeded` double-fire (see above).
- No D1-return event distinct from launch.
