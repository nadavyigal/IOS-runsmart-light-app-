# WP-43 S5 — Remove developer-vocabulary badges from trust surfaces

**Date:** 2026-07-14
**Branch:** `claude/bold-noyce-678ace`
**Audit ref:** §4 Risk 10, §10 B12 — "Imported activity · Heuristic", "SOURCE: Real" pill, and enum raw values rendered as user-facing badges.

## Change (three sites, exactly per plan)

1. **`PostRunLearningCard.swift`** — added `PostRunLearningSource.displayLabel` mapping the internal tiers to user language: `.heuristic` → "Based on your plan", `.fallback` → "Quick take", `.ai` → "Coach analysis", `.report` → "Coach report". The "COACH LEARNED" chip now renders `model.source.displayLabel` instead of `model.source.rawValue`. The raw enum (and `run.source.rawValue` narrative text) is unchanged for internal logic/analytics.
2. **`ActivityTabView.swift`** — deleted the `ActivityMetricPill(title: "Source", value: "Real")` pill from the Last-14-Days summary (it invited "as opposed to fake?").
3. **`TodayTabView.swift`** — the coach-safety card subtitle "Coach safety · Heuristic" → "Coach safety check".

**Scope note:** the separate post-run *debrief* chip (`PostRunDebriefModel.Source`, line ~290) renders "AI"/"Coach" and is **not** in the plan's listed S5 scope (which names `PostRunLearningSource` lines 28-32, the Activity pill, and the Today subtitle). I initially changed it, hit a compile error (it's a different enum), and reverted it to stay within scope. Flag for a possible follow-up if "AI" as a badge is considered dev-vocab.

## Validation

**Focused XCTest:** `testPostRunSourceDisplayLabelsAreUserFacing`.
- **Red confirmed (assertion-level):** with `displayLabel` returning `rawValue`, re-ran → `** TEST FAILED **` with, e.g. *`XCTAssertNotEqual failed: ("Heuristic") is equal to ("Heuristic") - heuristic must not render its raw enum value (Heuristic) to users`* and *`heuristic label leaks 'Heuristic': Heuristic`* — for all four tiers. Restored the mapping.
- **Green:** passes. Asserts each tier's `displayLabel` is non-empty, differs from its `rawValue`, and contains neither "heuristic" nor "fallback".

**Full regression:** `RunSmartReadinessTests` — **169 tests, 0 failures**.

**Debug build:** app target (incl. ActivityTabView + TodayTabView) compiled clean as part of the test build.

**Simulator QA (demo mode):**
- Report tab, **iPhone 17** (`assets-2026-07-14-wp43-s5/report-tab.png`) and **iPhone SE** (`report-tab-se.png`): the Last-14-Days card now shows only **RUNS** and **MOVING TIME** — the "Source: Real" pill is gone on both devices.
- Today tab, iPhone 17 (`today-tab.png`): renders clean (also confirms S4's honest "8 x 400m" on the Mon card). The coach-safety explanation card is a different Today state not surfaced in this demo snapshot; its subtitle change is a one-line string swap verified by grep (no remaining "· Heuristic" occurrence). The post-run learning-card badge change is code-verified + unit-tested (the card renders only after a completed run flow, not scriptable this session).

## Risks

Low. Copy/display-only; raw enums and analytics unchanged. Grep confirms no remaining user-facing "Heuristic"/"Source: Real" strings outside the enum raw values (kept internal) and code comments.
