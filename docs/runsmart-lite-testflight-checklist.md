# RunSmart Lite TestFlight Checklist

## Signing And Build

- Confirm bundle identifier.
- Confirm Apple Developer team.
- Confirm deployment target is intentional.
- Archive with Release configuration.
- Upload dSYMs with the build.

## Privacy And Permissions

- Add location usage strings before live run tracking.
- Add HealthKit usage strings before health sync.
- Add notification usage explanation before reminders.
- Add OAuth callback configuration before Garmin or Strava connection.

## Device Testing

- Test on at least one small iPhone and one large iPhone.
- Test cold launch, tab switching, coach sheet, and secondary sheets.
- Test airplane mode and poor network once live services are enabled.
- Test run flow outdoors after Core Location integration.

## Known Gaps Before External TestFlight

- Mock data only.
- No live auth.
- No real coach streaming.
- No Core Location run tracking.
- No HealthKit/Garmin/Strava sync.
- No test target yet.

## Release Gate

- Clean Xcode build.
- Manual QA checklist complete.
- No console runtime warnings from normal navigation.
- Privacy strings and permissions match shipped capabilities.
