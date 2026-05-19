# App Store Readiness Checklist — RunSmart v1.0 (build 5)

_Last updated: 2026-05-18_

## Code & Branch
- [x] All sprint work (Sprint 1–8) merged to `main`
- [x] `main` is the GitHub default branch
- [x] Stale branches deleted (sprint-8, runsmart-lite-build, routes, recovery/*, codex/*, fix/*)
- [x] GarminBridge polling flood fixed (debounce + 60s cache)

## Build
- [x] Version: 1.0 / Build: 5
- [x] Xcode project compiles without errors on Sprint 8 code
- [x] Privacy manifest (`PrivacyInfo.xcprivacy`) covers UserID, Health, Fitness, PreciseLocation
- [x] Entitlements: HealthKit, Apple Sign In, Associated Domains (runsmart-ai.com)
- [ ] Fresh archive from build 5 created (existing archives are build 4, pre-Sprint 8)
- [ ] Archive uploaded to App Store Connect

## Backend & Production
- [x] Production backend URL: `https://runsmart-ai.com` in Info.plist
- [x] Garmin gateway URL: `https://www.runsmart-ai.com/api/devices/garmin/connect`
- [x] Supabase Edge Function `coach_message` deployed
- [x] Coach RLS policies are owner-scoped
- [ ] Verify runsmart-ai.com is live and SSL is valid
- [ ] Verify coach_message Edge Function returns 200 for authenticated users

## App Store Connect
- [ ] App name and subtitle finalized
- [ ] App description written (no medical claims, no overpromised AI)
- [ ] Keywords set
- [ ] 6.7-inch and 6.1-inch screenshots captured from real device
- [ ] Support URL available (e.g., runsmart-ai.com/support)
- [ ] Privacy policy URL available
- [ ] Age rating set (4+)
- [ ] Category: Health & Fitness

## Compliance & Legal
- [x] Privacy manifest matches data collection (Health, Fitness, PreciseLocation linked to app functionality)
- [x] No medical diagnosis claims in UI
- [x] Location usage string is accurate (background only during active run)
- [x] HealthKit usage string is accurate
- [ ] Terms of service and privacy policy URL live
- [ ] Health claim copy reviewed for App Review guideline 5.1.3 compliance

## Test Account for App Review
- [ ] Test account credentials prepared
- [ ] Test account has a training plan loaded
- [ ] Instructions for reviewer documented (how to trigger Coach, start a run, view plan)

## Console Errors — Known Benign (do not file as bugs)
- `Failed to locate resource named "default.csv"` — MapKit framework internal
- `unsafeForcedSync called from Swift Concurrent context` — Supabase SDK internal
- `System gesture gate timed out` — iOS gesture subsystem
- `The variant selector cell index number could not be found` — UIKit emoji picker
- `PerfPowerTelemetryClientRegistrationService` errors — Sandbox restriction on device
