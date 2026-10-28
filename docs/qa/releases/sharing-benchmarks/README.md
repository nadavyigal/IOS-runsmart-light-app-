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
