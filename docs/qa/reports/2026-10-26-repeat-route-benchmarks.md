# Saved-report route benchmarks — 2026-10-26

## Problem and confirmed causes

The owner’s App Store reports contained run metrics/coach notes but no benchmark section. Initial source-only diagnosis was incomplete. Simulator QA reproduced a missing section even when the original GPS run resolved: the comparison loader initially rendered only EmptyView, and the task attached to that empty content never started. A stable VStack and explicit loading view keep the task mounted.

Related defects: report lookup used a 14-day recent-run list and case-sensitive UUID strings, reopened reports lacked map/save controls, stale no-match results were not refreshed, and storing both native/Health copies could count one physical workout twice.

## Delivered behavior

- Reopened reports carry the selected run and resolve identities across all visible local history (UUID/provider/consolidated aliases), while respecting hidden/deleted runs.
- Original map and Save Route action appear above coach notes. Saving defaults benchmark tracking on; an already matched route opens its saved details instead of encouraging another copy.
- Opening a report backfills stored route matches from older installations. Saving/enabling a route includes existing matching history. Route/run changes reload comparison without closing the report.
- Explicit loading/unavailable/GPS/no-match states replace silent disappearance.
- Comparisons retain the opened run's fresh match and count cross-provider copies once.
- Existing matching policy retained: endpoints within 120m plus distance and geometry checks; up to 8% distance difference for full matches, up to 25% for covered route variants. Variants compare by pace and do not set a full-route time PB.

## Verification

- Regression contract initially failed to compile before the new lookup seam existed.
- First focused run: 42 passed, 2 failed. Confirmed older-install backfill defect; second failure was a fixture assertion comparing fractional timestamps after whole-second persistence. Backfill fixed; GPS assertion now compares preserved coordinates.
- First complete run: 742 XCTest + 3 Swift Testing = 745 passed, zero failures/skips, iPhone 17 / iOS 26.5.
- Visual save check caught the remaining EmptyView lifecycle defect; corrected afterward. Final full-suite re-run after lifecycle correction: 742 XCTest + 3 Swift Testing = 745 passed, zero failures/skips; xcodebuild TEST SUCCEEDED.

## Limits

Synthetic simulator runs are not the owner's actual GPS traces. No physical-device GPS run, user's production-data mutation, backend migration, App Store upload, or release performed. Historical rematching retains the existing newest-300-run scoring bound. A report whose original run/GPS was lost cannot reconstruct a route from distance/time alone; it now explains this explicitly.

## Visual result on final build

Reopened the latest synthetic 5km run after app restart. Map and saved-route action appear above notes. Benchmark card is visibly present with Previous −1:40 vs 33:20, Route PB 31:40, Month Avg 6:40/km with 3 runs, and Improving trend. This matches the independent test fixture (35:00, 33:20, 31:40). Evidence: [comparison after relaunch](2026-10-26-repeat-route-benchmarks/comparison-after-relaunch.png).

The screenshot uses synthetic coordinates and a demo account. No owner GPS trace was inspected or changed. Fresh-save repeat passed on the final build: initial no-benchmark explanation was visible, Benchmark Route was on by default, and saving once replaced it with the three-run comparison immediately. [Immediate comparison screenshot](2026-10-26-repeat-route-benchmarks/comparison-immediately-after-save.png). The five affected simulator preference keys were restored byte-for-byte; simulator returned to its original booted state.
