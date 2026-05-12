# Security and Config Standards

- Never commit secrets, API keys, private tokens, or production credentials.
- Use Keychain for user tokens.
- Keep backend base URLs and feature flags explicit and environment-aware.
- Avoid logging sensitive auth, health, location, or payment data.
- Validate server responses and handle unauthorized states cleanly.
- Review App Transport Security and external domains before release.
- Keep TestFlight builds pointed at intended beta or production services only.

