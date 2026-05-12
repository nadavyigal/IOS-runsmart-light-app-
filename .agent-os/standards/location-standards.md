# Location Standards

- Treat location as sensitive data.
- Ask only when the user is about to use a location-based feature.
- Explain why location is needed in plain language.
- Handle denied, restricted, approximate, and temporarily unavailable states.
- For run tracking, test lock screen/background behavior on device when possible.
- If background location is used, verify both Info.plist background mode and runtime `CLLocationManager` configuration.
- Avoid claiming GPS accuracy until tested against real outdoor runs.
- Keep battery impact visible in design and implementation choices.

