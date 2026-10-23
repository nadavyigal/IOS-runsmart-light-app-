# App Privacy reconciliation — Strava deferred

Prepared from the current native PrivacyInfo.xcprivacy and source. No App Store Connect answers were changed in this session; reconcile the actual questionnaire before submission.

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

Policy source is maintained separately in the Running-coach- repository at /privacy. Publication status is recorded in that PR. Physical device and App Store Connect verification remain release gates.
