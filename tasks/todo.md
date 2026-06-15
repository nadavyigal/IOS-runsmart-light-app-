# Task State

## Current Task

**Objective:** Fix App Store rejection for RunSmart iOS v1.0.2 and prepare fresh build 15 for resubmission: make Delete Account flow clear in-app and declare full privacy manifest data/API usage.
**Status:** Source fixes are pushed; build number bumped to 15 for the fresh upload. Archive/export/upload and manual App Store Connect resubmission remain.
**Branch:** `main`

### Checklist
- [x] Read canonical task memory/lessons and inspect Xcode target/profile/auth files.
- [x] Update Account screen delete flow confirmation copy and error handling.
- [x] Expand `PrivacyInfo.xcprivacy` collected data declarations.
- [x] Run Release build validation with signing disabled.
- [x] Commit and push app repo privacy/account-deletion source changes.
- [x] Bump build number to 15 for fresh App Store Connect upload.
- [ ] Archive/export/upload build 15, then update outer pointer if needed.

### Validation - 2026-06-15
- `plutil -lint "IOS RunSmart app/PrivacyInfo.xcprivacy"` passed.
- `git diff --check` passed.
- Release generic iOS build passed:
  `xcodebuild -scheme "IOS RunSmart app" -destination "generic/platform=iOS" -configuration Release build CODE_SIGNING_ALLOWED=NO`
- Built app bundle contains the updated `PrivacyInfo.xcprivacy`.
- Build 15 archive succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-build15-AppStore-20260615.xcarchive" archive -allowProvisioningUpdates`
- Build 15 App Store export succeeded:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-build15-AppStore-20260615.xcarchive" -exportPath "build/RunSmart-build15-AppStoreExport-20260615" -exportOptionsPlist "ExportOptionsAppStore.plist" -allowProvisioningUpdates`
- Exported IPA inspection confirmed bundle id `com.runsmart.lite`, version `1.0.2`, build `15`, `ITSAppUsesNonExemptEncryption=false`, `get-task-allow=false`, HealthKit, Sign in with Apple, associated domains, and expanded `PrivacyInfo.xcprivacy`.

---

## Previous Current Task

**Objective:** Confirm RunSmart 1.0.2 build 14 archive/resubmission readiness after deployed delete-account and Garmin fixes.
**Status:** Archive/export/package validation is green from current `main`, and direct CoreDevice install/launch on the paired iPhone now works. Full authenticated smoke is not complete from this environment because the local simulator still fails Sign in with Apple with `ASAuthorizationError 1000`; complete the live device/TestFlight SIWA -> Garmin -> delete -> re-register smoke before App Store resubmission.
**Branch:** `main`

### Checklist
- [x] Inspect user-provided Xcode smoke logs for relevant app/backend errors.
- [x] Check Supabase Edge Function and Postgres logs for the delete-account failure.
- [x] Fix `delete_account` source so it no longer tries to delete from the production `garmin_activity_points` view.
- [x] Fix native Garmin OAuth so the iOS callback completes the gateway token exchange instead of only observing the callback URL.
- [x] Fix RunSmart web Garmin gateway source so native `runsmart://` redirects are accepted, request redirect URIs win, and signed state carries native identity context.
- [x] Run local compile/type validation.
- [x] Deploy updated Supabase `delete_account` Edge Function.
- [x] Deploy updated RunSmart web Garmin gateway to production.
- [x] Run fresh simulator install/build/launch smoke from current source.
- [x] Run Release iphoneos compile/store-validation build from current source.
- [x] Investigate physical-device install failure; direct CoreDevice install and launch succeeded.
- [x] Create fresh build 14 archive and non-upload App Store export from current source.
- [ ] Rerun live smoke on device/TestFlight: SIWA/register, Garmin connect, delete account, register/sign in again.
- [ ] Archive/upload/resubmit build 14 only after the live device/TestFlight smoke passes.

### Validation - 2026-06-14
- Supabase Edge Function logs showed `delete_account` returning 500 during the account-deletion smoke.
- Supabase Postgres logs showed the underlying database error: `cannot delete from view "garmin_activity_points"`.
- Xcode logs showed Garmin connect ending as `canceled`; source inspection found native OAuth returned from `ASWebAuthenticationSession` without POSTing the Garmin `code`/`state` to the gateway callback endpoint.
- iOS simulator build passed with signing disabled:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-bugfix-dd CODE_SIGNING_ALLOWED=NO build`
- RunSmart web type-check passed:
  `npm run type-check` from `/Users/nadavyigal/Documents/Projects /RunSmart /Running-coach-/v0`.
- `git diff --check` passed in both the iOS app repo and the RunSmart web repo.
- Deno Edge Function validation was not run because `deno` is not installed in this environment.
- Supabase CLI/token and Vercel deploy permissions are unavailable in this session, so production deployment and live smoke are still pending.

### Validation - 2026-06-15
- Source state: `main` at `c543ffe`, `MARKETING_VERSION = 1.0.2`, `CURRENT_PROJECT_VERSION = 14`, bundle id `com.runsmart.lite`.
- Fresh install reset passed on the booted iPhone 17 Pro simulator by uninstalling `com.runsmart.lite` before install.
- Debug simulator build passed with signing disabled:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Debug -destination "platform=iOS Simulator,id=FCC9843B-C0F3-4F7F-A04D-EF2C4875888B" -derivedDataPath /tmp/runsmart-release-smoke-20260615-dd CODE_SIGNING_ALLOWED=NO build`
- Simulator install and launch passed for `com.runsmart.lite`.
- Fresh sign-in surface showed `RunSmart`, Sign in with Apple, and `HealthKit reads approved data and can save completed GPS runs`.
- Tapping Sign in with Apple still failed on this simulator with `ASAuthorizationError 1000`, so authenticated Garmin/delete/re-register smoke was not reachable locally.
- Release iphoneos build passed with signing disabled and Xcode store validation:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -derivedDataPath /tmp/runsmart-release-smoke-20260615-release-dd CODE_SIGNING_ALLOWED=NO build`
- Release build emitted one pre-existing HealthKit deprecation warning for `HKWorkout` init; no build failure.
- `plutil -lint RunSmartInfo.plist "IOS RunSmart app/PrivacyInfo.xcprivacy"` passed.
- Static App Review scans confirmed SIWA requests `.fullName` and `.email`, no name/email onboarding text-field match appeared, visible HealthKit copy exists, and no CareKit match appeared.
- Built simulator app metadata confirmed bundle id `com.runsmart.lite`, version `1.0.2`, build `14`, `ITSAppUsesNonExemptEncryption=false`, full Supabase URL, and Garmin gateway URL.
- Supabase logs show patched `delete_account` version 2 was invoked after deployment, no longer returned 500, and an auth-user deletion plus later Apple signup/login occurred. The function returned 207 because non-critical cleanup warnings were present.
- Vercel runtime log access is still permission-limited in this environment, so Garmin production callback traffic could not be independently confirmed here.
- Investigated the Xcode physical-device install failure. The Debug app bundle metadata and signing looked sane, direct `devicectl device install app` succeeded, and direct `devicectl device process launch` succeeded for `com.runsmart.lite`; the original Xcode error is consistent with a flaky wireless CoreDevice/Xcode install-worker connection rather than a broken app package.
- Debug generic iphoneos build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Debug -destination "generic/platform=iOS" build CODE_SIGNING_ALLOWED=NO`
- Fresh Release archive succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-build14-AppStore-20260615.xcarchive" archive -allowProvisioningUpdates`
- Non-upload App Store export succeeded:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-build14-AppStore-20260615.xcarchive" -exportPath "build/RunSmart-build14-AppStoreExport-20260615" -exportOptionsPlist ExportOptionsAppStore.plist -allowProvisioningUpdates`
- Exported IPA inspection passed: `build/RunSmart-build14-AppStoreExport-20260615/RunSmart.ipa` contains bundle id `com.runsmart.lite`, version `1.0.2`, build `14`, `ITSAppUsesNonExemptEncryption=false`, Apple Distribution signing, Sign in with Apple, associated domains, HealthKit, `get-task-allow=false`, and dSYM symbols.

---

## Previous Current Task

**Objective:** Execute code review fix plan (identity, security, correctness, performance, cleanup).  
**Plan:** `docs/plans/2026-06-11-code-review-fix-plan.md`  
**Status:** Phases 0–3 complete; Phase 4 partial (4.3/4.4 file splits deferred). Backend migrations applied; build 14 archive/export validation passed; simulator XCTest execution still blocked by simulator install/launch infra.
**Branch:** `cursor/e7-wearable-depth-trends`

### Phase 0 — Baseline
- [x] 0.1 Export live schema (`profiles`, `challenge_enrollments`, `garmin_*`, `runs`, route tables)
- [x] 0.2 Audit RLS on `garmin_activity_points`, `garmin_activities`, `runs`
- [x] 0.3 List/verify indexes on hot query columns
- [x] 0.4 Xcode build green on branch (`/tmp/runsmart-dd`, iPhone 17 Pro Max sim); XCTest blocked by simulator SIGILL bootstrap — run tests locally after sim reset
- [x] 0.5 Create branch `fix/code-review-p0-identity`

### Phase 1 — P0 Identity, auth, data deletion
- [x] 1.1a Decide profile identity model (document in `docs/decisions/`)
- [x] 1.1b Fix challenge enrollment — stop using `userIdInt64` hash
- [x] 1.1c Fix Garmin connect for UUID profiles
- [x] 1.1d Fix cloud run upsert for UUID profiles (`upsertCompletedRunIfPossible`)
- [x] 1.1e Add integration test: profile → Garmin → run sync → challenge enroll
- [x] 1.2a Scope `activityRoutePoints` by `auth_user_id`
- [x] 1.2b RLS migration/verify for `garmin_activity_points`
- [x] 1.2c Restrict CORS on `delete_account` and `coach_message`
- [x] 1.2d Cap `coach_message` message length
- [x] 1.2e Externalize Supabase URL/key from Swift source
- [x] 1.2f Wipe `user_saved_routes` + `user_benchmark_routes` in `delete_account`
- [x] 1.2g Return partial-failure signal when delete wipe warnings exist
- [x] **PR-1** Identity (1.1b–1.1d) + tests
- [x] **PR-2** Security (1.2a–1.2d, 1.2g)
- [x] **PR-3** Account deletion + config (1.2e–1.2f)

### Phase 2 — P1 Correctness
- [x] 2.1 Implement real `disconnect(provider:)` (Garmin revoke + DB + local state)
- [x] 2.2 HealthKit: check `authorizationStatus` after prompt
- [x] 2.3 Garmin OAuth: strict callback, ephemeral session, fail on bad callback
- [x] 2.4 Align debrief client timeout with server (≥10s or async debrief)
- [x] 2.5 Stable Garmin run IDs from `providerActivityID`
- [x] 2.6 Surface Garmin/RLS errors in device status (not silent disconnected)
- [x] 2.7 Remove hardcoded production Garmin gateway fallback

### Phase 3 — P2 Performance
- [x] 3.1 Deduplicate `planRepo.activePlan()` on Today load
- [x] 3.2 Parallelize `latestRunReports`
- [x] 3.3 Bulk HealthKit run upsert
- [x] 3.4 Parallel Garmin route point fetch
- [x] 3.5 Debounce Activity tab refresh on run/report notifications
- [x] 3.6 Parallel `nearbyLoopRoutes`
- [x] 3.7 Add DB indexes (after prod EXPLAIN)

### Phase 4 — P3 Cleanup
- [x] 4.1 Remove dead code (`fetchPostRunInsight`, stub `finishRun`) — insight lookup removed; `finishRun` remains protocol stub
- [x] 4.2 Extract shared Garmin bucket logic — `GarminDistanceBucket` in `GarminMappers.swift`
- [ ] 4.3 Split `SupabaseRunSmartServices.swift` by protocol
- [ ] 4.4 Split `SecondaryFlowView.swift` by scaffold
- [x] 4.5 Gate/remove `LiveRunSmartServices` from release target — not wired in app shell
- [x] 4.6 Update stale `technical-risks.md`
- [x] 4.7 Harden `AhaMomentStore` (LIKE escape, error propagation)

### Validation (plan complete)
- [ ] TestFlight smoke: SIWA, Garmin connect, run sync, challenge, delete account
- [x] No critical code-review findings remain open in source/backend validation; live TestFlight smoke remains open
- [x] Update `tasks/lessons.md` with identity-model decision
- [x] 2026-06-12 simulator reset completed on iPhone 17 Pro Max.
- [x] 2026-06-12 `xcodebuild build-for-testing` passed for `RunSmartReadinessTests` + `WellnessTrendMapperTests` using `/tmp/runsmart-pr-readiness-focused-dd2`.
- [ ] 2026-06-12 focused XCTest execution built but stalled at simulator install/launch worker materialization; rerun from Xcode GUI or a healthier simulator before final TestFlight smoke.
- [x] 2026-06-12 production Supabase migrations applied and verified: `runs.auth_user_id`, `garmin_activity_points` security-invoker view, owner RLS on `garmin_activities`/`runs`, hot-path indexes, and duplicate challenge auth index cleanup.
- [ ] 2026-06-12 Edge Function deploy for `delete_account` / `coach_message` not run locally because Supabase CLI/token are unavailable in this environment.
- [x] 2026-06-12 App Store readiness package validation passed for build 14: Release archive, non-upload App Store export, IPA version/build/entitlements/signing inspection.

---

## Previous Task — App Review Build 12

**Objective:** Fix RunSmart 1.0.1 build 11 rejection and prepare build 12 for resubmission.
**Status:** Apple rejected build 11 on 2026-06-08 under Guideline 4 because onboarding asked for name/email after Sign in with Apple, and under Guideline 2.5.1 because HealthKit/CareKit API functionality was not clearly identified in the UI. Build 12 source/export validation passed locally on 2026-06-09; upload/resubmission are still pending.
**Branch:** codex/app-review-rejection-recovery

### Checklist
- [x] Confirm canonical app repo and preserve existing dirty work.
- [x] Record Apple rejection: Submission ID `fe1e059b-4eea-46e1-ae4e-980b1b027d84`, review date 2026-06-05, reviewed build `1.0.1 (9)`, devices iPhone 17 Pro Max and iPad Air 11-inch (M3).
- [x] Record latest Apple rejection: Submission ID `63f48069-3f6c-4279-8f7f-447d9d082a10`, review date 2026-06-08, reviewed build `1.0.1 (11)`, devices iPad Air 11-inch (M3) and iPhone 17 Pro Max.
- [x] Confirm HealthKit entitlement and HealthKit permission usage descriptions are present.
- [x] Confirm CareKit is not used in the repo.
- [x] Make HealthKit functionality explicit in visible UI: sign-in feature pill, onboarding privacy step, Profile connected-service tile, and HealthKit detail permissions/controls.
- [x] Add analytics coverage for HealthKit disclosure viewed and HealthKit connect intent.
- [x] Wire existing `plan_generated` analytics event to successful generated-plan persistence.
- [x] Remove the onboarding name field shown after Sign in with Apple.
- [x] Capture Apple-provided full name/email from AuthenticationServices and seed the profile internally when available.
- [x] Disable Fastlane automatic build-number increments for `beta` and `release`.
- [x] Replace stale build-5 readiness checklist with current 1.0.1 resubmission provenance gates.
- [x] Bump build number to `12` for the next App Store resubmission.
- [x] Run `git diff --check`.
- [x] Signing-disabled simulator build passes before the build 12 bump.
- [x] Re-run signing-disabled simulator build after the build 12 bump.
- [x] Create a local Release archive for build 12 as a compile/archive proof.
- [x] Inspect local archive metadata: bundle id `com.runsmart.lite`, version `1.0.1`, build `12`, `ITSAppUsesNonExemptEncryption=false`, HealthKit/Apple Sign in entitlements, and dSYM present.
- [x] Archive build 12 for App Store distribution/export validation.
- [x] Inspect archive/export bundle metadata: display name `RunSmart`, bundle id `com.runsmart.lite`, version `1.0.1`, build `12`, iPhone-only, `ITSAppUsesNonExemptEncryption=false`, dSYM present, distribution signing on the exported IPA, and `get-task-allow=false` on the exported IPA.
- [x] Export App Store Connect IPA with distribution signing.
- [ ] Upload build 12 to App Store Connect.
- [ ] Select processed build 12 and resubmit for review.

### Validation
- Whitespace validation passed: `git diff --check`.
- Static HealthKit/CareKit scan passed: HealthKit entitlement and permission strings present; no app-code CareKit usage found.
- Static Sign in with Apple scan passed: no `TextField("Your name"` call site remains in app code.
- Static name/email onboarding scan passed: no `TextField("Your name"`, `TextField("Email"`, or `TextField("Your email"` call site remains in app code.
- Analytics call-site scan confirmed: onboarding funnel, plan generation, run completion, HealthKit disclosure, HealthKit connect intent, and HealthKit sync completion call sites exist.
- Whitespace validation passed again on 2026-06-09: `git diff --check`.
- Active-source guard passed: `git ls-files --others --exclude-standard -- 'IOS RunSmart app/*.swift' 'IOS RunSmart app/**/*.swift' 'IOS RunSmart appTests/*.swift' 'IOS RunSmart appTests/**/*.swift'` returned no untracked Swift source under the active app/test roots.
- Signing-disabled simulator build passed on iPhone 17 Pro Max on 2026-06-09:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Debug -destination "platform=iOS Simulator,id=66F09A08-D5EE-467D-936D-E1406E5FEE0E" -derivedDataPath /tmp/runsmart-build12-resubmission-derived CODE_SIGNING_ALLOWED=NO build`
- Signing-disabled simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Debug -destination "platform=iOS Simulator,id=66F09A08-D5EE-467D-936D-E1406E5FEE0E" -derivedDataPath /tmp/runsmart-app-review-recovery-derived CODE_SIGNING_ALLOWED=NO build`
- Signing-disabled simulator build passed again after the build 12 bump; build output included `PROJECT:IOS RunSmart app-12`.
- Local Release archive passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-build12-local-validation.xcarchive" archive`
- Local archive inspection confirmed version `1.0.1`, build `12`, bundle id `com.runsmart.lite`, HealthKit and Sign in with Apple entitlements, HealthKit usage strings, `ITSAppUsesNonExemptEncryption=false`, and dSYM present.
- Local archive was development-signed with `get-task-allow=true`, so it is not the App Store distribution artifact.
- Build 12 archive/export validation passed on 2026-06-09:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-build12-AppStore.xcarchive" archive`
- Build 12 non-upload App Store export passed on 2026-06-09:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-build12-AppStore.xcarchive" -exportPath "build/RunSmart-build12-AppStoreExport" -exportOptionsPlist ExportOptionsAppStore.plist -allowProvisioningUpdates`
- Exported IPA inspection passed: `build/RunSmart-build12-AppStoreExport/RunSmart.ipa` contains display name `RunSmart`, bundle id `com.runsmart.lite`, version `1.0.1`, build `12`, iPhone-only `UIDeviceFamily = (1)`, `ITSAppUsesNonExemptEncryption=false`, Apple Distribution signing, HealthKit entitlement, Sign in with Apple entitlement, associated domains entitlement, and `get-task-allow=false`.
- Raw archive app remains development-signed before export (`Apple Development`, `get-task-allow=true`), so use only the inspected exported IPA for upload.
- Reviewer-device simulator evidence captured at `/tmp/runsmart-build12-reviewer-evidence-20260609/`: iPhone 17 Pro Max and iPad Air 11-inch (M3) sign-in screenshots show HealthKit disclosure and Sign in with Apple; Profile screenshots show HealthKit in Connected services above the fold. Onboarding Privacy and HealthKit detail were verified by static source inspection, not full visual navigation, in this session.

### Apple Rejection
- Guideline: 4 - Design.
- Issue: app offers Sign in with Apple but asks users to provide name and/or email afterward.
- Resolution path: keep AuthenticationServices SIWA scopes; remove post-auth name/email collection; use Apple-provided values internally when available.
- Guideline: 2.5.1 - Performance - Software Requirements.
- Issue: app uses HealthKit or CareKit APIs but does not clearly identify the HealthKit and CareKit functionality in the UI.
- Resolution path: keep HealthKit in the binary because the app uses HealthKit; make HealthKit read/write functionality visible in app UI. CareKit is not used.
- Provenance note: current `main` had build 10 at commit `62823e2`; App Review rejected build 11, but no local build 11 archive was found. Build 12 is the next intended resubmission build.

### Remaining Risks
- App Store Connect upload/resubmission were not performed in this session.
- Fresh-account SIWA authentication was not completed manually, so the post-auth no-name/email-field behavior is source/build verified but not account-flow verified in this session.
- HealthKit detail and onboarding Privacy screenshots were not captured through simulator navigation in this session; their HealthKit wording was verified statically in source.
- PostHog Live Events verification still requires a real token/configured production build and should confirm `app_launched`, `healthkit_disclosure_viewed`, `healthkit_connect_tapped`, `plan_generated`, and activation funnel events.
- Preserve pre-existing dirty changes in `IOS RunSmart app/Resources/Localizable.xcstrings` and `tasks/lessons.md` intentionally.

---

## Previous Task

**Objective:** Monitor App Store review for build 8.
**Status:** Waiting for Review
**Branch:** version-2

### Checklist
- [x] version-2: all 9 redesign stories (A1–A6, B2–B4) complete
- [x] Build 8: onboarding scroll fix applied
- [x] Build 8: version bump (1.0.1 → 1.0, build 7 → 8)
- [x] Full test suite passed
- [x] Visual QA passed (iPhone 17 Pro, iPhone 17 Pro Max, iPad Air 11-inch)
- [x] Bug review passed (checks A, B, E, F, G automated; C, D manual)
- [x] Executive OS gate passed
- [x] Archived and uploaded to ASC
- [x] Replied to Apple rejection message
- [x] Submitted for review
- [ ] **MONITOR**: Apple review outcome (24–48h)
- [ ] After approval: merge version-2 → main, run ./agentic-os refresh, publish launch post

---

## Launch Readiness QA Tracker

### T1 — Physical Device GPS + Battery QA
- [x] **PASS — 2026-05-27** — 7.23 km outdoor run, 39:51, 1,135 GPS pts, no drift/spikes, Coach Analysis generated (Steady), run saved, post-run debrief rendered. Background tracking held full duration. No crashes. Battery healthy. See lessons.md 2026-05-27 entry.

---

## Current Task
1.0.1 version-2 continuation — COMPLETE

### Stories From 1.0.1 Spec
- [x] A1 — Today v2 and bottom safe area.
- [x] A2 — Report v2.
- [x] A3 — Plan explanation guard folded into Today/Plan surfaces.
- [x] A4 — Plan v2.
- [x] A5 — Profile v2.
- [x] A6 — Post-run bridge.
- [x] B2 — iOS `VoiceCoachService` consuming existing `/api/coach/voice-cue`.
- [x] B3 — Run tab voice cue wiring.
- [x] B4 — Live run mute/audio control wiring.

### This Continuation
- [x] Fetched `https://github.com/nadavyigal/IOS-runsmart-light-app-.git` and continued from `origin/version-2` on isolated branch `codex/1.0.1-version2-continue`.
- [x] Kept the frozen v1.0 review branch/artifacts untouched; no archive/upload/submit.
- [x] Modernized voice coach Bluetooth audio session option from deprecated `.allowBluetooth` to `.allowBluetoothHFP`.
- [x] Added DEBUG-only env fallback for screenshot mode and initial-tab selection to make simulator visual QA repeatable when launch arguments stall.
- [x] Ran simulator build, test-target build, and screenshot capture for Today/Plan/Run/Report/Profile.

### Validation
- `xcodebuild build` passed on generic iOS Simulator with signing disabled after the voice coach cleanup.
- `xcodebuild build-for-testing` passed on `iPhone 17 Pro` simulator with signing disabled.
- `xcodebuild test` built/installed but stalled after simulator launch and was terminated; no test pass was claimed.
- Simulator screenshots captured to `/tmp/runsmart-101-version2-screenshots-env/`.
- Visual inspection found real UI on all five tabs; Today still shows an existing right-edge clipped week card on this upstream branch.
- Branch evidence: `codex/1.0.1-version2-continue` from `origin/version-2`.

### Remaining Risks
- Physical-device voice cue/audio-session QA still required.
- Web `/api/coach/voice-cue` flag/contract was read from spec context but not live-verified here.
- Dedicated VoiceCoachService tests are still missing.
- `origin/claude/distracted-proskuriakova-f558f2` contains a separate security/spec cleanup that diverges from `origin/version-2`; not merged in this pass.
- `PROJECT-BRIDGES/runsmart-web.md` and `PROJECT-BRIDGES/runsmart-ios.md` were not present in the local workspace.

### Next
- B5 — Voice coach QA hardening: live endpoint/flag verification, physical-device audio playback/mute test, and a small service test seam if feasible.

---

## Previous Task
E7 — Garmin / Wearable Depth Implementation — COMPLETE

### Checklist
- [x] Draft `docs/specs/e7-garmin-wearable-depth.md` with scope, states, data contract, AC, and QA plan.
- [x] Add `WellnessTrendSeries` model + 7-day Garmin fetch + service API.
- [x] Implement Striver persona gating helper + focused tests.
- [x] Wire Today mini-stat HRV/recovery sparklines to real 7-day data + add Striver trend card.
- [x] Add full 7-day HRV/training-readiness charts to Garmin Wellness and live Recovery dashboard wiring.
- [x] Add preview fixtures, focused tests, Xcode build validation, and QA checklist updates.
- [x] Harden Striver empty states (no fake sparklines), route trend fetch through `GarminBridge.dailyMetrics` fallback, sparse-history test, accessibility labels.

### Validation (2026-05-28 follow-up)
- Generic simulator build passed (`build/DerivedData`).
- Focused tests: `StriverPersonaGateTests`, `WellnessTrendMapperTests` (4 tests incl. sparse history).

### Remaining Risks
- Manual QA on physical device with real Garmin 7-day sync still required.
- Striver gate is a v1 heuristic; may need tuning from TestFlight feedback.
- Optional analytics (`e7_trend_card_viewed`) deferred per spec.

### Scope Guard
- No plan adaptation algorithm changes.
- No medical diagnosis language.
- No App Store/TestFlight portal-side operations.

---

## Current Task
Physical device QA bugs after latest `main` merge — COMPLETE

### Bugs From Device Logs
- [x] Fixed Flex Week Edge Function `400` fallback by encoding request DTO keys as `workoutId` / `missedWorkoutId`.
- [x] Fixed Flex Week response fallback decoding for `workoutId`, `workoutID`, `workout_id`, and snake_case top-level response keys returned by deployed services.
- [x] Fixed Flex Week save failure by stopping workout updates from sending undeployed `adjusted_at` / `adjusted_reason` columns.
- [x] Fixed Flex Week workout save constraint failure by mapping app intensities to deployed DB values and storing rest-day intensity as `nil`.
- [x] Fixed Garmin/manual morning check-in save failure by clamping wellness scores and avoiding `soreness = 0`.
- [x] Fixed Garmin/manual morning check-in source constraint failure by storing deployed DB source values (`garmin` / `manual`).
- [x] Added Flex Week DTO tests for Edge Function key spelling and response compatibility decoding.

### Validation
- Swift parse validation passed for touched app/test files.
- Whitespace validation passed with `git diff --check`.
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-device-fixes-derived-data CODE_SIGNING_ALLOWED=NO build`
- Focused Flex Week test target build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/runsmart-device-fixes-derived-data -only-testing:"IOS RunSmart appTests/FlexWeekTests" CODE_SIGNING_ALLOWED=NO build-for-testing`
- Focused simulator `test` command built and installed, then stalled after install; interrupted and replaced with `build-for-testing`.

### Notes
- The repeated `nw_*`, PerfPowerTelemetry/Maps sandbox, `CAMetalLayer`, and scene snapshot messages are Apple framework/runtime noise, not the root cause of the screenshots.
- Remaining Swift concurrency warnings are pre-existing and should be handled in a separate cleanup pass.

---

## Current Task
PR #21 PostHog Analytics merge-conflict resolution — COMPLETE

### Conflict Resolution
- [x] Merged current `origin/main` into `feat/posthog-analytics` in isolated worktree `/tmp/runsmart-posthog-pr21`.
- [x] Resolved `RunSmartLiteAppShell.swift` to keep screenshot-mode launch guard, push-navigation setup, and the PR's single `Analytics.setup(projectToken:host:)` path.
- [x] Resolved `PlanTabView.swift` to keep Flex Week UI while preserving `plan_workout_tapped` analytics.
- [x] Resolved `RunTabView.swift` to keep the latest pre-run start flow while preserving `run_started` analytics with planned/free source.
- [x] Resolved `RunSmartReadinessTests.swift` to keep both PostHog null-service coverage and the latest readiness/Flex Week tests from main.

### Validation
- Whitespace validation passed: `git diff --check`.
- Conflict-marker scan passed across the repo source.
- Swift parse validation passed for the conflict files plus analytics service files.
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-posthog-pr21-derived-data CODE_SIGNING_ALLOWED=NO build`
- Build still reports existing warning noise in Flex Week/Supabase/HealthKit code; no build failure remains.

---

## Current Task
Story 8 + Story 9: Flex Week Analytics + Gentle Intervention — COMPLETE

### Story 8 Checklist
- [x] PostHog initialized in RunSmartLiteAppShell
- [x] RunSmartAnalytics.swift with flex_week_triggered/confirmed/cancelled/intervention_shown/intervention_action
- [x] FlexWeekFlowView tracks triggered/confirmed/cancelled with reason, source, changesCount, timeToConfirm, entryPoint
- [x] FlexWeekAdjustmentHistory persists records to UserDefaults (capped at 10)
- [x] adjustmentHistoryWithin protocol method + default extension
- [x] FlexWeekAnalyticsTests: 7/7 pass

### Story 9 Checklist
- [x] GentleCoachInterventionCard.swift with "Talk to Coach" + "Just adjust this week" CTAs
- [x] FlexWeekReasonPicker shows card when priorAdjustmentCount >= 2
- [x] Intervention dismissed locally without blocking the reason picker
- [x] intervention_shown + intervention_action events firing
- [x] onTalkToCoach wired: dismisses flex week sheet, opens Coach after animation

### Validation
- Generic simulator build: PASS
- FlexWeekAnalyticsTests: 7/7 passed
- flex_week edge function: deployed to production (smoke 401 confirmed)
- Merge readiness review 2026-05-27:
  - PR #34 is open, mergeable, not draft, targeting `main`.
  - Story 8/9 code review found and fixed the missing `cancelled` intervention action and routed recent-history lookup through `adjustmentHistoryWithin`.
  - Whitespace validation passed: `git diff --check`.
  - Swift parse validation passed for touched Story 8/9 files.
  - Generic simulator build passed with `/tmp/runsmart-e5-story8-9-derived-data`.
  - Focused `FlexWeekAnalyticsTests` built and executed all 7 tests successfully; xcodebuild then stalled while finalizing the test log and was interrupted, returning 75.

### Next
- App Store Connect portal tasks (human-only — select build, screenshots, credentials, privacy)
- Remaining device QA: explicit battery % before/after, background re-entry test

### Previous Task
E5 Adaptive Flex Week — Stories 2 + 3: `flex_week` edge function + `flexCurrentWeek` iOS service wiring.

### Previous Task
Implement the App Store readiness closeout plan before the next archive: add deterministic screenshot mode, generate complete iPhone screenshot sets, document App Store Connect portal values, and run pre-archive validation while preserving existing dirty release work.

### Checklist
- [x] Read canonical lessons before planning and editing.
- [x] Confirm the app repo has existing dirty changes and preserve unrelated work.
- [x] Add DEBUG-only screenshot launch mode with safe sample data.
- [x] Add screenshot capture tooling and Fastlane wiring.
- [x] Generate 6.9-inch and 6.1-inch App Store screenshot sets.
- [x] Add App Store Connect portal checklist values.
- [x] Run static, build, focused test, screenshot, and preflight validation.
- [x] Record validation and remaining portal-only blockers.

### Validation
- Whitespace validation passed:
  `git diff --check`
- Screenshot script syntax passed:
  `bash -n fastlane/scripts/capture-app-store-screenshots.sh`
- No untracked Swift files were found under the app or test targets:
  `git ls-files --others --exclude-standard "IOS RunSmart app/**/*.swift" "IOS RunSmart appTests/**/*.swift"`
- Screenshot capture passed for both required display classes:
  `bash fastlane/scripts/capture-app-store-screenshots.sh`
- Screenshot dimensions passed with `sips`:
  - `iPhone_17_Pro_Max_01_today.png` through `iPhone_17_Pro_Max_05_profile.png`: `1320 x 2868`
  - `iPhone_17e_01_today.png` through `iPhone_17e_05_profile.png`: `1170 x 2532`
- Visual screenshot inspection passed after regenerating the blank early 17e Report capture with a longer settle delay.
- Focused readiness tests passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/runsmart-appstore-closeout-derived-data -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests" CODE_SIGNING_ALLOWED=NO test`
- Built app metadata inspection confirmed bundle id `com.runsmart.lite`, display name `RunSmart`, version `1.0`, build `5`, encryption export flag `false`, HealthKit/location permission strings, release URLs, and iPhone-only device family.
- Build/test still report existing warning noise in `BenchmarkRouteAnalyticsService`, `HealthKitSyncService`, and AppIntents metadata extraction; no closeout failure was introduced.

### Remaining Portal-Only Blockers
- Select the processed build only after the newly uploaded archive finishes processing in App Store Connect.
- Confirm App Store Connect privacy questionnaire, category, age rating, screenshot uploads, reviewer notes, and demo credentials in the portal.
- Enter demo credentials only in App Store Connect; do not store them in repo files.

### Scope Guard
- Do not store demo credentials, Apple credentials, API keys, or personal device details.
- Do not change Release/App Store production auth, onboarding, Supabase, HealthKit, Garmin, or location behavior.
- Do not overwrite unrelated dirty files.

### Previous Task
Continue the SwiftUI UI Patterns skill across the remaining RunSmart root tabs after the Today tab optimization. Preserve behavior and existing dirty release work while applying the same scroll, derived-state, and action-organization patterns to Plan, Run, Report, and Profile.

### Checklist
- [x] Read canonical lessons before planning and editing.
- [x] Confirm the app repo has existing dirty changes and preserve unrelated work.
- [x] Reload the Build iOS Apps SwiftUI UI Patterns skill.
- [x] Identify the remaining top-level tabs from the app shell.
- [x] Refactor Plan, Run, Report, and Profile tabs using local SwiftUI-native patterns.
- [x] Run focused static validation and an app build.
- [x] Record validation and follow-up notes.

### Validation
- Swift parse validation passed:
  `xcrun swiftc -parse "IOS RunSmart app/Features/Plan/PlanTabView.swift" "IOS RunSmart app/Features/Activity/ActivityTabView.swift" "IOS RunSmart app/Features/Profile/ProfileTabView.swift" "IOS RunSmart app/Features/Run/RunTabView.swift"`
- Whitespace validation passed:
  `git diff --check -- "IOS RunSmart app/Features/Plan/PlanTabView.swift" "IOS RunSmart app/Features/Activity/ActivityTabView.swift" "IOS RunSmart app/Features/Profile/ProfileTabView.swift" "IOS RunSmart app/Features/Run/RunTabView.swift" tasks/todo.md tasks/session-log.md`
- XcodeBuildMCP simulator build passed with the configured project, scheme, iPhone 17 simulator, and DerivedData outside synced storage:
  `build_sim CODE_SIGNING_ALLOWED=NO`
- Build log:
  `/Users/nadavyigal/Library/Developer/XcodeBuildMCP/workspaces/IOS-RunSmart-light-18e0783284c4/logs/build_sim_2026-05-24T08-57-57-262Z_pid15676_19753b02.log`

### Scope Guard
- Do not redesign screens.
- Do not change RunSmart product logic.
- Do not touch unrelated dirty files.

### Previous Task
Run the SwiftUI UI Patterns skill on the RunSmart iOS app with a focused optimization pass on the Today tab. Preserve behavior and existing dirty release work while improving scroll structure, derived state usage, and action organization.

### Checklist
- [x] Read canonical lessons before planning and editing.
- [x] Confirm the app repo has existing dirty changes and preserve unrelated work.
- [x] Load the Build iOS Apps SwiftUI UI Patterns skill.
- [x] Read relevant ScrollView, async state, and performance references.
- [x] Refactor `TodayTabView.swift` using local SwiftUI-native patterns without changing product behavior.
- [x] Run focused static validation and an app build.
- [x] Record validation and follow-up notes.

### Validation
- Swift parse validation passed:
  `xcrun swiftc -parse "IOS RunSmart app/Features/Today/TodayTabView.swift"`
- Whitespace validation passed:
  `git diff --check -- "IOS RunSmart app/Features/Today/TodayTabView.swift" tasks/todo.md`
- Generic simulator build passed with DerivedData outside synced storage:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-swiftui-ui-patterns-derived-data CODE_SIGNING_ALLOWED=NO build`
- XcodeBuildMCP simulator build was attempted first but timed out at 120 seconds while the underlying `xcodebuild` process continued; the direct incremental build above completed successfully.
- Build still reports pre-existing warning noise in AppIntents metadata extraction and the always-run metadata stripping script; no `TodayTabView.swift` compile error was introduced.

### Scope Guard
- Do not redesign screens.
- Do not change RunSmart product logic.
- Do not touch unrelated dirty files.

### Previous Task
Run the SwiftUI View Refactor skill on the RunSmart iOS app with a focused pass on the largest secondary-flow SwiftUI surface. Preserve behavior and existing dirty release work while improving view ordering, destination composition, and inline action structure.

### Checklist
- [x] Read canonical lessons before planning and editing.
- [x] Confirm the app repo has existing dirty changes and preserve unrelated work.
- [x] Load the Build iOS Apps SwiftUI View Refactor skill.
- [x] Refactor `SecondaryFlowView.swift` using dedicated view types and named actions without changing product behavior.
- [x] Run focused static validation.
- [x] Record validation and follow-up notes.

### Validation
- Swift parse validation passed:
  `xcrun swiftc -parse "IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift"`
- Whitespace validation passed:
  `git diff --check -- "IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift" tasks/todo.md`
- Generic simulator build passed with DerivedData outside synced storage:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-swiftui-refactor-derived-data CODE_SIGNING_ALLOWED=NO build`
- XcodeBuildMCP simulator build was attempted first but timed out at 120 seconds while the underlying `xcodebuild` process continued; the direct incremental build above completed successfully.
- Build still reports pre-existing warning noise in HealthKit, RunSmartAPIModels, BenchmarkRouteAnalyticsService, and AppIntents metadata extraction; no `SecondaryFlowView.swift` compile error was introduced.

### Scope Guard
- Do not redesign screens.
- Do not change RunSmart product logic.
- Do not touch unrelated dirty files.

### Previous Task
RunSmart iOS TestFlight readiness audit implementation is complete for the local safe scope: route surface filtering, release URLs, sign-in legal links, HealthKit warning cleanup, build validation, simulator launch smoke, and QA documentation are done. Final TestFlight submission remains blocked on release-owner authenticated QA, physical-device QA, App Store Connect portal tasks, and a clean simulator XCTest execution pass.

## RunSmart iOS TestFlight Readiness Audit - 2026-05-23

As the release owner, I want the TestFlight readiness audit plan implemented with local fixes, build/smoke validation, and a clear go/no-go record so remaining release blockers are explicit.

### Expected Files
- `IOS RunSmart app/Services/RouteSuggestionRanker.swift`
- `IOS RunSmart app/Features/Routes/RouteCreatorView.swift`
- `IOS RunSmart appTests/RouteRankingTests.swift`
- `IOS RunSmart app/Services/Supabase/AppLinks.swift`
- `IOS RunSmart app/Features/Auth/SignInView.swift`
- `IOS RunSmart app/Services/HealthKit/HealthKitSyncService.swift`
- `docs/qa/testflight-readiness-audit-2026-05-23.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Read canonical lessons before planning and editing.
- [x] Confirm the app repo has existing dirty changes and preserve unrelated work.
- [x] Review the route discovery surface controls and implement the missing ranking behavior.
- [x] Add focused route ranking coverage for Road and Trail preferences.
- [x] Replace placeholder support, marketing, privacy, and account deletion URLs with live RunSmart URLs.
- [x] Add a live Terms URL.
- [x] Make sign-in Terms and Privacy copy tappable.
- [x] Remove low-risk HealthKit optional-type warning noise.
- [x] Run local static validation.
- [x] Run generic simulator build-for-testing.
- [x] Install and launch the app on an iPhone simulator.
- [x] Verify public release URLs respond.
- [x] Record blocked authenticated, physical-device, and App Store Connect checks.

### Validation
- Swift parse validation passed for route ranking implementation and tests:
  `xcrun swiftc -parse "IOS RunSmart app/Services/RouteSuggestionRanker.swift" "IOS RunSmart appTests/RouteRankingTests.swift"`
- Whitespace validation passed for route-ranking files:
  `git diff --check -- "IOS RunSmart app/Services/RouteSuggestionRanker.swift" "IOS RunSmart app/Features/Routes/RouteCreatorView.swift" "IOS RunSmart appTests/RouteRankingTests.swift"`
- Generic simulator build-for-testing passed with DerivedData outside synced storage:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-audit-derived-data build-for-testing`
- Focused `RouteRankingTests` simulator execution with `test-without-building` stalled during simulator launch/test execution and was stopped. This is blocked, not passed.
- iPhone 17 Pro simulator install and launch passed for bundle id `com.runsmart.lite`.
- Launch smoke reached the RunSmart sign-in screen with Sign in with Apple visible.
- Public RunSmart marketing, support, privacy, terms, and account deletion URLs responded successfully.

### Scope Guard
- No secrets or demo credentials were committed.
- No App Store Connect portal claims were made without portal access.
- No physical-device GPS/background/HealthKit claims were made without device QA.
- Route surface ranking is conservative because current `RouteSuggestion` data has no persisted surface field.

### Next Recommended Action
Run a clean focused XCTest pass from a healthy simulator, then perform authenticated manual QA and physical-device GPS/background/HealthKit validation before App Store Connect submission.

## Sprint 10 TestFlight Closeout - 2026-05-20

As the release owner, I want local validation, authenticated QA, and App Store Connect closeout tracked in one place so RunSmart can move to TestFlight with a clean go/no-go.

### Expected Files
- `IOS RunSmart app.xcodeproj/project.pbxproj`
- `docs/specs/sprint-10-testflight-closeout.md`
- `docs/qa/sprint-10-testflight-closeout-report.md`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md` if a new failure or correction creates a reusable rule.

### Checklist
- [x] Read canonical app lessons before planning or editing.
- [x] Confirm app repo status and avoid unrelated untracked task files.
- [x] Create Sprint 10 spec/story artifact.
- [x] Inspect source tree for disallowed resource/Finder/FileProvider metadata.
- [x] Add app-target metadata stripping before code signing.
- [x] Run generic simulator build with `/tmp/runsmart-derived-data`.
- [x] Run generic simulator build-for-testing with `/tmp/runsmart-derived-data`.
- [x] Run focused `RunSmartReadinessTests` with `/tmp/runsmart-derived-data`.
- [x] Verify/fix only release-blocking Sprint 9 Today/post-run/Supabase regressions exposed by tests or smoke.
- [x] Document demo credential handling without committing credentials.
- [x] Record simulator signed-in Today smoke result or blocker.
- [x] Record physical-device Today smoke result or blocker.
- [x] Record Sprint 9 real-activity QA result or bug filings.
- [x] Record App Store Connect build/screenshots/demo credentials/privacy/category/age-rating status.
- [x] Re-run authenticated Coach smoke or record blocker.
- [x] Write final go/no-go report.

### Scope Guard
- No new AI behavior.
- No route, onboarding, or screen redesign work.
- No credentials committed to git or task memory.
- No manual App Store Connect claims without portal evidence.

### Validation
- Generic simulator build passed with DerivedData outside synced storage:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-derived-data build`
- Generic simulator build-for-testing passed with the same DerivedData path:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/runsmart-derived-data build-for-testing`
- Focused readiness tests passed on iPhone 17 Pro:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/runsmart-derived-data -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests" test`
- Codesign verification passed:
  `codesign --verify --deep --strict --verbose=2 "/tmp/runsmart-derived-data/Build/Products/Debug-iphonesimulator/IOS RunSmart app.app"`
- Demo credentials, authenticated Today smoke, physical-device Today smoke, App Store Connect portal checks, and authenticated Coach smoke are documented as release-owner blockers in `docs/qa/sprint-10-testflight-closeout-report.md`.

### Previous Task
AI Coach Story 5 validation is complete on the merged `origin/main` base after PR #18 and PR #19: docs/static checks pass, Swift parse passes, Xcode project listing passes, generic simulator build passes, and generic simulator build-for-testing passes. Focused readiness XCTest execution built successfully but stalled during simulator launch/test execution and should be retried from a healthy simulator before readiness UI wiring. App Store portal follow-ups remain: wait for build processing, select build 5, add screenshots, enter demo credentials, confirm privacy questionnaire/age rating/category, and re-run authenticated Coach smoke before final submit-for-review.

## AI Skills And Shared Contracts Import Investigation - 2026-05-19

As the iOS maintainer, I want a narrow investigation of the original RunSmart web/PWA AI coaching skills and shared contracts so the native app can reuse guardrails and DTO ideas without importing web-era operating files, task boards, or broad model layers.

### Expected Files
- `docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Read canonical app lessons before planning or editing.
- [x] Confirm the app repo worktree is dirty and avoid overwriting existing user changes.
- [x] Inspect only the requested source AI skill and shared contract areas.
- [x] Map each AI skill to iOS screens, flows, service callers, inputs, outputs, and safety guardrails.
- [x] Compare source `packages/shared/src/models/` and `packages/shared/src/api/` with current iOS models and DTOs.
- [x] Assess whether source TypeScript contracts should be copied, generated, manually mirrored, or documented.
- [x] Produce a concrete five-story implementation plan using the local Agent OS style.
- [x] Implement the first safe slice as docs only.
- [x] Preserve the coaching safety guardrails in the plan: no medical diagnosis, conservative uncertainty handling, stop/rest/professional guidance for pain/dizziness/injury signals, and `SafetyFlag` equivalents.

### Validation
- Documentation/path validation passed:
  `test -f docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md`
- Source scope validation passed: no source Agent OS files, workflows, root instructions, or task-board files were copied.
- Xcode availability check passed:
  `xcodebuild -version`
- Xcode project listing was attempted with `xcodebuild -project "IOS RunSmart app.xcodeproj" -list`, but it did not return past the invocation line within the observed window and was stopped.
- Swift behavior validation was not run for this slice because no Swift files or app behavior changed.

### Scope Guard
- No iOS models were overwritten.
- No `.codex`, `.cursor`, or `.claude` skill directories were copied into the app repo.
- No shared TypeScript model files were vendored.
- No generated Swift was added.
- No secrets or local env files were read into tracked docs.

### Next Recommended Story
Create an iOS-native AI coach skill contract doc that defines structured `SafetyFlag`, readiness, workout explainer, post-run debrief, and plan/load guard payloads using current iOS service and Supabase Edge Function boundaries.

## AI Coach Skill Contracts Story 3 - 2026-05-19

As the RunSmart iOS maintainer, I want iOS-native AI Coach skill contract docs so future Coach implementation can preserve web/PWA safety guardrails without importing web-era skill folders or path assumptions.

### Expected Files
- `docs/ai-coach/skill-contracts.md`
- `docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Plan Story 3 before implementation.
- [x] Add an iOS-native `docs/ai-coach/skill-contracts.md`.
- [x] Define structured `SafetyFlag` and common decision/confidence values.
- [x] Include per-skill request/response sketches for readiness, workout explainer, post-run debrief, plan generation metadata, load anomaly guard, conversational goal discovery, route builder, and adherence.
- [x] Reference current iOS screens, service protocols, DTO namespace, and Supabase Edge Function boundary instead of source web `v0` paths.
- [x] Keep `.codex`, `.cursor`, `.claude`, generated Swift, TypeScript model vendoring, and behavior changes out of scope.
- [x] Update Story 3 status in the investigation report.
- [x] Create PR after validation.

### Validation
- Contract doc path/content validation passed:
  `test -f docs/ai-coach/skill-contracts.md && rg -n "SafetyFlagDTO|ReadinessCheckRequestDTO|WorkoutExplainerRequestDTO|PostRunDebriefRequestDTO|LoadAnomalyGuardRequestDTO|GoalDiscoveryRequestDTO|RouteBuilderRequestDTO|AdherenceCoachRequestDTO|Supabase|PreRunView|RunSmartDTO" docs/ai-coach/skill-contracts.md`
- Source import guard passed:
  `test ! -d .codex && test ! -d .cursor && test ! -d .claude && test ! -f AGENTS.md && test ! -f CLAUDE.md && test ! -f CODEX.md && test ! -d docs/ai-skills`
- Whitespace validation passed for tracked edited files:
  `git diff --check -- docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md tasks/todo.md tasks/session-log.md`
- Xcode availability check passed:
  `xcodebuild -version`
- Swift build/test validation was not run because Story 3 changed only docs/task files.
- Draft PR created: https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/19

### Scope Guard
- No Swift files changed.
- No app behavior changed.
- No secrets or env files changed.
- Existing unrelated deleted docs remain untouched.

### Next Recommended Story
Story 4: add a manually mirrored `SafetyFlagDTO` plus readiness request/response DTOs with fixture-based Codable tests. Do not wire Pre-run UI behavior until the payloads pass tests and the service boundary is approved.

## AI Coach Readiness DTOs Story 4 - 2026-05-19

As the RunSmart iOS developer, I want minimal safety/readiness DTOs and fixture tests so future readiness features have type-safe payloads without importing the full web model layer.

### Expected Files
- `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `docs/ai-coach/skill-contracts.md`
- `docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Plan Story 4 before implementation.
- [x] Add focused Codable tests for proceed, modify-with-missing-data, skip-with-medical-caution, and request privacy.
- [x] Add manual `RunSmartDTO.SafetyFlagDTO`.
- [x] Add manual `RunSmartDTO.ReadinessCheckRequestDTO` and `RunSmartDTO.ReadinessCheckResponseDTO`.
- [x] Add only small readiness context DTOs needed by the request payload.
- [x] Leave existing iOS domain models intact.
- [x] Leave current live Coach `safetyFlags: [String]?` behavior unchanged.
- [x] Avoid Pre-run UI behavior wiring and backend endpoint wiring.
- [x] Amend PR #19 after validation.

### Validation
- Swift parse validation passed:
  `xcrun swiftc -parse "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift" "IOS RunSmart appTests/RunSmartReadinessTests.swift"`
- Whitespace validation passed:
  `git diff --check -- "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift" "IOS RunSmart appTests/RunSmartReadinessTests.swift" docs/ai-coach/skill-contracts.md docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md tasks/todo.md tasks/session-log.md`
- Static symbol check passed:
  `rg -n "SafetyFlagDTO|ReadinessCheckRequestDTO|ReadinessCheckResponseDTO|CoachDecisionDTO|CoachConfidenceDTO|testReadinessCheck" "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift" "IOS RunSmart appTests/RunSmartReadinessTests.swift"`
- Focused red-state command was attempted before DTO implementation, but `xcodebuild ... build-for-testing` stalled after the invocation line and was stopped.
- Generic build-for-testing was attempted after implementation, but `xcodebuild ... build-for-testing` again stalled after the invocation line and was stopped.
- Draft PR #19 amended with Story 4 code/tests and updated title/body: https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/19

### Scope Guard
- No Pre-run UI behavior changed.
- No backend endpoint added.
- No generated Swift or TypeScript model vendoring added.
- No secrets or env files changed.
- Existing unrelated deleted docs remain untouched.

### Next Recommended Story
Story 5: complete validation and QA when Xcode build infrastructure is responsive, then design the readiness service/backend boundary before any UI gating.

## AI Coach Validation And QA Story 5 - 2026-05-19

As the release owner, I want validation evidence for every AI skill/shared contract import slice so TestFlight readiness is not weakened by AI contract work.

### Expected Files
- `docs/qa/ai-coach-story-5-validation-2026-05-19.md`
- `docs/ai-skills-shared-contracts-import-investigation-2026-05-19.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Confirm PR #18 and PR #19 are merged into `origin/main`.
- [x] Create a clean Story 5 branch from `origin/main`.
- [x] Run docs/path/content validation for Story 1-3 artifacts.
- [x] Run source import guards for `.codex`, `.cursor`, `.claude`, root instruction files, and source docs.
- [x] Run static symbol and Swift parse validation for Story 4 DTOs/tests.
- [x] Run Xcode project listing.
- [x] Run generic simulator build-for-testing.
- [x] Run generic simulator build.
- [x] Attempt focused readiness XCTest execution on iPhone 17 simulator.
- [x] Record passed, blocked, and intentionally skipped checks.
- [x] Leave app behavior, backend wiring, secrets, and generated DTO import out of scope.

### Validation
- Merged branch check passed:
  `git log --oneline --decorate -6`
- Xcode project listing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -list`
- Story 3 docs/content check passed:
  `test -f docs/ai-coach/skill-contracts.md`
  plus targeted `rg` for skill contract symbols and iOS boundaries.
- Source import guard passed:
  `test ! -d .codex && test ! -d .cursor && test ! -d .claude && test ! -f AGENTS.md && test ! -f CLAUDE.md && test ! -f CODEX.md && test ! -d docs/ai-skills`
- Story 4 static symbol check passed:
  `rg -n "SafetyFlagDTO|ReadinessCheckRequestDTO|ReadinessCheckResponseDTO|CoachDecisionDTO|CoachConfidenceDTO" "IOS RunSmart app" "IOS RunSmart appTests"`
- Swift parse validation passed:
  `xcrun swiftc -parse "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift" "IOS RunSmart appTests/RunSmartReadinessTests.swift"`
- Xcode build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath build/DerivedData-Story5 build-for-testing`
- Xcode generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" -derivedDataPath build/DerivedData-Story5 build`
- Focused readiness XCTest execution was attempted:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath build/DerivedData-Story5 -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests" test`
  The app and test bundle built, then the run produced no output during simulator launch/test execution for roughly 90 seconds. It was stopped and ended with `** BUILD INTERRUPTED **`.

### Scope Guard
- No Swift app behavior changed.
- No Pre-run UI gating added.
- No backend readiness endpoint added.
- No generated Swift or TypeScript model vendoring added.
- No source Agent OS directories or task-board files imported.
- No secrets or env files changed.

### Next Recommended Story
Plan the readiness service/backend boundary before any Pre-run UI behavior change. Decide whether readiness should use a new Supabase Edge Function intent, a dedicated iOS service protocol, or an extension of the existing Coach service while preserving structured `SafetyFlagDTO` output.

## App Store Readiness Pass - 2026-05-19

As the release owner, I want a clear App Store readiness assessment so RunSmart can reach TestFlight/App Store without hidden signing, privacy, archive, or legacy-code surprises.

### Expected Files
- `RunSmartInfo.plist`
- `IOS RunSmart app/Features/Secondary/DIAGNOSTIC_REPORT.md`
- `docs/qa/app-store-readiness-report-2026-05-19.md`
- `docs/qa/app-review-notes-2026-05-19.md`
- `ExportOptionsAppStore.plist`
- `ExportOptionsAppStoreUpload.plist`
- `fastlane/metadata/en-US/*.txt`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Checklist
- [x] Read Agent OS lessons and release/QA checklists.
- [x] Inspect bundle id, version/build, entitlements, permissions, privacy manifest, and Fastlane lanes.
- [x] Verify public marketing/support/legal URLs respond successfully.
- [x] Verify deployed Coach endpoint rejects unauthenticated requests instead of exposing data.
- [x] Run generic simulator build.
- [x] Run generic simulator build-for-testing.
- [x] Run release archive.
- [x] Fix archived app display name from project name to `RunSmart`.
- [x] Add non-exempt encryption declaration for App Store Connect.
- [x] Remove bundled diagnostic markdown from the app archive.
- [x] Re-run build/build-for-testing/archive after release metadata cleanup.
- [x] Inspect archive Info.plist, entitlements, dSYM, and bundled diagnostic files.
- [x] Document readiness status and blockers.
- [x] Remove untracked ResumeBuilder/ATS/Tailor/V2/paywall files from the folder-synced app tree.
- [x] Remove stale ResumeBuilder/ATS/Tailor/PDF/credits strings from shipped string catalog.
- [x] Resolve AppIcon unassigned-child warning by removing stray unreferenced icon PNGs.
- [x] Produce an App Store distribution-signed IPA export.
- [x] Confirm exported IPA entitlements use distribution signing with `get-task-allow = false`.
- [x] Upload build 5 to App Store Connect.
- [x] Add Fastlane App Store metadata files.
- [x] Add App Review notes without storing credentials.
- [x] Record release-owner physical GPS/battery QA evidence.
- [ ] Wait for uploaded build processing to complete in App Store Connect and select build 5.
- [ ] Add App Store screenshots.
- [ ] Enter demo credentials directly in App Store Connect.
- [ ] Confirm App Store Connect privacy questionnaire and age rating/category.
- [ ] Re-run authenticated Coach smoke before final submit-for-review.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Release archive passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-AppStoreReady-2026-05-19-v2.xcarchive" archive`
- Clean release archive passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -configuration Release -destination "generic/platform=iOS" -archivePath "build/RunSmart-AppStoreReady-2026-05-19-clean.xcarchive" archive`
- App Store Connect IPA export passed:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-AppStoreReady-2026-05-19-clean.xcarchive" -exportPath "build/AppStoreExportClean" -exportOptionsPlist ExportOptionsAppStore.plist -allowProvisioningUpdates`
- App Store Connect upload passed:
  `xcodebuild -exportArchive -archivePath "build/RunSmart-AppStoreReady-2026-05-19-clean.xcarchive" -exportPath "build/AppStoreUploadClean" -exportOptionsPlist ExportOptionsAppStoreUpload.plist -allowProvisioningUpdates`
- Archive Info.plist now shows display name `RunSmart`, bundle id `com.runsmart.lite`, version `1.0`, build `5`, and `ITSAppUsesNonExemptEncryption = false`.
- Archive contains a dSYM and no `DIAGNOSTIC_REPORT.md`.
- Exported IPA has `get-task-allow = false`, active beta reports, distribution signing, and symbols included.
- Upload log reports the uploaded package is processing and upload succeeded.
- Exported IPA and localized resources contain no diagnostic, ResumeBuilder, ATS, Tailor, jobs, credits, or PDF legacy content.
- No untracked source files remain inside `IOS RunSmart app/`.
- Public root, privacy, support, and terms URLs return HTTP 200 after redirect to the canonical host.
- Deployed `coach_message` endpoint returns HTTP 401 without auth, which confirms it is deployed and not anonymously callable.
- Metadata text lengths are within checked App Store limits.
- `plutil -lint` passed for `ExportOptionsAppStore.plist`, `RunSmartInfo.plist`, `PrivacyInfo.xcprivacy`, and exported distribution plists.
- Release-owner evidence: outdoor GPS run recorded successfully with acceptable battery use; exact battery percentages are not stored in repo memory.

### Scope Guard
- No screen redesign, product logic rewrite, backend schema migration, or App Store Connect submission was performed in this readiness pass.

### Previous Task
Sprint 8 complete: Live AI Coach Backend Endpoint + iOS Coach Integration is implemented, deployed to Supabase, remotely smoke-tested with live AI, and build-validated. Manual in-app QA on a signed-in simulator/device remains before beta sign-off.

## Sprint 8 - Live AI Coach Backend Endpoint - 2026-05-18

As a signed-in runner, I want Coach chat to use a real authenticated backend AI endpoint while preserving deterministic fallback and existing persisted history.

### Expected Files
- `supabase/functions/coach_message/index.ts`
- `supabase/config.toml`
- `supabase/migrations/20260518130000_live_ai_coach_endpoint.sql`
- `supabase/migrations/20260518133000_tighten_coach_rls_policies.sql`
- `supabase/migrations/20260518140000_conversation_messages_auth_user_id.sql`
- `supabase/migrations/20260518145000_coach_messages_rpc.sql`
- `supabase/migrations/20260518150000_drop_unused_coach_messages_view.sql`
- `supabase/migrations/20260518151000_harden_coach_messages_rpc_grants.sql`
- `scripts/deploy-coach-message.sh`
- `docs/specs/live-ai-coach-endpoint.md`
- `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift`
- `IOS RunSmart app/Services/Live/LiveRunSmartServices.swift`
- `IOS RunSmart app/Services/Supabase/RunSmartSupabaseClient.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md` if reusable lessons are learned

### Checklist
- [x] Create Supabase Edge Function `coach_message`.
- [x] Add migration for `conversations.auth_user_id`, message idempotency/source fields, indexes, and RLS policies.
- [x] Add iOS request/response DTOs for live Coach.
- [x] Encode sanitized `TrainingContextSnapshot` without raw coordinates.
- [x] Call Supabase Edge Function from iOS when authenticated.
- [x] Keep deterministic local fallback and fallback persistence.
- [x] Avoid duplicate live/fallback message rows using `client_message_id`.
- [x] Add focused DTO/client/fallback tests.
- [x] Run backend syntax check.
- [x] Apply remote Supabase schema migration.
- [x] Tighten existing broad Coach RLS policies to owner-scoped access.
- [x] Add a one-command deploy script that reads ignored `local.env` and deploys with Supabase CLI `--use-api`.
- [x] Deploy Edge Function using `SUPABASE_ACCESS_TOKEN`.
- [x] Run authenticated remote smoke test against deployed `coach_message`.
- [x] Verify Coach history reload path returns persisted user + assistant messages without direct table-read duplication.
- [x] Run Xcode build.
- [x] Run Xcode build-for-testing.
- [x] Document validation results and deployment steps.

### Scope Guard
- No direct OpenAI call from iOS, no exposed `OPENAI_API_KEY`, no raw GPS coordinates sent to AI, no live in-run AI claim, no automatic plan mutation, no Coach UI redesign, and no social/notifications/route-marketplace work.

### Validation
- `npx -y deno check supabase/functions/coach_message/index.ts` passed.
- Supabase MCP migration `live_ai_coach_endpoint` applied successfully.
- Supabase MCP migration `tighten_coach_rls_policies` applied successfully; post-check shows owner-scoped authenticated policies plus service-role access.
- OpenAI Responses API key smoke test returned HTTP 200 with text from configured model `gpt-4.1-mini`.
- Local Edge Function smoke test started on Deno and returned JSON `401` for a POST missing a bearer token.
- `scripts/deploy-coach-message.sh` linked project `dxqglotcyirxzyqaxqln`, set Coach OpenAI secrets, and deployed `coach_message`.
- Deployed Edge Function remote smoke test returned HTTP 200 with `source = live_ai` and `fallback = false`.
- Supabase SQL verification confirmed two persisted rows for the smoke conversation: user source `client` and assistant source `live_ai`, both owned by the authenticated user.
- Coach history RPC smoke test returned 2 rows for the signed-in user; anonymous execute is revoked and authenticated execute remains enabled.
- Smoke-test users/conversations/messages were cleaned up after validation.
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed and compiled the new live Coach DTO/client/fallback tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Focused Coach XCTest attempt compiled the app/test bundle, then failed during simulator install with CoreSimulator 405 / NSMach -308; per existing lesson this is recorded as simulator infrastructure failure, not a Coach compile failure.
- Supabase Edge Function logs show recent deployed `POST /functions/v1/coach_message` requests returning HTTP 200.
- Supabase advisors still report broader pre-existing project warnings, plus the intentional signed-in security-definer Coach history RPC warning; anon execution for that RPC is revoked and the SQL body filters by `auth.uid()`.
- Manual signed-in app QA remains required before beta sign-off: send Coach from Today, close/reopen thread, break backend and verify iOS fallback, ask from Report, confirm no duplicate rows, and inspect stored metadata for no raw coordinates.

### Previous Task
Sprint 7 implemented: Real Run Completion State Fix. Physical-device QA remains pending.

## Sprint 7 - Real Run Completion State Fix - 2026-05-18

As a beta runner, I want a real RunSmart GPS run to save once, exit cleanly, appear everywhere, and complete the planned workout when it matches.

### Expected Files
- `docs/specs/sprint-7-real-run-completion-state-fix.md`
- `IOS RunSmart app/Features/Run/RunTabView.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Run/PostRunLearningCard.swift`
- `IOS RunSmart app/Features/Activity/ActivityTabView.swift`
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Plan/PlanTabView.swift`
- `IOS RunSmart app/Features/Profile/ProfileTabView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Supabase/TrainingPlanRepository.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Create Sprint 7 spec artifact.
- [x] Clear Run tab finished-run state after Keep Activity / Done or Delete.
- [x] Prevent stale router post-run summaries from showing "Run not saved" after valid saves.
- [x] Persist completed RunSmart GPS runs through the canonical activity/report path.
- [x] Refresh Today, Plan, Report, and Profile after completed-run processing.
- [x] Mark matching same-day planned workouts complete.
- [x] Make Today ignore completed same-day workouts when selecting the next recommendation.
- [x] Resolve report detail from cached/generated reports instead of skeleton-only activity rows.
- [x] Remove user-facing Xcode-console copy from suggested-workout failures.
- [x] Add focused regression coverage.
- [x] App builds successfully.

### Scope Guard
- No live AI backend, route marketplace, new notification features, share-card changes, or marketing-copy changes beyond safe error copy.

### Validation
- Generic simulator build-for-testing passed and compiled the new Sprint 7 regression tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Static copy scan found no remaining user-visible "Xcode console", "Check the console", or debug save-suggested-workout copy.
- Manual QA remains required on a physical iPhone: real GPS run, Keep Activity / Done exit, Report/Profile agreement, Today/Plan completion state, Garmin duplicate handling, and suggested-next-run save.

## Sprint 6B - Return Loop + Share Cards + TestFlight Readiness - 2026-05-17

As a beta runner, I want calm return reminders, private progress sharing, and honest beta copy so RunSmart is safer to expand through TestFlight.

### Expected Files
- `IOS RunSmart app/Core/Push/PushService.swift`
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Routes/BenchmarkComparisonCard.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart app/Features/Profile/ProfileTabView.swift`
- `IOS RunSmart app/Features/Auth/SignInView.swift`
- `IOS RunSmart app/Features/Onboarding/OnboardingView.swift`
- `RunSmartInfo.plist`
- `docs/qa/testflight-checklist.md`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Add/update local notification scheduler for workout due, missed workout recovery, rest day/recovery, and weekly recap placeholder.
- [x] Respect user notification preferences and denial state.
- [x] Cancel relevant workout reminder when a workout is completed.
- [x] Route notification opens to Today, Plan, or Report where current navigation supports it.
- [x] Add reusable private progress share card and share utility.
- [x] Add share buttons to run report, benchmark comparison, and habit/milestone surface where available.
- [x] Ensure share defaults do not expose raw coordinates or exact route maps.
- [x] Clean unsupported live AI, medical, and overpromising integration copy.
- [x] Review permission copy for location, HealthKit, notifications, and Garmin.
- [x] Create or update TestFlight/physical-device QA checklist.
- [x] App builds successfully.

### Scope Guard
- No remote push, social feed, leaderboard, public sharing backend, live in-run AI claim, or Hebrew localization.

### Validation
- Generic simulator build-for-testing passed and compiled the new Sprint 6B reminder/share tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Static copy scan checked live AI, real-time plan adaptation, medical/diagnosis wording, notification/reminder copy, Garmin/HealthKit, and location permission copy.
- Manual QA required: permission accepted, permission denied, schedule tomorrow workout, complete workout before reminder, missed workout reminder, rest day reminder, report share, benchmark share, share cancel, sign-in copy, onboarding copy, location permission, HealthKit permission, and Garmin flow.
- No event analytics wrapper was found; Sprint 6B did not add analytics events.

## Sprint 6A - Routes + Benchmark Coaching - 2026-05-17

As a runner, I want RunSmart to recommend a route for today's workout and explain benchmark route comparisons safely.

### Expected Files
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/RouteSuggestionRanker.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Run/RunTabView.swift`
- `IOS RunSmart app/Features/Run/PreRunView.swift`
- `IOS RunSmart app/Features/Routes/BenchmarkComparisonCard.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart appTests/RouteRankingTests.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Add a route recommendation model with route, reason, fit score, warning, and unavailable state.
- [x] Rank saved/generated/benchmark routes by today's workout distance and intent.
- [x] Add a Today recommended route card with conservative route copy and useful empty state.
- [x] Carry the selected route into the Run pre-start flow where the existing architecture supports it.
- [x] Improve benchmark comparison states for first run, matched comparison, PB, monthly average, weak GPS, and no benchmark.
- [x] Keep route copy conservative when route points are missing.
- [x] App builds successfully.

### Scope Guard
- No public route marketplace, Strava segments, social leaderboards, map overhaul, or live AI during runs.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed and compiled the new Sprint 6A route ranking and benchmark readiness tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Manual QA required: saved route, benchmark route, generated route if available, no route, no GPS permission, route without points, first benchmark run, second run on same route, imported matching Garmin run, and weak GPS.
- Existing `BenchmarkRouteAnalyticsService` is a comparison computation helper, not an event-tracking wrapper; Sprint 6A did not add analytics events.

## Sprint 5 - Beginner 5K Habit Track + Guided Cue Preview - 2026-05-17

As a beginner runner, I want to see a habit track on Today and a cue preview before planned runs so I know exactly what to do next.

### Expected Files
- `IOS RunSmart app/Features/Today/Beginner5KHabitCard.swift`
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Run/PreRunView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Add `Beginner5KHabitTrack` model with detection, state resolution, and factory.
- [x] Add `Beginner5KHabitCard` view showing progress dots, state message, next action, confidence label.
- [x] Show card on Today only for First 5K / Getting started users.
- [x] Non-beginner never sees the card.
- [x] Missed workout copy is non-shaming.
- [x] Rest day explains recovery.
- [x] Add `PreRunCueTimeline` with collapsible workout steps for planned runs.
- [x] Free run shows pacing intent panel.
- [x] Missing workout structure handled gracefully.
- [x] App builds successfully.

### Scope Guard
- No plan rewrite, C25K engine, live audio coaching, route recommendation, notifications, or shame-based streaks.
- No new service protocol methods.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed and compiled 6 new Sprint 5 tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Manual QA required: First 5K beginner, intermediate user, missed workout, rest day, completed easy run, easy planned run, tempo run, free run, small iPhone.
- No analytics wrapper found; Sprint 5 did not add analytics events.

---

## Sprint 4 - First Sync Review for Garmin + HealthKit - 2026-05-17

As a runner, I want a clear first-sync review after Garmin or HealthKit imports so I trust what RunSmart imported, skipped, and can now use.

## Sprint 4 - First Sync Review for Garmin + HealthKit - 2026-05-17

As a runner, I want a clear first-sync review after Garmin or HealthKit imports so I trust what RunSmart imported, skipped, and can now use.

### Expected Files
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Live/LiveRunSmartServices.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Add a lightweight `FirstSyncReview` model for provider, imported/skipped counts, route availability, recent activities, Coach capabilities, next action, and seen state.
- [x] Persist first-sync-review seen state per provider.
- [x] Create a first-sync review after the first successful Garmin sync.
- [x] Create a first-sync review after the first successful HealthKit sync.
- [x] Show the review once on the connected-service detail surface.
- [x] Explain empty sync, duplicate-only sync, and route-less imports honestly.
- [x] Keep next action to existing Today, Report, or Plan navigation.
- [x] Verify the app builds.

### Scope Guard
- No Garmin sync rewrite, HealthKit sync rewrite, benchmark comparison, notifications, plan adaptation, or live AI during runs.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed and compiled the new `FirstSyncReview` tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- The first build-for-testing attempt exposed missing default implementations for new optional `DeviceSyncing` review APIs on test doubles; fixed with protocol extension fallbacks before the passing rerun.
- Focused simulator XCTest execution was not run because recent repo validation repeatedly hit simulator install/launch infrastructure failures; build-for-testing was used for compile/link coverage.
- Manual QA remains required for Garmin first sync, HealthKit first sync, permission denied, no data, duplicate-only import, route-less import, and normal import with activities.
- No existing analytics wrapper was found, so Sprint 4 did not add `first_sync_*` events.

---

## Sprint 3 - Today + Plan Explanation Surfaces - 2026-05-17

As a runner, I want a compact explanation for today's workout and recent plan state so I understand why Coach recommends the current session and why the plan changed or stayed steady.

### Expected Files
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Features/Today/TodayTabView.swift`
- `IOS RunSmart app/Features/Plan/PlanTabView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Add a lightweight `PlanExplanation` model with trigger, evidence, recommendation, optional action, and source.
- [x] Derive explanation from plan/workout state, recent runs/imports, missed workouts, and recovery when available.
- [x] Show a compact "Why this workout?" card on Today.
- [x] Show a compact "Plan adjusted because..." or "Plan is on track" card on Plan.
- [x] Keep actions to one recommended existing action.
- [x] Cover no plan, rest day, missed workout, recent completed/imported run, low recovery, and on-track states.
- [x] Verify the app builds.

### Scope Guard
- No new plan engine, complex adaptation workflow, notifications, route recommendation, advanced dashboard charts, or live AI during runs.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed and compiled the new `PlanExplanation` tests:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Focused simulator test execution was not run because recent repo validation repeatedly hit simulator install/launch infrastructure failures; build-for-testing was used for compile/link coverage.
- Manual QA remains required for active plan with today workout, rest day, no plan, missed workout, recent completed run, imported old run, low recovery, and regenerated plan.
- No existing analytics wrapper was found, so Sprint 3 did not add `plan_explanation_*` events.

---

Story complete: Sprint 2 Post-Run Coach Learning Card.

Base branch run-save/Garmin merge fix is merged into `routes`; PR conflict resolution is in progress.

Physical-device build and install passed on connected iPhone; app launch/manual outdoor background/battery QA is still blocked until the device is unlocked and a real outdoor run is recorded.

## Sprint 2 - Post-Run Coach Learning Card - 2026-05-17

As a runner, I want a compact post-run learning card after completed or imported runs so I can see what Coach learned and the safest next action without needing live Coach AI.

### Expected Files
- `IOS RunSmart app/Features/Run/PostRunLearningCard.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Add a lightweight `PostRunLearningCardModel`.
- [x] Derive fallback learning from run, report, plan, route-match, and post-activity outcome data.
- [x] Display the learning card in the RunSmart GPS post-run summary.
- [x] Display the learning card in Garmin/import report flow and saved report detail flow.
- [x] Include what happened, what Coach learned, plan impact, one next action, and source.
- [x] Handle no active plan, missing report, fallback report, short run, GPS-poor run, imported/no-map run, and benchmark route match when already available on the run.
- [x] Keep CTA either actionable via existing `saveSuggestedWorkout` or clearly unavailable.
- [x] Avoid live Coach backend AI, plan adaptation execution, new route recommendation, notifications, share cards, and live run AI.
- [x] Add focused model coverage for fallback suggested workout action and no-plan short-run state.

### Validation
- Generic simulator build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Focused Sprint 2 XCTest attempt built the app and test bundle but failed during simulator install/launch with `com.apple.CoreSimulator.SimError Code=405` and `NSMachErrorDomain Code=-308`; this is recorded as blocked, not a test pass:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testPostRunLearningCardUsesFallbackReportAndSuggestedWorkoutAction" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testPostRunLearningCardHandlesNoActivePlanAndShortRun" test`
- Manual QA remains required for GPS run, manual run if available, Garmin import, HealthKit import, report failure, no active plan, and benchmark-route match.

## Sprint 1 - Coach Persistence + Safe Response - 2026-05-17

As a signed-in runner, I want Coach messages to persist and reload so the deterministic Coach fallback behaves like a real saved conversation before live AI is introduced.

### Expected Files
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Supabase/RunSmartSupabaseClient.swift`
- `IOS RunSmart app/Features/Coach/CoachFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Checklist
- [x] Add a Supabase `send(message:context:)` override.
- [x] Reuse the most recent current-user conversation or create one when none exists.
- [x] Persist the user message into `conversation_messages`.
- [x] Generate the assistant response with `TrainingContextCoachResponder.response(...)`.
- [x] Persist the assistant fallback response into `conversation_messages`.
- [x] Return the assistant `CoachMessage` to the UI.
- [x] Leave the default service fallback unchanged for fake/non-Supabase services.
- [x] Keep Coach UI nearly unchanged; only disable send controls while a turn is in flight.
- [x] Prevent rapid double-submit from creating duplicate saved turns.
- [x] Avoid persisting raw training context or GPS coordinates.
- [x] Add focused encoding coverage for the conversation/message insert payloads.
- [x] Confirm no live Coach backend endpoint is currently implemented or safe to call.

### Scope Guard
- No live backend AI, invented endpoint, unconfirmed Edge Function, run reports, plan adaptation, routes, notifications, Hebrew, share cards, or live run coaching.

### Validation
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Generic simulator build-for-testing passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Sprint 1 rerun after duplicate-send guard passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Sprint 1 rerun after duplicate-send guard passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build-for-testing`
- Focused Coach persistence XCTest compiled the app and test bundle, then stalled during simulator launch and was interrupted; this is recorded as blocked/stalled, not a test pass:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testCoachPersistenceInsertRowsUseOnlyThreadRoleAndContent" test`
- Early focused test attempts exposed test-only JSON key materialization errors; fixed before the successful build/build-for-testing validation.
- One failed build-for-testing/build attempt was caused by running Xcode builds concurrently and hitting the build database lock; rerunning sequentially passed.
- Manual Supabase runtime QA remains required on a signed-in app session.
- Backend endpoint check: `docs/runsmart-ios-supabase-backend-plan.md` lists `POST coach_message` as a future/planned contract, not a confirmed implementation. Existing `/api/v1/chat` code belongs to the resume/optimization chat stack, so Sprint 1 uses the deterministic fallback.

## Story - Unified Training Context + AI Coach Context Integration - 2026-05-16

As a runner, I want Coach to understand my current training state so its answers can be specific without exposing raw GPS route data.

### Expected Files
- `docs/specs/training-context-coach.md`
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Live/LiveRunSmartServices.swift`
- `IOS RunSmart app/App/RunSmartLiteAppShell.swift`
- `IOS RunSmart app/Features/Coach/CoachFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Add typed Coach entry points and training context summary models.
- [x] Add a `TrainingContextProviding` service API and integrate it into `RunSmartServiceProviding`.
- [x] Build context from existing Today, Plan, Run, Report, Route, Recovery, Wellness, and Profile services.
- [x] Limit context to summarized data and omit raw GPS coordinates.
- [x] Wire Coach UI to load/show context and send messages with context.
- [x] Keep compatibility fallback for `send(message:)`.
- [x] Add focused XCTest coverage for context completeness, limits, omissions, limitations, and fallback responses.
- [x] Run targeted XCTest and generic simulator build.

### Scope Guard
- No backend endpoint, Supabase schema, live AI call, permissions, TestFlight, or Coach redesign work in this story.

### Validation
- Focused training context tests passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testTrainingContextIncludesSummariesAndLimitsPrivateRouteData" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testTrainingContextReportsMissingDataLimitations" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testCoachFallbackResponseUsesEntryPointSpecificContext" test`
- Generic simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- PR rebuild passed after commit:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Simulator launch passed on booted iPhone 17 Pro:
  `xcrun simctl install booted ".../IOS RunSmart app.app" && xcrun simctl launch booted com.runsmart.lite`
- First focused test attempt failed during compile because an async context load was placed inside a `??` expression; fixed by branching before awaiting.
- Build/test still emit pre-existing AppIcon unassigned-child warnings and older resume-era actor-isolation warning noise.

## Critical Bug - Run Save And Garmin Merge Investigation - Merged From Base
As a TestFlight runner, I want a real completed run to save once, display real metrics, merge with Garmin when it is the same workout, and produce a useful coach report so RunSmart activity history stays trustworthy.

### Status
- [x] Post-run summary shows actual distance, time, and pace for a valid recorded run.
- [x] Done closes the post-run summary/sheet and the run remains visible.
- [x] Garmin mapping rejects invalid/non-running records.
- [x] Garmin fragments overlapping or adjacent to a longer real run do not appear as separate activities.
- [x] Garmin + RunSmart versions of the same workout merge into one canonical activity.
- [x] Run reports have useful deterministic coach notes if backend AI generation is unavailable.
- [x] Save failure path has safer copy and debug diagnostics.
- [x] Focused tests and simulator build pass.

### Validation
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Focused run-save/Garmin merge regression tests passed on iPhone 17 simulator.
- Nearby Garmin import, batch, and consolidation tests passed on iPhone 17 simulator.
- Full test pass succeeded:
  `xcodebuild -quiet -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,id=A24FA1E8-AD0C-46DB-85B7-651A24B1BB38" test`
- Manual physical-device GPS/Garmin TestFlight QA still required.

## Physical Device Outdoor Background Battery QA - 2026-05-15

### Device
- `<REDACTED_DEVICE_NAME>` / iPhone 13 (`iPhone14,5`) / iOS 26.4.2.
- Device UDID: `<REDACTED_UDID>`.
- CoreDevice identifier: `<REDACTED_COREDEVICE_ID>`.
- Full device identifiers are kept out of git-tracked task memory and should remain in private/local QA notes only.

### Status
- [x] Connected physical iPhone discovered by `xcrun xctrace list devices`.
- [x] Connected physical iPhone discovered by `xcrun devicectl list devices`.
- [x] Active scheme listed for `IOS RunSmart app.xcodeproj`.
- [x] Physical-device Debug build succeeded for `com.runsmart.lite`.
- [x] Debug app installed on the connected iPhone.
- [ ] App launch on the device completed.
- [ ] Outdoor GPS run recording started.
- [ ] Location permission prompt/denial/approval behavior verified on device.
- [ ] Run continued correctly with the phone locked/backgrounded.
- [ ] Battery start/end percentage and duration recorded.
- [ ] Weak GPS, sparse points, or permission issues documented from the real run.
- [ ] Route/benchmark/Garmin limitations rechecked after a saved/finished run.

### Validation Evidence
- `xcrun xctrace list devices` showed `<REDACTED_DEVICE_NAME> (26.4.2) (<REDACTED_UDID>)`.
- `xcrun devicectl list devices` showed `<REDACTED_DEVICE_NAME>`, identifier `<REDACTED_COREDEVICE_ID>`, state `available (paired)`, model `iPhone 13 (iPhone14,5)`.
- `xcodebuild -list -project "IOS RunSmart app.xcodeproj"` succeeded and listed scheme `IOS RunSmart app`.
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS,id=<REDACTED_UDID>" build` succeeded.
- Build evidence: `** BUILD SUCCEEDED **`; signing identity `Apple Development: <REDACTED_EMAIL> (<REDACTED_TEAM_ID>)`; provisioning profile `iOS Team Provisioning Profile: com.runsmart.lite`; bundle id `com.runsmart.lite`; HealthKit, associated domains, and background location entitlements were present.
- `xcrun devicectl device install app --device <REDACTED_COREDEVICE_ID> ".../IOS RunSmart app.app"` succeeded for bundle id `com.runsmart.lite`.
- `xcrun devicectl device process launch --device <REDACTED_COREDEVICE_ID> com.runsmart.lite` failed because the device was locked: `Unable to launch com.runsmart.lite because the device was not, or could not be, unlocked`.

### Manual QA Steps Still Required
- Unlock the connected iPhone and launch `RunSmart`.
- Record starting battery percentage before tapping `Start Run`.
- From the Run tab, tap `Start Run`; approve location permission if prompted and capture whether the app copy is clear.
- Wait for `Recording` or `Finding GPS` to resolve under open sky; note GPS accuracy text and any weak-GPS copy.
- Walk/run outdoors for at least 10 minutes, lock the phone for at least 5 minutes, then unlock and confirm time/distance/route continued.
- Finish the run, save it, and confirm the post-run route/benchmark/Garmin limitation copy remains accurate.
- Record ending battery percentage, duration, distance, GPS notes, and whether background continuation passed.

### Blocker
- External TestFlight archive/upload readiness should not start until the locked-device launch blocker is cleared and the outdoor/background/battery evidence above is captured.

## Agent OS Source Of Truth - 2026-05-15

### Status
- [x] Canonical app repo is `<LOCAL_APP_REPO_PATH>`.
- [x] Canonical status files are `tasks/todo.md`, `tasks/lessons.md`, and `tasks/session-log.md` in the app repo.
- [x] Outer wrapper `tasks/*.md` files are pointer stubs only.
- [x] Removed duplicate loose task files `tasks/todo 2.md` and `tasks/todo 3.md`.
- [x] No app feature code changed.

### Validation
- File discovery after cleanup showed exactly these app-repo status files: `tasks/todo.md`, `tasks/lessons.md`, and `tasks/session-log.md`.
- Outer wrapper discovery showed only pointer stubs: `tasks/todo.md`, `tasks/lessons.md`, and `tasks/session-log.md`.

## Open Task Triage - 2026-05-15

### What Was Checked
- Re-read `tasks/todo.md`, `tasks/session-log.md`, `tasks/lessons.md`, the Agent OS implementation and bug-fix workflows, and the active RunSmart project files.
- Checked the historical open questions for `RunSmartTab` ambiguity and `GlassCard` redeclaration.
- Verified the active `IOS RunSmart app.xcodeproj` simulator build no longer reproduces those compile blockers.

### Status
- [x] `RunSmartTab` ambiguity is not present in the active simulator build.
- [x] `GlassCard` redeclaration is not present in the active simulator build.
- [x] Active simulator build succeeds for `IOS RunSmart app`.
- [x] Connected physical device is visible: `<REDACTED_DEVICE_NAME>` / iPhone 13 / iOS 26.4.2.
- [x] Physical-device Debug build succeeds for bundle id `com.runsmart.lite`.
- [ ] Manual outdoor/background recording and battery-delta check completed before external TestFlight.

### Validation
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Full iPhone 17 XCTest run was attempted but did not complete because the simulator launch worker stalled and ended with `NSMachErrorDomain Code=-308` after interruption.
- Device discovery passed:
  `xcrun xctrace list devices`
  Evidence: `<REDACTED_DEVICE_NAME> (26.4.2) (<REDACTED_UDID>)`.
- Device list passed:
  `xcrun devicectl list devices`
  Evidence: `<REDACTED_DEVICE_NAME>`, identifier `<REDACTED_COREDEVICE_ID>`, state `connected`, model `iPhone 13 (iPhone14,5)`.
- Physical-device build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS,id=<REDACTED_UDID>" build`
  Evidence: `** BUILD SUCCEEDED **`; signing identity `Apple Development: <REDACTED_EMAIL> (<REDACTED_TEAM_ID>)`; provisioning profile `iOS Team Provisioning Profile: com.runsmart.lite`; bundle id `com.runsmart.lite`.
- Build still reports pre-existing AppIcon unassigned-child warnings and older resume-era actor-isolation warning noise.

## Route Feature Story 10 - TestFlight Polish And Privacy Review
As a beta runner, I want route, GPS, Garmin, and benchmark behavior to be clear and trustworthy so I understand what RunSmart records and where limitations remain.

### Expected Files
- `RunSmartInfo.plist`
- `IOS RunSmart app/Features/Routes/SaveRouteSheet.swift`
- `IOS RunSmart app/Features/Routes/RouteDetailView.swift`
- `IOS RunSmart app/Features/Run/RunTabView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `docs/qa/testflight-checklist.md`
- `docs/qa/ios-qa-checklist.md`
- `docs/qa/route-benchmark-testflight-notes.md`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Route/location privacy copy is clear.
- [x] Weak GPS and missing Garmin map data are handled with non-alarming copy.
- [x] Saved route deletion clarifies RunSmart-only deletion and benchmark tracking removal.
- [x] TestFlight release notes mention route/benchmark limitations.
- [x] Battery/background behavior is called out for physical-device validation.
- [ ] Physical-device battery/background run check completed before external TestFlight.

### Validation
- `plutil -lint RunSmartInfo.plist "IOS RunSmart app/PrivacyInfo.xcprivacy"` passed.
- Static copy check found the updated location, weak GPS, Garmin missing-map, privacy, and TestFlight notes strings.
- Simulator build passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Full iPhone 17 test pass succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" test`
- Build/test still emit pre-existing warning noise from older resume-era view models and AppIntents metadata extraction, but no Story 10 failures.

---

## Previous Task
Story 9 complete: Garmin Import Processing Into Route Flow.

## Route Feature Story 9 - Garmin Import Processing Into Route Flow
As a Garmin runner, I want imported activities to behave like RunSmart-recorded runs so route matching, benchmark comparisons, and reports are consistent.

### Expected Files
- `IOS RunSmart app/Services/Garmin/GarminImportProcessor.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Garmin sync processes newest run through `processCompletedActivity`.
- [x] Garmin route points are normalized before matching when available.
- [x] Garmin run reports can show benchmark comparison through the existing matched-run report path.
- [x] Missing Garmin route points still leave a route-less import/report path.
- [x] Duplicate Garmin activities remain stable by provider activity id.
- [x] Report generation failure does not block sync status.

### Status
- [x] Added `GarminImportProcessor` to normalize Garmin activities into newest-first `RecordedRun` values.
- [x] Hydrates route points before matching when Garmin map data exists.
- [x] Keeps route-less Garmin runs processable when route points are unavailable.
- [x] Skips hidden Garmin runs before choosing the newest import.
- [x] Dedupes duplicate Garmin activity rows by provider activity id.
- [x] Supabase Garmin sync now sends the newest normalized run through `processCompletedActivity`.
- [x] Local production Garmin sync now uses the same completed-activity path for the newest gateway run.
- [x] Completed-activity persistence now saves the canonical run even when no route match is available.

### Validation
- Focused Story 9 tests passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorHydratesRoutePointsAndOrdersNewestFirst" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorKeepsRouteLessRunWhenMapDataIsMissing" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorSkipsHiddenRunsBeforeSelectingNewest" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testGarminImportProcessorDedupesDuplicateProviderActivities" test`
- Simulator build check passed:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`

---

## Previous Task
Story 8 complete: Route Discovery Ranking MVP.

## Route Feature Story 8 - Route Discovery Ranking MVP
Full-bleed map route cards (map fills entire card, data overlaid via gradient scrim),
three-bucket ranked discovery (Benchmarks → My Routes → Generated Nearby),
distance filter chips, recommendation reason chips on each card. Applied to both
RouteCreatorView and RouteSelectorScaffold.

### Files Changed
- `IOS RunSmart app/Models/RunSmartModels.swift` — extended RouteKind + RouteSuggestion
- `IOS RunSmart app/Services/RouteSuggestionRanker.swift` — new pure ranker
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift` — rankedRouteSuggestions
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift` — rankedRouteSuggestions
- `IOS RunSmart app/Features/Routes/FullBleedRouteCard.swift` — new component file
- `IOS RunSmart app/Features/Routes/RouteCreatorView.swift` — redesigned
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift` — RouteSelectorScaffold redesigned
- `IOS RunSmart app/PreviewSupport/RunSmartPreviewData.swift` — added routeSuggestions
- `IOS RunSmart appTests/RouteRankingTests.swift` — new tests (all pass)

### Status
- [x] RouteSuggestion model extended with kind (.benchmark, .saved), recommendationReason, isFavorite
- [x] RouteSuggestionRanker with rank(), filter(), reason() — tested
- [x] rankedRouteSuggestions on RouteProviding + both service implementations
- [x] FullBleedRouteCard (full-bleed map + scrim + overlaid data)
- [x] RouteCreatorView redesigned with filter bar + three buckets
- [x] RouteSelectorScaffold redesigned with filter bar + three buckets
- [x] Preview data added

---

## Previous Task
Story 7 complete: Benchmark Comparison Card In Run Reports.

## Goal
Show route-specific benchmark progress in post-run and run report detail screens without recalculating Story 6 analytics in SwiftUI.

## Route Feature Story 7 - Benchmark Comparison Card In Run Reports
As a runner, I want run reports to show route-specific progress so I can understand improvement on benchmark routes without hunting through analytics.

### Expected Files
- `IOS RunSmart app/Features/Routes/BenchmarkComparisonCard.swift`
- `IOS RunSmart app/Services/BenchmarkComparisonPresentation.swift`
- `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`
- `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Show route name and match confidence for benchmark-matched runs.
- [x] Show previous, PB, and monthly average comparisons.
- [x] Show 1-3 deterministic coaching insights.
- [x] Do not show for non-benchmark routes.
- [x] Handle first-run and not-enough-history states clearly.
- [x] Keep Dynamic Type-friendly layout.

## Route Feature Story 6 - Benchmark Comparison Data
As a runner, I want benchmark route reports to compare my current run with route history so I can see progress on routes I actually repeat.

### Expected Files
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/BenchmarkRouteAnalyticsService.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`

### Checklist
- [x] Calculate comparisons only for high-confidence matches attached to benchmark routes.
- [x] Provide previous run, personal best, all-time average, current-month average, and recent trend.
- [x] Handle first-run and not-enough-history states.
- [x] Aggregate monthly averages by the provided local calendar month.
- [x] Support duration, pace, and optional heart-rate averages.
- [x] Cover mixed Garmin and RunSmart matched runs.

## Route Feature Story 5 - MVP Route Matching Service
As a runner, I want RunSmart to recognize repeated saved and benchmark routes so route-aware reports can compare progress later.

### Expected Files
- `IOS RunSmart app/Models/RunSmartModels.swift`
- `IOS RunSmart app/Services/RouteMatchingService.swift`
- `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift`
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`
- `IOS RunSmart app/Services/RunSmartServices.swift`
- `IOS RunSmart appTests/RunSmartReadinessTests.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md`

### Checklist
- [x] Add route match result data to completed runs.
- [x] Distinguish high-confidence, possible, and no-match states.
- [x] Ignore manual or route-less runs.
- [x] Match both RunSmart GPS runs and Garmin/imported runs through `processCompletedActivity`.
- [x] Support reversed-route matching.
- [x] Verify same route, possible route, unrelated route, reversed route, and route-less cases.

## Story 1 - Bug Fix
As a developer, I want the existing test target to compile so validation can catch real regressions.

### Expected Files
- `RunSmartTests/ResumeOptimizationServiceSwiftTestingTests.swift`

### Checklist
- [x] Update stale test doubles to match `ResumeOptimizationServiceProtocol`.
- [x] Run the existing test target.
- [x] Keep fix scoped to tests only.

## Story 2 - Today Shell
As a runner, I want the first app tab to point me toward Today so the app starts moving toward daily runner jobs without losing current functionality.

### Expected Files
- `RunSmart/Core/DesignSystem/Components/RunSmartTabBar.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md` if a new lesson is learned

### Checklist
- [x] Keep the existing first-tab content reachable.
- [x] Update only shell-level tab naming/iconography for the first tab.
- [x] Do not implement the full redesign.
- [x] Do not change signing, certificates, provisioning, paid services, Garmin, or HealthKit.
- [x] Run build/tests after implementation.

## Story 3 - Today Content Wrapper
As a runner, I want the Today tab to open on a lightweight daily command-center surface so the app starts to feel like RunSmart while keeping the current score/check flow available.

### Expected Files
- `RunSmart/App/MainTabViewV2.swift`
- `RunSmart/Features/V2/Today/TodayView.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md` if a new lesson is learned

### Checklist
- [x] Add a real Today wrapper as the first tab content.
- [x] Keep the existing score/check flow reachable from Today.
- [x] Preserve the existing `ScoreViewModel` instance so score flow state is not reset by the wrapper.
- [x] Do not implement full Plan, Run, Coach, HealthKit, Garmin, signing, or paid-services work.
- [x] Run build/tests after implementation.

## Story 4 - Separate Plan From Report
As a runner, I want Plan and Report to be distinct top-level areas so upcoming training and past progress are not mixed together.

### Expected Files
- `RunSmart/App/MainTabViewV2.swift`
- `RunSmart/Core/DesignSystem/Components/RunSmartTabBar.swift`
- `RunSmart/Features/V2/Plan/PlanView.swift`
- `RunSmart/Features/V2/Report/ReportView.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md` if a new lesson is learned

### Checklist
- [x] Add a lightweight Plan surface as its own tab content.
- [x] Add a lightweight Report surface as its own tab content.
- [x] Keep the current Tailor/Improve flow reachable from Plan.
- [x] Keep the current Track/applications flow reachable from Report.
- [x] Do not implement full Run, Coach, HealthKit, Garmin, signing, or paid-services work.
- [x] Run build/tests after implementation.

## Prior Story 5 - Run Entry Point
As a runner, I want a clear Run tab so I can see where GPS tracking and manual run logging will live.

### Expected Files
- `RunSmart/App/MainTabViewV2.swift`
- `RunSmart/Core/DesignSystem/Components/RunSmartTabBar.swift`
- `RunSmart/Features/V2/Run/RunView.swift`
- `tasks/todo.md`
- `tasks/session-log.md`
- `tasks/lessons.md` if a new lesson is learned

### Checklist
- [x] Add a lightweight Run surface as the middle tab content.
- [x] Show GPS start and manual log entry points as unavailable placeholders only.
- [x] Keep the current Design/redesign flow reachable from Run while product ownership is unresolved.
- [x] Do not request location permissions or change GPS/background-location behavior.
- [x] Do not implement full Coach, HealthKit, Garmin, signing, or paid-services work.
- [x] Run build/tests after implementation.

## Risks
- Existing uncommitted Swift/resource changes are present and must be preserved.
- The app still contains resume-builder product naming and flows.
- Story 2 is intentionally a shell step; it improves IA direction but does not yet create the full Today screen.
- Story 3 creates a command-center wrapper but still uses placeholder/no-plan states until approved RunSmart data models are connected.
- Story 4 separates Plan and Report with placeholder states while preserving the existing Tailor and Track flows.
- Story 5 must not touch permissions or background tracking; it is an entry-point shell story only.

## Validation
- Story 7 benchmark presentation focused tests succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonPresentationShowsFirstRunHistoryPrompt" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonPresentationShowsImprovementAgainstPreviousAndMonth" test`
- Story 7 simulator build check succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Story 6 benchmark comparison focused tests succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonReturnsFirstRunNotEnoughHistory" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonUsesPreviousPBAndAveragesAcrossGarminAndRunSmartRuns" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testBenchmarkComparisonMonthlyAverageRespectsLocalCalendarMonthBoundary" test`
- Story 6 simulator build check succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "generic/platform=iOS Simulator" build`
- Story 5 route matching focused tests succeeded:
  `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingReturnsHighConfidenceForSameRoute" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingMarksNearbyNoisyRouteAsPossibleWithoutAttaching" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingReturnsNoMatchForUnrelatedRoute" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingHandlesReversedRouteAsMatch" -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRouteMatchingIgnoresManualRouteLessRuns" test`
- `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "platform=iOS Simulator,name=iPhone 17" test` succeeded.
- Simulator install and launch succeeded on iPhone 17.
- Visual evidence captured at `build/qa/story2-today-tab-after-wait.png`.
- First screenshot was blank because it was captured before the app finished drawing; the follow-up screenshot showed the app UI and the active `Today` tab.
- Story 3 test run succeeded with the same `xcodebuild ... test` command on iPhone 17.
- Final Story 3 simulator build check succeeded with `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "generic/platform=iOS Simulator" build`.
- Story 3 simulator install and launch succeeded on iPhone 17.
- Story 3 visual evidence captured at `build/qa/story3-today-wrapper.png`.
- Story 4 simulator build check succeeded with `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "generic/platform=iOS Simulator" build`.
- Story 4 test run succeeded with `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "platform=iOS Simulator,name=iPhone 17" test`.
- Story 5 simulator build check succeeded with `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "generic/platform=iOS Simulator" build`.
- Story 5 test run succeeded with `xcodebuild -project "IOS RunSmart app.xcodeproj" -scheme "RunSmart" -destination "platform=iOS Simulator,name=iPhone 17" test`.

## Review Notes
- Keep both changes small and reviewable.
- Existing unrelated app/resource changes remain untouched.
- Story 7 can now consume `benchmarkComparison(for:)` to render the report card without recalculating analytics in SwiftUI.
