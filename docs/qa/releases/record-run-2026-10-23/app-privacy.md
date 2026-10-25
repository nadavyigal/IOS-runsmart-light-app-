# App Privacy reconciliation — Strava deferred

Published and verified in App Store Connect on 23 October 2026 for **RunSmart: AI Run Coaching**, Apple app ID **6768297840**. Reconciled with the current native PrivacyInfo.xcprivacy and source. No binary upload, app-version submission or release was performed.

| Data type | Purpose | Linked to account | Tracking |
|---|---|---|---|
| Name, Email Address | App Functionality | Yes | No |
| User ID | App Functionality, Analytics | Yes | No |
| Health | App Functionality | Yes | No |
| Fitness | App Functionality, Analytics | Yes | No |
| Precise Location | App Functionality | Yes | No |
| Other User Content | App Functionality | Yes | No |
| Product Interaction | Analytics | Yes | No |
| Crash Data | App Functionality | No | No |

Location routes and fitness information synchronize with authenticated RunSmart backend features. PostHog events include account identity and run statistics; do not mark them anonymous. Weight for calorie estimates is local-only. Health workout route/pause/calorie writes and locally composed share images are permission/user-controlled. Title and notes are local-only in this iOS build. Strava is config-hidden, has no client ID or deployed OAuth function, and adds no active disclosure for this build.

Review additional SDK/device diagnostics against the questionnaire instead of treating this manifest as exhaustive. Apple's definitions: https://developer.apple.com/app-store/app-privacy-details/

Policy source is maintained separately in the Running-coach- repository at /privacy. Publication status is recorded in that PR. App Store Connect privacy verification is complete. Physical-device testing remains a merge/release gate.

## Saved answer corrections

- Added Name and Other User Content: App Functionality, linked to identity, no tracking.
- Added Analytics alongside App Functionality for Fitness and User ID; both purposes linked to identity, no tracking.
- Corrected Product Interaction to linked to identity for Analytics; no tracking.
- Email Address, Health, Precise Location and Crash Data retained their existing purposes/linkage.
- Confirmed the existing privacy URL is https://www.runsmart-ai.com/privacy.

Verification: Apple showed 9 data types, a recent Published timestamp, no pending setup warning, the corrected purposes and linked identity. New Analytics purposes initially persisted as unlinked despite the earlier wizard selection; re-entered each wizard and explicitly set Yes, republished, and verified the product preview has only Crash Data under Data Not Linked to You. Screenshots and reloaded page evidence are stored alongside this file.
