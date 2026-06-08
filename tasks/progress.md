Status: Rejected - fix implemented locally
Current Phase: App Store Review Response
Active Story: Fix June 08 rejection for Sign in with Apple and HealthKit UI disclosure, then prepare RunSmart 1.0.1 build 12
Last Completed Story: RunSmart 1.0.1 build 11 rejected by Apple on 2026-06-08 for requiring name/email after Sign in with Apple and for unclear HealthKit/CareKit UI identification
Next Recommended Story: Run visual QA on reviewer device classes, archive/export build 12 with distribution signing, inspect archive provenance, upload to App Store Connect, and resubmit with the updated reviewer response
Estimated Completion: Ready after build 12 archive/export/upload, reviewer-device screenshots, and App Store Connect build selection
Blockers: Founder-controlled distribution archive/export/upload; App Store Connect resubmission; manual SIWA fresh-account visual QA
Last Validation: Static scans found no app-code CareKit references and no `TextField("Your name"` call site. HealthKit UI strings are present on sign-in, onboarding, Profile, and HealthKit detail surfaces. Signing-disabled simulator build passed on iPhone 17 Pro Max with DerivedData `/tmp/runsmart-app-review-recovery-derived` on 2026-06-08. Local Release archive `build/RunSmart-build12-local-validation.xcarchive` passed and inspected as `1.0.1 (12)`, but it is development-signed with `get-task-allow=true`, so distribution export/upload remains open.
Last Updated: 2026-06-08
