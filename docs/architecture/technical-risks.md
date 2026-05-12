# Technical Risks

## High
- Project identity mismatch: active target and bundle id still use resume-builder naming while product docs describe RunSmart.
- `IOS RunSmart app.xcodeproj` appears incomplete because no `project.pbxproj` was found.
- TestFlight readiness cannot be trusted until bundle id, signing, app name, privacy strings, and archive path are verified.

## Medium
- App currently forces dark mode; light mode support may be absent or untested.
- Tests appear focused on old resume-builder logic, not RunSmart coaching, plans, run tracking, or integrations.
- Existing docs mention HealthKit/Garmin/location, but inspected source did not show active implementation.
- Build artifacts and archives are checked into or present inside the repo under `build/`, increasing noise and risk of stale assumptions.

## Low
- SwiftUI state patterns mix app-level state, view models, and local view state; future work should preserve existing conventions until architecture is clarified.
- Several names and folders may confuse agents during migration.

## Mitigation Rules
- Confirm the authoritative Xcode project before app code edits.
- Rename or migrate product identity only through an approved spec.
- Add RunSmart-specific tests as features are implemented.
- Treat health, location, and integration work as privacy-sensitive.

