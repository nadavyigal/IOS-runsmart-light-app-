# RunSmart iOS — Resubmission as Build 8

**Status:** Approved
**Date:** 2026-06-03
**Base branch:** `version-2`
**Target build:** 8 (resubmission after build 6 rejection on Guideline 2.1a)

---

## Situation

Build 6 was rejected. Apple reviewed on iPad Air 11-inch (M3) / iPadOS 26.4.2 and found the app stuck on the Privacy onboarding screen.

`version-2` already contains the full 1.0.1 UX redesign (stories A1–A6, B2–B4): Today v2, Report v2, Plan v2, Profile v2, post-run bridge, and VoiceCoachService. All stories are marked complete. The build compiles. Tests stalled at simulator launch last session (infrastructure issue, not a code failure). Screenshots were captured and show real UI on all five tabs.

**What version-2 does NOT have:**
- The onboarding scroll fix (the actual rejection root cause)
- A clean test suite run
- A confirmed visual QA pass on iPad Air 11-inch specifically
- The full bug review pass
- Executive OS sign-off

This spec covers the remaining gap to get from version-2 → a submission-ready build 8.

---

## Rejection Root Cause

**File:** `IOS RunSmart app/Features/Onboarding/OnboardingView.swift`
**Struct:** `OnboardingStepShell` (line ~151)

`OnboardingStepShell` wraps all step content in a plain `VStack` with no `ScrollView`. The Privacy step (step index 3) has the most content of any step: coaching tone grid + toggle + caption + 2 device preview rows + rookie callout + button. On iPad — even in "Designed for iPhone" compatibility mode — the button is pushed off-screen and unreachable. All 5 steps use this shell, so the fix benefits all of them.

### Fix

Replace the `VStack` root in `OnboardingStepShell.body` with a `ScrollView`. Convert the outer `Spacer(minLength:)` calls to padding (spacers have no effect inside `ScrollView`):

```swift
// Before
var body: some View {
    VStack(alignment: .leading, spacing: 22) {
        Spacer(minLength: 20)
        HStack(spacing: 14) { /* logo + icon */ }
        VStack(alignment: .leading, spacing: 8) { /* title + subtitle */ }
        ContentCard {
            VStack(alignment: .leading, spacing: 14) { content }
        }
        Spacer(minLength: 20)
    }
    .padding(24)
}

// After
var body: some View {
    ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) { /* logo + icon */ }
            VStack(alignment: .leading, spacing: 8) { /* title + subtitle */ }
            ContentCard {
                VStack(alignment: .leading, spacing: 14) { content }
            }
        }
        .padding(24)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }
}
```

No other onboarding changes. All 5 steps inherit the fix automatically.

---

## Known Visual Issue to Address

From the last version-2 session log: "Today still shows an existing right-edge clipped week card on this upstream branch."

Before archiving: launch in simulator, check the Today tab week strip right edge. If still clipped, fix the horizontal padding or trailing clip on `TodayWeekStripSection` before archiving.

---

## Implementation Sequence

1 task, 1 agent. No parallel dispatch needed — the design work is done.

### Task 1 — Onboarding scroll fix (on version-2)

Branch from `version-2`. Apply the `ScrollView` fix to `OnboardingStepShell`. Commit. Merge back to `version-2`.

### Task 2 — Test suite (reset simulator if needed)

The last test run stalled at simulator launch (CoreSimulator infrastructure, not a test failure). Before claiming pass:

```bash
# Reset the problematic simulator first
xcrun simctl shutdown all
xcrun simctl erase all   # WARNING: erases all simulator data

xcodebuild test \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -derivedDataPath /tmp/runsmart-build8-derived \
  2>&1 | tail -30
```

Expected: all tests pass. If specific tests fail, fix them before proceeding. Do not skip or ignore failures.

### Task 3 — Simulator visual QA

Run on these three simulators. Take a screenshot of each tab on each device. All must look correct before archiving.

| Simulator | Why |
|---|---|
| iPhone 16 (6.1-inch) | Primary target |
| iPhone 16 Plus (6.7-inch) | Largest iPhone |
| **iPad Air 11-inch (M3)** | The rejection device — MUST verify onboarding scrolls |

Checklist per device:
- [ ] Onboarding Privacy step: "Confirm Privacy" button visible and tappable (scroll down if needed)
- [ ] Today tab: coach icon in header, week strip, decision card in first viewport, no hero card/quick actions visible
- [ ] Plan tab: current week section first, "Explain this week" compact button visible
- [ ] Report tab: Runs | Reports | Progress segment picker renders
- [ ] Profile tab: connected services visible above fold, no run reports list

Today right-edge clip: confirm `TodayWeekStripSection` is not clipped on any device size.

---

## Full Bug Review Gate

Run all checks before generating the archive. Do not skip any step.

### A — Force-unwrap sweep

```bash
grep -rn "[^!]![^=]" "IOS RunSmart app/" --include="*.swift" \
  | grep -v ".git\|Test\|#if DEBUG\|//\|\"" \
  | grep -v "\.xcconfig\|\.plist" \
  | wc -l
```

Target: zero new force-unwraps introduced since `main`. Compare against:
```bash
cd /tmp && git clone --depth 1 --branch main <repo-url> rs-main-check
grep -rn "[^!]![^=]" rs-main-check/IOS\ RunSmart\ app/ --include="*.swift" | grep -v ".git\|Test\|#if DEBUG\|//\|\"" | wc -l
```

Any net increase must be reviewed and justified.

### B — iPad onboarding confirmation

On the iPad Air 11-inch (M3) simulator:
1. Delete app, fresh install
2. Go through all 5 onboarding steps
3. Confirm every step's primary CTA button is visible and tappable
4. Confirm Privacy step (step 4) advances to the Completion step when tapped

### C — Voice coach audio gate

On iPhone 16 simulator:
1. Start a run (Run tab)
2. Confirm voice coaching phase transitions fire (log output acceptable — physical device QA for actual audio is a post-submit risk)
3. Confirm mute toggle is visible in LiveRunView
4. Confirm the app does not crash when voice cue endpoint returns an error

### D — Coach entry points

From the Today tab: tap ✦ icon → CoachFlowView opens.
From the Plan tab: tap "Explain this week" → CoachFlowView opens.
From the Report tab: tap a run report row "Explain this run" link → CoachFlowView opens.
Confirm no duplicate or orphaned Coach entry points on any root tab.

### E — No ResumeBuilder artifacts

```bash
grep -rn "resume\|Resume\|ATS\|job description\|optimize" \
  "IOS RunSmart app/" --include="*.swift" \
  | grep -v ".git\|Test\|#if DEBUG\|//\|comment" \
  | grep -vi "RunSmart\|Garmin\|run\|speed\|pace\|supabase" \
  | head -20
```

RunSmart should have no visible ResumeBuilder-era copy, buttons, or flows. Any match must be investigated.

### F — Analytics regression

```bash
grep -rn "Analytics.track" "IOS RunSmart app/" --include="*.swift" \
  | grep -v ".git\|Test" | sort
```

Confirm these events still have call sites:
- `trackOnboardingStarted`
- `trackOnboardingStepCompleted`
- `trackOnboardingCompleted`
- `trackRunCompleted` (or equivalent)
- `trackPlanGenerated` (or equivalent)

### G — Secrets audit

```bash
grep -rn "phc_\|eyJ\|secret\|api.key\|apiKey\|API_KEY" \
  "IOS RunSmart app/" --include="*.swift" \
  | grep -v ".git\|Test\|#if DEBUG\|xcconfig\|// "
```

Expected: zero results. All secrets must live in `RunSmartSecrets.xcconfig` (gitignored).

---

## Executive OS Gate

After bug review passes, before archiving:

```bash
cd "/Users/nadavyigal/Documents/Projects /Agentic OS" && ./agentic-os refresh
```

Open `executive-os/EXECUTIVE-DASHBOARD.md`. Confirm:
- RunSmart iOS status updated to "Build 8 resubmission ready"
- Risk board has no unresolved blockers
- No open CEO decisions surfaced by this change
- Portfolio focus is still Resumely iOS submission (parallel track) — RunSmart does not overtake it

If any CEO decision is surfaced, resolve it before archiving. If none, proceed.

---

## Archive and Submit (Build 8)

### Pre-archive checklist

- [ ] `version-2` branch is clean (`git status` shows no uncommitted changes)
- [ ] `RunSmartSecrets.xcconfig` present with real PostHog key (not the `.example` placeholder)
- [ ] Build number in `RunSmartInfo.plist` is **8** (`CFBundleVersion = 8`)
- [ ] Version string is **1.0** (`CFBundleShortVersionString = 1.0`) — the 1.0.1 redesign ships AS 1.0; no live users exist to compare against a prior version

### Archive steps

1. Xcode: set destination to **Any iOS Device (arm64)**
2. **Product → Archive** (Release configuration)
3. Organizer → validate before uploading
4. Distribute App → App Store Connect → Upload
5. In ASC: select build 8 on the 1.0 submission page
6. **Reply to the Apple rejection message** in ASC: "Fixed the Privacy onboarding step overflow — all steps now scroll, ensuring the Continue button is reachable on all device sizes including iPad."
7. Submit for Review

### Post-submit

- Update `tasks/progress.md` on `version-2` with submission date and build number
- Run `./agentic-os refresh` to sync the dashboard
- Commit the memory update: `git commit -m "chore(release): build 8 submitted to App Store review"`
- Merge `version-2` → `main`

---

## What Does NOT Change

- Run tab (out of scope)
- Garmin / HealthKit integration
- Backend schema or Supabase services
- CoachFlowView internals
- Any ASO metadata (descriptions, screenshots, keywords) — those were finalized for build 6

---

## Parallel Track: Resumely iOS

Resumely iOS submission is happening simultaneously (WP3 plan). The two tracks are independent. If Resumely device smoke blocks, RunSmart work continues. Do not let one block the other.
