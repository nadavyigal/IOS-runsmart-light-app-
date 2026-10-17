# RunSmart 1.1.9 (34) — App Store review handoff

Prepared 2026-10-17 (Asia/Jerusalem). App Store submission remains founder-owned.

## Decision

**Not ready to submit until the live privacy-policy correction, ASC privacy/metadata checks, and final device smoke are complete.** Local archive and test checks passed; distribution export is waiting for macOS Keychain approval. Do not interpret a checked historical 1.0.2 or TestFlight checklist as evidence for this version.

## Candidate and scope

- App: RunSmart / bundle `com.runsmart.lite` / team `8VC4R5M425`.
- Version/build: **1.1.9 (34)** for app, test target and Live Activity extension, all six configurations checked.
- Release PR: https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/157
- Original candidate: `f0dbf3e2225af71f3b6094d41a9411371989cc43`. Current preparation includes current main's documentation, corrected native privacy declarations, and corrected store description; no product logic or UI changes.
- Public store lookup during this session: **1.1.8**, released `2026-10-02T19:28:34Z`. This does not establish which builds have already been uploaded to ASC.
- This release carries the merged Release analytics credential validation and test-host deinit fixes. Public 1.1.8 already emits analytics; 1.1.9 is not presented as restoring a proven public outage.
- The built source is an export of the original candidate plus the corrected manifest, without `RunSmartSecrets.xcconfig`. `source-fingerprints.json` pins build-critical files and matches the prepared checkout.

## Corrections included

1. Product interaction analytics is declared linked to the user because native sign-in calls `Analytics.identifyUser(userId:)`.
2. User ID and Fitness include the Analytics purpose alongside App Functionality; run completion/abandonment events carry distance, duration, pace and run type.
3. Name and Other User Content are declared linked for profile name and persisted coach conversations. Existing email, health, fitness, precise location and crash declarations remain. Tracking remains false.
4. Store description no longer advertises currently unavailable Garmin connections. This is local Fastlane metadata until copied/saved in ASC.

## Local verification

- **Release archive: PASS**, including the final privacy resource; signed app and extension, matching 1.1.9 (34), both dSYMs, HealthKit/Apple sign-in/associated-domain entitlements, and deep/strict signature verification.
- **Built configuration: PASS** without a local secrets xcconfig. Analytics key matches the committed public key; analytics host and required backend settings are resolved; no unresolved build placeholders or bundled Swift/markdown/xcconfig/private-key files.
- **Privacy packaging: PASS**, parsed archived manifest equals the final source. The archive has development signing / `get-task-allow=true`, which is expected before distribution export. This is not a distribution IPA signature claim.
- **Simulator suite: PASS**, 421 passed, zero failures/skips on iPhone 17 Pro / iOS 26.5. The final resource candidate was rerun: **421 passed, zero failures/skips**; app logic is unchanged.
- **Fresh launch: PASS**, dedicated fresh iPhone 17e / iOS 26.5 simulator. Inspected guest CTA, Apple/email sign-in and legal links with no clipping. Screenshot: `fresh-launch-iphone-17e.png`. This was a simulator Debug build, not the device archive. The temporary smoke simulator was removed afterward.
- **App Store export: WAITING**, `codesign` is waiting for Keychain signature access. A prompt was requested from the release owner; distribution IPA and Apple's server-side validation have not passed yet.
- **Not run:** physical-device/upgrade/auth/provider/background GPS smoke, ASC processing or review checks. Existing actor-isolation and HealthKit deprecation warnings remain in untouched Swift sources.

The archive is installed in Xcode's normal Organizer location:
`/Users/nadavyigal/Library/Developer/Xcode/Archives/2026-10-17/RunSmart 1.1.9 (34) - Review Prep.xcarchive`.

Export invocation uses `ExportOptionsAppStore.plist`: local export only, `manageAppVersionAndBuildNumber=false`, so it cannot silently increment build 34 or submit the app. It is currently running from `/private/tmp/runsmart-1.1.9-34-20261017`, writing `build/AppStoreExport` and `export.log`. After Keychain approval, verify the resulting IPA uses Apple Distribution signing with `get-task-allow=false` before uploading.

Archive inspection: `archive-verification.json`. Test summary: `test-summary.json`. Raw build logs are kept under `build/release-1.1.9-34/` in the canonical app checkout. The `.xcresult` bundles remain under the temporary build snapshot.

Static checks passed: project/Info/privacy plist syntax, all six version/build pairs, metadata character limits, and absence of a local secrets file in the build copy. Public support, privacy and AASA endpoints return HTTP 200; AASA contains the native application identifier. The privacy URL's content still needs correction despite returning 200.

Xcode 26.5 / iOS SDK 26.5 meets Apple's current upload SDK minimum (Xcode 26 / iOS 26). See https://developer.apple.com/news/upcoming-requirements/?id=02032026a .

## Before upload and submission

- [ ] Publish an accurate native privacy policy at https://www.runsmart-ai.com/privacy . It currently claims browser-only IndexedDB storage/no central activity database and anonymous analytics, conflicting with native backend persistence and account-linked analytics. `privacy-policy-native-draft.md` supplies the verified corrections and identifies the few owner confirmations needed before publishing. This session did not deploy the website.
- [ ] In ASC App Privacy, reconcile the declarations with the final manifest: Name, Email Address, User ID, Health, Fitness, Precise Location and Other User Content for App Functionality, linked to the user; User ID, Fitness and Product Interaction for Analytics, linked to the user. Existing Crash Data is declared unlinked for App Functionality. Review additional SDK/device diagnostics against Apple's questionnaire rather than assuming this manifest is the complete ASC answer set. Do not label account-linked analytics anonymous.
- [ ] Complete `final-device-smoke.md` using the actual TestFlight build, especially auth, upgrade/persistence, locked-screen GPS/save, permissions and disposable-account deletion.
- [ ] Confirm build **34** is unused before upload. If it is already uploaded, confirm its provenance and manifest before selecting it; do not substitute a different archive with the same version/build or overwrite the server build. If needed, increment all targets and rebuild.
- [ ] Upload the inspected IPA/archive through Xcode Organizer or Transporter; wait for processing to finish. Check that Apple reports no invalid binary or missing-compliance issues. Distribution signing/local export does not prove server-side validation.
- [ ] Create/select iOS version **1.1.9** in ASC and select processed build **34**. Check the app AND Live Activity extension version if Apple's validation reports a mismatch.
- [ ] Paste `fastlane/metadata/en-US/release_notes.txt` into What's New and the corrected `description.txt` into Description. Keep the existing listing name unless intentionally changing it. Confirm every required localization and screenshot size is populated with current, accurate screenshots; do not blindly re-upload all local screenshot assets.
- [ ] Confirm working support/privacy URLs, category, updated age-rating questionnaire, content rights, pricing/availability, agreements and any DSA trader information required by the selected storefronts. These account/version fields were not readable without ASC authentication.
- [ ] Enter a working dedicated review account directly in ASC and verify it can sign in without the reviewer using your personal account. Guest preview alone does not expose authenticated plans/reports. Keep credentials out of Git and review notes.
- [ ] Paste `app-review-notes.txt` into review notes after entering the review credentials and current review contact details.
- [ ] Confirm export compliance. The binary declares `ITSAppUsesNonExemptEncryption=false`; answer consistently with the app's actual standard transport encryption and Apple's questionnaire.
- [ ] Choose the desired release mode. For controlled rollout, choose **Manually release this version**.
- [ ] Founder: **Add for Review**, resolve any reported missing items, inspect the resulting submission, then **Submit for Review**.

Apple submission reference: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/ . Neither adding a version nor uploading a build is equivalent to submitting it.

## Access and practical limits

App Store Connect opened at its Apple Account sign-in screen. This environment has no configured ASC API key. No upload, build processing, reviewer-account login, live metadata change, agreements acceptance, submission or release has been claimed. The final physical-device/background and live-provider checks require release-owner evidence. Simulator success cannot close those gates.
