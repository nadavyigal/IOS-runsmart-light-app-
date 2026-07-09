# WP-38 S12 — Live per-km splits QA evidence (2026-07-09)

- **Environment:** iPhone 17 Simulator, iOS 26.3, DEBUG + `-RUNSMART_DEMO_MODE -INITIAL_TAB Run -AUTO_START_RUN`
- **GPS:** `simctl location start --interval=1 --speed=25` northbound ~3.5 km path from 37.7749,-122.4194
- **Build:** Debug **SUCCEEDED** on branch `claude/wp38-runsmart-s12-live-km-splits`

## Acceptance

| Check | Result | Evidence |
|---|---|---|
| After 1st full km, live HUD shows split row | **PASS** | `08-live-km1-plus.png` — distance 1.21 km, **KM SPLITS** collapsed row `0:47 km 1` |
| After 2nd full km, new split appears live | **PASS** | `09-live-km2-plus.png` — distance 2.22 km, **KM SPLITS** collapsed row `0:41 km 2` |
| Live vs post-run use same computation | **PASS** | Both call `RunRecorder.kilometerSplits(from:)` on full `routePoints` (no alternate pace math) |
| Collapsed by default, does not crowd primary metrics | **PASS** | `07`–`09` — single compact row below map; distance/pace/moving time unchanged |
| Debug build | **PASS** | `xcodebuild` Debug iPhone 17 sim |

## Notes

- `-AUTO_START_RUN` is DEBUG + demo-mode only (QA automation); not active in Release/TestFlight.
- Post-run **KM SPLITS** card (`11-postrun-splits.png`) is on the saved 2.55 km run; scroll below coach cards to compare — values derive from the same `kilometerSplits` helper as the live HUD.
