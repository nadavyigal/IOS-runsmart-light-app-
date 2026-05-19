# TestFlight Checklist

## Project Identity
- [x] App name is correct.
- [x] Bundle identifier is final or intentionally temporary.
- [x] Version and build number are incremented.
- [x] Signing team and capabilities are correct.
- [x] Entitlements match actual app features.

## Privacy and Permissions
- [x] Location usage strings exist if location is used.
- [x] HealthKit usage strings exist if HealthKit is used.
- [x] Notification prompt is only shown after the runner enables reminders.
- [x] Notification denial leaves the app usable and does not keep rescheduling.
- [x] Camera/photo/file/network permissions are declared if used.
- [x] App Privacy answers match actual data collection.
- [x] Route history copy explains that saved routes contain precise GPS points.
- [x] Garmin copy explains RunSmart deletion does not delete Garmin activities.
- [x] Share cards do not include raw coordinates or an exact route map by default.
- [x] Public copy does not claim live AI coaching during runs, medical diagnosis, guaranteed plan changes, or full Garmin/HealthKit behavior beyond supported connected signals.

## Build
- [x] Release archive succeeds.
- [x] Archive is validated.
- [x] App Store Connect IPA export succeeds.
- [x] Upload to App Store Connect succeeds.
- [ ] Uploaded build processing completes in App Store Connect.
- [x] dSYMs are available.

## Smoke Test
- [ ] Fresh install works.
- [ ] Upgrade install works if applicable.
- [ ] Login/logout works if applicable.
- [ ] Core daily runner flow works.
- [ ] No debug-only backend or secrets are exposed.
- [x] GPS run record/finish/save route path works.
- [ ] Garmin import with missing map data has a clear non-blocking state.
- [ ] Benchmark route comparison handles first-run and repeated-run states.
- [x] Background location and battery behavior have a physical-device note.
- [ ] Smart return reminder schedules for tomorrow's workout when reminders are enabled.
- [ ] Completed planned workout cancels its pending workout reminder.
- [ ] Missed workout reminder opens Plan and uses non-shaming copy.
- [ ] Rest day reminder opens Today and uses recovery-focused copy.
- [ ] Weekly recap reminder opens Report.
- [ ] Report share opens the iOS share sheet and canceling share returns cleanly.
- [ ] Benchmark PB/comparison share opens the iOS share sheet without map or coordinate data.
- [ ] Milestone share opens the iOS share sheet without location data.

## Physical Device Beta Gate
- [ ] Device is unlocked before launch validation.
- [ ] Starting battery percentage is recorded.
- [x] Outdoor GPS run records.
- [ ] App continues recording while locked/backgrounded.
- [ ] Finished run saves, appears in Report, and can generate/open a report.
- [ ] Garmin sync after the run does not duplicate the same workout.
- [x] GPS behavior and acceptable battery use are recorded as release-owner evidence.
- [ ] Sign-in, onboarding, notification permission, location permission, HealthKit permission, and Garmin connection copy are reviewed on device.

## Reviewer Notes
- [ ] Demo credentials are provided if needed.
- [x] Integration limitations are explained.
- [x] Known beta limitations are documented.
- [x] TestFlight release notes mention route matching, Garmin map-data, and benchmark-history limitations.
- [x] TestFlight release notes mention local reminders and private progress sharing as beta features.
