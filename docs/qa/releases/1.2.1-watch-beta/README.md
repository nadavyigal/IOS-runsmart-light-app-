# RunSmart 1.2.1 (38) — external Apple Watch beta

Owner approved the external TestFlight plan and named-tester invitation on October 26, 2026. Scope: upload this beta, create the external group, submit for beta review, and invite the approved tester. No public App Store release, PR merge, Garmin/Strava activation or production service changes.

Source archive: `feee81cdaa4a6304a76ab2342c7fb653290e639d`. Application code is unchanged from the source with 749/749 tests; only version/build settings and testing documentation changed. Six configurations use 1.2.1 (38). Live ASC check found build37 latest, all uploads complete, with no newer pending upload.

Archive and Apple Distribution export succeeded. App/extension versions match; strict/deep signatures, disabled debugging, HealthKit entitlement, permission strings, packaged privacy manifest, analytics configuration and both dSYM UUIDs pass. Actual archived and IPA backend keys pass live Auth settings HTTP200, Apple/email enabled. Strava client ID remains empty. See archive/IPA verification JSONs. Export SHA256: `3239a38a4de9b448794eb390e0118fa56a4fd68a047acd84718b3a298d60c9d1` (12,993,887 bytes). Local archive/export: `/Users/nadavyigal/Developer/runsmart-apple-watch-artifacts/2026-10-26/RunSmart-1.2.1-38.xcarchive`, `AppStoreExport38/RunSmart.ipa`.

## App Store Connect state — October 26, 2026
- Upload succeeded at 15:09:18 host-local time after owner approved signing access. Apple processing completed; build UUID `1792958d-9264-4ad2-b09e-5f741d314128`.
- External group **Apple Watch Beta** (`f49ada75-e4c3-497c-95dc-90f853aa71c2`) has one approved tester and one build, **1.2.1 (38)**.
- Owner-entered private TestFlight review fields were verified present after session recovery. Credentials and private contact values are excluded from evidence.
- Saved the exact `what-to-test.txt` instructions, submitted for beta review, and verified **Waiting for Review** in the group's build table and the persisted build association.
- **Automatically notify testers** was checked when submitted. The tester still shows **No Builds Available** while Apple review is pending. Invitation delivery, acceptance and installation are not yet verified. No public link was created.
- Public App Store 1.2.0 remains unchanged; PR165 remains draft pending paired physical Watch QA.

## Next steps
1. Apple approves the external beta; automatic notification is configured for the approved tester. If review requests changes, resolve those before testing.
2. Tester opens the TestFlight invitation on the paired iPhone, installs 1.2.1 (38), and follows the in-app What to Test checklist.
3. Record device models/OS, Watch scheduling and phone-free recording results, one accurate Health import and one intended completion, plus repeat-sync/edit/cancel cases.
4. Keep PR165 draft until physical Watch results pass. Public shipment requires a separate release decision.

The exact tester flow is in `what-to-test.txt`: send interval, inspect Watch goals/alerts, record phone-free, Health sync + RunSmart Sync Now, then exactly one accurate run/one intended completion. Repeat sync/late-data/permission/edit cases follow. No physical Watch QA has been performed.
