Status: Live on the App Store as of 2026-06-17; PostHog project 171597 live verification shows 6 users in the last 2 days, latest activity 2026-06-17 12:16.
Current Phase: Live on App Store; monitor launch analytics and complete the real-device/TestFlight authenticated smoke follow-up.
Active Story: Perform live smoke on a physical device or TestFlight: SIWA sign-in, Garmin connect, delete account, SIWA re-register.
Last Completed Story: 2026-06-15 App Review privacy/account-deletion fix from `main` commit `9f47ad2`: Delete Account confirmation dialog updated, privacy manifest expanded, Release generic iOS build passed, and the built app bundle contains the updated privacy manifest.
Next Recommended Story: Wait for build 15 processing, update App Store Connect App Privacy and App Review notes with the delete-account screen recording, run the live smoke on an Apple-auth-capable physical device/TestFlight build, then select build 15 and resubmit.
Estimated Completion: Ready to archive/export now; live smoke should take roughly 20-40 minutes on a device with Apple auth and Garmin credentials.
Blockers: Local simulator SIWA still returns `ASAuthorizationError 1000`, so this machine cannot complete authenticated Garmin/delete/re-register flow. Vercel runtime logs remain permission-limited here.
Last Validation: 2026-06-15 build 15 Release generic iOS build passed; archive/export passed; exported IPA inspection confirmed version `1.0.2`, build `15`, bundle id `com.runsmart.lite`, `ITSAppUsesNonExemptEncryption=false`, `get-task-allow=false`, HealthKit, Sign in with Apple, associated domains, and expanded `PrivacyInfo.xcprivacy`; upload to App Store Connect succeeded and package began processing.
Last Updated: 2026-06-15
