# Plan: HRV Dual-Source Collection + Garmin Attribution (v1.0.4 / build 17)

> Run this inside the RunSmart iOS repo. Part of v1.0.4 (build 17) — must ship **before** replying to Garmin.
> Sequencing is strict (no parallel work): finish every brand surface in the app → archive 1.0.4(17) →
> upload + submit to App Store → only then reply to Garmin (ticket 213145/213165). Garmin replies fast and
> inspects the live app, so the App Store build must already match the screenshots.

## Objective (one sentence)
Collect HRV from **both** Garmin and HealthKit, track each reading's provenance, and show a Garmin
attribution whenever the HRV is Garmin device-sourced (including Garmin data synced into HealthKit) —
on the Today HRV card and the Recovery/Wellness views — without mischaracterizing Apple Watch HRV.

## Why
- Founder uses a Garmin device and syncs Garmin data into Apple Health. So HRV can arrive two ways:
  (a) directly from Garmin, (b) via HealthKit where the originating app is **Garmin Connect**.
- Garmin API Brand Guidelines require a "Garmin [device model]" attribution wherever Garmin
  device-sourced data appears — this explicitly includes data transmitted through other systems.
- We deferred the Today HRV card earlier precisely because HRV can also be Apple Watch-sourced;
  this plan resolves that by detecting provenance instead of guessing.

## Current state (verified 2026-06-22)
- `Services/HealthKit/HealthKitSyncService.swift`
  - `HealthKitDailySnapshot` (line 7) has `hrvMilliseconds: Double?` — **no source field**.
  - HRV is read via `quantityAverage(.heartRateVariabilitySDNN…)` (line 343) — a plain average with
    **no `HKSource`/`HKSourceRevision`**, so Garmin-origin HRV is indistinguishable from Apple Watch.
- **No** `HKSource` / bundle-identifier / `com.garmin` detection exists anywhere in the app.
- `RecoverySnapshot` (`Models/RunSmartModels.swift:1326`) exposes `hrv: String` — no source.
- Production recovery loads a stored `HealthKitDailySnapshot`; Garmin gateway HRV is not yet wired.
- Garmin Connect writes to HealthKit under bundle id **`com.garmin.connect.mobile`**; Apple Watch
  under **`com.apple.health.*`** (the device source is the watch). Use the bundle id to classify.

## Design
Add a small `HRVSource` provenance enum and thread it from the HealthKit read → snapshot model →
recovery/today view models → the cards. Keep the classification and precedence as **pure functions**
so they are unit-testable without HealthKit or the simulator (TDD).

Provenance precedence (highest wins) when multiple readings exist for the day:
1. Direct Garmin API HRV → `.garmin`
2. HealthKit HRV whose source bundle is `com.garmin.connect.*` → `.garmin`
3. HealthKit HRV from `com.apple.*` (Apple Watch) → `.appleHealth`
4. Anything else / unknown → `.unknown`

Attribution mapping (display):
- `.garmin` → show `Garmin` attribution (brand-required). Once device model is surfaced, `Garmin <model>`.
- `.appleHealth` → show `Apple Health` (accurate, non-Garmin).
- `.unknown` → no source-specific attribution.

---

## Story 1 — Provenance model (TDD)
**Files:** `Models/RunSmartModels.swift`, `Services/HealthKit/HealthKitSyncService.swift`, `IOS RunSmart appTests/HRVSourceTests.swift`

1. Add `enum HRVSource: String, Codable, Hashable { case garmin, appleHealth, unknown }` with a
   computed `attributionLabel: String?` (`"Garmin"`, `"Apple Health"`, `nil`).
2. Add `var hrvSource: HRVSource = .unknown` to `HealthKitDailySnapshot` and a `hrvSource` to
   `RecoverySnapshot` (default `.unknown`; keep Codable back-compat — make it optional-with-default).
3. Tests: Codable round-trip with and without the new field present (back-compat for stored snapshots);
   `attributionLabel` mapping.

**Acceptance:** build + tests green. No behavior change yet.

## Story 2 — Source classification from HealthKit samples (TDD)
**Files:** `Services/HealthKit/HealthKitSyncService.swift`, `IOS RunSmart appTests/HRVSourceTests.swift`

1. Add a **pure** classifier: `static func classifyHRVSource(bundleIdentifier: String?) -> HRVSource`
   - `com.garmin.connect.*` → `.garmin`
   - `com.apple.*` → `.appleHealth`
   - else → `.unknown`
2. Add a sample-aware read: an `HKSampleQuery` for `.heartRateVariabilitySDNN` that returns the
   day's samples; compute the average **and** the dominant source bundle (most recent sample, or the
   source contributing the most samples — pick most-recent for determinism). Map via the classifier.
3. Populate `HealthKitDailySnapshot.hrvSource`. Keep `quantityAverage` for the value, or fold both
   into one query.
4. Tests for `classifyHRVSource` cover: garmin bundle, apple bundle, third-party bundle, nil.

**Acceptance:** build + tests green; a HealthKit snapshot now carries a real `hrvSource`.

## Story 3 — Merge Garmin API + HealthKit HRV with precedence (TDD)
**Files:** `Services/Production/RunSmartProductionServices.swift` (recovery assembly), `Services/RunSmartServices.swift`, `IOS RunSmart appTests/HRVSourceTests.swift`

1. Add a **pure** merge function:
   `static func resolveHRV(garminDirect: (value: Double, )?, healthKit: (value: Double, source: HRVSource)?) -> (value: Double, source: HRVSource)?`
   implementing the precedence above.
2. Wire it into `recoverySnapshot()` / `wellnessTrendSeries()` so `RecoverySnapshot.hrvSource` is set.
   (Garmin-direct HRV may be nil until the gateway provides it — that's fine; HealthKit path covers the
   founder's Garmin-via-HealthKit case today.)
3. Tests: precedence matrix (garmin-direct beats healthkit; garmin-via-healthkit beats apple; apple
   only; none).

**Acceptance:** build + tests green; recovery snapshot reports the correct `hrvSource` for each combo.

## Story 4 — Surface + attribute HRV on the cards (TDD where logic, screenshot for UI)
**Files:** `Features/Today/TodayTabView.swift` (HRV card ~line 919), `Features/Recovery/RecoveryDashboardView.swift`, `Features/Wellness/GarminWellnessViews.swift`

1. Pass `hrvSource` into the HRV card(s).
2. Render attribution from `hrvSource.attributionLabel` directly under the HRV heading, above the fold,
   plain unstylized text (matches the approved Garmin pattern). Show nothing when `nil`.
3. Today HRV card: previously had no attribution — now shows `Garmin` when Garmin-sourced,
   `Apple Health` when Apple Watch-sourced.
4. Recovery/Wellness: the unconditional "Garmin" we added in 1.0.4 stays for the Garmin-only Wellness
   screen; the Recovery dashboard HRV tile should reflect `hrvSource` like the Today card.

**Acceptance:** build green; visual check that attribution flips correctly with source.

## Story 5 — Verify + re-capture evidence
1. `xcodebuild … -scheme "IOS RunSmart app" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED.
2. Run the Today HRV and Recovery screens in demo mode; confirm `Garmin` attribution renders for the
   Garmin demo state.
3. Re-capture the affected screenshots; refresh `runsmart-garmin-screenshots-ios-2026-06-22.zip` in the
   web repo (`docs/garmin-application/`).
4. Update `tasks/progress.md` + `docs/garmin-application/GARMIN-STATUS.md`.

---

## Test target
`IOS RunSmart appTests/` (see `StriverPersonaGateTests.swift` for style). New file: `HRVSourceTests.swift`.
Keep classification, precedence, and attribution-mapping as pure functions so the whole feature is
covered without HealthKit entitlements or a simulator.

## Build / test commands
```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
# build
xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build CODE_SIGNING_ALLOWED=NO
# unit tests (pure-logic stories 1-3)
xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test CODE_SIGNING_ALLOWED=NO
```

## Out of scope (later)
- Garmin device **model** string (would upgrade `Garmin` → `Garmin Forerunner 265`). Needs the model
  from the Garmin API / HealthKit device; tracked separately.
- Workout-push / Training API (separate feature for the transfer screenshot).
- Official Garmin Connect tile asset swap in `FlowHeader.headerMark`.

## Definition of done (for v1.0.4 inclusion)
- HRV collected from Garmin and HealthKit with correct provenance.
- Today HRV card + Recovery HRV show `Garmin` when Garmin-sourced (incl. via HealthKit), `Apple Health`
  otherwise; no mischaracterization.
- Unit tests green for classification + precedence + attribution mapping.
- Build green; screenshots refreshed; status docs updated.
- Then: archive 1.0.4(17) → upload → submit → (after live/submitted) reply to Garmin.
