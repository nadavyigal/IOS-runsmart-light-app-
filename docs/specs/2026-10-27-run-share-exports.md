# Native run image and video sharing

Owner request: replace website discovery CTA with iOS App Store discovery, then implement both selected static route poster and brighter short route-follow video. The approved design lives in the Builder OS share prototype. Implementation is isolated on codex/run-share-exports from current origin/main; release/submission state is out of scope.

## Acceptance and test contracts

1. Real selected RecordedRun is the immutable export source. Derive distance/time/pace consistently; no prototype GPS or sample metrics in production. Preserve sequential out-and-back and paused segments. Invalid points create breaks rather than invented connecting lines.
2. Map off by default. Existing first/last 200m and start/end-radius privacy trimming happens before snapshot bounds, projection or replay. Missing/short GPS produces an intentional stats-only asset.
3. Native 1080×1920 Story PNG and ~10-second H.264 MP4; 1080×1350 Feed PNG. Bright readable MapKit geography, lime route, native RS mark, compact truthful metrics, visible map attribution.
4. Media footer says Get RunSmart on the App Store. Share sheet includes direct verified https://apps.apple.com/app/id6768297840. Printed media text itself is not falsely described as tappable.
5. Native share composer from post-run and saved-report screens. Preview, explicit route toggle, format choice, generation/progress, cancellation, useful errors/retry, native system share sheet. No auto-posting.
6. Focused payload/privacy tests, image/video export verification and simulator UI smoke. Full regression suite after focused checks pass. No TestFlight, submission or deployment in this change.

## Stories

A. Immutable export payload: privacy, invalid coordinates, stale average pace, zeros/nonfinite values, out-and-back identity, format dimensions and App Store URL. Tests owned separately and defined before implementation.
B. Native renderer: bounded native map plate/projected route, static poster and route reveal/follow/pullback video, private no-map alternative, incremental writing and cleanup on cancellation/failure. Renderer-only tests with local images avoid network dependency.
C. Share flow: integrate real saved run, expose image/video selection and native share sheet, retain legacy summary sharing where no run is available. Test with explicit DEBUG-only fixture; no release demo mode.
D. Verify and hand off: Xcode build/tests, actual simulator image/movie dimensions and playback evidence, native UI screenshot, source/diff review and project memory.

## Plan

1. Ground canonical current source, source data and direct App Store listing; create isolated checkout.
2. Amend review prototype CTA while native payload and renderer work proceed independently.
3. Integrate renderer into native share composer and the two report entry points.
4. Run focused tests and simulator export smoke; fix findings, then run relevant regression checks.
5. Update task memory and provide reviewable branch/PR with evidence. No release operations.
