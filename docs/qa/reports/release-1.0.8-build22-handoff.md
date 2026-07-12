# RunSmart 1.0.8 (22) — App Store Connect release handoff

**Date:** 2026-07-12  
**Source commit:** `main` @ `2877fcb` + version bump  
**Replaces ASC build:** 1.0.7 (21) — submitted ~2026-07-05 (WP-15 only)  
**ASC status:** **Archived 2026-07-12 — waiting for App Store Connect / App Review**

## Verdict: **Archived — awaiting review**

Automated Release archive **compiled and validated successfully**. Command-line export used a **Development** cert (expected without interactive Xcode login) — you must archive via **Xcode Organizer** so Distribution signing applies.

## What's in this build

| Work package | Highlights |
|---|---|
| **WP-40** | Apple Health in onboarding + auto-import on connect; Today activity card |
| **WP-38** | Live km splits, moving time labels, Live Activity, screen awake, haptics, a11y |
| **WP-37** | GPS transient errors, recorder reset, real splits, RPE persist, PreRun honesty, SE fixes |

## Pre-flight checks (done)

- [x] No Finder `* 2.swift` duplicates in app source
- [x] `RunSmartSecrets.xcconfig` present (PostHog key)
- [x] `MARKETING_VERSION = 1.0.8`, `CURRENT_PROJECT_VERSION = 22` (all targets)
- [x] Release archive build succeeded (clean worktree validation)
- [x] Archive Info.plist: `com.runsmart.lite`, `ITSAppUsesNonExemptEncryption = false`
- [x] Release notes drafted: `fastlane/metadata/en-US/release_notes.txt`
- [ ] **You:** `Product → Archive` with Distribution signing (Xcode GUI)
- [ ] **You:** Upload via Organizer → App Store Connect
- [ ] **You:** TestFlight smoke (onboarding HealthKit step + Today card)

## Your 5-minute Xcode steps

1. **Pull / save** — ensure `project.pbxproj` shows **1.0.8 (22)** (already bumped locally).
2. Open **`IOS RunSmart app.xcodeproj`** — signed in to team **8VC4R5M425**.
3. Scheme **IOS RunSmart app** → destination **Any iOS Device (arm64)**.
4. **Signing & Capabilities** — Automatic signing on for:
   - `IOS RunSmart app` (`com.runsmart.lite`)
   - `RunSmartRunLiveActivityExtension` (`com.runsmart.lite.runliveactivity`)
5. **Product → Archive** (⌘B clean optional first).
6. **Organizer → Distribute App → App Store Connect → Upload**.
7. In ASC: set **What's New** from `fastlane/metadata/en-US/release_notes.txt`.

## TestFlight smoke (before App Store release)

| # | Check |
|---|---|
| 1 | Fresh install → onboarding shows **Connect Apple Health** step |
| 2 | Connect → sync runs immediately (no second manual tap) |
| 3 | Today → **Today's activity / Apple Health** with real steps/kcal |
| 4 | Record a short run → live splits appear after 1 km (if distance allows) |
| 5 | Lock screen shows run Live Activity (supported devices) |

## Post-upload

- Re-run **WP-42** PostHog funnel after 3–7 days of real TestFlight/App Store users on **1.0.8 (22)**.
- Prior build-21 funnel data was founder QA traffic only — not comparable.

## Validation artifact

CLI archive (Development-signed, for compile proof only):  
`/tmp/rs-release-108-22/build/RunSmart-v1.0.8-build22-AppStore.xcarchive`

Safe to delete after your Xcode archive succeeds: `rm -rf /tmp/rs-release-108-22`
