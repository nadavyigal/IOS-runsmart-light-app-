# iOS Architecture Standards

- Confirm the authoritative Xcode project before editing app code.
- Follow the existing folder boundaries until a migration spec approves changes.
- Keep product logic separate from SwiftUI view rendering.
- Prefer view models for async feature workflows when the existing feature uses them.
- Keep app-wide state small and intentional.
- Handle authentication and token refresh through existing services.
- Do not introduce new dependencies without a spec-level reason.
- Keep secrets out of source control; use build settings, xcconfig, keychain, or secure backend where appropriate.
- Be aware of automatic signing and target capabilities before archive/TestFlight work.
- Document architecture decisions in `docs/decisions/`.

