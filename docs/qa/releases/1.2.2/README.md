# RunSmart 1.2.2 (40), release candidate

Requested 29 October 2026: consolidate current merged iPhone fixes and upload to ASC. Current status: uploaded, processed and assigned to RunSmart Internal. Exact build 40 is selected and saved in the ASC 1.2.2 draft (Prepare for Submission). App Review has not been submitted; the owner physical check remains pending.

## Included

Archive source `48ee7b3b5caae0a4517f4d6ad647f3a9fe2b5f5a`, based on main `3c2d679`: PRs 171/172 satellite sharing and PR 173 plan recovery/analytics, retaining benchmark implementation `5c96738`. Added a shared PNG/MP4 fallback for mapUnavailable; cancellation and invalid routes remain errors. Route privacy captions are accurate with or without a map. All six app/test/extension configurations use 1.2.2 (40). Apple Watch PR 165 is excluded; Strava stays hidden. No new monetization or backend migration.

## Validation

- Three map-failure/cancellation regressions fail before the fix; 14 renderer tests pass after it.
- Official Xcode result: 813 tests passed, 0 failed/skipped on iPhone 17 Pro / iOS 26.5 simulator, including live MapKit imagery and a playable 10-second MP4.
- Synthetic Story/Feed PNGs visually inspected: route endpoints trimmed, readable layout and Apple Maps attribution retained. These do not establish physical device behavior.
- Independent read-only QA: no blocking findings.
- Release archive: app/extension identities, signatures, entitlements, privacy manifest and matching dSYMs pass; no WorkoutKit or debug share harness.
- Exported IPA: both bundles Apple Distribution, get-task-allow=false; API host and analytics config present.
- Actual archive and IPA backend: Auth settings 200, Apple/email providers enabled.

## ASC and remaining checks

ASC 1.2.2 draft created and release/reviewer notes saved, with existing listing/reviewer credentials retained. Prior public 1.2.1 and highest build 39 verified against Apple/ASC. Build 40 upload succeeded at 22:14 host time. Processing completed; exact build UUID `3358ad8b-7f55-4209-8178-bca022544955` was assigned to RunSmart Internal (one existing tester), test notes saved, and the same build selected/saved in the production 1.2.2 draft. Leave Watch beta 38 separate. Owner physical sharing/map/comparison check remains pending before public review submission.

The export initially waited in codesign; owner approved the keychain request and export succeeded. A Developer License Agreement notice was observed; no acceptance was performed by the agent.

## Artifacts

Signed archive, IPA, logs, video and result bundle: `/private/tmp/runsmart-release-artifacts-2026-10-29`. Source worktree: `/private/tmp/runsmart-asc-release-2026-10-29`, branch `codex/release-1-2-2`. Official summaries and packaged-artifact verification JSON are saved here.

## Remaining owner check

Update from TestFlight to 1.2.2 (40), open an actual saved run, export/share Story, Feed and video, and verify map/privacy and saved-route comparisons after relaunch. No physical pass is claimed. PR #174 remains a draft for release-source review; no main merge or App Review submission was performed in this task. All compiled source/configuration matches archive source 48ee7b3; subsequent commits contain evidence only.
