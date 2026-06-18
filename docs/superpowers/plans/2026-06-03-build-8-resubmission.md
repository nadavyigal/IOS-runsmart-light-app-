# Build 8 Resubmission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the onboarding scroll fix to `version-2`, pass a full bug review and Executive OS gate, then archive and submit RunSmart iOS as build 8.

**Architecture:** `version-2` already contains the complete 1.0.1 UX redesign (stories A1–A6, B2–B4). The only code change needed is wrapping `OnboardingStepShell` in a `ScrollView` so the Privacy step button is reachable on iPad. Everything else is verification gates — test suite, visual QA, bug review, and Executive OS sign-off — before archiving.

**Tech Stack:** Swift 5.9, SwiftUI, Xcode 15+, xcodebuild CLI, xcrun simctl, App Store Connect (manual portal upload).

---

## File Change Map

| File | Change |
|---|---|
| `IOS RunSmart app/Features/Onboarding/OnboardingView.swift` | Wrap `OnboardingStepShell.body` in `ScrollView`; convert `Spacer` to padding |
| `IOS RunSmart app/Features/Today/TodayTabView.swift` | Fix trailing padding on `TodayWeekStripSection` horizontal scroll if clip is confirmed |
| `IOS RunSmart app.xcodeproj/project.pbxproj` | Bump `CURRENT_PROJECT_VERSION` 7 → 8; set `MARKETING_VERSION` 1.0.1 → 1.0 |
| `tasks/progress.md` | Post-submit status update |
| `tasks/todo.md` | Mark build 8 submitted |

---

## Task 1: Branch setup and version bump

**Files:**
- Modify: `IOS RunSmart app.xcodeproj/project.pbxproj`

- [ ] **Step 1: Check out version-2 and confirm clean state**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
git checkout version-2
git pull origin version-2
git status
```

Expected: `On branch version-2`, nothing to commit.

- [ ] **Step 2: Create a working branch off version-2**

```bash
git checkout -b fix/build-8-submission
```

Expected: `Switched to a new branch 'fix/build-8-submission'`

- [ ] **Step 3: Bump build number to 8**

Open `IOS RunSmart app.xcodeproj/project.pbxproj` and find all occurrences of:
```
CURRENT_PROJECT_VERSION = 7;
```
Replace every occurrence with:
```
CURRENT_PROJECT_VERSION = 8;
```

There are 4 occurrences (Debug + Release for the app target, Debug + Release for the tests target). Replace all 4.

Verify with:
```bash
grep "CURRENT_PROJECT_VERSION" "IOS RunSmart app.xcodeproj/project.pbxproj"
```
Expected: all lines show `= 8;`, none show `= 7;`.

- [ ] **Step 4: Set marketing version to 1.0**

The rejected submission in App Store Connect is version 1.0. `version-2` has `MARKETING_VERSION = 1.0.1`. Change it back to match the ASC slot.

In `project.pbxproj`, find all occurrences of:
```
MARKETING_VERSION = 1.0.1;
```
Replace with:
```
MARKETING_VERSION = 1.0;
```

There are 2 occurrences (one per target configuration that shows a version). Replace both.

Verify:
```bash
grep "MARKETING_VERSION" "IOS RunSmart app.xcodeproj/project.pbxproj"
```
Expected: all lines show `1.0;`, none show `1.0.1;`.

- [ ] **Step 5: Commit**

```bash
git add "IOS RunSmart app.xcodeproj/project.pbxproj"
git commit -m "chore(release): bump build 7 → 8, version 1.0.1 → 1.0 for resubmission"
```

---

## Task 2: Onboarding scroll fix

**Files:**
- Modify: `IOS RunSmart app/Features/Onboarding/OnboardingView.swift:151-185`

This is the only code change that matters for Apple's rejection. `OnboardingStepShell` uses a plain `VStack` with no `ScrollView`. On iPad the Privacy step content (coaching tone grid + toggle + 2 device rows + callout + button) overflows off-screen and the button is unreachable. Wrapping in `ScrollView` fixes all 5 steps at once.

- [ ] **Step 1: Open the file and locate the struct**

```bash
grep -n "private struct OnboardingStepShell\|var body: some View" \
  "IOS RunSmart app/Features/Onboarding/OnboardingView.swift" | head -10
```

Expected output includes a line like:
```
151:private struct OnboardingStepShell<Content: View>: View {
157:    var body: some View {
```

- [ ] **Step 2: Replace the body**

Find this exact block in `OnboardingView.swift` (lines 157–185):

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 20)
            HStack(spacing: 14) {
                RunSmartLogoMark(size: 76, filled: false, glow: true)
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(Color.black)
                    .frame(width: 52, height: 52)
                    .background(Color.accentPrimary, in: Circle())
                    .shadow(color: Color.accentPrimary.opacity(0.36), radius: 18)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.displayMD)
                    .displayTightTracking(-0.8)
                Text(subtitle)
                    .font(.bodyLG)
                    .foregroundStyle(Color.textSecondary)
            }
            ContentCard {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
            }
            Spacer(minLength: 20)
        }
        .padding(24)
    }
```

Replace it with:

```swift
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    RunSmartLogoMark(size: 76, filled: false, glow: true)
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(Color.black)
                        .frame(width: 52, height: 52)
                        .background(Color.accentPrimary, in: Circle())
                        .shadow(color: Color.accentPrimary.opacity(0.36), radius: 18)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.displayMD)
                        .displayTightTracking(-0.8)
                    Text(subtitle)
                        .font(.bodyLG)
                        .foregroundStyle(Color.textSecondary)
                }
                ContentCard {
                    VStack(alignment: .leading, spacing: 14) {
                        content
                    }
                }
            }
            .padding(24)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
    }
```

Changes from the original:
- Added `ScrollView(showsIndicators: false)` wrapper
- Removed both `Spacer(minLength: 20)` calls (spacers don't work inside ScrollView)
- Replaced them with `.padding(.top, 20)` and `.padding(.bottom, 20)` on the VStack
- The `.padding(24)` already present gives the horizontal gutters

- [ ] **Step 3: Build to confirm the change compiles**

```bash
xcodebuild build \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -derivedDataPath /tmp/runsmart-build8-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  -quiet 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

If the build fails, read the full error:
```bash
xcodebuild build \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -derivedDataPath /tmp/runsmart-build8-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep "error:"
```

- [ ] **Step 4: Commit**

```bash
git add "IOS RunSmart app/Features/Onboarding/OnboardingView.swift"
git commit -m "fix(onboarding): wrap OnboardingStepShell in ScrollView — Privacy button reachable on iPad"
```

---

## Task 3: Today week strip trailing clip fix

**Files:**
- Modify: `IOS RunSmart app/Features/Today/TodayTabView.swift:678–690`

The last session noted the Today week strip has a right-edge clip on the upstream `version-2` branch. The `TodayWeekStripSection` uses a horizontal `ScrollView` whose `LazyHStack` has only `.padding(.horizontal, 1)` — the last card gets cut by the scroll view's clip boundary. This task inspects and fixes it.

- [ ] **Step 1: Launch in simulator and inspect**

```bash
# Boot iPhone 16 simulator
xcrun simctl boot "iPhone 16" 2>/dev/null || true

xcodebuild build \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -derivedDataPath /tmp/runsmart-build8-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  -quiet 2>&1 | tail -3

xcrun simctl install booted \
  "$(find /tmp/runsmart-build8-derived -name "IOS RunSmart app.app" -not -path "*/iphoneos/*" | head -1)"

xcrun simctl launch booted com.runsmart.lite

sleep 3
xcrun simctl io booted screenshot /tmp/today-weekstrip-inspect.png
open /tmp/today-weekstrip-inspect.png
```

- [ ] **Step 2: Confirm whether the last day card is clipped**

Look at the Today tab week strip in `/tmp/today-weekstrip-inspect.png`. If the rightmost day card is visibly cut off at its right edge (not just near the screen edge, but actually clipped mid-card), apply the fix in Step 3. If it looks correct, skip to Step 4.

- [ ] **Step 3: Apply fix if clip is confirmed**

Find this block in `TodayTabView.swift` (inside `TodayWeekStripSection.body`, ~lines 678–689):

```swift
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(workouts) { workout in
                        Button { onWorkout(workout) } label: {
                            WorkoutDayCard(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 8)
            }
```

Replace `.padding(.horizontal, 1)` with `.padding(.leading, 1).padding(.trailing, 18)`:

```swift
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(workouts) { workout in
                        Button { onWorkout(workout) } label: {
                            WorkoutDayCard(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 1)
                .padding(.trailing, 18)
                .padding(.vertical, 8)
            }
```

Re-take the screenshot and confirm the last card is fully visible.

- [ ] **Step 4: Commit (only if Step 3 was applied)**

```bash
git add "IOS RunSmart app/Features/Today/TodayTabView.swift"
git commit -m "fix(today): add trailing padding to week strip horizontal scroll — last card no longer clipped"
```

If no clip was found in Step 2, skip this commit.

---

## Task 4: Full test suite

**Files:** No changes — this task runs existing tests only.

The last version-2 session stalled at simulator launch (CoreSimulator error 405, NSMach -308). Reset the simulator before running.

- [ ] **Step 1: Shut down and erase all simulators**

```bash
xcrun simctl shutdown all
xcrun simctl erase all
```

Expected: commands complete silently. This resets simulator state and clears the stale launch lock.

- [ ] **Step 2: Run the full test suite**

```bash
xcodebuild test \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -derivedDataPath /tmp/runsmart-build8-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -E "Test Suite|FAILED|PASSED|error:" | tail -30
```

Expected final lines:
```
Test Suite 'All tests' passed at ...
     Executed N tests, with 0 failures (0 unexpected) in ...
```

- [ ] **Step 3: If tests stall again, diagnose**

If the run hangs for more than 3 minutes after `Build SUCCEEDED`:

```bash
# Check if the simulator is booting
xcrun simctl list devices | grep -i "iPhone 16"
```

If the simulator shows `(Shutdown)` after 2 minutes, the simulator is broken. Try a different one:

```bash
xcodebuild test \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 15" \
  -derivedDataPath /tmp/runsmart-build8-derived-15 \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -E "Test Suite|FAILED|PASSED|error:" | tail -20
```

- [ ] **Step 4: Fix any failing tests**

If specific tests fail (not stall), read the full failure:

```bash
xcodebuild test \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -derivedDataPath /tmp/runsmart-build8-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -A 10 "FAILED\|error:"
```

Fix the failing test or its underlying logic. Do not skip or comment out tests. Commit fixes as separate commits with `fix(tests):` prefix before proceeding.

---

## Task 5: Simulator visual QA

**Files:** No changes — visual inspection only.

Run on all three simulators. Take a screenshot of each screen listed below. All must look correct before proceeding to the bug review.

- [ ] **Step 1: Boot the three simulators**

```bash
xcrun simctl boot "iPhone 16"         # 6.1-inch
xcrun simctl boot "iPhone 16 Plus"    # 6.7-inch
xcrun simctl boot "iPad Air 11-inch (M3)"  # the rejection device
```

If "iPad Air 11-inch (M3)" is not in the list:
```bash
xcrun simctl list devices available | grep -i "iPad Air"
```
Use the closest available iPad Air simulator.

- [ ] **Step 2: Install the build on all three**

```bash
APP_PATH="$(find /tmp/runsmart-build8-derived -name "IOS RunSmart app.app" -not -path "*/iphoneos/*" | head -1)"

xcrun simctl install "iPhone 16" "$APP_PATH"
xcrun simctl install "iPhone 16 Plus" "$APP_PATH"
xcrun simctl install "iPad Air 11-inch (M3)" "$APP_PATH"
```

- [ ] **Step 3: iPad onboarding — the critical check**

```bash
xcrun simctl launch "iPad Air 11-inch (M3)" com.runsmart.lite
sleep 4
xcrun simctl io "iPad Air 11-inch (M3)" screenshot /tmp/qa/ipad-onboarding-step1.png
```

Manually step through all 5 onboarding screens on the iPad simulator. For each step, verify the CTA button is visible without needing to scroll. For the Privacy step (step 4 of 5, index 3), scroll down — the "Confirm Privacy" button must be present and tappable below the device preview rows.

Take screenshots for each step:
```bash
# After each step tap, take a screenshot:
xcrun simctl io "iPad Air 11-inch (M3)" screenshot /tmp/qa/ipad-onboarding-step2.png
xcrun simctl io "iPad Air 11-inch (M3)" screenshot /tmp/qa/ipad-onboarding-step3.png
xcrun simctl io "iPad Air 11-inch (M3)" screenshot /tmp/qa/ipad-onboarding-privacy.png
xcrun simctl io "iPad Air 11-inch (M3)" screenshot /tmp/qa/ipad-onboarding-complete.png
```

**Pass condition:** The Privacy step shows a scrollable content area with the "Confirm Privacy" button reachable by scrolling down. The button must be fully visible and not clipped.

- [ ] **Step 4: Today tab — all three devices**

```bash
mkdir -p /tmp/qa
xcrun simctl launch "iPhone 16" com.runsmart.lite
sleep 3
xcrun simctl io "iPhone 16" screenshot /tmp/qa/iphone16-today.png
xcrun simctl io "iPhone 16 Plus" screenshot /tmp/qa/iphone16plus-today.png
xcrun simctl io "iPad Air 11-inch (M3)" screenshot /tmp/qa/ipad-today.png
open /tmp/qa/
```

Check for each device:
- Coach icon (✦) visible in top-right of header
- Week strip visible below the header
- Decision card visible in first viewport
- No `TodayCoachHeroCard` (large coach card at top) — it should be gone
- No `TodayQuickActions` row — it should be gone
- Bottom safe area: last card is not hidden behind the tab bar

- [ ] **Step 5: Plan, Report, Profile tabs — iPhone 16**

Navigate manually or via accessibility inspector. Take screenshots:

```bash
xcrun simctl io "iPhone 16" screenshot /tmp/qa/iphone16-plan.png
xcrun simctl io "iPhone 16" screenshot /tmp/qa/iphone16-report.png
xcrun simctl io "iPhone 16" screenshot /tmp/qa/iphone16-profile.png
```

Plan: "This Week" section must appear before the segment picker. "Explain this week" compact button must be visible below the week section.

Report: Three segment pills (Runs | Reports | Progress) must be visible at the top of the tab.

Profile: Connected services (Garmin + HealthKit rows) must appear above the fold. No run reports list visible.

- [ ] **Step 6: Note any visual issues**

Open all screenshots in Preview (`open /tmp/qa/*.png`). Note any issues that need fixing. Fix them and repeat from Step 2 before proceeding. Do not proceed to Task 6 with known visual failures.

---

## Task 6: Bug review

**Files:** No changes unless a bug is found. Each check below is a pass/fail gate.

- [ ] **Step A: Force-unwrap count — must not increase vs main**

```bash
# Count on current branch
BRANCH_COUNT=$(grep -rn "![^=!]" "IOS RunSmart app/" --include="*.swift" \
  | grep -v "\.git\|Test\|#if DEBUG\|// \|\"!\|'!\|!\"" \
  | wc -l)
echo "Branch force-unwrap count: $BRANCH_COUNT"

# Count on main for comparison
git stash
git checkout main
MAIN_COUNT=$(grep -rn "![^=!]" "IOS RunSmart app/" --include="*.swift" \
  | grep -v "\.git\|Test\|#if DEBUG\|// \|\"!\|'!\|!\"" \
  | wc -l)
echo "Main force-unwrap count: $MAIN_COUNT"
git checkout fix/build-8-submission
git stash pop
```

Expected: `BRANCH_COUNT <= MAIN_COUNT`. Any net increase must be reviewed. For each new force-unwrap, either replace it with `guard let` / `if let`, or leave a comment explaining why it is safe.

- [ ] **Step B: iPad onboarding scroll — confirmed in Task 5**

Already verified in Task 5 Step 3. Check the box if `/tmp/qa/ipad-onboarding-privacy.png` shows the "Confirm Privacy" button reachable.

- [ ] **Step C: Voice coach does not crash**

```bash
xcrun simctl launch "iPhone 16" com.runsmart.lite
sleep 3
```

Navigate to the Run tab. Tap "Start Run" (or "Begin Run"). Confirm the app reaches the live run recording screen without crashing. Tap the mute icon if visible. Confirm it toggles without crashing. Exit the run.

This is a simulator test — actual audio playback requires a physical device. Crashing is a blocker. Silent failure (no audio) is expected in the simulator and is not a blocker.

- [ ] **Step D: Coach entry points — no dead ends**

On iPhone 16 simulator:

1. Today tab: tap the ✦ icon in the header → `CoachFlowView` sheet must open. Dismiss.
2. Plan tab: tap "Explain this week" button → `CoachFlowView` sheet must open. Dismiss.
3. Report tab: if any run reports are visible under the Reports segment, tap "Explain this run" → `CoachFlowView` sheet must open.

If the app has no run data (fresh simulator), steps 2 and 3 may not be testable for the coach-opens-with-context part. Confirm the buttons are visible and tappable without crashing.

- [ ] **Step E: No ResumeBuilder artifacts**

```bash
grep -rn "resume\|Resume\|ATS\|job description\|optimize" \
  "IOS RunSmart app/" --include="*.swift" \
  | grep -v "\.git\|Test\|#if DEBUG\|// " \
  | grep -vi "runsmart\|garmin\|run\b\|speed\|pace\|supabase\|running\|runner\|resumeId\|resumable" \
  | head -20
```

Expected: zero results. Any match must be inspected. If it is RunSmart-domain code that uses the word "resume" in a non-ResumeBuilder sense (e.g., "resume recording"), verify it in context — that is fine. Flag any screen or button that exposes ATS scoring, job description, or resume-optimization functionality to the user.

- [ ] **Step F: Analytics events still have call sites**

```bash
grep -rn "Analytics.track\|PostHog\|trackOnboarding\|trackRun\|trackPlan" \
  "IOS RunSmart app/" --include="*.swift" \
  | grep -v "\.git\|Test\|//" | sort
```

Confirm these event names are present in at least one call site:
- `trackOnboardingStarted`
- `trackOnboardingStepCompleted`
- `trackOnboardingCompleted`

If any are missing, the analytics instrumentation was accidentally deleted in the redesign. Restore the call site in the appropriate view before archiving.

- [ ] **Step G: Secrets audit — nothing hardcoded**

```bash
grep -rn "phc_\|eyJhbGc\|sk_live\|secret\|apiKey\|API_KEY\|POSTHOG_API" \
  "IOS RunSmart app/" --include="*.swift" \
  | grep -v "\.git\|Test\|#if DEBUG\|// \|xcconfig\|\.plist\|Bundle.main"
```

Expected: zero results. All secrets must flow through `RunSmartSecrets.xcconfig` (gitignored) into the app's `Info.plist`. Verify `RunSmartSecrets.xcconfig` exists locally with a real PostHog key:

```bash
grep "POSTHOG_API_KEY" RunSmartSecrets.xcconfig
```

Expected: `POSTHOG_API_KEY = phc_` followed by a real key (not the placeholder from `.example`).

---

## Task 7: Executive OS gate

**Files:** No app code changes.

- [ ] **Step 1: Run agentic-os refresh**

```bash
cd "/Users/nadavyigal/Documents/Projects /Agentic OS" && ./agentic-os refresh
```

Expected output includes `refreshed Agentic OS` with today's date.

- [ ] **Step 2: Read the Executive Dashboard**

```bash
open "/Users/nadavyigal/Documents/Projects /Agentic OS/executive-os/EXECUTIVE-DASHBOARD.md"
```

Confirm:
- RunSmart iOS status shows as "resubmission ready / build 8"
- Risk board has no new unresolved items
- No CEO decision is flagged as blocking the submission

If a CEO decision is surfaced that was not known before, stop and resolve it before archiving. Do not submit with an open unresolved CEO question.

- [ ] **Step 3: Return to the RunSmart repo**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
```

---

## Task 8: Merge, archive, and submit

**Files:**
- Modify: `IOS RunSmart app.xcodeproj/project.pbxproj` (build number already changed in Task 1)

- [ ] **Step 1: Merge fix/build-8-submission into version-2**

```bash
git checkout version-2
git merge fix/build-8-submission --no-ff \
  -m "feat(release): build 8 resubmission — onboarding scroll fix + version bump"
```

Expected: clean merge, no conflicts (the only changed files are `OnboardingView.swift`, `project.pbxproj`, and optionally `TodayTabView.swift`).

If conflicts occur:
```bash
git status
# Open conflicted files, resolve manually, then:
git add <conflicted-file>
git merge --continue
```

- [ ] **Step 2: Final build verification on version-2**

```bash
xcodebuild build \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -derivedDataPath /tmp/runsmart-build8-final \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  -quiet 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Archive in Xcode (manual founder action)**

1. Open Xcode:
```bash
open "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/IOS RunSmart app.xcodeproj"
```
2. Set the destination to **Any iOS Device (arm64)** — not a simulator.
3. Confirm `RunSmartSecrets.xcconfig` is present and has a real PostHog key (checked in Task 6G).
4. Menu: **Product → Archive**
5. Wait for archive to complete. The Organizer window opens automatically.
6. In Organizer, confirm the archive shows **Version 1.0 (8)** and today's date.

- [ ] **Step 4: Validate before uploading**

In Organizer:
1. Select the archive → **Distribute App**
2. Select **App Store Connect**
3. Select **Validate App** (not Upload yet)
4. Click through signing prompts (Xcode uses the Apple Distribution cert already in your keychain)
5. Wait for validation to complete.

Expected: validation succeeds with no errors. Warnings about missing purpose strings or entitlements are acceptable if they were present in build 6.

If validation surfaces a new error not present in build 6, fix it before uploading.

- [ ] **Step 5: Upload to App Store Connect**

In Organizer (same flow, continuing from validation):
1. Select **Upload** (not Export)
2. Leave all checkboxes at defaults (symbols, bitcode if offered, managed signing)
3. Click **Upload**
4. Wait for upload confirmation. Xcode will show "Your app has been successfully uploaded."

- [ ] **Step 6: Reply to Apple's rejection message**

Go to https://appstoreconnect.apple.com → your RunSmart app → App Review → the rejected submission message.

Reply with:

> "Thank you for the detailed report. We've identified the root cause: the Privacy onboarding step used a fixed-height VStack layout that overflowed on iPad, pushing the Continue button off-screen. We've wrapped the onboarding shell in a ScrollView so all step content — including the Privacy step's device preview rows and the Confirm Privacy button — is reachable by scrolling on all device sizes. Build 8 includes this fix. We've also included the 1.0 UX redesign (simplified Today tab, week-first Plan tab, segmented Report tab, cleaned-up Profile) that we had prepared for the original launch. We look forward to your review."

- [ ] **Step 7: Select build 8 and submit**

In App Store Connect:
1. Navigate to your RunSmart iOS app → App Store → version 1.0
2. In the Build section, tap **+** and select build 8 (wait for it to finish processing if needed — takes 5–15 minutes)
3. Confirm all metadata, screenshots, and privacy responses are still populated from the build 6 submission
4. Tap **Submit for Review**

Expected: status changes to "Waiting for Review".

---

## Task 9: Post-submit memory update

**Files:**
- Modify: `tasks/progress.md`
- Modify: `tasks/todo.md`

- [ ] **Step 1: Update tasks/progress.md**

Open `tasks/progress.md` on the `version-2` branch and update:

```
Status: Submitted for Review
Current Phase: App Store Review
Active Story: Monitor Apple review; respond to feedback if rejected again
Last Completed Story: Build 8 submitted — onboarding scroll fix + 1.0.1 UX redesign (2026-06-03)
Next Recommended Story: After review approval — merge version-2 to main, update PROJECT-STATUS.md, publish launch post
Estimated Completion: 98%
Blockers: Apple review outcome is external
Last Validation: Build 8 archived and uploaded 2026-06-03. All tests passed. Visual QA passed on iPhone 16, iPhone 16 Plus, iPad Air 11-inch (M3). Onboarding scroll fix confirmed on iPad. Bug review passed (all 7 checks). Executive OS gate passed.
Last Updated: 2026-06-03
```

- [ ] **Step 2: Update tasks/todo.md**

Replace the current task section with:

```markdown
# Current Task

**Objective:** Monitor App Store review for build 8.
**Status:** Waiting for Review
**Branch:** version-2

## Checklist
- [x] version-2: all 9 redesign stories (A1–A6, B2–B4) complete
- [x] Build 8: onboarding scroll fix applied
- [x] Build 8: version bump (1.0.1 → 1.0, build 7 → 8)
- [x] Full test suite passed
- [x] Visual QA passed (iPhone 16, iPhone 16 Plus, iPad Air 11-inch)
- [x] Bug review passed (all 7 checks)
- [x] Executive OS gate passed
- [x] Archived and uploaded to ASC
- [x] Replied to Apple rejection message
- [x] Submitted for review
- [ ] **MONITOR**: Apple review outcome (24–48h)
- [ ] After approval: merge version-2 → main, run ./agentic-os refresh, publish launch post
```

- [ ] **Step 3: Refresh Agentic OS**

```bash
cd "/Users/nadavyigal/Documents/Projects /Agentic OS" && ./agentic-os refresh
```

- [ ] **Step 4: Commit memory updates**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
git add tasks/progress.md tasks/todo.md
git commit -m "chore(release): build 8 submitted — memory updated

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

- [ ] **Step 5: Push version-2**

```bash
git push origin version-2
```

---

## Self-Review

**Spec coverage check:**
- Rejection root cause fix → Task 2 ✓
- Build number bump + version string → Task 1 ✓
- Week strip clip → Task 3 ✓
- Test suite with simulator reset → Task 4 ✓
- Visual QA on iPad Air 11-inch → Task 5 ✓
- All 7 bug review checks → Task 6 A–G ✓
- Executive OS gate → Task 7 ✓
- Archive, reply to Apple, submit → Task 8 ✓
- Post-submit memory update + agentic-os refresh → Task 9 ✓

**Placeholder scan:** No TBD, TODO, or "implement later" text present. Every step has exact commands, expected output, or exact code blocks.

**Type consistency:** `OnboardingStepShell` body change uses the same property names (`symbol`, `title`, `subtitle`, `content`) as the existing struct definition. No new types introduced.
