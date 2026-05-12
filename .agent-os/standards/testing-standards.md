# Testing Standards

- For logic changes, add or update unit tests when a test target can cover the behavior.
- For SwiftUI-only changes, define a simulator smoke test and inspect small-phone layout.
- For network or integration work, test success, failure, empty, and unauthorized states.
- For permission work, test allow, deny, and not-yet-requested states.
- Run the smallest useful verification before done.
- Report exact commands and results.
- If a build/test cannot be run, state why and list the remaining risk.

## Common Commands
Run these from the GitHub repo root.

- List project: `xcodebuild -list -project "ResumeBuilder IOS APP.xcodeproj"`
- Build: `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination 'platform=iOS Simulator,name=iPhone 15' build`
- Test: `xcodebuild -project "ResumeBuilder IOS APP.xcodeproj" -scheme "ResumeBuilder IOS APP" -destination 'platform=iOS Simulator,name=iPhone 15' test`
