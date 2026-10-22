# Record-a-run Release B QA — 22 October 2026

## Scope and build

S4–S8 from `tasks/plan-record-run-ux-2026-10-22.md`. Separate branch `codex/2026-10-22-record-run-release-b` based on Release A S2 (`15e9edf`). Claude retains S3 ownership; its remote still ends at S2 at the last check. Merge the finished Release A into this branch and recheck the Start anyway path before merging Release B.

Project/scheme: `IOS RunSmart app.xcodeproj` / `IOS RunSmart app`. iPhone 17 Pro, iOS 26.5, x86_64 simulator. DerivedData `/tmp/runsmart-release-b-dd`.

Local speech lets the system manage its per-utterance audio session with [`usesApplicationAudioSession = false`](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/usesapplicationaudiosession). Background audio is declared alongside location. This still needs the physical audio checks below.

## Automated results

- Focused suite: **21 passed, 0 failed, 0 skipped**, includes cue cadence/preferences, exact milestone interpolation, auto-pause recorder integration, calorie persistence, long-route camera following and pause-segment preservation. See `focused-tests.json`.
- Full suite: **518 passed, 0 failed, 0 skipped**. Includes an additional moving-time rollback regression so auto-pause cannot replay a five-minute cue. See `full-tests.json`.
- Final review: clamped delayed-GPS pause starts to the actual run start and nonnegative resume duration; added a recorder regression. Final full rerun passed all 518 tests after these changes; targeted auto-pause suite passed 5/5 (`delayed-gps-tests.json`).
- `git diff --check` passed.

Reproduction:

```sh
xcodebuild -quiet -project 'IOS RunSmart app.xcodeproj' -scheme 'IOS RunSmart app' \
  -destination 'platform=iOS Simulator,id=BEC1533B-1E20-4AD8-B86F-E321B9F9DC53' \
  -derivedDataPath /tmp/runsmart-release-b-dd -parallel-testing-enabled NO test
```

## Simulator smoke

Demo mode bypasses auth, production analytics and backend writes. Location is synthetic Apple Park; the optional weight fixture is synthetic 70 kg. No physical run or real Health data was used.

- App launches; recording timer progresses.
- Tap Finish leaves the run recording. Holding for 1.7 seconds opens the single Save / Resume / Discard sheet.
- Sheet pauses moving time. Resume returns to recording, including when opened from an already manually paused run.
- Save completes to **Activity saved**; very short demo activity is honestly marked review-only.
- Stats and Map picker navigation works. Map renders, centers the current fix above its metrics card, and occupies approximately two-thirds of the visible live screen at default text size.
- Empty-weight state shows no fabricated calories. Settings offer optional Health weight or local manual kg.
- Evidence: final `stats.png` (synthetic 70 kg), plus `map.png`, `end-sheet.png`, `saved-demo.png` (the latter three captured before final metric reordering).

## Independent review and fixes

Independent reviewer identified and rechecked: manual-pause Resume behavior; recovery priority over optional weight setup; stationary GPS callbacks with no distance filter; exact milestone interpolation; stale AI playback cancellation and player identity; skipped segment markers in capped display routes. A standalone test failed on the old route simplifier and passed after marker propagation. Delayed stationary GPS callbacks are clamped to the run start, preventing pre-run seconds from being deducted as pause time. The moving-time rollback test failed before its high-water guard and passed afterwards.

## Physical checks still required

Guest airplane-mode spoken milestones, locked-phone start/pause/resume/finish speech, Spotify volume between cues, Bluetooth audio, continuous background/automatic-resume behavior and a real 10 km route. Health body-mass permission and unavailable/denied handling need a physical device. VoiceOver action is implemented but its spoken interaction has not been exercised. A new iPhone SE simulator stalled during first boot (BackBoard, then audio/keychain data migration); a concurrent test-host startup timed out, so that interrupted attempt is not counted as a test result. The temporary SE was shut down and deleted. Small-screen and maximum Dynamic Type runtime smoke remain open; the Stats page scrolls by construction. No iOS 26.3 runtime is installed.

## Release recommendation

Draft review candidate. Do not submit a build until S3 is integrated and device checks above pass. No App Store/TestFlight upload, merge or release performed. Release C (Health route/energy export, guided workouts, summary redesign, Strava) is excluded.
