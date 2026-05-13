# GPS Background Tracking Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `RunRecorder` so GPS location updates continue being delivered when the screen locks during a run, preventing the "6 points in 33 minutes" dropout.

**Architecture:** `RunRecorder` already has `UIBackgroundModes: location` in Info.plist and `pausesLocationUpdatesAutomatically = false`, but is missing the required programmatic flag `allowsBackgroundLocationUpdates = true` on its `CLLocationManager`. iOS requires both the plist key **and** the runtime flag to deliver location updates while the app is backgrounded. Adding two lines to `RunRecorder.init()` is the complete fix.

**Tech Stack:** Swift, CoreLocation (`CLLocationManager`), XCTest

---

## Investigation Summary

### Symptoms observed
| Source | Distance | Points | Time | Pace |
|--------|----------|--------|------|------|
| RunSmart | 1.08 km | 6 pts | 36:27 | 33:38/km |
| Garmin (actual) | 6.24 km | full route | 33:45 | 5:24/km |

6 GPS points in 33 minutes = roughly one point every 5–6 minutes. This matches the pattern where location is only delivered while the screen is active — the user started the run (screen on), glanced at the phone 3–4 times mid-run, then finished (screen on). Every screen-lock gap = no GPS points.

### Root cause: missing `allowsBackgroundLocationUpdates`

**File:** `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`  
**Location:** `RunRecorder.init()` at line 202–210

Current configuration:
```swift
manager.activityType = .fitness                        // ✅ correct
manager.desiredAccuracy = kCLLocationAccuracyBest      // ✅ correct
manager.distanceFilter = 5                             // ✅ correct
manager.pausesLocationUpdatesAutomatically = false     // ✅ correct
// manager.allowsBackgroundLocationUpdates = true      // ❌ MISSING
// manager.showsBackgroundLocationIndicator = true     // ❌ MISSING (required for App Store)
```

**What Apple requires for background location (both must be true):**
1. ✅ `UIBackgroundModes` contains `location` in `RunSmartInfo.plist` (line 56–58) — already present
2. ❌ `manager.allowsBackgroundLocationUpdates = true` on the `CLLocationManager` instance — **missing**

Without (2), iOS suspends location delivery the moment the app is backgrounded, regardless of (1).

**`showsBackgroundLocationIndicator`:** Apple requires this set to `true` when `allowsBackgroundLocationUpdates` is true. It displays the blue location indicator in the iOS status bar so the user knows tracking is active. Omitting it causes App Store rejection.

---

## File Map

| File | Change |
|------|--------|
| `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift` | Add 2 lines to `RunRecorder.init()` |
| `IOS RunSmart app/IOS RunSmart appTests/RunSmartReadinessTests.swift` | Add 1 test verifying continuous location accumulation |

---

## Task 1: Add background location flags to RunRecorder

**Files:**
- Modify: `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift:202-210`

- [ ] **Step 1: Open the file and locate the init block**

  The `RunRecorder.init(store:)` starts at line 202. The location manager configuration block currently ends at line 210:
  ```swift
  init(store: RunSmartLocalStore) {
      self.store = store
      super.init()
      manager.delegate = self
      manager.activityType = .fitness
      manager.desiredAccuracy = kCLLocationAccuracyBest
      manager.distanceFilter = 5
      manager.pausesLocationUpdatesAutomatically = false
      updatePhaseForAuthorization()
  }
  ```

- [ ] **Step 2: Add the two missing lines**

  Replace the init block so it reads:
  ```swift
  init(store: RunSmartLocalStore) {
      self.store = store
      super.init()
      manager.delegate = self
      manager.activityType = .fitness
      manager.desiredAccuracy = kCLLocationAccuracyBest
      manager.distanceFilter = 5
      manager.pausesLocationUpdatesAutomatically = false
      manager.allowsBackgroundLocationUpdates = true
      manager.showsBackgroundLocationIndicator = true
      updatePhaseForAuthorization()
  }
  ```

  `allowsBackgroundLocationUpdates = true` — enables location delivery when the app is backgrounded (screen locked, user switches apps).  
  `showsBackgroundLocationIndicator = true` — shows the blue status bar pill ("RunSmart is using your location"). Required by Apple; omitting it causes App Store rejection when background location is enabled.

- [ ] **Step 3: Build and verify no compile errors**

  Open the project in Xcode and build (`⌘B`). No new errors expected — these are standard `CLLocationManager` properties.

---

## Task 2: Add a test that verifies continuous location accumulation

This test exercises the recording pipeline with 30 consecutive location updates (simulating what should happen during a full background run). It verifies no location is silently dropped due to logic errors and that distance accumulates correctly across many points.

**Files:**
- Modify: `IOS RunSmart app/IOS RunSmart appTests/RunSmartReadinessTests.swift`

- [ ] **Step 1: Write the failing test**

  Add the following test to `RunSmartReadinessTests` (after `testRunRecorderDisplayRouteSimplificationPreservesRawRouteData`):

  ```swift
  @MainActor
  func testRunRecorderAccumulatesAllPointsAcrossConsecutiveLocationUpdates() {
      let recorder = RunRecorder()
      let origin = Date(timeIntervalSince1970: 5_000)

      // Acquire GPS lock
      recorder.startAcquiringLocation(startLocationUpdates: false)
      recorder.handleLocationUpdates([
          makeLocation(latitude: 32.0800, longitude: 34.7800, accuracy: 12, timestamp: origin)
      ], now: origin)
      XCTAssertEqual(recorder.phase, .recording, "should enter recording after good lock")

      // Simulate 29 more location updates arriving ~5 m apart (as they would during background tracking)
      for i in 1...29 {
          let t = origin.addingTimeInterval(Double(i) * 4)
          // Each step moves ~11 m north — well above the 1 m minimum delta
          let lat = 32.0800 + Double(i) * 0.0001
          recorder.handleLocationUpdates([
              makeLocation(latitude: lat, longitude: 34.7800, accuracy: 12, timestamp: t)
          ], now: t)
      }

      // 1 start point + 29 subsequent = 30 total; none should be dropped
      XCTAssertEqual(recorder.routePoints.count, 30)
      // Each step is ~11 m; 29 steps ≈ 319 m minimum
      XCTAssertGreaterThan(recorder.distanceMeters, 200)
      recorder.discard()
  }
  ```

- [ ] **Step 2: Run the test to verify it passes (it should — the logic already works)**

  In Xcode: `⌘U` or run the single test via the diamond gutter button.

  Expected: PASS. This confirms the accumulation logic is correct. The bug was purely in OS-level delivery (the missing `allowsBackgroundLocationUpdates`), not in `handleLocationUpdates`.

  If it fails: something is wrong with the location filter logic or the test coordinates — investigate before continuing.

- [ ] **Step 3: Commit**

  ```bash
  git add "IOS RunSmart app/Services/Production/RunSmartProductionServices.swift"
  git add "IOS RunSmart app/IOS RunSmart appTests/RunSmartReadinessTests.swift"
  git commit -m "fix: enable background GPS tracking in RunRecorder

  Add allowsBackgroundLocationUpdates = true and showsBackgroundLocationIndicator = true
  to RunRecorder's CLLocationManager. Without the runtime flag, iOS suspends location
  delivery when the screen locks even though UIBackgroundModes has 'location' in
  Info.plist — causing only ~6 points to be recorded across a 33-minute run.
  Also adds a regression test that verifies 30 consecutive location updates all
  accumulate correctly."
  ```

---

## Task 3: Manual verification on device

Unit tests cannot simulate OS-level background location delivery. After building and installing to device, verify the fix works end-to-end.

- [ ] **Step 1: Build and install to physical iPhone**

  Select your device in Xcode and run (`⌘R`). Simulator cannot replicate background GPS accurately.

- [ ] **Step 2: Start a recording, lock the screen, walk/run for 2+ minutes**

  1. Open RunSmart → Run tab → tap Start
  2. Wait for "Recording now" state (phase = `.recording`)
  3. **Lock the phone screen** (side button)
  4. Walk or run for at least 2 minutes
  5. Unlock and open RunSmart

- [ ] **Step 3: Verify the blue location indicator appeared in the status bar**

  While the screen was locked you should have seen the blue status bar pill ("RunSmart is using your location") when you briefly unlocked. This confirms `showsBackgroundLocationIndicator` is working and iOS is delivering background updates.

- [ ] **Step 4: Verify distance and route points**

  After finishing the run:
  - Distance should reflect actual movement (not a straight-line approximation)
  - Route map should show a continuous path, not just start + finish + a few points
  - Route point count in the Post Run Summary should be significantly higher than 6

- [ ] **Step 5: Compare against expected**

  For a 2-minute outdoor walk at normal pace (~5 km/h), expect:
  - At least 20–30 route points (one per ~5 m moved)
  - Distance between 140–200 m
  - Route that traces your actual path on the map

---

## Self-Review

**Spec coverage:**
- Root cause (missing `allowsBackgroundLocationUpdates`) ✅ Task 1
- `showsBackgroundLocationIndicator` for App Store compliance ✅ Task 1  
- Regression test ✅ Task 2
- End-to-end device verification ✅ Task 3

**Placeholder scan:** No TBDs, no "similar to above", all code blocks complete.

**Type consistency:** `makeLocation`, `RunRecorder`, `RunRoutePoint` — all match existing test helpers in the same file.

**What this plan does NOT cover:**
- Upgrading permission from "When In Use" to "Always" — not needed; background mode + `allowsBackgroundLocationUpdates` works with "When In Use" authorization when `UIBackgroundModes` contains `location`
- Heart rate during GPS runs — separate concern (requires HealthKit workout session or Apple Watch)
- Historical run correction (today's 1.08 km record) — can be manually deleted and re-run
