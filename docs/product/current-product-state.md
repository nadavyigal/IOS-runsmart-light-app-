# Current Product State

RunSmart is intended to be a native iOS AI running coach app. The iOS product should not be a direct copy of the web app. It should become a cleaner, lighter, premium SwiftUI mobile experience focused on daily runner behavior.

## Desired iOS Experience
- Native SwiftUI feel.
- Premium, simple, fast, and visual.
- Useful for everyday runners.
- Less cluttered than the web app.
- Optimized for daily use and App Store quality.

## Product Direction
- Today screen should become the main daily command center.
- Starting and reviewing runs should be simple.
- Training plans should be understandable at a glance.
- Profile should be useful but not overloaded.
- AI coaching should be helpful, specific, and non-gimmicky.
- Recovery, readiness, and next workout should be clear.
- Future Garmin and Apple Health integration should be anticipated.

## Repository Reality Check
- The tracked app target currently appears named `ResumeBuilder IOS APP`.
- Main screens currently include score, tailor, design, track, and profile flows from a resume-builder product.
- A partial RunSmart file exists at `IOS RunSmart app/Features/Goals/GoalWizardView 2.swift`, but `IOS RunSmart app.xcodeproj` lacks a visible `project.pbxproj`.
- Existing docs mention RunSmart App Store readiness, GPS background tracking, HealthKit, and Garmin, but the inspected tracked entitlements only show Sign in with Apple.

## Current Product Risk
The repo appears mid-transition. Before feature work, confirm the authoritative project, target name, bundle id, and which RunSmart screens/data models are current versus leftover prototype or migration artifacts.
