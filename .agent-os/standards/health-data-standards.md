# Health Data Standards

- Treat HealthKit and fitness data as high-sensitivity user data.
- Request only the data types needed for the current feature.
- Explain the benefit of each permission.
- Handle denied permissions without blocking unrelated app value.
- Do not imply medical diagnosis or guaranteed injury prevention.
- Keep Apple Health and Garmin import logic abstract enough that Today, Plan, and Coach can work with multiple sources later.
- Verify Info.plist privacy strings, entitlements, and App Privacy disclosures before TestFlight.

