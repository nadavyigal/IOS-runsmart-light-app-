# Build 15 Resubmit + Repo Cleanup — 2026-06-18

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to execute task-by-task.

**Repo:** `/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app`

**Goal:** Commit the in-progress analytics + DemoMode work, select build 15 in App Store Connect, run the physical-device smoke, and clear 2 agent worktrees.

**Context:**
- RunSmart iOS is live on the App Store.
- Build 15 was uploaded to ASC on 2026-06-15 and is processing/processed. It needs to be selected and submitted.
- The primary working tree has 18 modified files (analytics instrumentation + DemoMode refactor) and 3 untracked files — a coherent unit of work that needs committing before the next session.
- Physical device smoke is blocked on local simulator SIWA (ASAuthorizationError 1000) — it requires a real device or TestFlight build with Apple ID credentials and Garmin access.
- 2 agent worktrees (tender-thompson-60f370, youthful-moore-9d85c7) can be cleared via `./agentic-os clean --apply`.

---

## Task 1: Commit analytics instrumentation + DemoMode work (15 min)

18 modified tracked files + 3 untracked form a logical analytics/demo-mode unit.

- [ ] Review what's staged:
  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  git diff --stat HEAD
  git ls-files --others --exclude-standard
  ```

- [ ] Stage modified files:
  ```bash
  git add ".agent-os/distribution/analytics-instrumentation-spec.md" \
    "IOS RunSmart app/App/RunSmartLiteAppShell.swift" \
    "IOS RunSmart app/Core/RunSmartServiceProviding.swift" \
    "IOS RunSmart app/Features/Run/RunTabView.swift" \
    "IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift" \
    "IOS RunSmart app/PreviewSupport/RunSmartPreviewData.swift" \
    "IOS RunSmart app/Resources/Localizable.xcstrings" \
    "IOS RunSmart app/Services/Analytics/AnalyticsEvents.swift" \
    "IOS RunSmart app/Services/Analytics/AnalyticsService.swift" \
    "IOS RunSmart app/Services/Production/RunSmartProductionServices.swift" \
    "IOS RunSmart app/Services/RunSmartAnalytics.swift" \
    "IOS RunSmart app/Services/RunSmartServices.swift" \
    "IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift" \
    "IOS RunSmart app/Services/Supabase/SupabaseSession.swift" \
    "IOS RunSmart appTests/RunSmartReadinessTests.swift" \
    tasks/lessons.md \
    tasks/session-log.md \
    tasks/todo.md
  ```

- [ ] Stage untracked files:
  ```bash
  git add "IOS RunSmart app/App/RunSmartDemoMode.swift" \
    docs/qa/demo-mode-simulator-recording-checklist.md \
    docs/specs/demo-mode-simulator-recording.md
  ```

- [ ] Confirm staging looks right:
  ```bash
  git status --short
  ```
  Expected: 21 files staged, 0 untracked remaining.

- [ ] Commit:
  ```bash
  git commit -m "feat(analytics): wire PostHog analytics events + add DemoMode for simulator recording"
  ```

---

## Task 2: Push and open PR (5 min)

- [ ] Push to origin:
  ```bash
  git push origin main
  ```

- [ ] Verify no divergence:
  ```bash
  git status --short --branch
  ```
  Expected: `## main...origin/main` with no ahead/behind.

---

## Task 3: Delete merged local branch (2 min)

One local branch is already merged and can be safely removed.

- [ ] Identify and delete:
  ```bash
  git branch --merged main | grep -v '\* main' | xargs git branch -d
  ```
  Expected: deletes 1 branch.

---

## Task 4: Select build 15 and resubmit in App Store Connect (15 min, manual)

Build 15 was uploaded on 2026-06-15 and should have finished processing.

- [ ] Open App Store Connect: https://appstoreconnect.apple.com
  - Navigate: My Apps > RunSmart > iOS App > App Store (tab) > 1.0.2

- [ ] Confirm build 15 shows status "Ready to Submit" (not "Processing" or "Missing Compliance").
  - If still processing, wait 10 min and refresh.
  - If "Missing Compliance": set Encryption = No.

- [ ] Update App Review notes:
  - In the App Review Information section, add a note: "Build 15 adds a Delete Account flow (visible in Settings > Account > Delete Account) and an expanded PrivacyInfo.xcprivacy. A screen recording of the delete-account flow is attached."
  - Attach the delete-account screen recording if available. If not, note it in the text field.

- [ ] Update App Privacy in App Store Connect to reflect the PrivacyInfo.xcprivacy entries added in build 15 (if not already done on 2026-06-15).

- [ ] Select build 15 and click **Submit for Review**.

- [ ] Update progress:
  ```bash
  cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app"
  # Append to tasks/progress.md
  printf "\n## 2026-06-18 — Build 15 submitted for App Store review\n" >> tasks/progress.md
  git add tasks/progress.md
  git commit -m "docs: record build 15 submitted for App Store review 2026-06-18"
  git push origin main
  ```

---

## Task 5: Physical device smoke (20-40 min, requires physical device + Apple ID + Garmin)

SIWA fails on simulator (ASAuthorizationError 1000). This must run on a real device.

- [ ] Install via TestFlight or direct device build:
  - Option A (TestFlight): check that build 15 is available in TestFlight after processing completes. Install on a real iPhone.
  - Option B (direct): build to device via Xcode. Scheme: RunSmart, destination: connected iPhone. **Product > Run**.

- [ ] Run the full authenticated smoke:
  1. Launch app fresh (delete app first if needed for a clean state)
  2. Sign in with Apple (SIWA) — confirm no ASAuthorizationError
  3. Complete onboarding if prompted
  4. Navigate to Settings > Integrations > Connect Garmin — complete OAuth flow
  5. Confirm Garmin shows as connected
  6. Navigate to Settings > Account > Delete Account — confirm the deletion dialog appears and can be dismissed
  7. Re-register with SIWA from the login screen — confirm signup completes

- [ ] If all steps pass, mark smoke complete:
  ```bash
  printf "\n## 2026-06-18 — Physical device smoke PASSED (build 15)\nSteps: SIWA login, Garmin connect, Delete Account dialog, SIWA re-register\n" >> tasks/progress.md
  git add tasks/progress.md
  git commit -m "qa: physical device smoke passed — build 15 (2026-06-18)"
  git push origin main
  ```

- [ ] If any step fails, open a bug in `tasks/todo.md` with exact failure details before closing this session.

---

## Task 6: Remove agent worktrees (5 min)

Two agent worktrees (tender-thompson-60f370, youthful-moore-9d85c7) are stranded.

- [ ] Preview the cleanup:
  ```bash
  cd "/Users/nadavyigal/Documents/Projects /Agentic OS"
  ./agentic-os clean
  ```
  Confirm the RunSmart iOS worktrees appear in the dry-run output.

- [ ] Apply:
  ```bash
  ./agentic-os clean --apply
  ```

- [ ] Confirm:
  ```bash
  git -C "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app" worktree list
  ```
  Expected: only the main worktree remains.

---

## Done criteria
- [ ] 21 files committed and pushed to main
- [ ] Merged local branch deleted
- [ ] Build 15 submitted in App Store Connect
- [ ] App Review notes updated with delete-account screen recording reference
- [ ] Physical device smoke completed (or blockers logged in tasks/todo.md)
- [ ] 2 agent worktrees removed
