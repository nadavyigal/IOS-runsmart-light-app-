# RunSmart Lite SwiftUI Architecture

## Structure

Source is grouped under `IOS RunSmart app/IOS RunSmart app/`:

- `App`: root shell and tab orchestration.
- `Core`: shared app state and environment helpers.
- `DesignSystem`: tokens and reusable SwiftUI components.
- `Features`: Today, Plan, Run, Profile, Coach, and secondary flows.
- `Models`: lightweight domain models used by services and views.
- `Services`: protocols and mock implementations.
- `PreviewSupport`: sample data for previews and local scaffolding.

## UI Pattern

- SwiftUI-first views.
- `TabView` is avoided visually in favor of a custom shell so the Run tab can match the design assets.
- Navigation stacks should live per tab once deeper flows become real.
- Coach opens as a sheet/full-screen cover from contextual entry points.

## State And Dependencies

- Keep app-level tab selection and modal routing in the app shell.
- Use service protocols for domain access.
- Mock services return deterministic sample data for previews.
- Future live clients should conform to the same protocols.

## Service Boundaries

- Auth/profile service.
- Today service.
- Plan service.
- Workout/run logging service.
- Coach chat service.
- Route service.
- Reminders/preferences service.
- Device sync service.

## Testing Direction

- Unit test service mappers once live clients are added.
- Snapshot or visual checks should cover the four primary tabs.
- Manual QA must include Dynamic Type, reduced motion, dark mode, and run interruption scenarios.
