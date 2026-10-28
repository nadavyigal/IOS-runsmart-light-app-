# Repeat route comparisons from saved reports

## Outcome and acceptance
Save a route once and automatically compare future and existing matching runs. A reopened report must show its original map, offer Save Route, and display the previous run, route PB, monthly average and trend when available. Near endpoints alone do not establish the same route: retain existing geometry/coverage safeguards and variant labels.

## Story 1: Reliable original-run lookup
As a runner reopening a report, I want its recorded GPS run regardless of the recent-list cutoff, so I can save and compare the route.
- Resolve local UUIDs case-insensitively and provider/consolidated aliases without guessing from distance/date.
- Resolve all stored visible history, including runs older than 14 days; respect hidden/deleted runs.
- Keep the richer canonical GPS run when duplicate provider copies exist.
- Tests: UUID/alias/unknown-ID, old run, deletion and rich duplicate regressions.

## Story 2: Save once and compare immediately
As a regular runner, I want benchmark tracking enabled when saving my route and previous runs included immediately.
- Add map and Save Route to the reopened report; benchmark toggle defaults on and remains optional.
- Existing rematch on route save/enable includes prior runs; preserve tolerant matching and route-variant safeguards.
- Tests: save one route after three runs, reopen third, verify previous/PB/average; stale current-run copy must not override the refreshed comparison.

## Story 3: Visible and current comparison state
As a runner, I want an explanation when the original run/GPS is unavailable and refreshed comparisons after route changes.
- Never silently hide the comparison when no run resolves.
- Refresh old no-match results and respond to route/run notifications without generating more notifications on reads.
- Tests: missing/sparse GPS, missing run, stale no-match, changed routes, deleted route; retain all existing route matching tests.

## Validation and boundaries
Run regression tests red first, focused suite then complete iOS simulator suite. Visually inspect a deterministic report with three runs and save/compare flow. No backend schema, credentials, Garmin relaunch, release upload or App Store submission changes. Simulator checks cannot prove physical GPS or modify the user's installed App Store app.
