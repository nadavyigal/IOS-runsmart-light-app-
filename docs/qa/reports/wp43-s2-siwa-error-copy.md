# WP-43 S2 — Humanize Sign in with Apple failure copy

**Date:** 2026-07-14
**Branch:** `claude/bold-noyce-678ace`
**Audit ref:** §4 Risk 3, §10 B1 — real-mode narrative showed raw `com.apple.AuthenticationServices.AuthorizationError error 1000`.

## Change

- `SignInView.swift`: replaced `errorMessage = error.localizedDescription` with `Self.humanReadableAppleSignInError(for:)`, a pure static mapper. `.canceled` → `nil` (silent, user backed out). Every other failure → `"Apple sign-in didn't finish. Nothing was created — tap to try again."` The raw `NSError.localizedDescription` is never rendered.
- `AnalyticsEvents.swift`: added `trackSignInFailed(error:)` emitting `sign_in_failed { error_domain, error_code }` (WP-45). The raw domain/code goes to analytics only, not the UI. Called from the `catch` branch.

## Validation

**Focused XCTest:** `RunSmartReadinessTests/testSignInErrorMappingHidesRawNSError`
- **Red state confirmed:** before the fix, compile failed — `Type 'SignInView' has no member 'humanReadableAppleSignInError'` (×3). Test could not exist against the old `localizedDescription` path.
- **Green:** `** TEST SUCCEEDED **` — `testSignInErrorMappingHidesRawNSError()` passed (0.015s) on iPhone 17 sim. Asserts: `.canceled` → nil; `.failed` with a raw `com.apple…error 1000` localizedDescription → mapped copy that contains neither `com.apple` nor `1000`; `AppleSignInError.invalidCredential` → generic fallback that does not leak the raw wording.

**Debug build:** `** BUILD SUCCEEDED **` (iPhone 17 sim, Debug).

**Simulator QA:** sign-in screen renders cleanly on both required devices — no regression, no layout clip.
- iPhone 17: `assets-2026-07-14-wp43-s2/iphone17-signin.png`
- iPhone SE (3rd gen): `assets-2026-07-14-wp43-s2/iphonese-signin.png`

**Note on the failure path:** a real SIWA server failure (`ASAuthorizationError error 1000`) can't be deterministically forced on a simulator without live Apple auth infrastructure, so the failure-copy behavior is validated by the unit test (the mapper is a pure function fully covered there) rather than a live device repro. The screenshots confirm the screen itself is unaffected.

## Risks

None. Copy + analytics only; the sign-in success path and nonce handling are untouched. `.canceled` behavior preserved (still silent).
