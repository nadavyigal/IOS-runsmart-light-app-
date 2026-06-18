# Work Pack: RunSmart iOS Build 14 Submission

> Open this file in the RunSmart iOS repo. Run every step in order. Do not skip or reorder.

**Repo:** `/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app`

**Current state (as of 2026-06-12):**
- Checked out on `cursor/e7-wearable-depth-trends` (clean working tree)
- `main` is 2 commits behind `origin/main` — pull needed first
- `cursor` branch has 5 code-review fix commits — this IS build 14
- `fix/code-review-p0-identity` is local-only and fully superseded by the cursor branch

---

## Phase 1: Git cleanup (5 min)

- [ ] Confirm current state
  ```bash
  git status --short --branch
  ```
  Expected: `## cursor/e7-wearable-depth-trends...origin/cursor/e7-wearable-depth-trends`

- [ ] Sync main
  ```bash
  git fetch origin
  git checkout main
  git pull origin main
  git log --oneline -3
  ```
  Expected top commit: `bf49176 Merge pull request #44`

- [ ] Verify cursor branch has exactly the build 14 work
  ```bash
  git log --oneline cursor/e7-wearable-depth-trends ^main
  ```
  Expected — 5 commits, all code-review fixes:
  ```
  71791bb Fix PR review issues: coach message length guard and HealthKit upsert fallback.
  a18b893 Fix Supabase URL truncation in xcconfig that crashed launch on Build 14.
  270ba24 Finalize code review backend readiness
  2e461e2 Fix code review blockers: auth_user_id identity, Garmin security, and account deletion.
  71892bb Fix re-onboarding aha moments and Garmin OAuth callback on iOS.
  ```
  If you see any unexpected feature commits, stop and investigate before continuing.

- [ ] Push cursor branch
  ```bash
  git push origin cursor/e7-wearable-depth-trends
  ```

## Phase 2: PR — open, review, merge (10 min)

- [ ] Open the PR
  ```bash
  gh pr create \
    --title "Build 14: code review P0 fixes + aha moments + Garmin OAuth + URL truncation fix" \
    --body "$(cat <<'EOF'
  ## Summary
  - Fix re-onboarding aha moments skipping when same Apple auth uid returns after account deletion
  - Fix Garmin OAuth iOS callback: use runsmart:// scheme + poll Supabase for connected status
  - Fix code review P0 blockers: auth_user_id identity, Garmin RLS/security, account deletion
  - Fix Supabase URL truncation in xcconfig that crashed app on build 14 launch
  - Fix PR review issues: coach message length guard, HealthKit upsert fallback

  ## Build scope
  WP-4 (account deletion) + WP-6 (aha moments) + code review remediations. No new features.
  EOF
  )" \
    --base main
  ```

- [ ] Review the diff — must be only the 5 expected files and migration files
  ```bash
  gh pr diff
  ```
  Check: no new UI screens, no VOICE_COACH_ENABLED flip, no unrelated changes.

- [ ] Merge
  ```bash
  gh pr merge --squash --delete-branch
  git checkout main
  git pull origin main
  git log --oneline -3
  ```

- [ ] Delete the local superseded fix branch
  ```bash
  git branch -d fix/code-review-p0-identity
  ```

- [ ] Confirm clean state
  ```bash
  git status --short --branch
  git log --oneline @{u}..
  ```
  Expected: `## main...origin/main`, no unpushed commits.

## Phase 3: Archive (Xcode — 10 min)

- [ ] Open Xcode
- [ ] Set scheme: `IOS RunSmart app`, destination: `Any iOS Device (arm64)`
- [ ] `Product → Archive`
- [ ] In the Organizer: verify build number = 14 and bundle ID is correct
- [ ] Check: no "unsupported entitlement" warnings

## Phase 4: Upload and submit (App Store Connect — 10 min)

- [ ] In Organizer: `Distribute App → App Store Connect → Upload`
- [ ] Sign with Apple Distribution certificate (approve keychain access if prompted)
- [ ] In App Store Connect: select build 14, attach reviewer response (account deletion flow + aha moments change), submit for review

## Phase 5: Update progress

- [ ] In the repo, open `tasks/progress.md`
- [ ] Change `Current Phase` to: `1.0.2 build 14 submitted — Apple review pending`
- [ ] Update `Active Story` and `Last Updated` to today's date
  ```bash
  git add tasks/progress.md
  git commit -m "docs: update progress after build 14 submission"
  git push origin main
  ```
- [ ] Run `./agentic-os refresh` in the Agentic OS repo

---

**Done when:** Build 14 appears in App Store Connect as "Waiting for Review" and progress.md is pushed.
