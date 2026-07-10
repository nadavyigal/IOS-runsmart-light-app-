# WP-40 S2 Physical-Device QA — 2026-07-10

## Story boundary

Validated **S2 — Auto-import after connect, not manual-tap-only**, on a real physical device (`Nadav.Yigal's iPhone`, iOS 26.5), using the founder's real, already-HealthKit-authorized account. S3 value surfacing and S4 funnel verification are covered separately below/in the packet.

## What was found

`ProductionRunSmartServices.connect(provider:)` and `SupabaseRunSmartServices`'s equivalent path were **already manual-only** before this change: a successful `requestHealthAccess()` returned immediately without importing anything, so the first sync required a second, separate action (the Profile tab's manual Sync). This matches the packet's framing exactly — the gap was real, not hypothetical.

## Fix

Both `ProductionRunSmartServices.swift` and `SupabaseRunSmartServices.swift`: after `requestHealthAccess()` succeeds (`state == .connected`), immediately call `syncHealthData()` before returning from `connect(provider:)`. Also posts `.runSmartHealthDidChange` and tracks `Analytics.trackHealthKitSyncCompleted(importedCount:)` on the production path.

## Device evidence (real account, real data, not simulator/mock)

Build installed via `xcodebuild` + `xcrun devicectl device install app`, launched with `-RUNSMART_RECORD_ONBOARDING -RUNSMART_ONBOARDING_STEP 4` to land directly on the new S1 Apple Health onboarding step (see `wp40-simulator-qa.md` for S1's own simulator evidence; this device already had real HealthKit authorization from the founder's regular use, so tapping Connect exercised the already-authorized real sync path rather than a first-time permission sheet).

Tapping **Connect Apple Health** on the S1 onboarding step immediately showed, with no second manual step:

> **Health connected**
> Imported 4 Health workouts. Synced 4 to RunSmart. Skipped 70 already saved or hidden.

This is real production dedup logic exercising real data: 4 new workouts imported, 70 correctly recognized as already-saved and skipped — not a mock count. Tapping Continue advanced to the Ready screen ("Start RunSmart"), confirming S1+S2 compose correctly end to end.

## Test coverage

No new unit test added for `ProductionRunSmartServices`/`SupabaseRunSmartServices` — neither struct has any existing unit test coverage in this codebase (both hit real HealthKit/Supabase APIs directly with no injectable seam for `requestHealthAccess`/`syncHealthData`), and the packet's own acceptance criteria for S2 is device/simulator QA with real seeded data, not a unit test. Full existing suite (117 XCTest + 5 Swift Testing) re-run with these changes present: 0 failures.

## Explicitly not completed / deferred

- **Periodic/background re-sync** (e.g. on app foreground): confirmed no existing mechanism (`grep` for `scenePhase`/`willEnterForeground`/`didBecomeActive` in App/Services found nothing). Per the packet's own instruction ("don't build background refresh speculatively without confirming it's wanted"), this was **not built** — flagged as an open decision for the founder, not a gap in this story.
- No screenshot image files were saved to this report; the device evidence above is transcribed verbatim from the on-device UI observed live during this session (image-based screenshots were viewed in chat, not pulled to disk).
