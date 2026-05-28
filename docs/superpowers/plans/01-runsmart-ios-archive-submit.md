# RunSmart iOS Build 6 — Archive & Submit Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify E5/PostHog code is complete and tested, copy approved ASO copy, run preflight, bump to Build 6, archive + upload to App Store Connect, and submit for review.

**Architecture:** 7-phase release pipeline. Phases 1–4 are automatable from CLI. Phase 5 uses Xcode Organizer GUI (signing cert is on device). Phases 6–7 are portal-only human steps.

**Tech Stack:** Swift 6 / SwiftUI, Xcode 16+, xcodebuild CLI, Supabase CLI (npx), fastlane, App Store Connect portal.

---

## File Map

| File | Action | Phase |
|------|--------|-------|
| `supabase/functions/coach_message/` | Deploy to production | 1 |
| `IOS RunSmart appTests/FlexWeekAnalyticsTests.swift` | Run tests | 1 |
| `fastlane/metadata/en-US/description.txt` | Overwrite with approved copy | 2 |
| `IOS RunSmart app.xcodeproj/project.pbxproj` | Bump CURRENT_PROJECT_VERSION 5 → 6 | 4 |
| `build/RunSmart-Build6-2026-05-28.xcarchive` | Create via Xcode Archive | 5 |

---

## Phase 1: Verify + Complete Flex Week Plan

All code from `2026-05-27-flex-week-deploy-analytics-intervention.md` is merged (PRs #21, #34, #35). The tasks were never checked off. This phase confirms the code compiles, tests pass, and the edge function is live in production.

**Files:**
- Run: `IOS RunSmart appTests/FlexWeekAnalyticsTests.swift`
- Deploy: `supabase/functions/coach_message/` (handles flex_week intent)

- [ ] **Step 1: Confirm the three E5 files exist**

  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  ls "IOS RunSmart app/Services/RunSmartAnalytics.swift" \
     "IOS RunSmart app/Services/FlexWeekAdjustmentHistory.swift" \
     "IOS RunSmart app/Features/Plan/GentleCoachInterventionCard.swift" \
     "IOS RunSmart appTests/FlexWeekAnalyticsTests.swift"
  ```
  Expected: all four paths printed with no errors.

- [ ] **Step 2: Confirm PostHog init is wired in RunSmartLiteAppShell**

  ```bash
  grep -n "setupAnalyticsIfNeeded\|POSTHOG_API_KEY" \
    "IOS RunSmart app/App/RunSmartLiteAppShell.swift"
  ```
  Expected: two lines — one calling `setupAnalyticsIfNeeded()` inside `.task`, one reading `POSTHOG_API_KEY` from `Bundle.main`.

- [ ] **Step 3: Simulator build (no signing) — validates Tasks 1–8 of the flex week plan**

  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  xcodebuild \
    -project "IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath /tmp/runsmart-build6-derived \
    CODE_SIGNING_ALLOWED=NO \
    build \
    2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run FlexWeekAnalyticsTests**

  ```bash
  xcodebuild \
    -project "IOS RunSmart app.xcodeproj" \
    -scheme "IOS RunSmart app" \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
    -derivedDataPath /tmp/runsmart-build6-derived \
    -only-testing:"IOS RunSmart appTests/FlexWeekAnalyticsTests" \
    test \
    2>&1 | grep -E "PASS|FAIL|error:|Test Suite"
  ```
  Expected: 7 tests pass, 0 failures.

- [ ] **Step 5: Deploy coach_message edge function to production**

  The `coach_message` function handles the `flex_week` intent. Requires `SUPABASE_PROJECT_REF`, `SUPABASE_ACCESS_TOKEN`, and `OPENAI_API_KEY` in `env.local` or `local.env`.

  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  bash scripts/deploy-coach-message.sh
  ```
  Expected output ends with: `coach_message deployed.`

- [ ] **Step 6: Smoke-test the deployed endpoint**

  ```bash
  curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://dxqglotcyirxzyqaxqln.supabase.co/functions/v1/coach_message" \
    -H "Content-Type: application/json" \
    -d '{"intent":"flex_week","reason":"tired"}'
  ```
  Expected: `401` — confirms function is live and JWT-gated.

- [ ] **Step 7: Commit — mark flex week plan complete**

  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  git add tasks/todo.md
  git commit -m "chore(release): verify E5 complete — build passes, 7 analytics tests pass, coach_message deployed"
  ```

---

## Phase 2: Copy Approved ASO Description

The approved description lives in the Agentic OS distribution scaffold (experiment rs-aso-001, approved 2026-05-27). It replaces the current `fastlane/metadata/en-US/description.txt`.

**Files:**
- Read: `/Users/nadavyigal/Documents/Projects /Agentic OS/distribution-os/projects/runsmart/scaffold/drafts/2026-05-27-rs-aso-001/description.txt`
- Overwrite: `fastlane/metadata/en-US/description.txt`

- [ ] **Step 1: Confirm the approved draft exists and is marked approved**

  ```bash
  head -7 "/Users/nadavyigal/Documents/Projects /Agentic OS/distribution-os/projects/runsmart/scaffold/drafts/2026-05-27-rs-aso-001/description.txt"
  ```
  Expected: frontmatter containing `status: approved` and `approved-by: founder 2026-05-27`.

- [ ] **Step 2: Write the approved body (lines 9 onward, after frontmatter) to fastlane metadata**

  Write the following content exactly to `fastlane/metadata/en-US/description.txt`:

  ```
  RunSmart gives beginner and returning runners a clear daily answer: what to run today, a plan that adjusts when life gets in the way, and an honest post-run summary.

  Use the Today screen to see your next recommended session, your readiness context, and a route suggestion. Record outdoor runs with GPS, review your effort in plain language, and keep your plan aligned with what you actually completed.

  When connected, RunSmart imports activity data from Garmin and Apple Health to update your training readiness and workout history. Private progress sharing, local workout reminders, and a coach chat that explains your training context round out the experience.

  RunSmart is built for calm, consistent running. It does not diagnose medical conditions, replace professional medical advice, or guarantee race outcomes. Always listen to your body and seek professional guidance when pain, dizziness, chest pain, fainting, or unusual symptoms appear.
  ```

- [ ] **Step 3: Verify the file was written correctly**

  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  wc -l "fastlane/metadata/en-US/description.txt"
  head -1 "fastlane/metadata/en-US/description.txt"
  ```
  Expected: 7 lines; first line starts with "RunSmart gives beginner".

- [ ] **Step 4: Commit**

  ```bash
  git add "fastlane/metadata/en-US/description.txt"
  git commit -m "chore(aso): copy approved rs-aso-001 description to fastlane metadata"
  ```

---

## Phase 3: Archive Preflight Gate

Mirrors the gate from `docs/qa/app-store-connect-closeout-2026-05-24.md`. All checks must pass before bumping the build number.

**Files:**
- Read: `IOS RunSmart app/PrivacyInfo.xcprivacy`
- Check: `fastlane/screenshots/en-US/`
- Check: `IOS RunSmart app.xcodeproj/project.pbxproj`

- [ ] **Step 1: Git state — no unexpected dirty files**

  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  git status --short
  ```
  Expected: clean, or only expected files (task logs, any in-progress work that is understood). No untracked `.swift` files under `IOS RunSmart app/`.

- [ ] **Step 2: Screenshot dimension check — 6.9-inch (1320 × 2868)**

  ```bash
  for f in fastlane/screenshots/en-US/iPhone_17_Pro_Max_0{1,2,3,4,5}_*.png; do
    python3 -c "
  import struct, zlib
  with open('$f','rb') as fh:
    fh.read(8)
    fh.read(4)
    assert fh.read(4)==b'IHDR'
    w=struct.unpack('>I',fh.read(4))[0]
    h=struct.unpack('>I',fh.read(4))[0]
    print('$f',w,'x',h)
  "
  done
  ```
  Expected: each file prints `1320 x 2868`.

- [ ] **Step 3: Screenshot dimension check — 6.1-inch (1170 × 2532)**

  ```bash
  for f in fastlane/screenshots/en-US/iPhone_17e_0{1,2,3,4,5}_*.png; do
    python3 -c "
  import struct, zlib
  with open('$f','rb') as fh:
    fh.read(8)
    fh.read(4)
    assert fh.read(4)==b'IHDR'
    w=struct.unpack('>I',fh.read(4))[0]
    h=struct.unpack('>I',fh.read(4))[0]
    print('$f',w,'x',h)
  "
  done
  ```
  Expected: each file prints `1170 x 2532`.

- [ ] **Step 4: PrivacyInfo.xcprivacy exists**

  ```bash
  ls -la "IOS RunSmart app/PrivacyInfo.xcprivacy"
  ```
  Expected: file present, non-zero size.

- [ ] **Step 5: Permission strings present in build settings**

  ```bash
  grep "NSLocationWhenInUseUsageDescription\|NSHealthShareUsageDescription" \
    "IOS RunSmart app.xcodeproj/project.pbxproj" | wc -l
  ```
  Expected: `4` (two build configs × two keys).

- [ ] **Step 6: Bundle ID, version, and build number check**

  ```bash
  grep "PRODUCT_BUNDLE_IDENTIFIER\|MARKETING_VERSION\|CURRENT_PROJECT_VERSION" \
    "IOS RunSmart app.xcodeproj/project.pbxproj" | sort -u
  ```
  Expected output (exact strings):
  ```
  CURRENT_PROJECT_VERSION = 5;
  MARKETING_VERSION = 1.0;
  PRODUCT_BUNDLE_IDENTIFIER = com.runsmart.lite;
  ```
  If `CURRENT_PROJECT_VERSION` is not 5 here, stop — the build number was already changed. Investigate before continuing.

- [ ] **Step 7: No untracked Swift files**

  ```bash
  git ls-files --others --exclude-standard "IOS RunSmart app/" | grep "\.swift$"
  ```
  Expected: no output. Any output means a new Swift file is uncommitted — commit or delete it before archiving.

---

## Phase 4: Bump Build Number 5 → 6

**Files:**
- Modify: `IOS RunSmart app.xcodeproj/project.pbxproj` (4 occurrences of `CURRENT_PROJECT_VERSION`)

- [ ] **Step 1: Confirm current value is 5 (safety check)**

  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  grep -c "CURRENT_PROJECT_VERSION = 5;" "IOS RunSmart app.xcodeproj/project.pbxproj"
  ```
  Expected: `4`

- [ ] **Step 2: Replace all occurrences**

  ```bash
  sed -i '' 's/CURRENT_PROJECT_VERSION = 5;/CURRENT_PROJECT_VERSION = 6;/g' \
    "IOS RunSmart app.xcodeproj/project.pbxproj"
  ```

- [ ] **Step 3: Verify the replacement**

  ```bash
  grep "CURRENT_PROJECT_VERSION" "IOS RunSmart app.xcodeproj/project.pbxproj" | sort -u
  ```
  Expected: `CURRENT_PROJECT_VERSION = 6;` (with no `= 5;` remaining).

- [ ] **Step 4: Commit**

  ```bash
  git add "IOS RunSmart app.xcodeproj/project.pbxproj"
  git commit -m "chore(release): bump build number to 6"
  ```

- [ ] **Step 5: Verify Xcode sees build 6**

  Open `IOS RunSmart app.xcodeproj` in Xcode. Navigate to the project target's General tab. Confirm Build is `6` and Version is `1.0`.

---

## Phase 5: Archive + Export + Upload to App Store Connect

This phase uses Xcode Organizer (GUI). Signing certs and provisioning are on this machine — command-line signing is not configured. The prior build 5 archive path was `build/RunSmart-AppStoreReady-2026-05-19*.xcarchive`; build 6 will create a new one.

**Pre-condition:** Phase 4 is committed and Xcode shows Build 6.

- [ ] **Step 1: Clean derived data for a fresh Release build**

  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  rm -rf ~/Library/Developer/Xcode/DerivedData/IOS_RunSmart_app-*
  ```

- [ ] **Step 2: Archive via Xcode Organizer**

  In Xcode:
  1. Select the **IOS RunSmart app** scheme in the toolbar.
  2. Set the destination to **Any iOS Device (arm64)** (not a simulator).
  3. Menu: **Product → Archive**.
  4. Wait for the build — it takes 3–5 minutes. The Organizer window opens automatically when done.
  5. Confirm the new archive appears at the top of the list with version `1.0 (6)`.

- [ ] **Step 3: Distribute to App Store Connect**

  In the Organizer window with the Build 6 archive selected:
  1. Click **Distribute App**.
  2. Select **App Store Connect** → **Next**.
  3. Select **Upload** → **Next**.
  4. Leave all options at defaults (include symbols, manage version + build number: OFF since we set it manually) → **Next**.
  5. Select **Automatically manage signing** → **Next**.
  6. Review the summary: verify `com.runsmart.lite`, version `1.0`, build `6`.
  7. Click **Upload**.
  8. Wait for the upload to complete (1–3 minutes). Xcode shows "Upload Successful".

- [ ] **Step 4: Confirm processing in App Store Connect**

  In a browser, open App Store Connect → My Apps → RunSmart → TestFlight. Confirm Build 6 appears with status "Processing" (typically takes 5–15 minutes to become "Ready to Submit").

---

## Phase 6: Portal Checklist

All steps in this phase are performed in App Store Connect at https://appstoreconnect.apple.com. Execute after Build 6 shows "Ready to Submit".

- [ ] **Step 1: Select Build 6 for the 1.0 submission**

  App Store Connect → My Apps → RunSmart → 1.0 Prepare for Submission → Build → click the `+` → select Build 6. Remove any reference to the old Build 5.

- [ ] **Step 2: Upload screenshots — 6.9-inch (iPhone 17 Pro Max)**

  In the App Preview and Screenshots section, select the 6.9" slot. Upload in this order:
  1. `fastlane/screenshots/en-US/iPhone_17_Pro_Max_01_today.png`
  2. `fastlane/screenshots/en-US/iPhone_17_Pro_Max_02_plan.png`
  3. `fastlane/screenshots/en-US/iPhone_17_Pro_Max_03_run.png`
  4. `fastlane/screenshots/en-US/iPhone_17_Pro_Max_04_report.png`
  5. `fastlane/screenshots/en-US/iPhone_17_Pro_Max_05_profile.png`

  Do not upload `_99_signin.png` as a primary screenshot.

- [ ] **Step 3: Upload screenshots — 6.1-inch (iPhone 17e)**

  Upload in the 6.1" slot in the same order:
  1. `fastlane/screenshots/en-US/iPhone_17e_01_today.png`
  2. `fastlane/screenshots/en-US/iPhone_17e_02_plan.png`
  3. `fastlane/screenshots/en-US/iPhone_17e_03_run.png`
  4. `fastlane/screenshots/en-US/iPhone_17e_04_report.png`
  5. `fastlane/screenshots/en-US/iPhone_17e_05_profile.png`

- [ ] **Step 4: Confirm app metadata**

  Verify each field matches `docs/qa/app-store-connect-closeout-2026-05-24.md`:
  - Name: `RunSmart`
  - Subtitle: (whatever is in `fastlane/metadata/en-US/subtitle.txt`)
  - Description: matches the approved rs-aso-001 text (starts with "RunSmart gives beginner")
  - Keywords: matches `fastlane/metadata/en-US/keywords.txt`
  - Support URL: `https://www.runsmart-ai.com/support`
  - Marketing URL: `https://www.runsmart-ai.com`
  - Privacy Policy URL: `https://www.runsmart-ai.com/privacy`

- [ ] **Step 5: Set category**

  Primary category: **Health & Fitness**. No secondary category required.

- [ ] **Step 6: Age rating — confirm 4+**

  Open the age rating questionnaire. All questions should be answered No / None (no violence, no gambling, no mature content). Confirm the result is **4+**.

- [ ] **Step 7: Paste reviewer notes**

  In the "Notes for App Review" field, paste the suggested review flow from `docs/qa/app-review-notes-2026-05-19.md`:

  ```
  Sign in with the provided demo account.
  Open Today to view the next workout, readiness context, and Coach entry point.
  Open Plan to inspect upcoming workouts.
  Start a short run from Run, then stop before recording distance if testing indoors.
  Open Report or Activity to view completed-run history.
  Open Profile to review connected-service and reminder settings.
  Optional: enable notifications to verify local reminder copy.

  Apple Health access is optional. Location is used for GPS tracking only during an active run. Garmin connection is optional. Coach responses are informational training guidance, not medical advice.
  ```

- [ ] **Step 8: Enter demo credentials**

  In the "Sign-In Information" section, enter the demo account credentials directly in App Store Connect. Requirements:
  - Completed onboarding profile
  - Beginner-friendly active training plan
  - At least one recent completed run or sample activity
  - Coach reachable after sending a message

  Do not store credentials in this repository.

- [ ] **Step 9: Complete privacy questionnaire**

  In the App Privacy section, confirm or enter the following (source: `docs/qa/app-store-connect-closeout-2026-05-24.md`):
  - Data types collected: **User ID, Health, Fitness, Precise Location**
  - All collected types linked to user: **Yes**
  - Tracking: **No**
  - Tracking domains: **None**
  - Purposes: **App Functionality**

---

## Phase 7: Submit for Review

- [ ] **Step 1: Final save**

  Click **Save** on the App Store Connect submission page. Resolve any red-bordered fields before continuing.

- [ ] **Step 2: Submit for Review**

  Click **Add for Review** → confirm in the dialog → **Submit to App Store**.

- [ ] **Step 3: Record submission**

  After submission, note the submission date and confirm status changes to "Waiting for Review".

  Add to `tasks/todo.md`:
  ```markdown
  ## RunSmart 1.0 Build 6 — Submitted for Review
  - Submitted: 2026-05-28
  - Status: Waiting for Review
  - Next: monitor App Store Connect for reviewer questions or rejection
  ```

- [ ] **Step 4: Commit task memory**

  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  git add tasks/todo.md
  git commit -m "chore(release): record Build 6 submitted for App Store review"
  ```

---

## Self-Review

**Phase coverage check:**
1. Flex week plan tasks → Phase 1: all 9 tasks from the flex week plan are covered by Steps 1–7 (file audit, build, test, deploy, smoke test). ✓
2. Approved description → Phase 2: exact content from rs-aso-001 draft is in Step 2. ✓
3. Preflight gate → Phase 3: mirrors all 8 bullets from `app-store-connect-closeout-2026-05-24.md`. ✓
4. Build bump → Phase 4: 4-occurrence `sed` replacement in pbxproj, verified before and after. ✓
5. Archive + upload → Phase 5: Xcode Organizer walk-through with exact UI steps. ✓
6. Portal checklist → Phase 6: covers all portal bullets from the closeout doc plus screenshots, age rating, reviewer notes, demo credentials, privacy. ✓
7. Submit → Phase 7: submit + record. ✓

**Placeholder scan:** No TBDs. All steps have exact commands or exact UI instructions.

**Type consistency:** `CURRENT_PROJECT_VERSION = 5;` → `= 6;` in Phase 4; same string verified in Phase 3 Step 6.
