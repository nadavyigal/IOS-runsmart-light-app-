# External Research Prompt - App Review Rejection Recovery

Paste this into an external AI research session.

```text
Research Apple App Store rejection fixes for an iOS SwiftUI running app rejected on June 8, 2026 for:
1. Guideline 4 Design: app offers Sign in with Apple but requires name/email after SIWA. Current app uses AuthenticationServices SignInWithAppleButton, requests [.fullName, .email], then shows onboarding with a "Your name" TextField. We need a compliant pattern that still creates a Supabase profile with email/name when available.
2. Guideline 2.5.1: app uses HealthKit APIs but must clearly identify HealthKit/CareKit functionality in the UI. App uses HealthKit, not CareKit. It reads approved workouts/routes/heart rate/HRV/sleep/steps/active energy and optionally writes completed GPS runs.

Use only official Apple docs, Apple Developer Forums, and recent credible iOS developer reports. Find the most reliable fix patterns, exact UI/reviewer-note wording, and validation checklist. Pay special attention to whether Apple allows fallback display names when fullName is nil on repeat SIWA logins, whether a post-SIWA editable display-name field is ever acceptable, and what "clearly identify HealthKit functionality in UI" has meant in recent rejections. Return citations, recommended implementation, reviewer response text, and risks.
```

Apple references to start from:
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple
- https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidcredential/email
- https://developer.apple.com/design/human-interface-guidelines/healthkit
