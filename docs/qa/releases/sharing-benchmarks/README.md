# RunSmart 1.2.1 (39) — submitted for App Review

Verified 28 October 2026: **Waiting for Review**, submission `edea8327-0c3b-46d2-93e0-91a38ed5969f`. The exact processed build is `73d723ad-3a78-4b93-bbb2-ed6e5a53f19a`, archived from `98360efa95090d3b977818c5312e30778e18de37`. Automatic release after approval is enabled for all users immediately. Public 1.2.0 remains current until Apple approves/releases this update.

Includes native Story/Feed images, 10-second route video exports, save-once route benchmarks and saved-report comparisons, the richer Health-duplicate route-action fix, and redirect-safe authenticated API requests. **Apple Watch PR165/build38 is excluded** and stays an open draft/testing beta.

Validation: 785 simulator tests pass; signed archive/Apple Distribution IPA, app/extension identity and entitlements, matching dSYMs, privacy/analytics and actual-artifact live backend gates pass. Owner reported both build39 iPhone checks passed: sharing and actual saved same-route comparisons with relaunch persistence. PR168 merged as `a1ca742`; compiled source is unchanged by subsequent evidence commits.

Apple initially blocked Add for Review on new required age-rating questions. Completed Social Media=No and Social Media Disabled Under13=No: RunSmart has no in-app social feed/distribution, only an outbound system share sheet. Retained existing content answers, including Health/Wellness Topics=Yes; calculated rating remains9+. Existing reviewer credentials/listing screenshots were retained. Review validation then passed.

Evidence: `candidate-receipt.json`, `upload-receipt.json`, `build39-submitted.png`, signed artifact reports and `full-tests.json`. The original next-submission benchmark inclusion requirement is satisfied by this exact submitted build/source evidence. No duplicate archive/upload is needed.

## Historical preparation records

> Owner reported **both iPhone checks passed on1.2.1(39)**: image/video delivery and actual saved same-route comparisons with relaunch persistence. Physical candidate gate satisfied by owner report on28 October2026. Proceed with merge/review and App Review submission under the existing production-shipment authorization; Apple Watch remains excluded.

# Current delivery state — 28 October 2026

**1.2.1(39) is uploaded, processed and Testing in RunSmart Internal.** Build UUID `73d723ad-3a78-4b93-bbb2-ed6e5a53f19a`; one existing tester. What to Test saved and verified. Production1.2.1 draft selects this exact build39; release/reviewer notes are saved. Watch38 remains separate and excluded. ASC access and signing blockers are resolved.

Owner physical check requested: update via TestFlight; verify image/video delivery and actual saved same-route Previous/PB/average comparisons including persistence after relaunch. Await this result before merge/App Review submission. Do not interpret TestFlight assignment or draft build selection as production shipment. Public1.2.0 is unchanged. Original next-submission requirement remains open until actual submission evidence is recorded.

Archive source98360ef and all compiled files are unchanged by subsequent evidence-only commits.785 simulator tests, signed archive/export, dSYMs/privacy/analytics/entitlements, source inclusion/Watch exclusion and actual-artifact backend checks pass. No new build is needed solely for documentation. Proof: `upload-receipt.json`, `candidate-receipt.json`, `build39-testing.png`.

## Historical preparation log

> 28 October continuation: owner restored ASC access. Verified public1.2.0 Ready for Distribution and no build39 allocation. Upload of the existing verified archive succeeded at07:03:54 host-local; Apple shows1.2.1(39) Processing. Created1.2.1 production draft and saved release/reviewer notes. Watch38 remains in its separate group. Internal assignment and physical candidate checks remain pending; no App Review submission.

# Production sharing and benchmarks — 28 October 2026

Status: **not ready for production submission**. Archive, distribution IPA, live packaged backend and785 tests pass. Live ASC login/allocation and physical candidate gates remain open. No upload or submission.

Scope: PR166 saved-report/save-once benchmarks; PR167 PNG/MP4 sharing; PR158 redirect-safe API host. Source branch `codex/release-sharing-benchmarks`, checkout `/Users/nadavyigal/Developer/runsmart-production-release`.

Apple Watch PR165 is excluded. Its 1.2.1 (38) beta must never be selected for this production update. Current public App Store listing verified 1.2.0 on 28 October. Live ASC distribution session expired; owner sign-in requested. Prepared candidate: **1.2.1 (39)**, using the next build after observed Watch beta38. Verify no newer allocation in live ASC before uploading/selecting. Marketing version1.2.1 can contain this iPhone-only build independently of Watch beta38; never select build38 for production.

The outstanding PR166 review finding reproduced as a failing regression: the richer GPS-less Health canonical duplicate acquired GPS after stored matching, leaving its saved-route action unmatched. All local/remote report resolution paths now rematch the final consolidated geometry. The combined iPhone17/iOS26.5 suite passes **785 tests (782 XCTest + 3 Swift Testing), zero failures**. The new regression failed before and passed after the fix. The project version/build bump is metadata-only after this code test. iOS26.3 runtime is unavailable; physical candidate checks remain open.

Required delivery gates: clean recorded archive commit containing `5c96738` and PR167 head `2806227`, no Watch implementation, full suite; signed archive/export, matching app/extension versions/signatures/entitlements/dSYMs/privacy, nonempty analytics and live actual-artifact backend; exact ASC processing/selection proof. Physical Photos/social-app delivery and owner actual same-route history remain pending. No database migrations or new partner integrations.

## Verified archive

Source: `98360efa95090d3b977818c5312e30778e18de37`, clean at archive start. App and Live Activity extension1.2.1(39); deep/strict signatures, team/entitlements, permission strings, background location, analytics configuration, source privacy manifest and matching dSYM UUIDs pass. Archive uses expected Apple Development signing; exported IPA must prove Apple Distribution/debugging disabled. Live packaged Auth settings return200 with Apple/email enabled. API host is `www.runsmart-ai.com`, Strava stays hidden, no WorkoutKit linkage or DEBUG share harness.

Archive: `/Users/nadavyigal/Developer/runsmart-production-artifacts/RunSmart-1.2.1-39.xcarchive`. Export completed successfully (log `/private/tmp/runsmart-production-export.log`). Verified export folder: `/Users/nadavyigal/Developer/runsmart-production-artifacts/AppStoreExport39`. No duplicate archive/export is needed.

Exported IPA passed `/Users/nadavyigal/Developer/runsmart-production-artifacts/verify-candidate.py` (Apple Distribution, debugging disabled for both bundles) and the live packaged-backend gate. See `ipa-verification.json`/`ipa-backend.json`. Verify live ASC allocation before upload. Distribution session is currently at expired login; owner sign-in requested. Physical Photos/social delivery and actual same-route history must pass before production selection/submission. Keep Watch beta38 separate.

Combined Debug simulator smoke displays the complete share composer with map off, correct metrics and App Store CTA (explicit synthetic example data); `combined-share-composer.png`. This is source UI evidence, not a physical-device or distribution-binary pass.
