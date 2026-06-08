# RunSmart 1.0.1 Build 12 Submission Readiness Runbook

Use this from the RunSmart iOS repo:

```sh
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
```

## Goal
Rebuild RunSmart `1.0.1 (12)`, prove the June 08 App Review fixes work, export a distribution-signed App Store artifact, and submit only after source, archive, uploaded build, and selected review build all match.

## 1. Source Gate
- Confirm branch and commit:
  ```sh
  git status --short --branch
  git rev-parse --short HEAD
  ```
- Confirm version/build:
  ```sh
  rg "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "IOS RunSmart app.xcodeproj/project.pbxproj"
  ```
- Required result: `MARKETING_VERSION = 1.0.1`, `CURRENT_PROJECT_VERSION = 12`.
- Confirm Fastlane will not change the build number:
  ```sh
  rg "increment_build_number|CURRENT_PROJECT_VERSION" fastlane/Fastfile
  ```

## 2. Static App Review Gates
- Confirm SIWA no longer asks for name/email after authentication:
  ```sh
  rg 'TextField\("Your name"|TextField\("Email"|TextField\("Your email"' "IOS RunSmart app" || true
  ```
- Confirm no CareKit code is present:
  ```sh
  rg '\bCareKit\b|import CareKit' "IOS RunSmart app" RunSmart.entitlements RunSmartInfo.plist "IOS RunSmart app.xcodeproj/project.pbxproj" || true
  ```
- Confirm HealthKit is visibly named in UI surfaces:
  ```sh
  rg -n "HealthKit" \
    "IOS RunSmart app/Features/Auth/SignInView.swift" \
    "IOS RunSmart app/Features/Onboarding/OnboardingView.swift" \
    "IOS RunSmart app/Features/Profile/ProfileTabView.swift" \
    "IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift"
  ```
- Required result: no name/email onboarding field, no CareKit app-code references, HealthKit copy visible on sign-in, onboarding Privacy, Profile Connected, and HealthKit detail.

## 3. Local Build And Tests
- Clean whitespace:
  ```sh
  git diff --check
  ```
- Build on iPhone 17 Pro Max simulator with signing disabled:
  ```sh
  xcodebuild \
    -project "IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -configuration Debug \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
    -derivedDataPath /tmp/runsmart-build12-derived \
    CODE_SIGNING_ALLOWED=NO \
    build
  ```
- Build tests:
  ```sh
  xcodebuild \
    -project "IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
    -derivedDataPath /tmp/runsmart-build12-derived \
    CODE_SIGNING_ALLOWED=NO \
    build-for-testing
  ```
- Run tests if the simulator runner is stable:
  ```sh
  xcodebuild \
    -project "IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
    -derivedDataPath /tmp/runsmart-build12-derived \
    CODE_SIGNING_ALLOWED=NO \
    test
  ```
- Required result: build passes. If `test` stalls after install, record that honestly and keep `build-for-testing` evidence.

## 4. Manual Reviewer-Device QA
- Use a fresh install.
- Revoke RunSmart access for the Apple ID or use a fresh SIWA account.
- Complete Sign in with Apple.
- Required result: no name field and no email field appears after SIWA.
- Capture screenshots on iPad Air 11-inch (M3) and largest available iPhone simulator:
  - Sign-in screen with HealthKit wording.
  - Onboarding Privacy screen with HealthKit read/write wording.
  - Profile Connected services with HealthKit visible.
  - HealthKit detail screen explaining approved reads and optional completed-run writeback.
- Open HealthKit permission flow from Profile and confirm the Apple permission sheet path is reachable.

## 5. Distribution Archive And Export
- Archive from the exact checked commit:
  ```sh
  xcodebuild \
    -project "IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "build/RunSmart-build12-AppStore.xcarchive" \
    archive
  ```
- Export for App Store Connect:
  ```sh
  xcodebuild \
    -exportArchive \
    -archivePath "build/RunSmart-build12-AppStore.xcarchive" \
    -exportPath "build/RunSmart-build12-AppStoreExport" \
    -exportOptionsPlist ExportOptionsAppStoreUpload.plist \
    -allowProvisioningUpdates
  ```
- Inspect archive Info.plist:
  ```sh
  plutil -p "build/RunSmart-build12-AppStore.xcarchive/Info.plist"
  plutil -p "build/RunSmart-build12-AppStore.xcarchive/Products/Applications/IOS RunSmart app.app/Info.plist" | rg "CFBundleIdentifier|CFBundleShortVersionString|CFBundleVersion|ITSAppUsesNonExemptEncryption|UIDeviceFamily|NSHealth"
  ```
- Inspect entitlements:
  ```sh
  codesign -d --entitlements :- "build/RunSmart-build12-AppStore.xcarchive/Products/Applications/IOS RunSmart app.app" | plutil -p -
  ```
- Required result: bundle id `com.runsmart.lite`, version `1.0.1`, build `12`, dSYM present, HealthKit and SIWA entitlements present, distribution signing, and `get-task-allow=false`.

## 6. Upload And Submission Gate
- Upload only the inspected export.
- In App Store Connect, wait until build `1.0.1 (12)` finishes processing.
- Select exactly build `12` for review.
- Paste the reviewer response from `docs/qa/app-review-notes-2026-05-19.md`.
- App Review notes must explicitly state:
  - SIWA no longer asks for name or email after authentication.
  - HealthKit is optional and visibly identified in UI.
  - RunSmart reads only approved HealthKit data.
  - RunSmart writes completed GPS runs only if the user allows write access.
  - RunSmart does not use CareKit.

## 7. Evidence To Record After Submission
- Source commit SHA.
- Archive path and creation date.
- Archive Info.plist version/build.
- Signing identity and `get-task-allow=false`.
- Export path.
- Uploaded App Store Connect build number.
- Selected review build number.
- New submission ID.
- Screenshots path for reviewer-device QA.
