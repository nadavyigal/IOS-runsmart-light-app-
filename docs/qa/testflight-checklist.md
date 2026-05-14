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
- [ ] Route history copy explains that saved routes contain precise GPS points.
- [ ] Garmin copy explains RunSmart deletion does not delete Garmin activities.

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
- [ ] GPS run record/finish/save route path works.
- [ ] Garmin import with missing map data has a clear non-blocking state.
- [ ] Benchmark route comparison handles first-run and repeated-run states.
- [ ] Background location and battery behavior have a physical-device note.

## Reviewer Notes
- [ ] Demo credentials are provided if needed.
- [ ] Integration limitations are explained.
- [ ] Known beta limitations are documented.
- [ ] TestFlight release notes mention route matching, Garmin map-data, and benchmark-history limitations.
