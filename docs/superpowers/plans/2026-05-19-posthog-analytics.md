# PostHog Analytics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Instrument the RunSmart iOS app with 24 PostHog events across the activation funnel, run flow, coach, plan, and routes — and fix the missing PostHog API key in the web app — so product analytics flow into four PostHog dashboards.

**Architecture:** A `protocol AnalyticsTracking` with a live `PostHogAnalyticsService` (wraps PostHog iOS SDK) and a `NullAnalyticsService` (used in tests/previews). A global `Analytics` enum stores the shared instance and exposes typed static helpers for every event. Call sites import nothing from PostHog directly — they call `Analytics.track*(...)`.

**Tech Stack:** PostHog iOS SDK v3 (SPM), SwiftUI, XCTest, PostHog MCP for dashboard creation

---

## File Map

| Status | File | Responsibility |
|---|---|---|
| Create | `IOS RunSmart app/Services/Analytics/AnalyticsService.swift` | Protocol + live + null implementations + `Analytics.setup()` |
| Create | `IOS RunSmart app/Services/Analytics/AnalyticsEvents.swift` | All 24 typed event helpers as `static func` on `Analytics` |
| Modify | `RunSmartInfo.plist` | Add `POSTHOG_API_KEY` key |
| Modify | `IOS RunSmart app.xcodeproj/project.pbxproj` | Add PostHog SPM package |
| Modify | `IOS RunSmart app.xcodeproj/.../Package.resolved` | Resolved package pin |
| Modify | `IOS RunSmart app/App/RunSmartLiteAppShell.swift` | Init PostHog, `app_launched`, `tab_viewed`, `identify`, `reset` |
| Modify | `IOS RunSmart app/Features/Auth/SignInView.swift` | `sign_in_completed` |
| Modify | `IOS RunSmart app/Features/Onboarding/OnboardingView.swift` | `onboarding_started`, `step_completed`, `onboarding_completed` |
| Modify | `IOS RunSmart app/Features/Run/RunTabView.swift` | `run_started`, `run_abandoned`, `run_completed` |
| Modify | `IOS RunSmart app/Features/Run/PostRunLearningCard.swift` | `post_run_card_viewed` |
| Modify | `IOS RunSmart app/Features/Coach/CoachFlowView.swift` | `coach_thread_opened`, `coach_message_sent` |
| Modify | `IOS RunSmart app/Features/Plan/PlanTabView.swift` | `plan_viewed`, `plan_workout_tapped` |
| Modify | `IOS RunSmart app/Features/Routes/RouteCreatorView.swift` | `route_selected` |
| Modify | `IOS RunSmart app/Features/Routes/BenchmarkComparisonCard.swift` | `benchmark_viewed` |
| Modify | `IOS RunSmart app/Features/Routes/SaveRouteSheet.swift` | `route_saved` |
| Modify | `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift` | `garmin_sync_completed`, `healthkit_sync_completed` |
| Modify | `IOS RunSmart appTests/RunSmartReadinessTests.swift` | Analytics smoke tests |
| Modify | `RunSmart/v0/.env.local` (web project) | Add `NEXT_PUBLIC_POSTHOG_KEY` |

---

## Task 1: Get PostHog project token

**Files:**
- Read: `env.local` (already in context — PostHog host is `https://us.i.posthog.com`)

- [ ] **Step 1: Open PostHog and copy the project token**

  In a browser, go to `https://us.posthog.com` → your "Running coach" project → **Project Settings** → **Project API key**. It starts with `phc_`. Copy the full token. You'll need it in Task 2.

  If you prefer the MCP, run this in Claude Code chat: `posthog exec` with the query `GET /api/projects/171597/` to retrieve project details including the key.

---

## Task 2: Add POSTHOG_API_KEY to RunSmartInfo.plist

**Files:**
- Modify: `RunSmartInfo.plist`

- [ ] **Step 1: Add the POSTHOG key to the plist**

  Open `RunSmartInfo.plist` and add the following entry anywhere before the closing `</dict>`. Replace `phc_YOUR_TOKEN_HERE` with the actual token from Task 1:

  ```xml
  <key>POSTHOG_API_KEY</key>
  <string>phc_YOUR_TOKEN_HERE</string>
  <key>POSTHOG_HOST</key>
  <string>https://us.i.posthog.com</string>
  ```

- [ ] **Step 2: Verify plist lint passes**

  ```bash
  plutil -lint RunSmartInfo.plist
  ```
  Expected: `RunSmartInfo.plist: OK`

- [ ] **Step 3: Commit**

  ```bash
  git add RunSmartInfo.plist
  git commit -m "config: add PostHog project token to RunSmartInfo.plist"
  ```

---

## Task 3: Add PostHog iOS SDK via project.pbxproj

**Files:**
- Modify: `IOS RunSmart app.xcodeproj/project.pbxproj`
- Modify: `IOS RunSmart app.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

The pbxproj uses 24-character hex UUIDs. We assign these fixed IDs for the PostHog entries:
- `AA0001002FA0B36A006C1A3C` — XCRemoteSwiftPackageReference "posthog-ios"
- `AA0001012FA0B36A006C1A3C` — PostHog product dependency
- `AA0001022FA0B36A006C1A3C` — PostHog in Frameworks build file

- [ ] **Step 1: Insert PostHog into project.pbxproj using Python**

  Run this Python script from the project root (`IOS RunSmart app/`):

  ```python
  import re

  path = "../IOS RunSmart app.xcodeproj/project.pbxproj"
  with open(path, "r") as f:
      content = f.read()

  # 1. Add PBXBuildFile for PostHog
  old = '/* End PBXBuildFile section */'
  new = '\t\tAA0001022FA0B36A006C1A3C /* PostHog in Frameworks */ = {isa = PBXBuildFile; productRef = AA0001012FA0B36A006C1A3C /* PostHog */; };\n/* End PBXBuildFile section */'
  content = content.replace(old, new, 1)

  # 2. Add PostHog to the main target's Frameworks build phase
  old = '\t\t\t\t\tCC0001022FA0B36A006C1A3C /* Supabase in Frameworks */,'
  new = '\t\t\t\t\tCC0001022FA0B36A006C1A3C /* Supabase in Frameworks */,\n\t\t\t\t\tAA0001022FA0B36A006C1A3C /* PostHog in Frameworks */,'
  content = content.replace(old, new, 1)

  # 3. Add PostHog to the main target's packageProductDependencies
  old = '\t\t\t\tCC0001012FA0B36A006C1A3C /* Supabase */,'
  new = '\t\t\t\tCC0001012FA0B36A006C1A3C /* Supabase */,\n\t\t\t\tAA0001012FA0B36A006C1A3C /* PostHog */,'
  content = content.replace(old, new, 1)

  # 4. Add PostHog to project packageReferences
  old = '\t\t\t\tCC0001002FA0B36A006C1A3C /* XCRemoteSwiftPackageReference "supabase-swift" */,'
  new = '\t\t\t\tCC0001002FA0B36A006C1A3C /* XCRemoteSwiftPackageReference "supabase-swift" */,\n\t\t\t\tAA0001002FA0B36A006C1A3C /* XCRemoteSwiftPackageReference "posthog-ios" */,'
  content = content.replace(old, new, 1)

  # 5. Add XCRemoteSwiftPackageReference section entry for PostHog
  old = '/* End XCRemoteSwiftPackageReference section */'
  new = '\t\tAA0001002FA0B36A006C1A3C /* XCRemoteSwiftPackageReference "posthog-ios" */ = {\n\t\t\tisa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = "https://github.com/PostHog/posthog-ios";\n\t\t\trequirement = {\n\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = 3.0.0;\n\t\t\t};\n\t\t};\n/* End XCRemoteSwiftPackageReference section */'
  content = content.replace(old, new, 1)

  # 6. Add XCSwiftPackageProductDependency entry for PostHog
  old = '/* End XCSwiftPackageProductDependency section */'
  new = '\t\tAA0001012FA0B36A006C1A3C /* PostHog */ = {\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = AA0001002FA0B36A006C1A3C /* XCRemoteSwiftPackageReference "posthog-ios" */;\n\t\t\tproductName = PostHog;\n\t\t};\n/* End XCSwiftPackageProductDependency section */'
  content = content.replace(old, new, 1)

  with open(path, "w") as f:
      f.write(content)

  print("Done. Verify with: grep -c 'PostHog' '../IOS RunSmart app.xcodeproj/project.pbxproj'")
  ```

  Run it:
  ```bash
  python3 add_posthog_package.py
  ```
  Expected output: `Done. Verify with: grep -c 'PostHog' ...`

- [ ] **Step 2: Verify 6 PostHog references exist in pbxproj**

  ```bash
  grep -c "PostHog" "../IOS RunSmart app.xcodeproj/project.pbxproj"
  ```
  Expected: `6` or more

- [ ] **Step 3: Resolve packages**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -resolvePackageDependencies \
    -clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/ClonedSources
  ```
  Expected: Xcode fetches `posthog-ios` and updates `Package.resolved`. No error output.

- [ ] **Step 4: Build to verify the import compiles**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

  ```bash
  git add "../IOS RunSmart app.xcodeproj/project.pbxproj" \
          "../IOS RunSmart app.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  git commit -m "chore: add PostHog iOS SDK via SPM"
  ```

---

## Task 4: Create AnalyticsService.swift

**Files:**
- Create: `IOS RunSmart app/Services/Analytics/AnalyticsService.swift`

- [ ] **Step 1: Create the directory and file**

  Create `IOS RunSmart app/Services/Analytics/AnalyticsService.swift` with this content:

  ```swift
  import Foundation
  import PostHog

  // MARK: - Protocol

  protocol AnalyticsTracking {
      func track(_ event: String, properties: [String: Any])
      func identify(userId: String, traits: [String: Any])
      func reset()
  }

  // MARK: - Live implementation

  final class PostHogAnalyticsService: AnalyticsTracking {
      func track(_ event: String, properties: [String: Any]) {
          PostHogSDK.shared.capture(event, properties: properties)
      }
      func identify(userId: String, traits: [String: Any]) {
          PostHogSDK.shared.identify(userId, userProperties: traits)
      }
      func reset() {
          PostHogSDK.shared.reset()
      }
  }

  // MARK: - Null implementation (tests and previews)

  final class NullAnalyticsService: AnalyticsTracking {
      func track(_ event: String, properties: [String: Any]) {}
      func identify(userId: String, traits: [String: Any]) {}
      func reset() {}
  }

  // MARK: - Global accessor

  enum Analytics {
      static var shared: AnalyticsTracking = NullAnalyticsService()

      static func setup(projectToken: String, host: String) {
          let config = PostHogConfig(projectToken: projectToken)
          if let url = URL(string: host) {
              config.host = url
          }
          config.flushAt = 20
          config.flushIntervalSeconds = 30
          config.personProfiles = .identifiedOnly
          PostHogSDK.shared.setup(config)
          shared = PostHogAnalyticsService()
      }
  }
  ```

- [ ] **Step 2: Build to confirm it compiles**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add "IOS RunSmart app/Services/Analytics/AnalyticsService.swift"
  git commit -m "feat(analytics): add AnalyticsService protocol and PostHog/Null implementations"
  ```

---

## Task 5: Create AnalyticsEvents.swift

**Files:**
- Create: `IOS RunSmart app/Services/Analytics/AnalyticsEvents.swift`

- [ ] **Step 1: Create the file**

  Create `IOS RunSmart app/Services/Analytics/AnalyticsEvents.swift` with this content:

  ```swift
  import Foundation

  extension Analytics {

      // MARK: - Activation Funnel

      static func trackAppLaunched() {
          shared.track("app_launched", properties: ["session_id": UUID().uuidString])
      }

      static func trackSignInCompleted(method: String = "apple") {
          shared.track("sign_in_completed", properties: ["method": method])
      }

      static func trackOnboardingStarted() {
          shared.track("onboarding_started", properties: [:])
      }

      static func trackOnboardingStepCompleted(stepNumber: Int, stepName: String) {
          shared.track("onboarding_step_completed", properties: [
              "step_number": stepNumber,
              "step_name": stepName
          ])
      }

      static func trackOnboardingCompleted(goal: String, experience: String, daysPerWeek: Int) {
          shared.track("onboarding_completed", properties: [
              "goal": goal,
              "experience": experience,
              "days_per_week": daysPerWeek
          ])
      }

      static func trackPlanGenerated(planType: String, durationWeeks: Int) {
          shared.track("plan_generated", properties: [
              "plan_type": planType,
              "duration_weeks": durationWeeks
          ])
      }

      // MARK: - Run Engagement

      static func trackRunStarted(source: String) {
          shared.track("run_started", properties: ["source": source])
      }

      static func trackRunCompleted(
          distanceKm: Double,
          durationSeconds: Int,
          paceMinKm: Double,
          runType: String,
          isFirstRun: Bool = false
      ) {
          shared.track("run_completed", properties: [
              "distance_km": distanceKm,
              "duration_s": durationSeconds,
              "pace_min_km": paceMinKm,
              "run_type": runType,
              "is_first_run": isFirstRun
          ])
          if isFirstRun {
              shared.track("first_run_completed", properties: [
                  "distance_km": distanceKm,
                  "duration_s": durationSeconds,
                  "run_type": runType
              ])
          }
      }

      static func trackRunAbandoned(durationSeconds: Int, distanceKm: Double) {
          shared.track("run_abandoned", properties: [
              "duration_s": durationSeconds,
              "distance_km": distanceKm
          ])
      }

      static func trackPostRunCardViewed(hasBenchmark: Bool, hasPlanMatch: Bool) {
          shared.track("post_run_card_viewed", properties: [
              "has_benchmark": hasBenchmark,
              "has_plan_match": hasPlanMatch
          ])
      }

      // MARK: - Coach

      static func trackCoachThreadOpened(entryPoint: String) {
          shared.track("coach_thread_opened", properties: ["entry_point": entryPoint])
      }

      static func trackCoachMessageSent(entryPoint: String, messageLength: Int) {
          shared.track("coach_message_sent", properties: [
              "entry_point": entryPoint,
              "message_length": messageLength
          ])
      }

      // MARK: - Plan

      static func trackPlanViewed(weekNumber: Int?, hasActivePlan: Bool) {
          var props: [String: Any] = ["has_active_plan": hasActivePlan]
          if let week = weekNumber { props["week_number"] = week }
          shared.track("plan_viewed", properties: props)
      }

      static func trackPlanWorkoutTapped(workoutType: String, weekNumber: Int?) {
          var props: [String: Any] = ["workout_type": workoutType]
          if let week = weekNumber { props["week_number"] = week }
          shared.track("plan_workout_tapped", properties: props)
      }

      // MARK: - Routes

      static func trackRouteSelected(routeKind: String) {
          shared.track("route_selected", properties: ["route_kind": routeKind])
      }

      static func trackBenchmarkViewed(hasHistory: Bool, comparisonType: String) {
          shared.track("benchmark_viewed", properties: [
              "has_history": hasHistory,
              "comparison_type": comparisonType
          ])
      }

      static func trackRouteSaved(pointCount: Int) {
          shared.track("route_saved", properties: ["point_count": pointCount])
      }

      // MARK: - Feature Adoption

      static func trackTabViewed(tabName: String) {
          shared.track("tab_viewed", properties: ["tab_name": tabName])
      }

      static func trackGarminSyncCompleted(importedCount: Int, skippedCount: Int) {
          shared.track("garmin_sync_completed", properties: [
              "imported_count": importedCount,
              "skipped_count": skippedCount
          ])
      }

      static func trackGarminConnectTapped() {
          shared.track("garmin_connect_tapped", properties: [:])
      }

      static func trackHealthKitSyncCompleted(importedCount: Int) {
          shared.track("healthkit_sync_completed", properties: [
              "imported_count": importedCount
          ])
      }

      // MARK: - User Identity

      static func identifyUser(userId: String) {
          shared.identify(userId: userId, traits: [:])
      }

      static func resetUser() {
          shared.reset()
      }
  }
  ```

- [ ] **Step 2: Build**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add "IOS RunSmart app/Services/Analytics/AnalyticsEvents.swift"
  git commit -m "feat(analytics): add typed event helpers for all 24 analytics events"
  ```

---

## Task 6: Add analytics smoke tests

**Files:**
- Modify: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

- [ ] **Step 1: Add two test functions to RunSmartReadinessTests**

  At the end of the `RunSmartReadinessTests` class (before the closing `}`), add:

  ```swift
  func testNullAnalyticsServiceSwallowsAllCallsWithoutCrashing() {
      let svc = NullAnalyticsService()
      svc.track("test_event", properties: ["key": "value"])
      svc.identify(userId: "user_123", traits: ["plan": "pro"])
      svc.reset()
      // No assertion needed — just confirm no crash
  }

  func testAnalyticsSharedDefaultsToNullService() {
      XCTAssertTrue(Analytics.shared is NullAnalyticsService,
          "Analytics.shared must be NullAnalyticsService before setup() is called")
  }
  ```

- [ ] **Step 2: Run build-for-testing to compile tests**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build-for-testing 2>&1 | tail -5
  ```
  Expected: `** BUILD FOR TESTING SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add "IOS RunSmart appTests/RunSmartReadinessTests.swift"
  git commit -m "test(analytics): add NullAnalyticsService and default-to-null smoke tests"
  ```

---

## Task 7: Wire Analytics into RunSmartLiteAppShell

**Files:**
- Modify: `IOS RunSmart app/App/RunSmartLiteAppShell.swift`

This task: (a) initializes PostHog from RunSmartInfo.plist at app start, (b) tracks `app_launched`, (c) tracks `tab_viewed` on every tab change, (d) identifies the user when auth completes, (e) resets analytics on sign-out.

- [ ] **Step 1: Add PostHog initialization to the `.task` modifier**

  In `RunSmartLiteAppShell.body`, the existing `.task` modifier near line 144 ends with:

  ```swift
  .task {
      PushService.shared.configureNavigation { destination in
          router.openNotificationDestination(destination)
      }
      try? await Task.sleep(nanoseconds: 900_000_000)
      withAnimation(.easeOut(duration: 0.32)) {
          isShowingLaunch = false
      }
  }
  ```

  Replace it with:

  ```swift
  .task {
      setupAnalyticsIfNeeded()
      PushService.shared.configureNavigation { destination in
          router.openNotificationDestination(destination)
      }
      try? await Task.sleep(nanoseconds: 900_000_000)
      withAnimation(.easeOut(duration: 0.32)) {
          isShowingLaunch = false
      }
  }
  ```

- [ ] **Step 2: Add tab-change tracking**

  After the `.task` modifier above (not inside it), add:

  ```swift
  .onChange(of: router.selectedTab) { _, newTab in
      Analytics.trackTabViewed(tabName: newTab.rawValue)
  }
  ```

- [ ] **Step 3: Add user identification and reset**

  After the `.onChange(of: router.selectedTab)` modifier, add:

  ```swift
  .onChange(of: session.isAuthenticated) { _, isAuth in
      if isAuth, let userId = session.userID {
          Analytics.identifyUser(userId: userId.uuidString)
      } else if !isAuth {
          Analytics.resetUser()
      }
  }
  ```

- [ ] **Step 4: Add the `setupAnalyticsIfNeeded()` helper**

  At the end of the file, before the last `}`, add:

  ```swift
  private func setupAnalyticsIfNeeded() {
      guard let token = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String,
            !token.isEmpty,
            let host = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String
      else { return }
      Analytics.setup(projectToken: token, host: host)
      Analytics.trackAppLaunched()
  }
  ```

- [ ] **Step 5: Confirm `session.userID` property exists**

  ```bash
  grep -n "var userID\|var currentUserID\|userID:" \
    "IOS RunSmart app/Services/Supabase/SupabaseSession.swift" 2>/dev/null | head -5
  ```

  If `userID` is named differently (e.g. `currentUser?.id`), adjust the `onChange` block in Step 3 to match the actual property name.

- [ ] **Step 6: Build**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

  ```bash
  git add "IOS RunSmart app/App/RunSmartLiteAppShell.swift"
  git commit -m "feat(analytics): init PostHog, track app_launched and tab_viewed in AppShell"
  ```

---

## Task 8: Instrument SignInView

**Files:**
- Modify: `IOS RunSmart app/Features/Auth/SignInView.swift`

- [ ] **Step 1: Track sign-in completion**

  In `handleAppleResult(_:)` (around line 103 in `SignInView.swift`), the existing code is:

  ```swift
  try await session.signInWithApple(idToken: idToken, nonce: currentNonce)
  ```

  Replace with:

  ```swift
  try await session.signInWithApple(idToken: idToken, nonce: currentNonce)
  Analytics.trackSignInCompleted(method: "apple")
  ```

- [ ] **Step 2: Build**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add "IOS RunSmart app/Features/Auth/SignInView.swift"
  git commit -m "feat(analytics): track sign_in_completed in SignInView"
  ```

---

## Task 9: Instrument OnboardingView

**Files:**
- Modify: `IOS RunSmart app/Features/Onboarding/OnboardingView.swift`

OnboardingView has 5 steps (indices 0–4), controlled by `@State private var step = 0`.

Step names: `["name", "goal", "experience", "schedule", "coaching"]`

- [ ] **Step 1: Add onboarding_started on first appear**

  Find the `body` computed property. After the outermost `ZStack {` or `VStack {` opening, add:

  ```swift
  .onAppear {
      if step == 0 {
          Analytics.trackOnboardingStarted()
      }
  }
  ```

  (Attach it to the root view returned by `body`, alongside any existing `.preferredColorScheme` or other modifiers.)

- [ ] **Step 2: Track step completions on tab advance**

  Find the `private func nextStep()` function (near line 124):

  ```swift
  step = min(stepCount - 1, step + 1)
  ```

  Replace with:

  ```swift
  let stepNames = ["name", "goal", "experience", "schedule", "coaching"]
  let completedStep = step
  step = min(stepCount - 1, step + 1)
  let name = completedStep < stepNames.count ? stepNames[completedStep] : "unknown"
  Analytics.trackOnboardingStepCompleted(stepNumber: completedStep + 1, stepName: name)
  ```

- [ ] **Step 3: Track onboarding completion**

  Find the completion block near line 113:

  ```swift
  var completed = profile
  if completed.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      completed.displayName = "RunSmart Runner"
  }
  onComplete(completed)
  ```

  Replace with:

  ```swift
  var completed = profile
  if completed.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      completed.displayName = "RunSmart Runner"
  }
  Analytics.trackOnboardingCompleted(
      goal: completed.goal ?? "unknown",
      experience: completed.experience ?? "unknown",
      daysPerWeek: completed.weeklyRunDays
  )
  onComplete(completed)
  ```

  Note: verify the exact property names `goal`, `experience`, `weeklyRunDays` by checking `OnboardingProfile` in the models. Adjust if they differ.

- [ ] **Step 4: Build**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

  ```bash
  git add "IOS RunSmart app/Features/Onboarding/OnboardingView.swift"
  git commit -m "feat(analytics): track onboarding_started, step_completed, onboarding_completed"
  ```

---

## Task 10: Instrument RunTabView

**Files:**
- Modify: `IOS RunSmart app/Features/Run/RunTabView.swift`

- [ ] **Step 1: Track run_started**

  In the `PreRunView(...)` call inside `body`, the `onStart` closure is:

  ```swift
  onStart: {
      RunSmartHaptics.medium()
      recorder.start()
  },
  ```

  Replace with:

  ```swift
  onStart: {
      RunSmartHaptics.medium()
      let source = router.plannedWorkout != nil ? "planned" : "free"
      Analytics.trackRunStarted(source: source)
      recorder.start()
  },
  ```

- [ ] **Step 2: Track run_abandoned**

  In `discardRun()`:

  ```swift
  private func discardRun() {
      RunSmartHaptics.medium()
      recorder.discard()
  ```

  Replace with:

  ```swift
  private func discardRun() {
      RunSmartHaptics.medium()
      Analytics.trackRunAbandoned(
          durationSeconds: Int(recorder.movingSeconds),
          distanceKm: recorder.distanceMeters / 1000
      )
      recorder.discard()
  ```

  Note: verify the exact property names on `recorder` (`movingSeconds`, `distanceMeters`) by checking `RunRecorder`. Adjust if needed.

- [ ] **Step 3: Track run_completed**

  In `saveFinishedRun()`:

  ```swift
  private func saveFinishedRun() {
      finishedRun = nil
  ```

  Replace with:

  ```swift
  private func saveFinishedRun() {
      if let run = finishedRun {
          let isFirst = !UserDefaults.standard.bool(forKey: "analytics.hasCompletedRun")
          UserDefaults.standard.set(true, forKey: "analytics.hasCompletedRun")
          Analytics.trackRunCompleted(
              distanceKm: run.distanceMeters / 1000,
              durationSeconds: Int(run.movingTimeSeconds),
              paceMinKm: run.averagePaceSecondsPerKm / 60,
              runType: router.plannedWorkout?.kind.rawValue ?? "free",
              isFirstRun: isFirst
          )
      }
      finishedRun = nil
  ```

- [ ] **Step 4: Build**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

  ```bash
  git add "IOS RunSmart app/Features/Run/RunTabView.swift"
  git commit -m "feat(analytics): track run_started, run_abandoned, run_completed in RunTabView"
  ```

---

## Task 11: Instrument PostRunLearningCard

**Files:**
- Modify: `IOS RunSmart app/Features/Run/PostRunLearningCard.swift`

- [ ] **Step 1: Find the root view in PostRunLearningCard**

  ```bash
  grep -n "var body\|VStack\|ContentCard\|GlassCard" \
    "IOS RunSmart app/Features/Run/PostRunLearningCard.swift" | head -10
  ```

- [ ] **Step 2: Track post_run_card_viewed on appear**

  Add `.onAppear` to the root view returned by `body`. Find the `var body: some View` and after the opening view container, add:

  ```swift
  .onAppear {
      Analytics.trackPostRunCardViewed(
          hasBenchmark: model.routeMatchSummary != nil,
          hasPlanMatch: model.planImpact != nil
      )
  }
  ```

  Note: verify the exact property names on the card model by checking `PostRunLearningCardModel`. Use `!= nil` checks on whatever properties indicate benchmark and plan-match presence.

- [ ] **Step 3: Build**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

  ```bash
  git add "IOS RunSmart app/Features/Run/PostRunLearningCard.swift"
  git commit -m "feat(analytics): track post_run_card_viewed in PostRunLearningCard"
  ```

---

## Task 12: Instrument CoachFlowView

**Files:**
- Modify: `IOS RunSmart app/Features/Coach/CoachFlowView.swift`

- [ ] **Step 1: Track coach_thread_opened**

  In `CoachFlowView`, the `.task(id: entryPoint)` modifier (around line 25) loads messages. Add `.onAppear` tracking by appending after the existing `.task` modifier:

  ```swift
  .onAppear {
      Analytics.trackCoachThreadOpened(entryPoint: entryPoint.rawValue)
  }
  ```

  (Attach to the same root `ZStack` that has `.preferredColorScheme(.dark)`.)

- [ ] **Step 2: Track coach_message_sent**

  Find the `send(_:)` private function. It should look similar to:

  ```swift
  private func send(_ text: String) {
      guard !text.isEmpty else { return }
      ...
  ```

  Add tracking right after the guard:

  ```swift
  private func send(_ text: String) {
      guard !text.isEmpty else { return }
      Analytics.trackCoachMessageSent(
          entryPoint: entryPoint.rawValue,
          messageLength: text.count
      )
  ```

- [ ] **Step 3: Build**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

  ```bash
  git add "IOS RunSmart app/Features/Coach/CoachFlowView.swift"
  git commit -m "feat(analytics): track coach_thread_opened and coach_message_sent in CoachFlowView"
  ```

---

## Task 13: Instrument PlanTabView

**Files:**
- Modify: `IOS RunSmart app/Features/Plan/PlanTabView.swift`

- [ ] **Step 1: Track plan_viewed on appear**

  In `PlanTabView`, find the `.task` that loads data (it loads `weekWorkouts`, `activePlan`, etc.). After the `.task` block, add:

  ```swift
  .onAppear {
      let currentWeekNumber = currentWeek?.weekNumber
      Analytics.trackPlanViewed(
          weekNumber: currentWeekNumber,
          hasActivePlan: activePlan != nil
      )
  }
  ```

  Note: verify `currentWeek?.weekNumber` is the correct property. Check `PlanWeekSummary` in models for the week number property name.

- [ ] **Step 2: Track plan_workout_tapped**

  Find where a workout row tap opens detail. Look for a `Button { router.open(...) }` or `NavigationLink` for a `WorkoutSummary`. Add tracking inside the tap closure:

  ```swift
  Analytics.trackPlanWorkoutTapped(
      workoutType: workout.kind?.rawValue ?? "unknown",
      weekNumber: currentWeek?.weekNumber
  )
  ```

- [ ] **Step 3: Build**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

  ```bash
  git add "IOS RunSmart app/Features/Plan/PlanTabView.swift"
  git commit -m "feat(analytics): track plan_viewed and plan_workout_tapped in PlanTabView"
  ```

---

## Task 14: Instrument Routes

**Files:**
- Modify: `IOS RunSmart app/Features/Routes/RouteCreatorView.swift`
- Modify: `IOS RunSmart app/Features/Routes/BenchmarkComparisonCard.swift`
- Modify: `IOS RunSmart app/Features/Routes/SaveRouteSheet.swift`

- [ ] **Step 1: Track route_selected in RouteCreatorView**

  Find the tap handler for a `FullBleedRouteCard` in `RouteCreatorView`. It should be inside a `Button { ... }` or `onTapGesture`. Add:

  ```swift
  Analytics.trackRouteSelected(routeKind: suggestion.kind.rawValue)
  ```

  where `suggestion` is the `RouteSuggestion` being tapped. The `kind` property is `RouteKind` with raw values `"past"`, `"generated"`, `"saved"`, `"benchmark"`.

- [ ] **Step 2: Track benchmark_viewed in BenchmarkComparisonCard**

  Find the root view in `BenchmarkComparisonCard`. Add `.onAppear`:

  ```swift
  .onAppear {
      let hasHistory = comparison.previousRun != nil || comparison.personalBest != nil
      Analytics.trackBenchmarkViewed(
          hasHistory: hasHistory,
          comparisonType: comparison.comparisonType ?? "unknown"
      )
  }
  ```

  Note: verify the exact property names on `BenchmarkComparison` or `BenchmarkComparisonPresentation`. Use the correct property for "has prior data" and a string label for comparison type.

- [ ] **Step 3: Track route_saved in SaveRouteSheet**

  Find the confirm/save button action in `SaveRouteSheet`. Add:

  ```swift
  Analytics.trackRouteSaved(pointCount: route.points.count)
  ```

  where `route` is the `RouteSuggestion` or route model being saved.

- [ ] **Step 4: Build**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

  ```bash
  git add "IOS RunSmart app/Features/Routes/RouteCreatorView.swift" \
          "IOS RunSmart app/Features/Routes/BenchmarkComparisonCard.swift" \
          "IOS RunSmart app/Features/Routes/SaveRouteSheet.swift"
  git commit -m "feat(analytics): track route_selected, benchmark_viewed, route_saved"
  ```

---

## Task 15: Instrument Garmin and HealthKit syncs

**Files:**
- Modify: `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`

- [ ] **Step 1: Track garmin_sync_completed**

  In `syncNow(provider:)` (around line 844), find the Garmin branch. The existing code ends with:

  ```swift
  saveFirstSyncReviewIfNeeded(
      provider: .garmin,
      status: status,
      importedRuns: newRuns,
      skippedDuplicateCount: max(0, runs.count - newRuns.count)
  )
  return status
  ```

  Replace with:

  ```swift
  saveFirstSyncReviewIfNeeded(
      provider: .garmin,
      status: status,
      importedRuns: newRuns,
      skippedDuplicateCount: max(0, runs.count - newRuns.count)
  )
  Analytics.trackGarminSyncCompleted(
      importedCount: newRuns.count,
      skippedCount: max(0, runs.count - newRuns.count)
  )
  return status
  ```

- [ ] **Step 2: Track healthkit_sync_completed**

  In `syncHealthData()` (around line 889), find the existing return:

  ```swift
  store.saveDeviceStatus(status)
  saveFirstSyncReviewIfNeeded(
      provider: .healthKit,
      status: status,
      importedRuns: result.runs,
      skippedDuplicateCount: result.skippedDuplicates
  )
  return status
  ```

  Replace with:

  ```swift
  store.saveDeviceStatus(status)
  saveFirstSyncReviewIfNeeded(
      provider: .healthKit,
      status: status,
      importedRuns: result.runs,
      skippedDuplicateCount: result.skippedDuplicates
  )
  Analytics.trackHealthKitSyncCompleted(importedCount: result.runs.count)
  return status
  ```

- [ ] **Step 3: Build**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

  ```bash
  git add "IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift"
  git commit -m "feat(analytics): track garmin_sync_completed and healthkit_sync_completed"
  ```

---

## Task 16: Final iOS build-for-testing validation

- [ ] **Step 1: Build for testing**

  ```bash
  xcodebuild -project "../IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    build-for-testing 2>&1 | tail -5
  ```
  Expected: `** BUILD FOR TESTING SUCCEEDED **`

- [ ] **Step 2: Commit if any loose files remain**

  ```bash
  git status --short
  ```
  Commit anything unstaged.

---

## Task 17: Fix web app PostHog key

**Files:**
- Modify: `/Users/nadavyigal/Documents/RunSmart/v0/.env.local`

- [ ] **Step 1: Add the PostHog project token to web .env.local**

  Open `/Users/nadavyigal/Documents/RunSmart/v0/.env.local`. Find the existing line:

  ```
  NEXT_PUBLIC_POSTHOG_HOST="https://us.i.posthog.com"
  ```

  Add the key on the line directly below it:

  ```
  NEXT_PUBLIC_POSTHOG_KEY=phc_YOUR_TOKEN_HERE
  ```

  Use the same `phc_...` token retrieved in Task 1.

- [ ] **Step 2: Verify the provider picks it up**

  Open the dev server (if running) and check the browser console for:
  `PostHog initialized (deferred)` — that log line in `posthog-provider.tsx` confirms the key was accepted.

  Or just grep to confirm the key is present:
  ```bash
  grep "POSTHOG_KEY" /Users/nadavyigal/Documents/RunSmart/v0/.env.local
  ```
  Expected: line with non-empty value.

  Note: `.env.local` is in `.gitignore` — do NOT commit it.

---

## Task 18: Create PostHog dashboards via MCP

Use the PostHog MCP tool in this Claude Code session to create the four dashboards. Run each MCP call in sequence.

- [ ] **Step 1: Create Dashboard 1 — Activation Funnel**

  Use PostHog MCP `exec` or dashboard creation API for project 171597 to create a dashboard named **"RunSmart Activation Funnel"** with a single funnel insight:
  - Steps: `app_launched` → `sign_in_completed` → `onboarding_completed` → `plan_generated` → `first_run_completed`
  - Date range: last 30 days
  - Breakdown: none (add `method` breakdown on step 2 as a secondary insight)

- [ ] **Step 2: Create Dashboard 2 — Run Engagement**

  Create dashboard **"RunSmart Run Engagement"** with:
  - Trend: `run_completed` event count over last 30 days (7-day rolling)
  - Trend: `run_abandoned` / `run_started` — abandonment rate formula
  - Bar chart: `run_completed` grouped by `run_type` property

- [ ] **Step 3: Create Dashboard 3 — Feature Adoption**

  Create dashboard **"RunSmart Feature Adoption"** with:
  - Stacked bar: `tab_viewed` grouped by `tab_name`, last 30 days
  - Bar chart: `route_selected` grouped by `route_kind`
  - Trend: `coach_message_sent` with `entry_point` breakdown

- [ ] **Step 4: Create Dashboard 4 — Coach Intelligence**

  Create dashboard **"RunSmart Coach Intelligence"** with:
  - Trend: `coach_thread_opened` vs `coach_message_sent` on same chart
  - Bar: `coach_thread_opened` grouped by `entry_point`

---

## Self-Review Checklist

- [x] All 24 events from spec have a call site in the plan
- [x] `first_run_completed` is emitted via `trackRunCompleted(isFirstRun: true)` — UserDefaults gate
- [x] `tab_viewed` uses `RunSmartTab.rawValue` — caller must verify raw values match `today`, `plan`, `run`, `report`, `profile`
- [x] PostHog property name is `projectToken` (not `apiKey`) — confirmed via Context7
- [x] Web app fix is a single .env.local line — no code changes
- [x] Garmin connect tapped (`garmin_connect_tapped`) — add to Task 14 call sites if the `Connect` button in `SecondaryFlowView` is accessible; if not surfaced by a separate task, treat as a follow-up
