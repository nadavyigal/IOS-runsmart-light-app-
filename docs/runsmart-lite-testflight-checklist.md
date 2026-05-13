# RunSmart Lite TestFlight Checklist

## TestFlight Blockers

These must be resolved before any build can be uploaded to TestFlight.

### 1. App Icon Missing — Hard Blocker
`Assets.xcassets/AppIcon.appiconset` is empty. App Store Connect rejects uploads without a
1024×1024 PNG icon. Add the icon before archiving.

### 2. Deployment Target iOS 26.2 — Blocks External Testers Today
`IPHONEOS_DEPLOYMENT_TARGET = 26.2` in both Debug and Release configurations targets a beta
OS that is not publicly released. Consequences:
- **Internal testing (team on iOS 26 beta devices):** works today.
- **External TestFlight testers:** cannot install until iOS 26 ships publicly.
- When iOS 26 ships, this becomes a minimum-OS floor, limiting the tester pool to devices
  on iOS 26+.
- To reach broader testers now, lower the deployment target to iOS 17.0 or 18.0. Verify
  that no iOS 26–specific APIs are used before lowering (the current codebase does not use
  any platform-specific APIs beyond SwiftUI/Combine, so lowering is safe).

### 3. Bundle ID Not Registered
`PRODUCT_BUNDLE_IDENTIFIER = "RunSmart-IOS.IOS-RunSmart-app"` must be registered in
App Store Connect and match a provisioning profile before distribution.
- The ID uses uppercase letters and hyphens, which deviate from Apple's recommended
  reverse-DNS lowercase convention. This is not a hard rejection reason, but:
  - It cannot be changed after the first TestFlight upload without creating a new app record.
  - Consider adopting a clean ID (e.g., `com.nadavyigal.runsmart.lite`) before the first upload.

---

## Signing and Build

- [ ] Confirm bundle identifier is registered in App Store Connect.
- [ ] Confirm development team `8VC4R5M425` matches the certificate and provisioning profile.
- [ ] Confirm deployment target is intentional (see Blocker #2 above).
- [ ] Archive with **Release** configuration.
- [ ] Upload dSYMs with the build (enabled by default with `DEBUG_INFORMATION_FORMAT =
      dwarf-with-dsym` in Release).
- [ ] Verify the generated Info.plist in the archive contains the correct bundle ID, version,
      and short version string.

---

## Privacy and Permissions Guidance

No permissions are implemented in the current build. Add the relevant `INFOPLIST_KEY_*`
build settings or a separate Info.plist entry **only when the corresponding feature ships**.
Adding unused permission strings will cause App Review rejection.

| Feature | Key | When to add |
|---|---|---|
| Run tracking | `NSLocationWhenInUseUsageDescription` | When Core Location tracking is wired into RunTabView |
| HealthKit read | `NSHealthShareUsageDescription` | When HealthKit sync is implemented |
| HealthKit write | `NSHealthUpdateUsageDescription` | When workout saving to Health is implemented |
| Notifications | `NSUserNotificationsUsageDescription` | When ReminderPreferencesScaffold posts real notifications |
| Garmin OAuth | `CFBundleURLTypes` with callback scheme | When Garmin Connect OAuth flow is implemented |
| Strava OAuth | `CFBundleURLTypes` with callback scheme | When Strava OAuth flow is implemented |
| Live API | `NSAppTransportSecurity` domain exception | When URLSessionRunSmartAPIClient is wired to a real base URL |

For HealthKit and Location, also add the corresponding capabilities to the Xcode target
(Signing & Capabilities → +) to generate the required entitlements file. The app currently
has no entitlements file, which is correct while these features are absent.

---

## Manual Device Testing

### Cold Launch
1. Kill the app from the app switcher.
2. Tap the icon. App must reach the Today tab without a black screen or crash.
3. Verify the RunSmart logo, coach greeting, and Readiness card are visible within 1 second.

### Tab Navigation
4. Tap each of the four tabs in order: Today → Plan → Run → Profile.
5. Verify each tab renders without a blank screen or console error.
6. Return to Today from Profile in a single tap.

### Coach Sheet
7. On Today, tap **Talk to Coach**. Coach sheet must open at full height.
8. Tap the drag indicator; sheet must dismiss.
9. Re-open coach sheet, type a message, and tap Send. Message appears in thread; input clears.
10. Attempt to send an empty message. Nothing should happen.
11. Repeat steps 7–8 from Plan, Run, and Profile tabs.

### Secondary Sheets
12. On Today, tap the Coach Insight card. Workout Detail sheet must open.
13. On Plan, tap the plan adjustment entry. Plan Adjustment sheet must open.
14. On Run, tap **Finish**. Post-Run Summary sheet must open.
15. On Profile, tap each settings tile (Voice Coaching, Coaching Tone, Goal Focus, Check-in
    Cadence). Each opens the correct secondary sheet.
16. On Profile, tap Garmin Connect and Strava cards. Connected Service Detail opens.
17. Verify every secondary sheet has a visible title and subtitle and can be dismissed.

### Run Controls
18. On Run tab, tap **Audio**. Audio Cues sheet opens.
19. On Run tab, tap **Lap**. Lap Marker sheet opens.
20. On Run tab, tap **Pause**. No crash (button is wired but action is empty — verify no hang).
21. On Run tab, tap **Tap to talk**. Coach sheet opens.

### One-Handed and Small Device
22. Test all of the above steps on an iPhone SE (or the smallest available simulator).
23. Verify no button is clipped, no text truncates in a way that breaks meaning, and the
    custom tab bar remains reachable with a thumb.

---

## Known Gaps Before External TestFlight

- Mock data only — all service calls return hardcoded preview data.
- No live authentication.
- No real coach streaming (coach messages are local echoes).
- No Core Location run tracking.
- No HealthKit, Garmin, or Strava sync (ConnectedServiceDetailScaffold shows mock status).
- No unit test target (see Project Settings Audit for rationale).
- No app icon.
- Deployment target requires iOS 26 beta device.

---

## Project Settings Audit (2026-04-28)

| Setting | Current Value | Assessment |
|---|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET` | 26.2 | Blocker for external testers; fine for internal iOS 26 beta |
| `PRODUCT_BUNDLE_IDENTIFIER` | `RunSmart-IOS.IOS-RunSmart-app` | Non-standard style; must be registered; cannot be renamed after first upload |
| `CODE_SIGN_STYLE` | Automatic | Good |
| `DEVELOPMENT_TEAM` | 8VC4R5M425 | Present; verify certificate is active |
| `GENERATE_INFOPLIST_FILE` | YES | Good; add `INFOPLIST_KEY_*` settings per the table above as features ship |
| `MARKETING_VERSION` | 1.0 | Fine for first build |
| `CURRENT_PROJECT_VERSION` | 1 | Must increment with every TestFlight upload |
| `TARGETED_DEVICE_FAMILY` | 1,2 (iPhone + iPad) | iPad is untested; narrow to 1 (iPhone only) if iPad layout is not a priority |
| `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` | Portrait + Landscape | Running apps typically lock to portrait; landscape may show layout issues |
| `AppIcon.appiconset` | Empty | Hard blocker — add 1024×1024 icon before archiving |
| Entitlements file | None | Correct while Location and HealthKit are not implemented |
| `objectVersion` | 77 (Xcode 26 beta format) | Cannot be opened by Xcode < 26 |

---

## Release Gate

- [ ] Clean Xcode build with no warnings.
- [ ] Manual QA checklist complete on at least two device sizes.
- [ ] No console runtime warnings during normal navigation.
- [ ] Privacy strings and capabilities match exactly what the shipped build uses — no more,
     no less.
- [ ] `CURRENT_PROJECT_VERSION` incremented from the previous upload.
- [ ] App icon present and validated in Xcode asset catalog.
