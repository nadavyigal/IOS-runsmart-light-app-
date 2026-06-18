# RunSmart 1.0.1 Build 12 - App Review Rejection Recovery

## Goal
Prepare RunSmart iOS `1.0.1 (12)` for App Store resubmission after the June 08, 2026 rejection for Sign in with Apple onboarding and HealthKit UI disclosure.

## Current Evidence
- Current implementation source: `main`.
- Starting source commit: `62823e2` (`1.0.1 (10)`).
- Latest rejected build: `1.0.1 (11)`, Submission ID `63f48069-3f6c-4279-8f7f-447d9d082a10`.
- Build 11 provenance gap: no local build 11 archive was found; continue from `main` and submit build 12.

## Implementation Checklist
- [x] Remove the onboarding name field shown after Sign in with Apple.
- [x] Capture Apple-provided full name and email from `ASAuthorizationAppleIDCredential`.
- [x] Seed new profile/onboarding display name internally from Apple values when available.
- [x] Use `RunSmart Runner` as an internal fallback, without asking users for name or email.
- [x] Preserve and strengthen visible HealthKit wording on sign-in, onboarding Privacy, Profile Connected, and HealthKit detail screens.
- [x] Confirm no CareKit usage in app code, entitlements, Info.plist, or project settings.
- [x] Disable Fastlane build-number auto-increment for `beta` and `release`.
- [x] Replace stale release checklist with current provenance and rejection gates.
- [x] Bump `CURRENT_PROJECT_VERSION` to `12` after compile validation.

## Validation Checklist
- [x] `rg 'TextField\("Your name"|\\bCareKit\\b|import CareKit'` over app code, entitlements, Info.plist, and project settings has no app-code issue.
- [x] HealthKit strings are visible in the relevant UI source files.
- [x] Signing-disabled simulator build passes on iPhone 17 Pro Max.
- [x] Re-run signing-disabled simulator build after build 12 bump.
- [x] Local Release archive succeeds for build `12` and contains a dSYM.
- [x] Local archive inspection confirms bundle id `com.runsmart.lite`, version `1.0.1`, build `12`, HealthKit entitlement, Sign in with Apple entitlement, and HealthKit purpose strings.
- [ ] Fresh SIWA account or revoked app access confirms no name/email field appears after Apple authentication.
- [ ] iPad Air 11-inch (M3) screenshots cover sign-in, onboarding Privacy, Profile Connected, and HealthKit detail.
- [ ] iPhone 17 Pro Max screenshots cover the same four surfaces.
- [ ] Distribution archive is inspected for build `12`, distribution signing, `get-task-allow=false`, dSYM, entitlements, display name, bundle id, encryption flag, and device family.

## Archive Evidence
- Local archive path: `build/RunSmart-build12-local-validation.xcarchive`.
- Archive Info.plist: bundle id `com.runsmart.lite`, version `1.0.1`, build `12`, signing identity `Apple Development: nadav.yigal@gmail.com (V2D7D57MXR)`.
- App Info.plist: `ITSAppUsesNonExemptEncryption=false`, HealthKit share/update purpose strings present.
- Entitlements: HealthKit enabled, Sign in with Apple enabled, associated domains present.
- dSYM: `build/RunSmart-build12-local-validation.xcarchive/dSYMs/IOS RunSmart app.app.dSYM`.
- Important gate: this local archive is development-signed and has `get-task-allow=true`; a distribution-signed archive/export is still required before upload.

## Reviewer Response
Use the response in `docs/qa/app-review-notes-2026-05-19.md` and `docs/qa/app-store-readiness-checklist.md`.

## External Research
Use `docs/superpowers/plans/2026-06-08-app-review-rejection-external-research-prompt.md` for a second-opinion research pass before resubmission.
