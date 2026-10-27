# Native run sharing — 28 October 2026

Implemented Story (1080×1920) and Feed (1080×1350) PNG exports plus a 10-second, 24 fps, 1080×1920 H.264 MP4. Post-run and saved-run reports open the composer with the selected RecordedRun. Existing benchmark/milestone sharing is retained.

The artwork says “Get RunSmart on the App Store”; the native activity sheet includes the file, its captured caption, and https://apps.apple.com/app/id6768297840 as separate items. Destination apps decide whether accompanying text/URLs are retained.

## Verification

- Full iPhone 17 / iOS 26.5 Simulator suite: **762 passed, 0 failed, 0 skipped**, xcresult summary in `test-summary.json`.
- Production renderer smoke generated Story.png, Feed.png and Video.mp4 through the DEBUG-only example harness. Six exact-time video frames extracted; start, replay, and final frames visually inspected: upright, brighter map, chronological out-and-back reveal, final statistics/App Store footer.
- Native map snapshot retains MapKit attribution. No per-frame network calls or new dependencies.
- Regression coverage includes malformed metrics/GPS, privacy trimming, pause gaps, exact-boundary path rendering, stale run/options/insight snapshots, and scoped temporary-file cleanup.
- `git diff --check` passed.

Local generated media (ignored to keep binaries out of source): `exports/Story.png`, `exports/Feed.png`, `exports/Video.mp4`, and `video-frames/`. These use clearly marked example QA data; no private user route is committed. Production has no demo-route fallback.

## Privacy and lifecycle

The map starts off. Opting in applies existing first/last 200 m and start/end-radius protection, preserving GPS segment breaks. Missing GPS produces a stats-only export. Caption/file share the same immutable payload. Option/run changes cancel obsolete work; cancellation discards partial videos. Recent completed files remain available to extensions and are pruned after 24 hours on subsequent export creation.

## Remaining release checks

No physical iPhone/social-app delivery test, TestFlight upload, merge, or public release was performed. Device QA should check Photos saving and Instagram/WhatsApp/Messages behavior, offline map retry, dismissal/cancellation during video creation, VoiceOver, and large text. App Store URL is separately attached because rendered text cannot itself be clickable.
