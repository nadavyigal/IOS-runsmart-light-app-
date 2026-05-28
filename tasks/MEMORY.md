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
