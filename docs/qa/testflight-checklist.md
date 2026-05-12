# TestFlight Checklist

## Project Identity
- [ ] App name is correct.
- [ ] Bundle identifier is final or intentionally temporary.
- [ ] Version and build number are incremented.
- [ ] Signing team and capabilities are correct.
- [ ] Entitlements match actual app features.

## Privacy and Permissions
- [ ] Location usage strings exist if location is used.
- [ ] HealthKit usage strings exist if HealthKit is used.
- [ ] Camera/photo/file/network permissions are declared if used.
- [ ] App Privacy answers match actual data collection.

## Build
- [ ] Release archive succeeds.
- [ ] Archive is validated.
- [ ] Upload to App Store Connect succeeds.
- [ ] dSYMs are available.

## Smoke Test
- [ ] Fresh install works.
- [ ] Upgrade install works if applicable.
- [ ] Login/logout works if applicable.
- [ ] Core daily runner flow works.
- [ ] No debug-only backend or secrets are exposed.

## Reviewer Notes
- [ ] Demo credentials are provided if needed.
- [ ] Integration limitations are explained.
- [ ] Known beta limitations are documented.

