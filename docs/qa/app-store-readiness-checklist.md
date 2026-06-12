# App Store Readiness Checklist - RunSmart 1.0.2 Build 14 Resubmission

_Last updated: 2026-06-12_

## Source And Build Provenance
- [ ] Work is on `main`; no release work is performed from another worktree.
- [ ] Record source commit SHA before archive.
- [ ] Record `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `IOS RunSmart app.xcodeproj/project.pbxproj`.
- [x] Confirm the source build number is greater than the latest rejected App Store Connect build (`14` > rejected `11`).
- [ ] Confirm Fastlane did not auto-increment the build number during archive or upload.
- [ ] Record archive path, archive creation date, and selected App Store Connect build number.

## App Review Rejection Gates
- [ ] Sign in with Apple requests `.fullName` and `.email` through AuthenticationServices.
- [ ] Fresh SIWA flow does not show a name or email field after authentication.
- [ ] Onboarding collects only running goal, experience, schedule, privacy/tone/reminder preferences, and completion.
- [ ] Static scan has no `TextField("Your name"` call site.
- [ ] HealthKit is explicitly named in visible UI on sign-in, onboarding Privacy, Profile Connected, and HealthKit detail screens.
- [ ] HealthKit UI states RunSmart reads only approved workout/wellness data and can write completed GPS runs only if allowed.
- [ ] Static scan confirms no CareKit imports or references in app code, entitlements, Info.plist, or project settings.

## Build And Archive Inspection
- [ ] Signing-disabled simulator build passes.
- [x] Release archive succeeds from the recorded source commit.
- [x] Archive/export Info.plist shows bundle id `com.runsmart.lite`, version `1.0.2`, build `14`, and `ITSAppUsesNonExemptEncryption=false`.
- [x] Exported IPA entitlements include Sign in with Apple, associated domains, and HealthKit.
- [x] Exported IPA uses distribution signing with `get-task-allow=false`.
- [x] dSYM is present.
- [ ] No diagnostic markdown, untracked Swift source, secrets, or debug-only artifacts are bundled.

## Reviewer Device QA
- [ ] iPad Air 11-inch (M3) sign-in screenshot shows Sign in with Apple and HealthKit disclosure.
- [ ] iPad Air 11-inch (M3) onboarding Privacy screenshot shows HealthKit read/write disclosure and reachable CTA.
- [ ] iPad Air 11-inch (M3) Profile screenshot shows Connected services above the fold, including HealthKit.
- [ ] iPad Air 11-inch (M3) HealthKit detail screenshot shows permission/read/write explanation.
- [ ] Largest available iPhone simulator repeats the same four screenshots.
- [ ] Fresh install SIWA path reaches onboarding without asking for name or email.

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
