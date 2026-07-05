# RunSmart iOS — Decision Log

Project-specific decisions. Read at the start of every session.

## Format
```
## YYYY-MM-DD — [Decision title]
**Decided:** [What was chosen]
**Why:** [The reasoning]
**Rejected:** [Alternatives considered and why ruled out]
```

---

## 2026-07-05 - WP-15 shipped build 21 + activation readout (in progress)

Worked on: Ship WP-15 fix (`6ed8b97`) to App Store Connect; verify activation funnel against D7 Readout #2 baseline.

Completed:
- Pre-submission checklists reviewed (`tasks/lessons.md`, `docs/qa/testflight-checklist.md`, `docs/qa/app-store-readiness-checklist.md`).
- Release archive **1.0.7 (21)** succeeded from clean detached worktree (main worktree blocked by Finder duplicate `* 2.swift` files in folder-synced app root).
- ASC upload **succeeded** 2026-07-05 ~20:18 UTC+3 via `ExportOptionsAppStoreUpload.plist`.
- PostHog project **171597** baseline funnel (2026-06-19→2026-07-05, `filterTestAccounts=true`): `plan_generated`=1 → `plan_run_cta_tapped`=0 → `run_started`=0 → `run_completed`=0 (**0% plan-to-run**); `first_run_cta_viewed`=0 confirms sheet-skip root cause.
- Documented full query + readout in `tasks/progress.md`.

Decisions: Treat D7 Readout #2 (0/12 mature `run_completed`, 94.7% onboarding drop) as canonical pre-fix baseline. Post-fix measurement deferred to **2026-07-08+** on build-21 cohort. Success gate remains >=20% plan-to-run.

Next session: Re-run PostHog funnel for build-21 users after 3–7 days live. If `first_run_cta_viewed` lifts but `run_started` stays flat, investigate permission blocks and Today `upNext` routing before broader onboarding redesign.

---

## 2026-07-05 - WP-15 plan-to-run activation + WP-34 credential-guard loss

Worked on: Agentic OS WP-15 (D7 readout: 0/12 run_completed, 94.7% onboarding drop) and WP-34 (recover `codex/wp24-garmin-credential-guard` / `baa19aa`).

Completed:
- Audited activation funnel events on live code paths: `app_launched`, `sign_in_completed`, `onboarding_started/step/completed`, `plan_generated`, `first_run_cta_*`, `plan_run_cta_tapped`, `run_started`, `run_completed`, reminder events — names match `AnalyticsEvents.swift` call sites; no `run_logged` duplicate-class bug; permission denials not instrumented.
- Confirmed post-plan UI: `FirstRunActivationSheet` (Start Now / Remind Me Tomorrow), Today `upNext` → "Start Next Run" (PR #62), Plan tab workout taps — all on main.
- Root cause for plan_generated → no run: `saveTrainingGoal` returns before async `regenerateTrainingPlan` completes; `presentFirstRunActivationIfNeeded` immediately called `nextWorkouts`, got `[]`, skipped sheet silently.
- Fix: poll `nextWorkouts` up to 45s before presenting first-run sheet (`RunSmartLiteAppShell.swift`).
- WP-34: exhaustive git/bundle/clone/stash/fsck search — commit `baa19aa` and branch absent; logged in `tasks/ERRORS.md`.

Decisions: Ship WP-15 as tiny one-file fix; do not re-create WP-34 credential guard without explicit founder approval (new scope). Monitor `plan_generated -> plan_run_cta_tapped -> run_started -> run_completed`; success threshold >=20% plan-to-run.

Next session: Release build with WP-15 fix; founder decides WP-34 re-implement vs park.

---

## 2026-07-02 - WP-27 Garmin Numbering Collision Cleanup

Worked on: Corrected same-day Garmin WP numbering collision on PR #72.

Completed:
- Renamed the Gate-4 evidence recapture runbook from WP-26 to WP-27.
- Replaced the misleading local WP-25 Garmin track spec with a pointer to canonical Agentic OS work-packet specs.
- Recorded that this repo does not own WP-25 or WP-26; WP-26 is founder-only Garmin Developer Portal application work.
- Replaced the local Garmin Connect tile JPEG derivative with Garmin's official iOS tile PDF from Garmin's public brand page.
- Ran the full XCTest suite on iPhone 17 Pro, OS 26.5; 234 XCTest tests and 3 Swift Testing tests passed, including both WP-27 attribution/provenance tests.

Decisions: Keep the reviewed Garmin data trust fixes in PR #72, but do not let them substitute for WP-27's founder-owned Gate-4 evidence deliverables.

Next session: Push PR #72 update if needed, then leave physical-device screenshot capture pending for the founder.

---

## 2026-07-02 - WP-25 Garmin Track

Worked on: Superseded local planning artifact; canonical WP-25 lives in Agentic OS, not this repo.

Completed:
- Created branch `codex/wp25-garmin-track` from current `main`.
- Added `docs/specs/wp25-garmin-track.md`, later replaced with a pointer because canonical Garmin work-packet specs live in Agentic OS executive-os/work-packets/WP-25 through WP-28.
- Recorded that PR #69 and PR #70 are already on `main`: Garmin Gate-4 naming/logo remediation plus `1.0.7 (20)` build bump.

Decisions: This repo does not own WP-25 or WP-26. Do not combine WP-24, E7 wearable-depth implementation, or founder-only App Store/Garmin-ticket actions into this package.

Next session: Continue WP-27 Gate-4 evidence cleanup and data trust audit verification on PR #72.

---

## 2026-06-30 - WP-20 first-run activation on Garmin fix branch

Worked on: Agentic OS WP-20 combined with PR #67 Garmin attribution fallback.

Completed:
- First-run activation sheet after plan save with Start Now / Remind Me Tomorrow.
- Smart return reminders default ON for new onboarding profiles.
- First-run analytics events and one-time App Store review prompt after first completed run.
- Build bumped to `1.0.6 (19)` on `codex/garmin-attribution-fallback`.

Decisions: Keep scope to one ASC train; defer sign-in-wall and broader onboarding redesign. Fold activation into the same build as Garmin fallback because both are small and founder plans to merge to `main` as `1.0.6 (19)`.

Next session: Founder archive/upload `1.0.6 (19)`, confirm live, recapture Garmin screenshots.

## 2026-06-24 - WP-15 RunSmart plan-to-run activation diagnostic

Worked on: Diagnosed why a cohort could reach `plan_generated` but not reach D7 `run_completed`.

Completed:
- Mapped onboarding, plan-generation, Today/Plan CTA, run-start, and run-completion analytics.
- Found the likely product break: if the generated plan's first workout is upcoming rather than today, Today showed it as `upNext` but the primary action sent users to Coach instead of Run.
- Changed Today `upNext` planned workouts to show Start Next Run and route directly to the Run flow.
- Added `plan_run_cta_tapped` as the bridge metric before `run_started`.
- Added focused readiness coverage for the CTA behavior and analytics event.

In progress: Focused XCTest methods compiled but did not execute because CoreSimulator stalled while materializing test workers.

Decisions: Treat `plan_generated -> plan_run_cta_tapped -> run_started -> run_completed` as the actionable activation funnel for this fix. Success threshold is at least 20% plan-to-run conversion in the next usable cohort.

Next session: Review and merge the WP-15 activation patch, then monitor PostHog for the bridge event and run-start lift.

## 2026-06-01 — Sprint 11 — UX Redesign + Voice Coach (1.0.1 / build 7)

Worked on: All 10 Sprint 11 stories on `feature/ux-redesign-1.0.1` (14 commits).

Completed:
- A1: Today v2 — new header (greeting + streak + sparkles icon), week strip above decision card, removed coach/insight/conversation/quick-actions/stat-strip cards, latest-run preview row taps to Report tab, padding 140
- A2: Report v2 — 3-segment Runs/Reports/Progress; reports list with "Explain this run" link; progress tab with zone analysis + RecoveryInsightPlanCard + RunTrendChartCard; concurrent async let fetch
- A3: PlanExplanationCard guard folded into A1 body rewrite
- A4: Plan v2 — week first, "Explain this week" compact button, removed PlanBriefingCard and InsightCard, renamed "Add Activity"
- A5: Profile v2 — connected section above fold, removed RecentRunReportsCard
- A6: Post-run bridge — "View Report" calls onSave (clears finishedRun) then sets selectedTab = .report
- B1: /api/coach/voice-cue in RunSmart Web — generateText gpt-4o-mini + fetch OpenAI TTS (tts-1, nova, aac, 0.95); 503 when VOICE_COACH_ENABLED off
- B2: VoiceCoachService.swift — AVAudioSession duckOthers+spokenAudio+allowBluetooth, 300s timer, 8s timeout, silent failure
- B3: RunTabView wiring — phase onChange, cue timer onReceive; explicit stopSession in finishRun/discardRun
- B4: LiveRunView mute toggle — waveform/waveform.slash LiveControlButton
- Version bumped: 1.0.1 / build 7 — build passes

Key decisions:
- RecoveryPlanCard renamed RecoveryInsightPlanCard to avoid clash with PostRunSummaryView's private struct of same name
- stopSession() called explicitly in finishRun/discardRun because phase never transitions to .idle/.ready after recorder.finish()
- B1 uses fetch (not raw openai npm package — not installed in web repo)
- View Report calls onSave() first to nil finishedRun, preventing stale summary on Run tab revisit

NOT done (human actions required):
- Physical device QA checklist
- VOICE_COACH_ENABLED=true flip in Vercel
- TestFlight upload for build 7
- PR: feature/ux-redesign-1.0.1 -> main

Next session:
- Human uploads build 7 to TestFlight, runs physical device QA, flips VOICE_COACH_ENABLED when ready
- After QA passes: create PR feature/ux-redesign-1.0.1 -> main

## 2026-05-27 — First weekly distribution cycle completed

Worked on: Weekly distribution cycle run #1 — ASO finalization

Completed:
- screenshot-overlay-copy.md: all A variants approved and locked (01A–05A). File in `.agent-os/distribution/screenshot-overlay-copy.md`.
- app-store-program.md: Garmin sentence approved and marked. File in `.agent-os/distribution/app-store-program.md`.
- analytics-instrumentation-spec.md: in `.agent-os/distribution/analytics-instrumentation-spec.md`.
- Draft description.txt filed at `distribution-os/projects/runsmart/scaffold/drafts/2026-05-27-rs-aso-001/description.txt`.
- email-platform-brief.md: Resend via Supabase Edge Functions, full trigger architecture, dedup spec. In `.agent-os/distribution/email-platform-brief.md`.
- email-drafts/welcome.md: created from scratch, status draft.
- email-drafts/plan-generated-nudge.md: created from scratch, status draft.
- email-drafts/2-day-no-show.md: created from scratch, status draft.
- Experiment log (global) updated: rs-aso-001, rs-analytics-001, rs-aso-002, rs-email-001 added.
- Distribution command center updated for week of 2026-05-27, target submit 2026-06-01.
- Weekly growth review entry appended (Week 1, pre-launch baseline).
- Demo credentials: confirmed NOT in repo (correct). Must be entered directly in App Store Connect. Requirements: completed onboarding, active beginner plan, ≥1 completed run, coach chat reachable.

Resend config (from Vercel running-coach project):
- API key: RESEND_API_KEY (in Vercel env vars — copy to Supabase secrets)
- From: RunSmart <noreply@runsmart-ai.com>
- Domain: runsmart-ai.com (already verified)

NOTE: Previous session files (.agent-os/distribution/) were in a git worktree branch that never merged to main. Recreated from context on 2026-05-27.

In progress / awaiting action:
- rs-aso-001 (description): copy `drafts/2026-05-27-rs-aso-001/description.txt` to `fastlane/metadata/en-US/description.txt` — product session
- rs-aso-002 (screenshots): render caption overlays in Canva/Figma using approved table in screenshot-overlay-copy.md
- rs-analytics-001 (analytics): instrument onboarding_completed, plan_generated, run_logged — product session, spec at `.agent-os/distribution/analytics-instrumentation-spec.md`
- App Store submit checklist: privacy questionnaire, demo credentials, build selection — founder action in App Store Connect

Decisions:
- Screenshot A variants approved for all 5 slots (founder 2026-05-27)
- Garmin description sentence approved (founder 2026-05-27)
- First distribution focus: ASO finalization before submit-for-review
- Top 3 experiments scored: rs-aso-001 (24), rs-analytics-001 (22), rs-aso-002 (18)

Next session:
- Product-code session: apply description.txt, instrument analytics events, wire email via Resend
- Distribution: render screenshot overlays (rs-aso-002), then submit App Store listing for review

---

## 2026-05-27 — Distribution OS installed for RunSmart iOS

Worked on: Distribution OS install + GTM v0

Completed:
- Scaffold installed at `.agent-os/distribution/` (15 files) — NOTE: recreated in main tree 2026-05-27 after worktree loss
- Positioning mirrored to `.agents/product-marketing.md`
- `app-store-program.md` filled from fastlane metadata + App Store Connect closeout doc
- `metrics.md` audited — PostHog wired, flex week events tracked, activation events NOT yet fired
- `lifecycle-program.md` audited — local push live (4 types), email not wired
- `assets-needed.md` updated with 17 asset gaps
- `competitors.md` confirmed accurate
- `gtm-plan.md` v0 drafted from RunSmart Web GTM + iOS reality
- All 6 open questions resolved with founder (see gtm-plan.md §17)

Decisions:
- v1.0 ships free; paid tier planned later (model/price/timeline TBD)
- Garmin activity import live; physical-device OAuth smoke still pending
- Hebrew App Store metadata in scope (UI stays English)
- Apple attribution (at= / ct=) NOT wired — wire before any web budget
- Android: no plans for 2026
- App Store status: uploaded to App Store Connect 2026-05-19; not yet submitted for review

---

## 2026-05-20 — Agentic OS Setup

**Decided:** Added MEMORY.md and ERRORS.md to Claude Code and Desktop setup
**Why:** To eliminate re-explaining context and re-proposing failed approaches between sessions
**Rejected:** Minimal patch — structural enforcement requires the full system
