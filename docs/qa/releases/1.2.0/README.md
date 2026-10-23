# RunSmart 1.2.0 (35) — record-a-run test candidate

Scope: Releases A/S0–S3, B/S4–S8, C/S9–S12, with Strava deferred and config-hidden. Latest unchanged-code simulator suite: 724 passed, 0 failed, 0 skipped. Privacy policy and App Store Connect answers are published and verified. GitHub head checks passed (secret scan; CodeRabbit skipped). Real-iPhone testing has not been completed; founder requested a testing build before public production release.

Candidate version/build is incremented across app, tests and Live Activity extension. Archive, distribution export and upload succeeded. Apple finished processing and the internal group shows **1.2.0 (35): Testing**. No public release or App Review submission until the device pass. PR164 remains open during device testing.

Testing instructions: `testflight-notes.txt`. Proposed public release notes: `release-notes.txt`. Keep release-owner evidence for locked/background recording, audio coexistence, recovery, auto-pause, guided intervals, Health exports and optional share map.

## Signed candidate

Source: `0e3c389b557bceb93cc582f60c23239ced6cb59c`. Only version/build and documentation changes follow the code that passed 724 tests. Archive succeeded on Xcode 26.5; existing concurrency/deprecation warnings remain.

Archive: `/Users/nadavyigal/Library/Developer/Xcode/Archives/2026-10-23/RunSmart 1.2.0 (35) - Record a Run.xcarchive`.
Export: `build/release-1.2.0-35/AppStoreExport/RunSmart.ipa` (12,909,942 bytes). Export SHA-256: `2f763fd16928f41a3b72adbabc423722bf934ca23e3a704feca70e812e9edae2`. This fingerprint identifies the local exported IPA; Xcode's upload action repackages the same verified archive.

App and extension: version 1.2.0/build 35, Apple Distribution signing, debugging disabled, deep/strict signatures valid. HealthKit, Apple sign-in, associated domains and team verified. Production backend and analytics configured; Strava client ID empty; packaged privacy manifest equals source. Both dSYM UUIDs match. See `archive-verification.json`, `ipa-verification.json`, `dsym-verification.json`.

Internal TestFlight group `RunSmart Internal` created with automatic distribution disabled. Only the founder's existing account was added, after explicit invitation authorization. Upload succeeded at 12:55:39 UTC; processing completed, test notes saved, build attached to RunSmart Internal. The group shows **Testing**, and founder status is **Invited**. See `upload-receipt.json` and `testflight-testing.png`. No public release or App Review submission.

## Owner handoff

Open the TestFlight invitation on the iPhone using the invited Apple account and install **1.2.0 (35)**. Follow What to Test, especially locked-phone/Spotify/Bluetooth audio, recording and paused recovery, traffic-light auto-pause, planned intervals, Health route/pauses/calories, and optional share map. Record any failure with the step and observed behavior. Simulator results do not close this gate.

After the device pass: merge PR164, create the App Store 1.2.0 version and select processed build 35, reconcile the listing/review notes/screenshots with this candidate, and submit for App Review under the owner's production-shipment request. Public production remains at 1.1.9 until that process completes.
