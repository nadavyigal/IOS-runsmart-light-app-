# RunSmart 1.0.8 (22) public-build smoke evidence

**Date:** 2026-07-13  
**Distribution:** Public App Store  
**Binary:** `com.runsmart.lite`, version `1.0.8`, build `22`  
**Device:** Paired physical iPhone  
**Scope:** Evidence only; no product code or feature changes

## Verdict

**Partial pass.** Public installation, Today Apple Health data, run entry, short-run recording, finish confirmation, and saved completion all passed. A true first-account HealthKit onboarding replay and true first-run-user state were **not observed** because the public reinstall restored an existing signed-in account with prior onboarding and run history.

## Results

| Check | Result | Evidence |
|---|---|---|
| Public 1.0.8 (22) install | PASS | CoreDevice app inventory reported `RunSmart`, `com.runsmart.lite`, version `1.0.8`, build `22`; public binary launched successfully. |
| HealthKit onboarding | NOT OBSERVED | Reinstall restored the existing signed-in/onboarded account and opened Today. No account deletion or destructive reset was performed. |
| HealthKit disclosure / connection | PASS | Profile showed `HealthKit — Connected`. Detail screen explicitly explained HealthKit read/write behavior and showed Activities, Sleep, Heart rate, HRV, Steps, and Routes enabled, with Connect and Sync controls. |
| Today data | PASS | Today showed Apple Health attribution with 1.8k steps and 46 active kcal. Sleep showed `--`, an honest missing-data state. |
| First-run CTA | PARTIAL | Run screen showed `GPS ready`, `Free Run`, and a prominent `Start Run` CTA. The account already had prior run history, so a true first-run-user condition was not established. |
| Short run | PASS | Recording advanced normally; at capture it showed 00:20 moving time, 7 m GPS accuracy, active route recording, and reachable Pause / Finish / Coach controls. |
| Finish confirmation | PASS | Short-run alert showed honest review-only copy and both `Finish and Save` and `Keep Recording`. |
| Completion | PASS | Activity saved after 1:41 as a review-only short activity with 0.00 km and 1 route point. Completion kept RPE unset and stated that the activity was too short for reliable analysis. |

## Evidence files

- `assets-2026-07-13-release-1.0.8-build22-live-smoke/01-today-apple-health.png`
- `assets-2026-07-13-release-1.0.8-build22-live-smoke/02-run-entry-cta.png`
- `assets-2026-07-13-release-1.0.8-build22-live-smoke/03-short-run-live.png`
- `assets-2026-07-13-release-1.0.8-build22-live-smoke/04-finish-dialog.png`
- `assets-2026-07-13-release-1.0.8-build22-live-smoke/05-completion.png`
- `assets-2026-07-13-release-1.0.8-build22-live-smoke/06-profile-healthkit-connected.png`
- `assets-2026-07-13-release-1.0.8-build22-live-smoke/07-healthkit-disclosure.png`

## Not run

- Destructive account deletion or server-side onboarding reset.
- New Apple-account registration to manufacture a fresh-user cohort.
- A distance-bearing outdoor run; this was intentionally a short indoor completion smoke.
- Build or XCTest validation; the tested artifact was the public App Store binary.

