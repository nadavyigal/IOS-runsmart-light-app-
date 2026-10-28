# Production sharing and benchmark release

Owner authorization: ship completed RunSmart iPhone changes, including run image/video sharing and saved-route comparisons. Apple Watch testing remains separate in PR165/build38.

## Story 1: Combine completed iPhone work
As a runner I want sharing and comparisons in one build so saved runs can be compared and shared. Acceptance: PR166 and PR167 source ancestry; API-host protection PR158; no WorkoutKit/PR165 code. Verify source diff and full suite.

## Story 2: Preserve saved route action for merged workouts
As a runner I want an existing route to open when Health imports duplicate my run so I do not save the same route again. Acceptance: richer Health canonical run with merged GPS resolves the saved route ID. Test: service regression fails before fix and passes after; review action and comparison consistency.

## Story 3: Deliver verified candidate
As release owner I want a traceable signed build so the App Store receives the tested source. Acceptance: unused live-ASC version/build, archive/export signatures/entitlements/privacy/dSYMs, live packaged backend pass, exact processed build selected. Physical share and actual same-route history checks remain explicit gates. No Watch shipment, backend migration or new feature expansion.
