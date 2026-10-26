# RunSmart 1.2.1 (38) — external Apple Watch beta

Owner approved the external TestFlight plan and named-tester invitation on October 26, 2026. Scope: upload this beta, create the external group, submit for beta review, and invite the approved tester. No public App Store release, PR merge, Garmin/Strava activation or production service changes.

Source archive: `feee81cdaa4a6304a76ab2342c7fb653290e639d`. Application code is unchanged from the source with 749/749 tests; only version/build settings and testing documentation changed. Six configurations use 1.2.1 (38). Live ASC check found build37 latest, all uploads complete, with no newer pending upload.

Archive and Apple Distribution export succeeded. App/extension versions match; strict/deep signatures, disabled debugging, HealthKit entitlement, permission strings, packaged privacy manifest, analytics configuration and both dSYM UUIDs pass. Actual archived and IPA backend keys pass live Auth settings HTTP200, Apple/email enabled. Strava client ID remains empty. See archive/IPA verification JSONs. Export SHA256: `3239a38a4de9b448794eb390e0118fa56a4fd68a047acd84718b3a298d60c9d1` (12,993,887 bytes). Local archive/export: `/Users/nadavyigal/Developer/runsmart-apple-watch-artifacts/2026-10-26/RunSmart-1.2.1-38.xcarchive`, `AppStoreExport38/RunSmart.ipa`.

## App Store Connect state
- External group **Apple Watch Beta** created (`f49ada75-e4c3-497c-95dc-90f853aa71c2`). Only the explicitly approved tester was added by email; roster shows **No Builds Available**, not an install-ready invitation.
- Upload preparation is waiting in macOS codesign key access. The protected SecurityAgent dialog is blocked to computer-use tooling. Owner has been asked to approve any codesign / Apple Distribution Keychain prompt locally. Upload success has not been claimed; do not start a duplicate upload before checking the existing process/ASC history.
- Beta description, public links, feedback email, owner name/contact email and detailed review notes are filled in the open Test Information form. Contact phone and existing reviewer username/password remain blank because published review values are masked from automation. Owner has been asked to fill these directly and Save; no password should be sent in chat. This form has not been saved/submitted yet.
- App Store public 1.2.0 remains unchanged. PR165 remains draft pending physical Watch QA.

## Resume after owner input
1. Check the existing upload log/process and ASC build history; do not blindly retry. Confirm 1.2.1 (38) upload/processing.
2. Verify Test Information saved and reviewer credentials present (do not expose them).
3. Add build38 to Apple Watch Beta, save `what-to-test.txt`, submit for TestFlight beta review, and enable notification of the approved tester after approval.
4. Verify the tester's actual invitation state. Keep Apple approval, email delivery and tester acceptance as separate states.
5. Record evidence and update PR165 without claiming physical Watch success.

The exact tester flow is in `what-to-test.txt`: send interval, inspect Watch goals/alerts, record phone-free, Health sync + RunSmart Sync Now, then exactly one accurate run/one intended completion. Repeat sync/late-data/permission/edit cases follow. No physical Watch QA has been performed.
