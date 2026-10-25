# Current candidate: 1.2.0 (37)

Owner reported build-36 TestFlight testing passed on 25 October 2026 and authorized the recommended release steps. Build 37 fixes the initial GPS checkpoint losing a planned workout guide after immediate termination. The new disk/relaunch recovery regression failed before the fix and passes afterward; the full simulator suite passed **725 tests, zero failures/skips**. No additional physical build-37 test is claimed.

Source archive: `760364f4749665fe70cac700207ecf37067f4d62`. Archive/export succeeded. App and Live Activity extension are 1.2.0 (37); exported Apple Distribution signatures are valid with debugging disabled; required entitlements/permission strings/background location and matching dSYMs verified. Packaged privacy manifest equals source, Strava remains hidden, and the keys extracted from both archive and IPA pass the live Auth settings gate with Apple/email enabled.

IPA SHA-256: `e8733b962aeb9fa6acc2e556fac0b409df0f78d48cedd401cbe6d57301708e1e`; size 12,911,084 bytes. Archive: `build/release-1.2.0-37/RunSmart.xcarchive`; export: `build/release-1.2.0-37/AppStoreExport/RunSmart.ipa`.

App Store 1.2.0 draft created, current release/reviewer notes saved, inherited reviewer credentials/assets retained. Privacy/support pages reachable; App Privacy remains published with nine data types. Upload succeeded and Apple processing completed. Build 37 is assigned to RunSmart Internal, with notes saved. App Store version 1.2.0 selects build 37 and is **Waiting for Review** after verified successful submission on 25 October 2026. Submission `d03f75e6-03cc-43ad-9f8d-9bffc12e6659`; automatic release after approval, all users immediately. Source delivery is tracked in PR164. Public production remains 1.1.9 until Apple approval/release.

Known limits: run titles/notes remain local-only; a Health save skipped after duplicate-query failure has no automatic retry; Strava is disabled. Prior candidate records below are historical.

# Historical candidate: 1.2.0 (36) — beta sign-in repair

Build 35 is superseded because an ignored local xcconfig override supplied an invalid client API key. The committed default and public 1.1.9 archive were valid. Build 36 corrects that local override; no backend credentials were rotated and no authentication security was relaxed.

Build 36: signed archive/export, actual packaged-key live Auth check (HTTP 200, Apple/email enabled), 25 focused auth tests and fresh full suite **724/724** passed. Both distribution signatures and required entitlements are valid; both dSYMs match. Supabase Auth also rejected a deliberately malformed Apple token with HTTP 400/validation_failed rather than an API-key 401. This is configuration/endpoint verification, not a completed real-user Apple authorization.

**TestFlight status:** uploaded and processed; build 36 is Testing in RunSmart Internal with the existing founder tester. Build 35 is removed from that group. No App Review submission or public release.

Evidence and owner sign-in instructions: `build36-auth-fix.md`, `build36-testflight-notes.txt`, and the `build36-*` JSON files. Source archive: `477bdcc`; exported IPA SHA-256 `e0ba7b09de9fe9f53bc30ce9bf9945f58ccad2f773a9f48de507d548b292f047` (12,909,947 bytes). Archive: `/Users/nadavyigal/Library/Developer/Xcode/Archives/2026-10-23/RunSmart 1.2.0 (36) - Auth Fix.xcarchive`. Export: `build/release-1.2.0-36/AppStoreExport/RunSmart.ipa`.

The record below for build 35 is historical. Do not select build 35 for production or use its earlier presence-only config checks as a live sign-in pass.

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
