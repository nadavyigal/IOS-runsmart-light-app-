---
product: RunSmart iOS
artifact: PRD
feature: HRV dual-source attribution
status: draft
founder-review-needed: yes
date: 2026-06-22
source-plan: tasks/plan-hrv-dual-source-attribution-2026-06-22.md
source-pr: "#55"
release-train: v1.0.4 build 17
---

# PRD: HRV Dual-Source Attribution

## 1. Summary

RunSmart needs to collect HRV from both Garmin and HealthKit while preserving source provenance, so the app can show Garmin attribution only when HRV is Garmin device-sourced. Today HRV is stored as a plain value, so Garmin HRV synced through HealthKit cannot be separated from Apple Watch HRV.

This PRD turns PR #55's plan into a product gate for v1.0.4 build 17. The goal is correct attribution, not broader Garmin coaching or new wellness features.

## 2. Contacts

| Name | Role | Comment |
|---|---|---|
| Nadav Yigal | Founder, product owner | Reviews scope, approves Garmin reply and App Store sequencing. |
| Codex | PM layer agent | Converts PR #55 plan into PM artifacts and release risks. |
| Implementation agent | Engineering executor | Executes one approved story at a time from this PRD. |
| Garmin reviewer | External reviewer | Reviews the live app and screenshots for attribution compliance. |

## 3. Background

PR #55 is open on `garmin/ios-v1.0.4-brand-completeness`. It already includes a brand-completeness sweep, version bump to `1.0.4 (17)`, and a plan for HRV dual-source collection plus provenance attribution.

The key code finding is clear:

- `HealthKitDailySnapshot` has `hrvMilliseconds` but no source field.
- `HealthKitSyncService.readDailySnapshot` reads HRV through a daily average, without sample source detection.
- `RecoverySnapshot` exposes `hrv` as a display string, with no source.
- Recovery and Today surfaces can show HRV without knowing whether it came from Garmin, Apple Watch, or another HealthKit writer.

Why now: Garmin requires device-sourced data attribution, including Garmin data transmitted through another system. If RunSmart shows Garmin HRV without attribution, it risks Garmin rejection. If RunSmart labels Apple Watch HRV as Garmin, it misleads users and creates the opposite brand problem.

## 4. Objective

The objective is to make HRV source-aware before v1.0.4 is submitted or used as Garmin review evidence.

This matters because runners use HRV as a recovery signal. The app must tell them the truth about where that signal came from. The business value is lower Garmin review risk, cleaner App Store resubmission evidence, and a safer foundation for future adaptive coaching.

### Key Results

1. Before v1.0.4 build 17 is submitted, HRV has a source model that can represent Garmin, Apple Health, and unknown.
2. Before v1.0.4 build 17 is submitted, HealthKit HRV reads classify Garmin Connect samples as Garmin-sourced and Apple samples as Apple Health-sourced.
3. Before v1.0.4 build 17 is submitted, Today and Recovery HRV surfaces show `Garmin` only for Garmin-sourced HRV and `Apple Health` only for Apple-sourced HRV.
4. Before v1.0.4 build 17 is submitted, pure unit tests cover source classification, attribution labels, Codable back-compat, and precedence.
5. Before replying to Garmin, screenshots and status docs match the submitted or live v1.0.4 behavior.

## 5. Market Segments

### Primary segment

Runners who use Garmin and sync Garmin data into Apple Health.

Their job: "Use my Garmin recovery data in RunSmart, and make it clear that Garmin is the source."

### Secondary segment

Runners who use Apple Watch or Apple Health without Garmin.

Their job: "Use my Apple Health HRV accurately without labeling it as Garmin."

### Constraints

- Garmin attribution must be visible near Garmin device-sourced HRV.
- Apple Watch HRV must not be described as Garmin data.
- Existing stored HealthKit snapshots must continue decoding.
- HealthKit sample-source logic must be testable without relying on simulator entitlements.
- No broad redesign, new paid feature, or Garmin device-model work belongs in this release slice.

## 6. Value Propositions

### For Garmin runners

- RunSmart can use Garmin HRV even when it arrives through HealthKit.
- Garmin-sourced HRV gets visible attribution.
- Garmin review evidence is more credible because the app handles the real sync path.

### For Apple Health runners

- Apple Watch HRV remains useful without false Garmin branding.
- Recovery views stay honest when Garmin is disconnected.

### For RunSmart

- The app avoids brand-compliance regressions.
- The HRV model becomes ready for future adaptive coaching.
- Tests capture the risky logic as pure functions.

## 7. Solution

### 7.1 UX and surfaces

Affected surfaces:

- Today wearable trend HRV row.
- Recovery dashboard HRV tile.
- Garmin Wellness screen, which remains Garmin-only and keeps Garmin attribution.
- Screenshots used for Garmin ticket 213145/213165.

The UI rule is simple:

- Garmin-sourced HRV shows `Garmin`.
- Apple-sourced HRV shows `Apple Health`.
- Unknown HRV shows no source-specific attribution.

### 7.2 Key features

#### Provenance model

Add an `HRVSource` model with these states:

- `garmin`
- `appleHealth`
- `unknown`

The model needs a display attribution label and safe defaults for older stored snapshots.

#### HealthKit source classification

HealthKit HRV reads must inspect sample source metadata, classify bundle identifiers, and carry the result into `HealthKitDailySnapshot`.

The PR plan treats Garmin Connect bundle identifiers as Garmin-sourced and Apple bundle identifiers as Apple Health-sourced. This is a high-risk assumption that needs a real-device validation path.

#### HRV precedence

If multiple HRV paths exist:

1. Direct Garmin API HRV wins.
2. Garmin-via-HealthKit HRV wins over Apple Health.
3. Apple Health HRV wins over unknown.
4. Unknown is shown without source attribution.

#### Display attribution

The Today HRV and Recovery HRV views must consume the source model, not infer source from Garmin connection state alone.

### 7.3 Technology

Likely implementation surfaces from PR #55:

- `HealthKitSyncService.swift`
- `RunSmartModels.swift`
- `SupabaseRunSmartServices.swift`
- `TodayTabView.swift`
- `RecoveryDashboardView.swift`
- `GarminWellnessViews.swift`
- New tests in `IOS RunSmart appTests/HRVSourceTests.swift`

The core classification and precedence logic should be pure functions.

### 7.4 Assumptions

- Garmin Connect writes HealthKit HRV with a stable bundle identifier that can be classified.
- HealthKit sample queries can retrieve enough source metadata for the day's HRV readings.
- Most-recent sample is an acceptable deterministic source rule when multiple HRV sources exist on the same day.
- Existing storage can decode snapshots without the new source field.
- Build 17 can be submitted after screenshots and status docs are refreshed.

## 8. Release

### First version

The first version should ship only source-aware HRV attribution:

- Add the model.
- Classify HealthKit HRV source.
- Resolve HRV source precedence.
- Show source-aware attribution on Today and Recovery.
- Keep Garmin Wellness attribution.
- Add focused tests.
- Re-capture evidence.

### Later versions

- Garmin device model attribution, such as `Garmin Forerunner 265`.
- Workout-push or Training API work.
- Official Garmin Connect tile asset swap.
- More detailed multi-source HRV history.

### Release gate

Do not treat PR #55 as merge-ready for App Store resubmission until the launch-blocking pre-mortem Tigers are closed or explicitly accepted by the founder.
