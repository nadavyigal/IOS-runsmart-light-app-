# Route Feature Review — Creator, Library, Benchmarks (2026-07-23)

**Scope:** user-level review of the route feature (Route Creator, route discovery, saved routes, benchmark routes, benchmark comparison), root-cause of "the feature I designed disappeared," and fixes.
**Status:** fixes merged into PR #116; the route-tables migration was applied to production on 2026-07-23 with founder approval. Remaining gate: device smoke of the record → save → benchmark → re-run → comparison loop.
**Method:** full code-path trace of every route surface and service implementation, plus simulator walk-through as a user (iPhone 17, iOS 26.5, demo mode) with screenshots.

## Findings (ordered by severity)

### F1 — Supabase route tables were never created (root cause of "disappeared")
`RouteRepository.swift` reads/writes `user_saved_routes` and `user_benchmark_routes`, but the SQL to create them only ever existed as a code comment ("Run the following SQL in the Supabase dashboard"). Verified live: neither table exists in project `dxqglotcyirxzyqaxqln`. Every remote fetch throws, `remoteRouteTablesUnavailable` latches true, and the app silently falls back to `UserDefaults`-backed local storage. **Saved routes and benchmarks therefore never left the device and are wiped by delete/reinstall.**
**Fixed and applied 2026-07-23** (founder-approved): `supabase/migrations/20260723120000_create_user_route_tables.sql` — owner-scoped per-command RLS, FK indexes, a `CHECK` pinning `source` to the four `RouteSource` cases, non-negative distance/elevation guards, and an **ownership-enforcing composite FK** so a benchmark row can only reference a saved route belonging to the same user. Verified post-apply on the live project: both tables exist with RLS on and 4 policies each, and a probe confirmed the composite FK rejects a cross-user benchmark insert, the `source` CHECK rejects an unknown value, and the non-negative CHECK rejects a negative distance. Supabase security advisors report no findings on either new table. The client heals on next fetch — existing device-local routes upsert to the cloud the next time a signed-in user saves or benchmarks a route.

### F2 — Route Creator was a dead end
`RouteCreatorView` could generate and select routes, but its only button was "Generate Route". No way to use a selection for a run, no way to open a route's details. The PreRun "Route" button led here, so the pre-run route flow ended in a cul-de-sac.
**Fixed:** primary **Use This Route** CTA (hands the selected route to the run flow exactly like the Route Selector's CTA); "Generate Route" demoted to secondary styling.

### F3 — Route Detail screen was unreachable (dead code)
`RouteDetailScaffold` — the screen with Favorite, **Make Benchmark**, Delete, and benchmark stats (PB, avg pace, run count) — existed in the router but **nothing anywhere opened `.routeDetail`**. `SaveRouteSheet` copy even pointed users to "route details" that could not be reached. Benchmarks could only be enabled at save time, never after, and never inspected.
**Fixed:** saved/benchmark route cards in both the Route Creator and Route Selector now carry a **Details** chip that opens the route detail screen.

### F4 — Demo/QA service path killed the whole benchmark loop
`DemoRunSmartServices` hardcoded `saveRoute → false` (Save Route always showed "Failed to save"), `matchRoute → nil`, `benchmarkComparison → nil`, and served route suggestions with empty map points and dangling `savedRouteID`s (blank map cards). The feature could not be demoed or QA'd in a simulator at all.
**Fixed:** demo services now seed the preview fixtures into the local store once and then run the real production logic (`RouteMatchingService`, `BenchmarkRouteAnalyticsService`, local store persistence). Save → benchmark → match → comparison is fully exercisable in demo mode.

### F5 — Route screens opened at half height
The creator opened at the `.medium` sheet detent: shape controls filled the viewport and every route card sat below the fold (screenshot evidence). **Fixed:** `.routeCreator` and `.routeSelector` present at `.large`.

### F6 — Route usage was unmeasurable
Only `route_selected` (card tap) and `route_saved` existed; attaching a route to a run emitted nothing. **Fixed:** new `route_used_for_run` event with `source` = `route_creator` | `route_selector` | `today_card`.

### QA-hook gap (fixed in passing)
`-OPEN_SECONDARY` had no route destinations; added `routeCreator` and `routeSelector` so route QA is deterministic (per the lessons rule on QA entry points).

## Not fixed — follow-ups recorded in tasks/todo.md
- Garmin "past" route suggestions have `points: []` (blank cards, can never route-match) — needs the Garmin route-point loader wired into suggestion building.
- The Today route recommendation card renders only for `plannedToday`; free-run users never see the working route path.
- Generated "loops" are MKDirections out-and-back walks labeled "loop"; elevation is always 0, so the Hilly/Flat preference cannot differentiate generated routes.
- Live run screen does not show the planned route polyline.

## Validation
- New regression tests `RouteLibraryDemoServiceTests` (3): confirmed **failing** against the pre-fix implementation, passing after (red → green).
- Full iOS suite: see tasks/progress.md entry for the final count.
- Simulator smoke: Route Creator opens full-height with Use This Route CTA and Details chips; screenshots in session scratchpad.

## Evidence
- Route Creator before fix (controls-only viewport, no CTA): session scratchpad `04-route-creator.png` / `05-after-dialog.png`.
- Missing tables: `information_schema.tables` query returned zero rows for both route tables.
