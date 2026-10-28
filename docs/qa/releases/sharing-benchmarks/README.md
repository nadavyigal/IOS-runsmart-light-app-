# Production sharing and benchmarks — 28 October 2026

Status: preparing, not uploaded or submitted.

Scope: PR166 saved-report/save-once benchmarks; PR167 PNG/MP4 sharing; PR158 redirect-safe API host. Source branch `codex/release-sharing-benchmarks`, checkout `/Users/nadavyigal/Developer/runsmart-production-release`.

Apple Watch PR165 is excluded. Its 1.2.1 (38) beta must never be selected for this production update. Current public App Store listing verified 1.2.0 on 28 October. Live ASC distribution session expired; owner sign-in requested. Prepared candidate: **1.2.1 (39)**, using the next build after observed Watch beta38. Verify no newer allocation in live ASC before uploading/selecting. Marketing version1.2.1 can contain this iPhone-only build independently of Watch beta38; never select build38 for production.

The outstanding PR166 review finding reproduced as a failing regression: the richer GPS-less Health canonical duplicate acquired GPS after stored matching, leaving its saved-route action unmatched. All local/remote report resolution paths now rematch the final consolidated geometry. The combined iPhone17/iOS26.5 suite passes **785 tests (782 XCTest + 3 Swift Testing), zero failures**. The new regression failed before and passed after the fix. The project version/build bump is metadata-only after this code test. iOS26.3 runtime is unavailable; physical candidate checks remain open.

Required delivery gates: clean recorded archive commit containing `5c96738` and PR167 head `2806227`, no Watch implementation, full suite; signed archive/export, matching app/extension versions/signatures/entitlements/dSYMs/privacy, nonempty analytics and live actual-artifact backend; exact ASC processing/selection proof. Physical Photos/social-app delivery and owner actual same-route history remain pending. No database migrations or new partner integrations.
