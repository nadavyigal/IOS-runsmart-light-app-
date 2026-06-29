# Build 18 ASC Submission + Garmin Brand Compliance Resend — 2026-06-26

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to execute task-by-task.

**Repo:** `/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app`
**Companion repo:** `/Users/nadavyigal/Documents/RunSmart` (web, Garmin webhook/device_name work)

**Goal:** Get build 18 live on the App Store (it carries `plan_run_cta_tapped` — no plan-to-run activation cohort can be measured until it ships), then recapture and verify the 6 Gate-4 screenshots against the new device-attribution + logo fixes, and send the Garmin reply that has twice been blocked on stale screenshots.

**Context (verified against code + git, 2026-06-26):**
- iOS PR #66 (device-model attribution for screens 04-06 + Garmin wordmark for 01-03) is **merged to main**.
- Web PR #103 (`device_name` column + threading through both Garmin ingestion paths) is **merged and confirmed deployed to production**.
- `xcodebuild archive -configuration Release` already succeeded and passed `-validate-for-store` against the founder's local keychain — the code itself is store-ready as of build 18.
- The live App Store build is still v1.0.4 (build 17), which has **neither** brand fix. Build 18 has not been archived/uploaded/submitted yet.
- Garmin (Marc Lussi, ticket 213145/213165) rejected the screenshots twice already (06-22, 06-26). A third rejection risk exists specifically on screens 01-03: the fix uses Garmin's *general corporate wordmark* (light/dark PNG from the Consumer Brand Style Guide), not the Connect-app-specific tile from `developer.garmin.com/brand-guidelines/connect/` — that dedicated tile requires a clickwrap download the founder hasn't pulled yet. This is a documented, accepted risk, not a gap to silently fix in this plan.
- Reply draft `docs/garmin-application/20-GARMIN-REPLY-DRAFT-2026-06-26.md` (in the web repo) exists but is explicitly marked **NOT READY TO SEND** — it has placeholders for version/build/date that can only be filled in once build 18 is genuinely live.
- Do not touch Garmin env vars/credentials or send anything to Garmin without an explicit founder go-ahead per the standing sequencing rule.

---

## Task 1: Pre-flight check before archiving (10 min)

1. `git -C "<repo>" status --short --branch` — confirm `main` is clean, PR #66 is actually merged (not just locally present), no stray uncommitted files.
2. `git -C "<repo>" log --oneline -5` — confirm `5fdea72` (PR #66 merge) is in the history.
3. Confirm `CURRENT_PROJECT_VERSION` is 18 in the Xcode project (it was bumped in PR #63, then PR #66 layered on top without bumping again — verify it's still 18, not accidentally reset).
4. Re-run the same archive validation that already passed once: `xcodebuild archive -scheme "RunSmart" -configuration Release -archivePath <path> ... -validate-for-store` (use the exact invocation from the 2026-06-26 session log entry in `GARMIN-STATUS.md` if available) to confirm nothing regressed since that pass.

**Success criteria:** Clean tree on main with PR #66 merged, version confirmed 18, archive validation passes again.

## Task 2: Founder-only — archive, upload, submit (external, not Codex-executable)

This step requires the founder's Apple ID / 2FA and cannot be automated by an agent:

- [ ] Founder: Xcode Organizer → Archive → Validate → Distribute to App Store Connect (or `bundle exec fastlane ios release` if `APP_STORE_CONNECT_API_KEY_ID`/`_API_ISSUER_ID`/`_API_KEY` get configured first)
- [ ] Founder: select build 18 in ASC, submit for review
- [ ] Founder: wait for Apple approval, confirm genuinely live (check the actual App Store listing, not just ASC status)

**Do not proceed to Task 3 until build 18 is confirmed live.** Recapturing screenshots against a non-live build risks a third rejection for the same reason as before (evidence not matching the live build).

## Task 3: Recapture and verify all 6 Gate-4 screenshots (30-45 min)

Once build 18 is live:

1. Re-run the iOS screenshot capture script (see `docs/garmin-application/11-GATE-4-IOS-FOUNDER-RUN-SHEET.md` and the capture script referenced in `GARMIN-STATUS.md` session log 2026-06-22 — it was patched to uninstall/reinstall between shots to avoid stale-state bugs caught that day).
2. For screens 01-03: confirm the Garmin wordmark renders correctly, unstretched, at its real ~3:1 aspect ratio, light/dark variant matching system appearance.
3. For screens 04-06: confirm each shows `"Garmin [device model]"` (e.g. "Garmin Forerunner 265"), not bare "Garmin" — this requires a connected Garmin account with at least one synced activity so device_name has propagated.
4. Diff each new screenshot against Garmin's brand PDF requirements and the Hashiri.AI/NeverDone reference examples one more time before zipping.
5. Re-zip as `runsmart-garmin-screenshots-ios-2026-06-26.zip` (or appropriate date) in `docs/garmin-application/`.

**Success criteria:** All 6 screenshots visually verified against brand requirements; zip created.

## Task 4: Finalize and send the Garmin reply (founder-gated send)

1. Open `docs/garmin-application/20-GARMIN-REPLY-DRAFT-2026-06-26.md` (web repo) and fill in the version/build/date placeholders with the now-confirmed-live build 18 details.
2. Attach the new zip from Task 3.
3. Flag the 01-03 wordmark-vs-tile risk explicitly in the reply if not already covered — proactively naming the documented fallback may reduce rejection-cycle count if Marc still wants the dedicated tile.
4. **Founder reviews and sends** to ticket 213145/213165 from `nadav.yigal@runsmart-ai.com` (per the corrected sender identified in the 06-22 session log — do not use `hello@runsmart.ai`, that address doesn't exist).

**Success criteria:** Reply sent with verified, build-18-accurate evidence attached.

## Task 5: Update status docs

1. Update `GARMIN-STATUS.md` (web repo) session log with the outcome of each task above.
2. Update `tasks/progress.md` in both repos per the standing rule (after every commit/session).
3. If Garmin responds with a third rejection or approval, log it immediately — do not let `GARMIN-STATUS.md` go stale again.

---

## What This Plan Does NOT Cover

- Obtaining the official Garmin Connect tile asset (clickwrap download) — founder-only, separate from this plan; only pursue if the wordmark fallback gets rejected again.
- The `garmin_connections.scopes` empty-array cosmetic bug and `wheelchair_push_walk`/`unknown` sport-tag exclusion — tracked separately, not blocking.
- Training API workout-push — parked per founder decision 2026-06-25, not revisited here.
- Any new feature work beyond what's needed to ship build 18 and close the Garmin loop.
