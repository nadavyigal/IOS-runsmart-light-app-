# App Store Readiness Report - 2026-05-19

## Status
Uploaded to App Store Connect; remaining portal/manual assets before review submission.

RunSmart now has a cleaned RunSmart-only app tree, passing simulator build, passing build-for-testing, a successful release archive, a successful App Store Connect IPA export, and a successful App Store Connect upload. The uploaded package is distribution-signed with `get-task-allow = false`.

The remaining items are portal/manual items before submit-for-review: wait for App Store Connect processing, add real App Store screenshots, confirm privacy questionnaire/age/category/reviewer fields in App Store Connect, and enter demo credentials directly in App Store Connect.

## Fixed This Pass
- Set archived display name and bundle name to `RunSmart`.
- Added `ITSAppUsesNonExemptEncryption = false` for App Store Connect export metadata.
- Removed `Features/Secondary/DIAGNOSTIC_REPORT.md` from the app bundle.
- Removed untracked ResumeBuilder/ATS/Tailor/V2/paywall files from the folder-synced app source tree.
- Removed stale ResumeBuilder/ATS/Tailor/PDF/credits strings from the shipped string catalog.
- Removed stray unreferenced app icon PNGs that caused asset warnings.
- Added `ExportOptionsAppStore.plist` for reproducible App Store Connect exports.
- Added `ExportOptionsAppStoreUpload.plist` for reproducible App Store Connect uploads.
- Added Fastlane App Store metadata text files.
- Added App Review notes without storing credentials.

## Verified
- Bundle id: `com.runsmart.lite`
- Marketing version: `1.0`
- Build number: `5`
- Entitlements present: Sign in with Apple, associated domains, HealthKit.
- Privacy manifest present for user id, health, fitness, precise location, and UserDefaults data categories.
- Required permission strings exist for HealthKit and location usage.
- Public web URLs for root, privacy, support, and terms return HTTP 200 after canonical redirect.
- Deployed `coach_message` returns HTTP 401 without auth, confirming the endpoint is deployed and protected from anonymous use.
- Archive contains a dSYM.
- Archive no longer contains `DIAGNOSTIC_REPORT.md`.
- Exported IPA exists at `build/AppStoreExportClean/RunSmart.ipa`.
- Exported IPA is Apple Distribution-signed and has `get-task-allow = false`.
- Exported IPA has `beta-reports-active = true`.
- App Store Connect upload succeeded and the uploaded package began processing.
- Exported IPA localized resources contain no ResumeBuilder/Resume/ATS/Tailor/jobs/credits/PDF legacy strings.
- No untracked source files remain inside `IOS RunSmart app/`.
- App Store metadata files are present and within checked text limits.
- App Review notes are documented in `docs/qa/app-review-notes-2026-05-19.md`.
- The release owner reported an outdoor GPS run recorded successfully with acceptable battery use on May 19, 2026.

## Commands Run
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-AppStoreReady-2026-05-19-v2.xcarchive" archive`
- Archive Info.plist inspection with `plutil`.
- Archive entitlement inspection with `codesign`.
- Archive bundled-file inspection with `find`.
- App Store Connect export:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-AppStoreReady-2026-05-19-clean.xcarchive" -exportPath "build/AppStoreExportClean" -exportOptionsPlist ExportOptionsAppStore.plist -allowProvisioningUpdates`
- App Store Connect upload:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-AppStoreReady-2026-05-19-clean.xcarchive" -exportPath "build/AppStoreUploadClean" -exportOptionsPlist ExportOptionsAppStoreUpload.plist -allowProvisioningUpdates`
- Exported IPA inspection with `unzip`, `plutil`, `codesign`, `find`, and `strings`.
- Metadata length validation with Ruby.
- Plist validation with `plutil -lint`.
- Public URL and deployed Coach unauthenticated smoke checks.

## Results
- Simulator build: passed.
- Build-for-testing: passed.
- iOS release archive: passed.
- App Store Connect IPA export: passed.
- App Store Connect upload: passed; Apple reported the uploaded package is processing.
- Archive Info.plist: `CFBundleDisplayName = RunSmart`, `CFBundleName = RunSmart`, `CFBundleIdentifier = com.runsmart.lite`, `CFBundleShortVersionString = 1.0`, `CFBundleVersion = 5`, `ITSAppUsesNonExemptEncryption = false`.
- Archive diagnostics: no bundled `DIAGNOSTIC_REPORT.md` found.
- Archive signing: development-signed, as expected before export.
- Exported IPA signing: Apple Distribution profile with `get-task-allow = false`.
- Exported IPA diagnostics: no bundled diagnostic or legacy ResumeBuilder/ATS/Tailor files found.

## Blocking Issues
1. App Store Connect processing and build selection still need portal confirmation.
   The upload succeeded and began processing. After processing finishes, select build 5 in TestFlight/App Store Connect.

2. App Store screenshots are still missing from the repo.
   No `fastlane/screenshots` assets exist yet. Capture 6.7-inch and 6.1-inch App Store screenshots before final submission.

3. App Store Connect privacy and reviewer fields must be entered in the portal.
   Privacy answers, demo credentials, age rating, category, and reviewer notes need final entry/confirmation in App Store Connect.

4. Authenticated Coach production smoke was not re-run in this pass.
   The deployed endpoint remains protected from anonymous access; the latest authenticated remote smoke remains from the Sprint 8 deployment completion.

## Non-Blocking Risks
- Build output still contains RunSmart-native warning noise around HealthKit deprecation/unused `map`, AI DTO actor isolation, benchmark analytics actor isolation, and AppIntents metadata extraction.
- Exact physical-device battery percentages were not stored in repo memory; only the release-owner result summary was recorded.

## Recommended Next Steps
1. Wait for App Store Connect processing to finish, then select build 5 for TestFlight/App Store.
2. Capture required App Store screenshots and place them under `fastlane/screenshots/` or upload them directly in App Store Connect.
3. Enter demo credentials directly in App Store Connect and paste the reviewer notes from `docs/qa/app-review-notes-2026-05-19.md`.
4. Confirm the App Store privacy questionnaire matches `PrivacyInfo.xcprivacy`.
5. Re-run authenticated Coach smoke before final submit-for-review.
