# Lessons Memory

Review this file at the start of future tasks.

## Active Rules
- Keep `AGENTS.md`, `CLAUDE.md`, and `CODEX.md` as routers, not manuals.
- Load only the files needed for the current workflow.
- Use app-repo `tasks/todo.md`, `tasks/lessons.md`, and `tasks/session-log.md` as the single source of truth; outer wrapper status files should only point here.
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

## Lesson Log

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
