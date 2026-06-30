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
