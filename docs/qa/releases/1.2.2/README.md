# RunSmart next release preparation, 29 October 2026

Requested: consolidate current merged iPhone fixes and upload to App Store Connect. ASC 1.2.2 draft created and release/reviewer notes saved. Planned new build 40; previous highest observed TestFlight build 39. No upload or review submission has occurred in this preparation record.

Base source: 3c2d679da3380900e2862de5270ca1c1582726ae, including merged PRs 171/172 satellite sharing and PR 173 Gate A; PR166 saved-route benchmarks remains an ancestor. PR165 Apple Watch beta is excluded. No new monetization, Garmin commercial enablement or backend migration.

Release blocker being verified: preserve image/video export when MapKit reports mapUnavailable; cancellation and invalid-route errors must not be swallowed.

Validation to record: focused red/green regression, complete simulator suite, network-backed map/media renders, physical owner iPhone check, archive and Apple Distribution export signatures/config/permissions/privacy/dSYMs, packaged live backend gate, processed ASC build identity.

Physical device: owner iPhones unavailable at first check; requested connection/unlock. ASC: owner restored access;1.2.2 draft created. Account shows updated Developer Program License Agreement notice; owner asked to accept personally. These checks are pending, not passed.

## Simulator verification

810 XCTest plus 3 Swift Testing cases passed, 0 failures/skips, including live MapKit satellite renders and a playable 10-second MP4. Story/Feed PNGs from synthetic test data were visually checked: route endpoints trimmed, layout readable, Apple Maps attribution retained. These are not physical-device evidence. Focused renderer suite 14/14 passed after three red map-failure regressions. Independent read-only QA found no blocking source issues.

Prepared1.2.2 (40) in all six app/test/extension configurations. Signed archive/export, actual-artifact backend proof, ASC processing and owner physical candidate pass remain pending. Existing invalid-route error wording still suggests no-map sharing; normal snapshot sanitization avoids that path, and this pre-existing minor copy remainder is not part of the map-service failure fix.
