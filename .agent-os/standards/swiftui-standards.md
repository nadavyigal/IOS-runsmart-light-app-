# SwiftUI Standards

- Prefer native SwiftUI APIs and existing design-system components.
- Keep views focused; extract subviews when a body becomes hard to scan.
- Use stable `@State` or injected view models when preserving in-flight async state matters.
- Keep async work tied to clear lifecycle events and avoid duplicate network calls.
- Use `NavigationStack` and typed routing where practical.
- Provide loading, empty, error, and success states for user-facing flows.
- Avoid tiny text, overlapping content, and layouts that only work on large phones.
- Use previews for meaningful states when changing visual components.
- Respect Dynamic Type and VoiceOver labels for custom controls.
- Do not copy web layouts directly into iOS.

