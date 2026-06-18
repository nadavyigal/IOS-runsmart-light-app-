# App Store Readiness Checklist - RunSmart 1.0.2 Build 14 Resubmission

_Last updated: 2026-06-15_

## Source And Build Provenance
- [x] Work is on `main`; no release work is performed from another worktree.
- [x] Record source commit SHA before archive: `c543ffe`.
- [x] Record `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `IOS RunSmart app.xcodeproj/project.pbxproj`: `1.0.2 (14)`.
- [x] Confirm the source build number is greater than the latest rejected App Store Connect build (`14` > rejected `11`).
- [x] Confirm Fastlane did not auto-increment the build number during archive or upload; Fastlane was not used for the 2026-06-15 archive/export.
- [x] Record archive path and archive creation date: `build/RunSmart-build14-AppStore-20260615.xcarchive`, created 2026-06-15.
- [ ] Record selected App Store Connect build number after upload.

## App Review Rejection Gates
- [x] Sign in with Apple requests `.fullName` and `.email` through AuthenticationServices.
- [ ] Fresh SIWA flow does not show a name or email field after authentication.
- [ ] Onboarding collects only running goal, experience, schedule, privacy/tone/reminder preferences, and completion.
- [x] Static scan has no `TextField("Your name"` call site.
- [x] HealthKit is explicitly named in visible UI on sign-in, onboarding Privacy, Profile Connected, and HealthKit detail screens.
- [x] HealthKit UI states RunSmart reads only approved workout/wellness data and can write completed GPS runs only if allowed.
- [x] Static scan confirms no CareKit imports or references in app code, entitlements, Info.plist, or project settings.

## Build And Archive Inspection
- [x] Signing-disabled simulator build passes.
- [x] Release archive succeeds from the recorded source commit.
- [x] Archive/export Info.plist shows bundle id `com.runsmart.lite`, version `1.0.2`, build `14`, and `ITSAppUsesNonExemptEncryption=false`.
- [x] Exported IPA entitlements include Sign in with Apple, associated domains, and HealthKit.
- [x] Exported IPA uses distribution signing with `get-task-allow=false`.
- [x] dSYM is present.
- [x] No diagnostic markdown or untracked Swift source is bundled; IPA inspection and active-source guard passed.

## Reviewer Device QA
- [ ] iPad Air 11-inch (M3) sign-in screenshot shows Sign in with Apple and HealthKit disclosure.
- [ ] iPad Air 11-inch (M3) onboarding Privacy screenshot shows HealthKit read/write disclosure and reachable CTA.
- [ ] iPad Air 11-inch (M3) Profile screenshot shows Connected services above the fold, including HealthKit.
- [ ] iPad Air 11-inch (M3) HealthKit detail screenshot shows permission/read/write explanation.
- [ ] Largest available iPhone simulator repeats the same four screenshots.
- [ ] Fresh install SIWA path reaches onboarding without asking for name or email.

2026-06-14 note: Fresh install reached the expected sign-in screen on the
iPhone 17 Pro simulator, including Sign in with Apple and visible HealthKit
disclosure. Tapping Sign in with Apple failed locally with
`com.apple.AuthenticationServices.AuthorizationError error 1000`, so live
onboarding, delete account, and register-again smoke remain blocked until the
test runs on a simulator/device with working Apple auth.

2026-06-14 update after user smoke logs: production delete account failed in
the deployed Edge Function because it attempted to delete from the
`garmin_activity_points` view. Source now skips that view and deletes the
underlying Garmin activity rows. Garmin native connect source now completes the
OAuth callback token exchange, and the web gateway source accepts the native
`runsmart://` redirect. These fixes must be deployed and live-smoked before
archive/upload/resubmission.

## Deployment Gates Before Archive
- [x] Deploy Supabase Edge Function `delete_account` from the patched source.
- [x] Deploy the RunSmart web Garmin gateway changes to production.
- [x] Confirm delete account succeeds for the smoke-test user and removes the account without Edge Function 500s.
- [x] Confirm the same Apple account can register/sign in again.
- [ ] Confirm the same Apple account does not see name/email collection in the iOS app after re-registering.
- [ ] Confirm Garmin connect completes from iOS and creates the production `garmin_connections`/token records.

2026-06-15 update: Fresh simulator install/build/launch passed from `main`
commit `c543ffe`, and Release iphoneos signing-disabled build passed with
Xcode store validation. The local simulator still returns
`ASAuthorizationError 1000` when tapping Sign in with Apple, so the full
authenticated iOS flow could not be completed here. Supabase logs show patched
`delete_account` version 2 no longer 500s and auth deletion plus Apple signup
occurred after deployment. Vercel runtime log access is permission-limited here,
so Garmin callback traffic still needs device/TestFlight confirmation.

2026-06-15 device/archive update: The reported physical-device Xcode install
failure was reproduced as an Xcode/CoreDevice transport issue rather than an app
package/signing failure. Direct CoreDevice install and launch both succeeded for
`com.runsmart.lite`. Fresh Release archive passed at
`build/RunSmart-build14-AppStore-20260615.xcarchive`, and non-upload App Store
export passed at `build/RunSmart-build14-AppStoreExport-20260615/RunSmart.ipa`.
Exported IPA inspection confirmed bundle id `com.runsmart.lite`, version
`1.0.2`, build `14`, `ITSAppUsesNonExemptEncryption=false`, Apple Distribution
signing, HealthKit, Sign in with Apple, associated domains, `get-task-allow=false`,
and dSYM symbols.

## App Store Connect
- [ ] Uploaded build processing completes.
- [ ] The selected review build matches the inspected archive build number.
- [ ] Screenshots, category, age rating, privacy questionnaire, support URL, privacy URL, and metadata are current.
- [ ] Demo credentials are entered directly in App Store Connect, not stored in repo memory.
- [ ] Notes for App Review include the current rejection response text from `docs/qa/app-review-notes-2026-05-19.md`.

## Reviewer Response Text
Use this in App Store Connect:

```
Thank you for the review. In this build, we fixed the Sign in with Apple onboarding flow so RunSmart no longer asks users to provide their name or email address after authentication. The app requests the standard full name and email scopes through AuthenticationServices and uses Apple-provided account information when available, with an internal fallback display name if Apple does not return a name.

We also made HealthKit functionality explicit in the app UI. HealthKit is now identified on sign-in, onboarding Privacy, Profile Connected services, and the HealthKit detail screen. The UI explains that HealthKit access is optional, that RunSmart reads only approved workout and wellness data, and that completed GPS runs are written to Health only when the user allows write access. RunSmart does not use CareKit.
```
