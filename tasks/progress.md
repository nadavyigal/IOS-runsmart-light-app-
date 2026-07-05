Status: WP-15 plan-to-run activation race fixed locally (first-run sheet now waits for async plan generation). WP-34 Garmin credential-guard branch `codex/wp24-garmin-credential-guard` / commit `baa19aa` is unrecoverable — founder decision required (re-implement or park). WP-27 Garmin Gate-4 evidence cleanup remains complete on main/PR #72; founder-run screenshots still pending.
Current Phase: PHASE 2 — Activation diagnostics + Garmin maintenance (EXD-015).
Active Story: WP-15 — ship first-run activation wait fix and monitor `plan_generated -> plan_run_cta_tapped -> run_started -> run_completed` (target >=20% plan-to-run).
Last Completed Story: 2026-07-05 — WP-15 diagnostic: audited activation funnel instrumentation; root cause = `presentFirstRunActivationIfNeeded` queried workouts before async `regenerateTrainingPlan` finished, so `first_run_cta_viewed` rarely fired. One-file poll fix in `RunSmartLiteAppShell.swift`. WP-34 exhaustive recovery search — branch/commit not found anywhere local.
Next Recommended Story: Founder: merge/release WP-15 fix build; watch PostHog bridge metrics for 7 days. Founder: decide WP-34 re-implement vs park. Then WP-27 Gate-4 screenshots if Garmin path resumes.
Estimated Completion: WP-15 code fix is local; needs build bump + ASC release to affect live cohort. WP-34 blocked on founder decision.
Blockers: (1) WP-34 lost work — no merge path without re-implementation. (2) Live App Store build may predate WP-20 first-run sheet (verify which build the 12-user cohort ran). (3) WP-27 founder screenshots still pending.
Last Validation: 2026-07-05 — WP-15 one-file Swift change; `xcodebuild` generic/iOS Release build passed (exit 0, ~9 min; known HKWorkout deprecation warning only). Prior 2026-07-02 full test suite pass on main still applies to unchanged areas.
PM Artifacts: Activation funnel events documented in `.agent-os/distribution/analytics-instrumentation-spec.md`; WP-34 incident in `tasks/ERRORS.md`.
Last Updated: 2026-07-05
