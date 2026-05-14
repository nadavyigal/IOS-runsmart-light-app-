# Route And Benchmark TestFlight Notes

## Suggested Release Notes
Routes and Benchmark Routes are now in beta. You can save GPS routes from recorded runs and Garmin imports, mark repeat routes as benchmarks, and see route-aware comparison cards in run reports.

Known beta limits: route matching needs GPS map points, Garmin activities may import without map data, MapKit-generated routes can be unavailable, and benchmark insights become useful only after repeated runs on the same route.

## Privacy And Data Notes
- Saved routes contain precise GPS points.
- Deleting a saved route removes the RunSmart route copy and its benchmark tracking only.
- Hiding or deleting a Garmin-backed run in RunSmart does not delete anything from Garmin.
- Background location is used only while an outdoor run is in progress.
- Weak GPS can reduce route-match confidence and benchmark comparison availability.

## Manual TestFlight Checks
- [ ] Clean install: route library empty states are clear.
- [ ] Upgrade install: existing runs and saved routes remain available.
- [ ] Location denied: run and route discovery copy explains the limitation without crashing.
- [ ] Weak GPS or sparse points: app records the run and avoids overclaiming route-match certainty.
- [ ] Garmin activity with map data: route points load, Save Route works, benchmark comparison can appear after matching.
- [ ] Garmin activity without map data: report still works and route actions explain that GPS points are required.
- [ ] Route deletion: saved route disappears from RunSmart and copy clarifies Garmin is unaffected.
- [ ] Battery/background: outdoor recording continues when locked; note device, duration, and battery delta before external beta.

## Status
Ready with risks after simulator build/test validation. Device battery/background validation and App Store Connect upload still need a physical-device pass.
