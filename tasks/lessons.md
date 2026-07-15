# Lessons Memory

Review this file at the start of future tasks.

## Active Rules
- Keep a decision metric's terminal-event numerator independent of diagnostic intermediate events; report a fully ordered funnel separately so telemetry gaps or alternate valid routes cannot erase real activation.
- In PostHog verification queries, never select the whole `properties.$set` object; it can include enriched geographic/system data. Select only the required nested key, such as `properties.$set.onboarding_completed_at`.
- In PostHog HogQL, do not use `sequenceMatch` for ordered funnels; use `windowFunnel` with `toDateTime(timestamp)`, and use `countIf` instead of nullable-left-join assumptions because missing joined rows can carry defaults.
- Keep `AGENTS.md`, `CLAUDE.md`, and `CODEX.md` as routers, not manuals.
- Load only the files needed for the current workflow.
- Use app-repo `tasks/todo.md`, `tasks/lessons.md`, and `tasks/session-log.md` as the single source of truth; outer wrapper status files should only point here.
- A branch name, dirty diff, or QA artifact is not authoritative work-packet status; read the canonical packet and follow the user's stated story boundary before declaring work started or blocked.
- For Xcode validation, prefer quiet/filtered logs because build settings can echo xcconfig-backed service keys; never paste raw build setting output into task memory or final reports.
- Do not assume the project is already a clean RunSmart app; verify whether files still use resume-builder names.
- Do not change app feature code when the task is to install or update the operating layer only.
- Before TestFlight claims, verify signing, bundle id, archive status, permissions, privacy strings, and smoke tests.
- When a workspace contains nested git repositories or nested Xcode projects, explicitly state which root is the GitHub repo and write committed docs relative to that root.
- If an approved spec exists only in conversation, create a repo-tracked spec/story artifact before changing SwiftUI navigation or app code.
- When validating integration readiness docs, explicitly check for platform terms users care about, such as HealthKit, not only friendlier product names like Apple Health.
- If validation exposes an unrelated pre-existing test failure, record the exact failure and do not fold the fix into the current story unless the story owns that area.
- When optimization flow tests exercise scanned-resume behavior, provide both `resumeId` and `jobDescriptionId`; pasted job text alone is no longer enough.
- Do not preserve ResumeBuilder-era flows in the RunSmart shell unless the user explicitly asks; remove visible resume/job/ATS/design/application entry points from RunSmart surfaces.
- Before opening Xcode, prefer the RunSmart-named project/workspace and verify it has a readable `project.pbxproj`; if it is broken, state that clearly and open the closest buildable project only as a fallback.
- For route matching tests, keep possible-match fixtures close enough to represent GPS noise or small deviations; far parallel routes should remain no-match.
- For local-calendar month boundary tests, construct dates with the test `Calendar` and `DateComponents`; do not use opaque epoch constants.
- If a simulator XCTest run stalls during launch, stop it, record the exact launch error, and keep the completed build as separate validation instead of claiming a test pass.
- If focused XCTest builds but fails at simulator install/launch with CoreSimulator error 405 and NSMach -308, treat it as simulator infrastructure failure and rely on build-for-testing plus app build until the simulator is reset.
- For physical-device QA, confirm the device is unlocked and capture starting battery percentage before attempting app launch; build/install success is not launch, outdoor, background, or battery evidence.
- Do not put awaited fallback calls inside nil-coalescing expressions; branch explicitly before `await` because `??` uses a synchronous autoclosure.
- Route discovery controls must connect to service behavior or clearly present as unavailable; do not ship decorative filters that leave results unchanged.
- For RunSmart Supabase Edge Functions, use `SupabaseManager.functionsBaseURL` and the current Supabase publishable key; do not route app-native Coach features through stale ResumeBuilder `BackendConfig.apiBaseURL`.
- Before copying local API secrets into the iOS workspace, add env file patterns to both wrapper and app `.gitignore`; never print secret values in logs or task memory.
- After adding owner-scoped Supabase RLS policies, inspect and remove older broad authenticated policies on the same tables; permissive policies combine with restrictive-looking policies and can still expose rows.
- Raw connected-service activities must go through the same mapper, hidden-run, fragment, and consolidation rules before display that they use before persistence.
- Redact personal device names, UDIDs, CoreDevice identifiers, emails, team IDs, and local absolute paths before committing task memory or QA evidence.
- When asserting JSON key sets from `Dictionary<String, Any>`, materialize optional keys explicitly before building a `Set`; avoid overload-prone `String.init` mapping.
- Do not run multiple Xcode builds against the same DerivedData concurrently; build database locks are false failures, so run validation sequentially unless separate DerivedData paths are configured.
- When adding optional behavior to a shared service protocol, provide default extension fallbacks or update every test double in the same pass before validation.
- Before App Store readiness claims, inspect the built archive bundle for display name, encryption declaration, bundled diagnostics, dSYMs, entitlements, and distribution-only signing; source checks alone are not enough.
- In this Xcode folder-synchronized project, untracked Swift files inside `IOS RunSmart app/` can still compile; before release, inspect and clean untracked source under the synced app root, not only tracked project references.
- For plan/workout date-only strings, format and compare with the user's local calendar/timezone; do not normalize date-only schedule values through UTC during Today matching.
- Treat low stress as healthy or neutral in recovery classifiers; only high or elevated stress should contribute to low-recovery decisions.
- After Sign in with Apple, do not ask users to type name or email; use AuthenticationServices-provided values when available and an internal fallback when they are not.
- Onboarding aha moments must not auto-skip from stale `user_aha_moments` rows when the same Apple auth uid returns after account deletion; always show the onboarding container and reset onboarding moments on delete.
- Garmin OAuth on iOS must use the registered `runsmart://` callback scheme with `ASWebAuthenticationSession`, then poll `garmin_connections` until connected before returning success.
- Before applying RLS or index migrations, inspect the live relation type in `pg_class`; views need `security_invoker` and protection on underlying tables, not table RLS or direct indexes.
- With XcodeBuildMCP build tools, set DerivedData through session defaults or omit it; do not pass `-derivedDataPath` in `extraArgs` unless the tool is not already supplying one.
- Before recording an App Store validation command as executable, verify the installed `xcodebuild` supports the flags; for this environment, `-validate-for-store` is not a supported CLI option, so use archive/export inspection locally and leave Organizer/ASC validation to founder-gated tooling.
- If App Store Connect says a pre-release train is closed for new submissions, bump `MARKETING_VERSION` to the next train and re-archive; changing only `CURRENT_PROJECT_VERSION` cannot reopen a closed approved marketing version.
- For Garmin submission evidence, visually verify each required screenshot against the exact rejected requirement; source support for `device_name` is not enough when legacy activity rows can lack it and need connection-level fallback.
- A `RunRecorder` phase-reset test that relies on the test host's `.notDetermined` authorization masks the device zombie-recorder bug: `updatePhaseForAuthorization()` resets `.recording`→`.idle` under `.notDetermined` but leaves it stuck under `.authorizedWhenInUse`. Inject authorization via `authorizationStatusProvider` and assert the authorized-path phase transition, or the test passes on CI while the bug ships.
- Post-run recorder teardown (`finish()`/`discard()`) must call `resolveTerminalPhase()` (always exits `.recording`/`.paused`), never `updatePhaseForAuthorization()` (guarded, no-op mid-run); the auth-change callback must keep using `updatePhaseForAuthorization()` so a mid-run permission change never yanks an active run to `.ready`.
- `RunRecorder`'s `CLLocationManager(_:didFailWithError:)` must only stop an active run for an explicit `.denied` `CLError`; every other failure (notably `kCLErrorLocationUnknown`) is transient per Apple's docs and must not silently abort a `.recording`/`.paused` run. Clear `lastErrorMessage` on the next accepted location so the GPS pill doesn't stick on stale error copy after signal recovers.
- `LiveRunView`'s bottom control row must never exceed 3 buttons: `prominent(112) + 78 + 78 + spacing/padding` already reaches ~340pt, and a 4th 78pt button plus its spacing pushes past both iPhone SE (375pt) and iPhone 17 (402pt) widths. When adding a state-dependent action (e.g. Discard-while-paused), swap it in place of an inert action for that state rather than appending a 4th button.
- Local simulator location-authorization state persists across test runs (real `CLLocationManager` instances, not mocked) and can drift from `.notDetermined` to `.authorizedWhenInUse` on a given Mac, which changes which branch of `updatePhaseForAuthorization()`-style guards executes. A phase-reset test that only exercises the `.notDetermined` path can silently mask a real device bug; verified 2026-07-08 that `testRunRecorderDiscardResetsCurrentWorkoutWithoutSaving` now fails on unmodified `main` in this environment because the simulator has real authorization granted — corroborates WP-37 S1's root cause independent of that story's own analysis. Inject authorization via a seam (`authorizationStatusProvider`) so tests exercise both branches explicitly rather than relying on whatever state the local simulator happens to be in.
- Never derive per-segment display data (splits, laps, intervals) from a run's *aggregate* stat (`averagePaceSecondsPerKm`) plus an arbitrary formula — that's fabrication even if it "looks plausible." A `max(1, ...)` guard forcing at least one entry is a second, subtler fabrication (a sub-1km run gets a fake "km 1" split). Derive per-segment data from the actual per-point GPS timestamps/distances, and let the segment legitimately not exist (empty state) when the recorded data doesn't support it — see `RunRecorder.kilometerSplits(from:)`.
- On this environment's iOS 26 simulator, SwiftUI `confirmationDialog` renders only the destructive/primary action button and silently drops any `role: .cancel` button — device-confirmed via zoomed screenshot, not a hypothesis. `.alert` with the identical copy/roles/actions reliably renders both buttons. Prefer `.alert` over `confirmationDialog` for any destructive confirmation with a cancel path until this is fixed upstream.
- A `GeometryReader` + non-scrolling `VStack` with fixed-height-floor panels (e.g. `.frame(height: max(174, min(218, proxy.size.height * 0.25)))`) has no scroll fallback and can silently clip trailing content (button labels) on short screens (iPhone SE, 667pt) even though it renders fine on taller phones. Wrap in `ScrollView` and change the inner frame from `maxHeight: .infinity` to `minHeight: proxy.size.height` — this preserves the existing bottom-pinned layout (via `Spacer(minLength: 0)`) on tall screens while making short screens scroll instead of clip.
- SwiftUI Map `Annotation` titles render as visible map labels. For live runner/current-position indicators, use an unlabeled annotation and put the meaning in the surrounding UI or accessibility surface; otherwise replacing a wrong "Finish" marker with a visible "Current position" label still violates the plain-dot intent.
- Post-run controls that ask for subjective user input must either persist that input to the saved run or start in a clearly unset state and remain non-authoritative; never preselect a fake value that is silently discarded. When validating accelerated demo-mode runs, make sure the QA service path can surface locally saved runs in history without weakening production visibility filters.
- Pre-run previews must not claim live GPS unless they are backed by real location/map data. Decorative route sketches should be labeled as sketches, and short-screen reachability must be verified by scrolling on iPhone SE as well as checking the first viewport on larger phones.

## Lesson Log

### 2026-07-10 - Branch State Is Not Work-Packet Status (WP-40 correction)
Trigger: WP-40 was initially treated as in-progress because the checkout was on `claude/wp40-healthkit-activation` with matching dirty files and screenshots, but the canonical packet still said Not Started and the user explicitly directed execution.

Lesson: Workspace evidence can be partial, stale, or abandoned. It is useful implementation context, but it does not override the canonical packet or the user's current instruction.

Future rule: Read the named work packet first, lock exactly one story, then classify dirty matching files as partial work to preserve and audit—never as proof that the story is already active or blocked.

### 2026-07-08 - Zombie Recorder: Phase Never Reset After Finish/Discard (WP-37 S1)
Trigger: Fable run-recording audit found that after Save/View Report/Delete, the Run tab renders a frozen "Recording" zombie screen (no Start button, tab bar hidden, only escape is killing the app); ships in 1.0.7 (21).

Lesson: `RunRecorder.finish()` and `discard()` delegated the post-run phase reset to `updatePhaseForAuthorization()`, whose authorized branch only resets phase when it is `.idle/.requestingPermission/.denied/.failed` — never `.recording/.paused`. On a device (`.authorizedWhenInUse`) the phase stuck; the existing discard test passed only because the test host is `.notDetermined` (which does reset to `.idle`), masking the device bug.

Future rule: For terminal state-machine transitions, do not reuse an authorization-normalizer whose guards were written for a different call site. Add a dedicated resolver (`resolveTerminalPhase()`) that unconditionally exits the live state, keep the guarded normalizer for auth-change callbacks, and unit-test the authorized path via an injected authorization seam plus a red-state check (reintroduce the bug, confirm the test fails).

### 2026-07-08 - Transient GPS Errors Must Not Abort An Active Run (WP-37 S2)
Trigger: Fable run-recording audit found `locationManager(_:didFailWithError:)` set `phase = .failed` on any CoreLocation error while recording, silently kicking an active run back to PreRun on a momentary GPS hiccup with no save.

Lesson: Apple documents `kCLErrorLocationUnknown` as transient. Treating every location error the same as an explicit permission denial destroys in-progress work for a class of failure that resolves itself within seconds.

Future rule: While `.recording`/`.paused`, only stop the run for an explicit `CLError.denied`; treat every other location error as transient (keep recording, surface degraded-GPS copy via `lastErrorMessage`, clear that message on the next accepted location). Corroborating finding from this same validation pass: this Mac's iPhone 17 simulator has drifted to real `.authorizedWhenInUse` location authorization, which reproduced WP-37 S1's zombie-phase bug live on unmodified `main` — confirming simulator authorization state, not just test design, can silently mask or reveal these device bugs across sessions.

### 2026-07-08 - Finish/Discard Dialogs Had No Visible Cancel Button; iPhone SE Clipped Control-Row Labels (WP-37 S4 + SE follow-up)
Trigger: Fable run-recording audit plus device-QA smoke test found `RunTabView`'s Finish and Discard `confirmationDialog`s rendered with only the destructive/primary button visible on iOS 26 — no "Keep Workout"/"Keep Recording" button, leaving a mid-run mis-tap with only an undiscoverable tap-outside escape hatch. The same smoke pass found `LiveRunView`'s control-row button labels ("Pause"/"Finish"/"Coach", "Resume"/"Finish"/"Discard") clipped off-screen on iPhone SE (375×667pt): the non-scrolling `GeometryReader`+`VStack` with fixed-height-floor panels left less vertical room than the row needed, with no scroll fallback.

Lesson: `confirmationDialog` silently dropping `role: .cancel` buttons is an iOS 26 simulator/runtime quirk, not a code bug — the SwiftUI declaration was correct. Fixed height floors on the metric/preview panels above the button row assumed every supported screen had enough vertical space; nothing degraded gracefully when that assumption broke on the shortest supported device.

Future rule: Prefer `.alert` over `confirmationDialog` for destructive confirmations with a cancel path on this codebase until Apple fixes the rendering bug (same copy/roles/actions carry over unchanged). For any non-scrolling `GeometryReader`+`VStack` layout with height-floor panels, wrap in `ScrollView` with `minHeight: proxy.size.height` (not `maxHeight: .infinity`) on the inner frame so short screens scroll instead of clipping, while tall screens keep the existing bottom-pinned layout via `Spacer(minLength: 0)`. Verify both dialog rendering and label visibility on both iPhone 17 and iPhone SE simulators, not just the default destination.

### 2026-07-08 - SwiftUI Map Annotation Titles Are Visible Labels (WP-37 S6)
Trigger: While fixing the live map's wrong red "Finish" flag, the first pass replaced it with an `Annotation("Current position", ...)` dot. The red Finish marker was gone, but the map rendered visible "Current position" text under the dot, which was still not the requested plain live-position indicator.

Lesson: SwiftUI Map annotation titles are display text, not just accessibility metadata. Using a descriptive title can accidentally add another map label and turn a visual trust fix into a different kind of clutter.

Future rule: For live/current-position dots in `RouteMapView`, keep the annotation title empty unless product explicitly wants a visible label. Verify map-label changes with screenshots, not just accessibility snapshots, because the rendered map content is the acceptance surface.

### 2026-07-08 - RPE Selectors Must Persist Or Stay Unset (WP-37 S7)
Trigger: The post-run summary preselected "How did that feel?" at 6/10 and then threw the value away on save, so a runner could reasonably believe RunSmart had stored a rating that did not exist.

Lesson: A preselected subjective rating is a product claim, not a harmless default. If the saved model and history/report surfaces do not carry that value, the control teaches users not to trust the run summary.

Future rule: For any post-run subjective control, wire persistence and a visible readback in the saved run before shipping; otherwise start from an explicit unset state or remove the control. For simulator runs compressed by `-RUNSMART_DEMO_MODE`, keep production filtering intact and expose local recorded runs only through the demo service path so history persistence can still be QAed.

### 2026-07-08 - PreRun Preview Copy Must Match Data Reality (WP-37 S8)
Trigger: `PreRunView` labeled a decorative `RunSmartRoutePreview` as `GPS preview`, while the same non-scrolling layout could keep the real Last Run card out of reach on iPhone SE.

Lesson: Sensor-language copy ("GPS preview") reads like live data, even when the implementation is only a stylized sketch. Pairing that with unreachable real history reverses the trust hierarchy: fake-looking-live content is prominent, real content is hidden.

Future rule: Do not label decorative route art as GPS/current-location/map preview unless it is backed by real location data. Use a scrollable short-screen fallback for PreRun-style stacks and verify both first-viewport copy and scroll reachability on iPhone 17 plus iPhone SE.

### 2026-06-30 - Garmin Evidence Needs Row-Level Visual Verification
Trigger: Live `1.0.5 (18)` screenshots showed Recovery/Wellness with `Garmin Forerunner 965`, but Report/Run Report still displayed bare `Garmin` because individual activity rows lacked `device_name`.

Lesson: Passing code paths for new Garmin imports do not guarantee submission screenshots are compliant when legacy or cached rows omit attribution fields.

Future rule: For Garmin submission evidence, visually verify each required screenshot against the exact rejected requirement; source support for `device_name` is not enough when legacy activity rows can lack it and need connection-level fallback.

### 2026-06-29 - Closed ASC Release Train Requires Marketing Version Bump
Trigger: Founder archive upload for build 18 failed because App Store Connect rejected `CFBundleShortVersionString = 1.0.4`; the previously approved `1.0.4` train is closed for new build submissions.

Lesson: A build-number bump is not enough once Apple has approved/released that marketing version. New upload attempts must move to the next marketing version train.

Future rule: If App Store Connect says a pre-release train is closed for new submissions, bump `MARKETING_VERSION` to the next train and re-archive; changing only `CURRENT_PROJECT_VERSION` cannot reopen a closed approved marketing version.

### 2026-06-26 - xcodebuild Store Validation Flag Is Not Portable
Trigger: The build-18 Garmin plan asked Codex to rerun `xcodebuild ... -validate-for-store`, but the installed `xcodebuild` rejected `-validate-for-store` as an invalid option.

Lesson: Release plans can preserve shorthand from Xcode Organizer or older/local tooling that is not actually executable in the current CLI.

Future rule: Before recording an App Store validation command as executable, verify the installed `xcodebuild` supports the flags; for this environment, `-validate-for-store` is not a supported CLI option, so use archive/export inspection locally and leave Organizer/ASC validation to founder-gated tooling.

### 2026-06-17 - Filter Xcode Build Logs Around Secrets
Trigger: A Release `xcodebuild` validation emitted expanded build settings, including service configuration values, in raw terminal output.

Lesson: Xcode build logs can expose xcconfig-backed values even when source files are clean.

Future rule: For Xcode validation, prefer quiet/filtered logs because build settings can echo xcconfig-backed service keys; never paste raw build setting output into task memory or final reports.

### 2026-06-16 - Avoid Duplicate DerivedData Arguments In XcodeBuildMCP
Trigger: A simulator compile for the Sign in with Apple demo failed immediately because `-derivedDataPath` was passed through `build_sim.extraArgs` while XcodeBuildMCP already supplied its own DerivedData argument.

Lesson: XcodeBuildMCP may manage DerivedData internally, so adding another `-derivedDataPath` through `extraArgs` can create a false build failure unrelated to app source.

Future rule: With XcodeBuildMCP build tools, set DerivedData through session defaults or omit it; do not pass `-derivedDataPath` in `extraArgs` unless the tool is not already supplying one.

### 2026-06-14 - SIWA Smoke Needs Apple-Auth-Capable Simulator Or Device
Trigger: Final build 14 smoke reached the fresh Sign in with Apple screen, but tapping SIWA on the local simulator returned `ASAuthorizationError 1000`, blocking the delete-account and register-again path.

Lesson: Source/build/archive checks cannot substitute for the Apple review account-cycle smoke when the rejection risk is auth/onboarding behavior.

Future rule: Before promising App Store resubmission readiness for SIWA/delete-account fixes, run the account-cycle smoke on a simulator signed into Apple ID or an Apple-auth-capable physical device. If SIWA returns authorization error 1000, report the live smoke as blocked and do not green-light archive/upload solely from static checks.

### 2026-06-12 - xcconfig URLs Must Escape Double Slashes
Trigger: Build 14 smoke test crashed at `SupabaseClient.init` because the built app had `SUPABASE_URL = https:` instead of the full Supabase host.

Lesson: In `.xcconfig`, `//` starts a comment, so `SUPABASE_URL = https://...` silently truncates to `https:` and the app fatals on launch.

Future rule: Never put raw `https://` values in xcconfig. Use `https:/$()/host/path` or keep full URLs in `Info.plist` literals. After changing xcconfig secrets, verify the built app `Info.plist` contains the full `SUPABASE_URL` before archiving.

### 2026-06-12 - Inspect Supabase Relation Types Before RLS
Trigger: The Garmin RLS migration assumed `garmin_activity_points` was a table, but production has it as a view over `garmin_activities.telemetry_json`, so `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` failed.

Lesson: Live Supabase schemas can drift from migration assumptions. For views, RLS belongs on the underlying tables and the view should run with invoker security when exposed to authenticated clients.

Future rule: Before applying RLS or index migrations, inspect `pg_class.relkind` and existing view definitions. Use `ALTER VIEW ... SET (security_invoker = true)` for exposed owner-scoped views, and index the underlying base tables instead of the view.

### 2026-06-12 - Keep WellnessTrendMapper When Extracting Garmin Helpers
Trigger: Phase 4.2 added `GarminDistanceBucket` but closed the enum before `WellnessTrendMapper`, leaving orphaned static methods and a compile failure.

Lesson: When adding a new type mid-file, verify the following enum/struct still has its opening brace; run `xcodebuild` before marking cleanup done.

Future rule: After editing `GarminMappers.swift`, confirm both `GarminDistanceBucket` and `WellnessTrendMapper` compile; parallel route loads in `GarminImportProcessor` need `@escaping RoutePointLoader`.

### 2026-06-12 - Hybrid auth_user_id Identity For iOS + Web Profiles
Trigger: Code review found hashed challenge `user_id`, unscoped Garmin GPS reads, and UUID profile run-sync failures.

Lesson: Treat `auth_user_id` as canonical for enrollments, RLS, and new writes; keep legacy numeric `profiles.id` only where gateway or bigint FKs still require it.

Future rule: Resolve identity via `RunSmartIdentity` / `TrainingPlanRepository.identity(authUserID:)`; never synthesize enrollment IDs from UUID hashes; scope Garmin route queries by `(auth_user_id, activity_id)`; coordinate Garmin gateway `authUserId` support before claiming UUID-only connect works.

### 2026-06-11 - Re-onboarding Must Replay Aha Moments And Garmin Needs App Callback
Trigger: Smoke test after delete account + Sign in with Apple showed no onboarding aha moments, and Garmin OAuth finished in Safari without updating iOS connection state.

Lesson: `OnboardingAhaMomentsContainer` skipped both moments when `user_aha_moments` still had rows for the unchanged auth uid. Garmin used `callbackURLScheme: nil` with an https redirect, so the auth session never returned to the app.

Future rule: Do not gate onboarding aha moments on prior `hasFired` state; reset onboarding moments during account deletion. Use `runsmart://garmin/callback`, set `callbackURLScheme: "runsmart"`, and poll Supabase for `garmin_connections.status == connected`.

### 2026-06-08 - Sign In With Apple Must Not Be Followed By Name Or Email Collection
Trigger: Apple rejected RunSmart 1.0.1 build 11 under Guideline 4 because the app requested name/email after Sign in with Apple.

Lesson: Requesting `.fullName` and `.email` through AuthenticationServices is fine, but showing a post-auth onboarding name or email field can be treated as requiring information Apple already provides.

Future rule: For Sign in with Apple flows, capture `ASAuthorizationAppleIDCredential.fullName` and `email` when Apple returns them, seed the profile internally, and use an internal display-name fallback instead of asking the user for name or email during onboarding.

### 2026-06-07 - App Review Needs API Names In Visible UI
Trigger: Apple rejected RunSmart 1.0.1 build 9 under Guideline 2.5.1 because HealthKit/CareKit functionality was not clearly identified in the app UI.

Lesson: Permission strings, App Store copy, and friendly Apple Health wording are not enough when the binary includes HealthKit. The app UI itself needs explicit HealthKit functionality disclosure near the connection flow.

Future rule: Before resubmitting any HealthKit build, verify visible UI names HealthKit and states what is read and written; if CareKit is not used, confirm no CareKit imports, entitlements, or claims remain.

### 2026-06-04 - Distribution Keychain Access Blocks Export
Trigger: App Store export for RunSmart 1.0.1 build 9 reached the Apple Distribution identity but `codesign` blocked in Security/keychain signing and no IPA was produced.

Lesson: A valid Apple Distribution identity is not enough for unattended release export if the private key still requires a macOS keychain approval prompt.

Future rule: Before a release-day upload, run a tiny distribution-signing/export check or pre-authorize the Apple Distribution key for Apple tool access, then archive/export.

### 2026-05-20 - Date-Only Plan Matching Must Use User-Local Days
Trigger: Sprint 10 readiness tests exposed that date-only plan formatting in UTC could make a same-day planned workout look like the wrong day for users outside UTC.

Lesson: Scheduled workout `yyyy-MM-dd` values are user-calendar values, not instants to normalize through UTC during matching or query construction.

Future rule: For plan/workout date-only strings, format and compare with the user's local calendar/timezone, and keep tests on the same calendar semantics as the app path.

### 2026-05-20 - Low Stress Is Not Low Recovery
Trigger: Sprint 10 readiness tests showed that the word "Low" in Garmin stress text was being treated as low recovery.

Lesson: Recovery classifiers must interpret metric direction by field, not by scanning all labels for alarming words.

Future rule: Treat low stress as healthy/neutral; only high or elevated stress should contribute to low-recovery decisions.

### 2026-05-12 - Thin OS Install
Trigger: User explicitly asked for a lightweight Agent OS, not a third-party framework or huge prompt file.

Lesson: Agent behavior changes best when workflow, memory, templates, and QA files exist in the repo, while router files stay short.

Future rule: Put detailed guidance under `.agent-os/`; keep root agent files token-efficient.

### 2026-05-12 - Nested Workspace Root
Trigger: Verification initially checked the nested iOS folder while the Agent OS was installed at the outer workspace root.

Lesson: This workspace has an outer folder and an inner GitHub-connected iOS repo, so path assumptions can be wrong.

Future rule: Before writing or verifying repo-level files, confirm whether paths are relative to the outer workspace or the GitHub repo root.

### 2026-05-12 - Conversation Spec Handoff
Trigger: Implementation request referenced an approved iOS feature spec, but the repo only had `docs/specs/README.md`.

Lesson: Conversation-level approval is easy for future agents to miss unless it becomes a repo artifact.

Future rule: For the first implementation step after planning, create or update a tracked spec/story artifact before runtime UI changes.

### 2026-05-12 - Explicit Integration Terms
Trigger: A coverage check failed because the IA mapping mentioned Apple Health but not the platform term HealthKit.

Lesson: Release and integration docs need both user-facing names and platform/API names so QA and future agents can find the right constraints.

Future rule: Include explicit platform terms in planning artifacts for integrations, permissions, capabilities, and TestFlight risk checks.

### 2026-05-12 - Unrelated Test Failure Scope
Trigger: Running the existing test target failed because test doubles use `jobDescription` while `ResumeOptimizationServiceProtocol` now requires `jobDescriptionId`.

Lesson: Validation can surface real but unrelated failures in a dirty worktree.

Future rule: Record exact failing files and symbols, but keep the current story scoped unless the failure blocks the story's own acceptance criteria.

### 2026-05-12 - Scan-First Test Fixtures
Trigger: The test target compiled after protocol label fixes but still failed because optimize tests lacked `jobDescriptionId`.

Lesson: The current optimization flow is scan-first and requires a persisted job description id before optimization.

Future rule: Update both XCTest and Swift Testing fixtures when required flow state changes, especially when a free-text field is replaced by an ID-backed backend record.

### 2026-05-13 - RunSmart Shell Must Not Expose ResumeBuilder Flows
Trigger: User corrected the direction after the shell preserved ResumeBuilder-era score, tailor, design, resume, and application flows.

Lesson: During the RunSmart migration, preserving old functionality in code is not the same as keeping it visible in the RunSmart app experience.

Future rule: Keep RunSmart screens focused on running jobs; hide or remove resume/job/ATS/design/application entry points unless an approved story explicitly includes them.

### 2026-05-14 - Route Matching Fixtures Need Realistic Offsets
Trigger: The first possible-match test used a route offset large enough that the service correctly returned no-match.

Lesson: Matching confidence tests should encode product meaning, not just desired labels; "possible" should be nearby/noisy, while far parallel routes are unrelated.

Future rule: Build route matching fixtures with realistic GPS drift and distance deltas for possible matches, and reserve larger spatial offsets for no-match cases.

### 2026-05-14 - Calendar Boundary Fixtures Need Calendar-Built Dates
Trigger: The first Story 6 month-boundary test used hard-coded epoch values that did not express the intended local calendar months.

Lesson: Epoch literals make calendar-boundary tests hard to audit and easy to get wrong.

Future rule: Use the same `Calendar`, `TimeZone`, and `DateComponents` in tests that assert local month, week, or day behavior.

### 2026-05-15 - Simulator XCTest Launch Stalls Are Not Test Passes
Trigger: Full iPhone 17 XCTest validation stalled after build/signing and ended with `NSMachErrorDomain Code=-308` when interrupted.

Lesson: A successful app build and a completed XCTest run are separate validation signals; a simulator launch failure should be reported as blocked, not folded into a pass.

Future rule: If a simulator XCTest run stalls during launch, stop it, record the exact launch error, and keep the completed build as separate validation instead of claiming a test pass.

### 2026-05-15 - App Repo Task Memory Is Canonical
Trigger: The workspace contained outer wrapper task files plus app-repo task files and loose duplicate `todo` copies, causing agents to read stale state.

Lesson: In a nested workspace, duplicated Agent OS memory becomes misleading faster than code changes.

Future rule: Treat `IOS RunSmart app/tasks/todo.md`, `tasks/lessons.md`, and `tasks/session-log.md` as canonical; keep outer task files as pointers only and remove loose duplicate task copies when found.

### 2026-05-15 - Physical Device QA Needs Unlock And Battery Baseline
Trigger: Device build and install succeeded, but `devicectl` launch failed because the connected iPhone was locked and no starting battery percentage had been recorded.

Lesson: Physical-device readiness has separate evidence layers: build, install, launch, hands-on outdoor recording, background continuation, and battery delta.

Future rule: Before starting physical-device manual QA, confirm the phone is unlocked and record starting battery percentage; do not treat build/install success as outdoor/background/battery validation.

### 2026-05-16 - Await Before Nil-Coalescing
Trigger: The first focused training-context test build failed because `trainingContext ?? await services.trainingContext(...)` placed an async call inside the synchronous autoclosure used by `??`.

Lesson: Swift async fallback work needs an explicit branch before awaiting.

Future rule: Do not put awaited fallback calls inside nil-coalescing expressions; branch explicitly before `await` because `??` uses a synchronous autoclosure.

### 2026-05-16 - Redact Device QA Evidence In Task Memory
Trigger: PR review flagged git-tracked task docs containing a personal device name, UDID, CoreDevice identifier, signing email/team ID, and local absolute path.

Lesson: QA evidence can be useful without storing raw personal or device identifiers in repo history.

Future rule: Redact personal device names, UDIDs, CoreDevice identifiers, emails, team IDs, and local absolute paths before committing task memory or QA evidence; keep full values only in private/local notes.

### 2026-05-17 - XCTest JSON Key Materialization
Trigger: The first focused Coach persistence test build failed because optional dictionary keys were passed into `Set` in a shape Swift could not type-check, then `String.init` mapping introduced overload ambiguity.

Lesson: JSON payload tests should materialize `[String]` keys plainly before comparing sets.

Future rule: When asserting JSON key sets from `Dictionary<String, Any>`, materialize optional keys explicitly before building a `Set`; avoid overload-prone `String.init` mapping.

### 2026-05-17 - Sequential Xcode Validation
Trigger: A build-for-testing/build validation attempt failed with an Xcode build database lock because two xcodebuild processes were running against the same DerivedData.

Lesson: Concurrent Xcode validation can create infrastructure failures unrelated to the code under test.

Future rule: Do not run multiple Xcode builds against the same DerivedData concurrently; build database locks are false failures, so run validation sequentially unless separate DerivedData paths are configured.

### 2026-05-17 - Focused XCTest Simulator Install Failure
Trigger: Focused Sprint 2 XCTest built the app and test bundle, then failed during simulator install/launch with `com.apple.CoreSimulator.SimError Code=405` and `NSMachErrorDomain Code=-308`.

Lesson: A focused XCTest can validate compile/link but still fail before test execution because the simulator install worker is unhealthy.

Future rule: If focused XCTest builds but fails at simulator install/launch with CoreSimulator error 405 and NSMach -308, treat it as simulator infrastructure failure and rely on build-for-testing plus app build until the simulator is reset.

### 2026-05-17 - Shared Service Protocol Additions Need Fallbacks
Trigger: Sprint 4 build-for-testing initially failed because a training-context test double did not implement newly added first-sync review APIs on `DeviceSyncing`.

Lesson: Optional service behavior can break unrelated tests when it is added to a shared protocol without defaults.

Future rule: When adding optional behavior to a shared service protocol, provide default extension fallbacks or update every test double in the same pass before validation.

### 2026-05-18 - RunSmart Backend Calls Must Avoid Legacy ResumeBuilder Base URLs
Trigger: Live Coach needed a new backend endpoint while `BackendConfig.apiBaseURL` still pointed to legacy ResumeBuilder infrastructure.

Lesson: RunSmart-native Supabase operations should use the Supabase project URL/function base directly unless a confirmed RunSmart web API route exists.

Future rule: For RunSmart Supabase Edge Functions, call `SupabaseManager.functionsBaseURL` with the Supabase publishable key and user JWT; do not route app-native Coach features through `BackendConfig.apiBaseURL`.

### 2026-05-18 - Local Env Imports Need Ignore Rules First
Trigger: User asked to copy RunSmart web API keys into the iOS workspace for backend use.

Lesson: Local env files can accidentally appear as untracked files if ignore rules are missing in the wrapper or nested app repo.

Future rule: Before copying local API secrets into the iOS workspace, add env file patterns to both wrapper and app `.gitignore`; never print secret values in logs or task memory.

### 2026-05-18 - Supabase RLS Policies Combine Permissively
Trigger: Live Coach migration added owner-scoped conversation/message policies, but the remote database still had older broad authenticated policies on the same tables.

Lesson: Adding safer RLS policies is not enough if existing permissive policies still allow access; Supabase/Postgres policies are ORed for the same command and role.

Future rule: After adding owner-scoped Supabase RLS policies, inspect and remove older broad authenticated policies on the same tables before calling the schema secure.

### 2026-05-19 - App Store Readiness Requires Archive Inspection
Trigger: App Store readiness inspection found the archive still exposed the project name as the app name, bundled a diagnostic markdown file, and used development signing even though builds succeeded.

Lesson: Passing local builds does not prove submission readiness; release evidence has to come from the archived app bundle and signing entitlements.

Future rule: Before App Store readiness claims, inspect the built archive bundle for display name, encryption declaration, bundled diagnostics, dSYMs, entitlements, and distribution-only signing; source checks alone are not enough.

### 2026-05-19 - Folder-Synchronized Xcode Projects Compile Untracked Sources
Trigger: App Store cleanup found untracked ResumeBuilder-era Swift files inside the folder-synced app root, and Xcode had been compiling them even though they were not tracked in git.

Lesson: In a folder-synchronized Xcode project, file presence under the synced root is enough to affect build and archive behavior.

Future rule: In this Xcode folder-synchronized project, untracked Swift files inside `IOS RunSmart app/` can still compile; before release, inspect and clean untracked source under the synced app root, not only tracked project references.

### 2026-05-18 - Verify PostgREST Reads With Real Auth Tokens
Trigger: Live Coach SQL/RLS checks passed, but deployed PostgREST reads from `conversation_messages` still returned no rows for a signed-in smoke-test user.

Lesson: SQL simulation and direct table reads can diverge in deployed Supabase flows, especially after schema/RLS evolution.

Future rule: For mobile history reload paths, verify with a real user JWT against the deployed REST/RPC surface. If direct table reads are unreliable, expose a narrow owner-filtered RPC and harden grants before wiring iOS to it.

### 2026-05-14 - Route Discovery Controls Need Real Wiring
Trigger: QA found Route Creator elevation/surface controls and generated-route buckets that did not affect loaded suggestions.

Lesson: Premium route UI loses trust quickly when controls look functional but are disconnected from route generation/ranking.

Future rule: For discovery/filter controls, verify each visible control changes service inputs, ranking, or explicit unavailable-state copy before marking the story complete.

### 2026-05-14 - MapKit Failure Should Not Hide Saved Routes
Trigger: First draft of MapKit failure state replaced the entire route list, hiding saved/past routes that were still available.

Lesson: Partial failures (generated routes unavailable) should degrade gracefully; unaffected buckets (Benchmarks, My Routes) must still render.

Future rule: Show failure/retry state only inside the affected section (Generated Nearby), not as a full-screen replacement. Saved and past routes must remain visible when only generated-route fetch fails.

### 2026-05-14 - Garmin Sync Idempotency Needs Explicit providerActivityID Guard
Trigger: Production syncNow processed only the newest Garmin run; Supabase syncNow processed all but had no cross-sync duplicate guard.

Lesson: generateRunReportIfMissing is idempotent for report generation, but processCompletedActivity still calls routeMatch and workout-completion on every run, so repeated calls for the same providerActivityID waste CPU and can produce redundant notifications.

Future rule: Before calling processCompletedActivity in any Garmin sync path, filter out runs whose providerActivityID already exists in the local store.

### 2026-05-15 - Connected-Service Lists Must Use Canonical Activity Rules
Trigger: Garmin recent activity UI could show raw short fragments even though import/consolidation logic treated activities more carefully.

Lesson: A raw provider row is not necessarily a user-visible workout; UI lists, report lists, and persistence need the same validity, hidden-run, dedupe, and fragment rules.

Future rule: Never render connected-service activity rows directly from provider tables. Normalize to canonical `RecordedRun` candidates first, then map back to display rows only for surviving provider IDs.

### 2026-05-26 - Mock Services Must Override generateWeeklySummary For Screenshots
Trigger: Phase 3 design review found WeeklyProgressCard invisible in App Store screenshots because MockRunSmartServices inherited the protocol-default `generateWeeklySummary()` returning `nil`. TodayTabView only renders the card when the value is non-nil.

Lesson: Protocol default implementations that return nil/empty are silent; any new conditional-render feature backed by a service call needs its mock override checked before screenshot capture or preview demos.

Future rule: After adding any `func foo() async -> T?` to a service protocol with a nil default, immediately add a non-nil mock override to MockRunSmartServices. Write a check in PRE-SCREENSHOT checklist: grep for `nil` returns in MockRunSmartServices against cards that render conditionally.

### 2026-05-20 - Return Xcode To Main After Merge
Trigger: After merging a PR, Xcode reopened on a temporary Codex branch while local `main` had diverged, leaving the branch picker noisy and builds showing stale errors.

Lesson: A successful PR validation branch is not the right local state for user handoff after merge; Xcode can also retain stale DerivedData from the previous branch.

Future rule: After merge handoff, align local `main` to `origin/main`, remove temporary local branches/worktrees, clear the app's DerivedData, and reopen Xcode on `main`.

### 2026-05-27 - Verify Throwing Decoder Fallbacks In Xcodebuild
Trigger: A Flex Week response compatibility decoder parsed with `swiftc -parse` but failed the Xcode build because a throwing nil-coalescing fallback was not explicitly handled.

Lesson: Parser-only validation is useful but not enough for Codable compatibility edits that use throwing expressions.

Future rule: After changing custom `Decodable` fallbacks, run an Xcode build before handoff and prefer explicit `if let` decode branches over throwing `??` expressions.

### 2026-06-01 - xcconfig-Based Secret Injection For API Keys
Trigger: PostHog API key was hardcoded in `RunSmartInfo.plist`, visible in git history.

Lesson: iOS API keys that must not appear in git should be injected through a committed wrapper xcconfig that optionally includes a gitignored secrets file. Pointing Xcode directly at the gitignored file breaks clean clones and CI before secrets are generated.

Setup for this project:
1. `RunSmartConfig.xcconfig` (committed) — defines safe defaults and `#include? "RunSmartSecrets.xcconfig"`
2. `RunSmartSecrets.xcconfig` (gitignored) — defines `POSTHOG_API_KEY = phc_...`
3. `RunSmartSecrets.xcconfig.example` (committed) — template with placeholder value
4. `RunSmartInfo.plist` uses `$(POSTHOG_API_KEY)` instead of the raw key
5. App target Debug and Release configs in `project.pbxproj` reference the committed wrapper config
6. On CI: `echo "POSTHOG_API_KEY = $POSTHOG_API_KEY" > RunSmartSecrets.xcconfig` before xcodebuild

Future rule: Never hardcode third-party API keys in plist files. Always use xcconfig injection so keys stay out of git.

### 2026-06-14 - Account Delete Must Not Delete From Views
Trigger: Live account-deletion smoke failed because the deployed `delete_account` Edge Function attempted to delete directly from the production `garmin_activity_points` view.

Lesson: Account deletion code must delete owned base tables or call safe RPCs; direct deletes against views can fail in production even when the table-like name looks deleteable in source.

Future rule: Before adding a relation to account-deletion cleanup, verify whether it is a base table or view in the live schema. If it is a view, delete the underlying owner-scoped base rows instead.

### 2026-06-14 - Native OAuth Must Complete The Server Exchange
Trigger: Garmin connect returned to the iOS app through `ASWebAuthenticationSession`, but the app only observed the callback and then polled Supabase; the gateway never received the returned `code` and `state` to persist tokens.

Lesson: Native OAuth callbacks are not complete until the app hands the authorization result back to the backend that owns the client secret/token exchange.

Future rule: For native OAuth flows routed through a web gateway, validate the full loop: request native redirect, receive custom-scheme callback, POST `code`/`state` to the gateway callback, persist connection/tokens, then poll or refresh UI.

### 2026-07-15 — Frozen activation snapshots must freeze exclusion evidence too

- For a reproducible decision snapshot, bound lifetime QA/device exclusion evidence at `snapshot_end`; later events must not rewrite an earlier cohort.
- Treat missing production-device flags as unknown, not false. A physical-install candidate must carry explicit false values for emulator, TestFlight, and sideload flags.
