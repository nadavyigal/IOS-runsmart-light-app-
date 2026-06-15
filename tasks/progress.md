Status: Privacy/account-deletion source fixes are pushed on current `main`; build number is being advanced to 15 for the fresh App Store resubmission binary. Final resubmission confidence still depends on a real-device/TestFlight authenticated smoke because the local simulator still rejects Sign in with Apple.
Current Phase: 1.0.2 build 15 - archive/export/upload prep
Active Story: Perform live smoke on a physical device or TestFlight: SIWA sign-in, Garmin connect, delete account, SIWA re-register.
Last Completed Story: 2026-06-15 App Review privacy/account-deletion fix from `main` commit `9f47ad2`: Delete Account confirmation dialog updated, privacy manifest expanded, Release generic iOS build passed, and the built app bundle contains the updated privacy manifest.
Next Recommended Story: Archive/export/upload build 15, then run the live smoke on an Apple-auth-capable physical device/TestFlight build: SIWA -> Garmin connect -> delete account -> SIWA re-register. If that passes, select build 15 and resubmit.
Estimated Completion: Ready to archive/export now; live smoke should take roughly 20-40 minutes on a device with Apple auth and Garmin credentials.
Blockers: Local simulator SIWA still returns `ASAuthorizationError 1000`, so this machine cannot complete authenticated Garmin/delete/re-register flow. Vercel runtime logs remain permission-limited here.
Last Validation: 2026-06-15 Release generic iOS build passed for `1.0.2` build `14` after the privacy/account-deletion fix; `PrivacyInfo.xcprivacy` lint passed and the built app bundle contained the expanded privacy manifest. Build 15 archive/export validation is next.
Last Updated: 2026-06-15
