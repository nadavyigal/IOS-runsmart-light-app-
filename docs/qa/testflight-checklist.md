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
- [ ] Notification prompt is only shown after the runner enables reminders.
- [ ] Notification denial leaves the app usable and does not keep rescheduling.
- [ ] Camera/photo/file/network permissions are declared if used.
- [ ] App Privacy answers match actual data collection.
- [ ] Route history copy explains that saved routes contain precise GPS points.
- [ ] Garmin copy explains RunSmart deletion does not delete Garmin activities.
- [ ] Share cards do not include raw coordinates or an exact route map by default.
- [ ] Public copy does not claim live AI coaching during runs, medical diagnosis, guaranteed plan changes, or full Garmin/HealthKit behavior beyond supported connected signals.

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
- [ ] Outdoor GPS run records for at least 5 minutes.
- [ ] App continues recording while locked/backgrounded.
- [ ] Finished run saves, appears in Report, and can generate/open a report.
- [ ] Garmin sync after the run does not duplicate the same workout.
- [ ] Ending battery percentage, duration, and GPS behavior are recorded.
- [ ] Sign-in, onboarding, notification permission, location permission, HealthKit permission, and Garmin connection copy are reviewed on device.

## Reviewer Notes
- [ ] Demo credentials are provided if needed.
- [ ] Integration limitations are explained.
- [ ] Known beta limitations are documented.
- [ ] TestFlight release notes mention route matching, Garmin map-data, and benchmark-history limitations.
- [ ] TestFlight release notes mention local reminders and private progress sharing as beta features.
