# WP-43 S3 — Fix the aha-timeline contradiction and remove the overpromise

**Date:** 2026-07-14
**Branch:** `claude/bold-noyce-678ace`
**Audit ref:** §4 Risk 6, §10 B2 — aha screen headline "Six weeks from now…" while the timeline graphic and milestone said "in 8 weeks", plus the guarantee "we know you'll finish".

## Root cause

`GoalTimelineMomentView.headline` hardcoded `"Six weeks from now, you could be lining up at your first 5K."` for any 5K distance goal, independent of `timeline.weeks`. The timeline graphic's endpoint node renders `"in \(timeline.weeks) weeks"`. For any persona whose plan isn't 6 weeks (e.g. an 8- or 12-week beginner 5K), the headline and the graphic disagreed. The subline hardcoded a guarantee the product can't honestly make.

## Change (`GoalTimelineMomentView.swift`)

- Extracted the headline into `static func headlineText(for: GoalTimelineProjection)` and single-sourced the duration from `timeline.weeks` — the 5K branch now reads `"In \(timeline.weeks) weeks, you could be lining up at your first 5K."` so headline and graphic can never disagree across goals.
- Extracted the subline into `static let sublineText`, replacing the guarantee with credible framing: `"Runners who stick with this plan usually get there."`
- The view's `headline`/`subline` computed properties now delegate to these static members (no behavior change at the call site).

## Validation

**Focused XCTest** (plan's required test + a guarantee-language guard): `testGoalTimelineHeadlineMatchesMilestoneWeeks`, `testGoalTimelineSublineHasNoGuaranteeLanguage`.
- **Red confirmed (assertion-level):** temporarily restored the hardcoded `"Six weeks…"` headline and the old guarantee subline, re-ran → `** TEST FAILED **` with the exact contradiction, e.g. *"headline must state the timeline's own 8-week duration for First 5K; got: Six weeks from now, you could be lining up at your first 5K."* and *"must not guarantee the runner will finish."* Restored the fix.
- **Green:** both tests pass. `testGoalTimelineHeadlineMatchesMilestoneWeeks` asserts, across First 5K / 10K / Half / Marathon / Faster 5K / habit goals and weeks ∈ {6, 8, 12}, that the headline contains `"\(weeks) weeks"` and never the literal "Six weeks".

**Full regression:** `RunSmartReadinessTests` — **168 tests, 0 failures** (`-parallel-testing-enabled NO`).

**Debug build:** app target compiled clean as part of the test build.

**Simulator QA note:** the aha-moment overlay fires only after completing onboarding, which requires taps that couldn't be scripted this session (`simctl` has no tap; `idb`/`cliclick` absent; computer-use Simulator control declined). The headline/subline output is a pure function of `timeline`, fully exercised by the red→green unit test across every goal category and week count — this is stronger coverage than a single-persona screenshot.

## Risks

Low. Copy + a pure-function extraction; the graphic, analytics (`future_vision` moment id), and CTA wiring are unchanged. No other code referenced the old strings (verified by grep).
