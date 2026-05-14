# Lessons Memory

Review this file at the start of future tasks.

## Active Rules
- Keep `AGENTS.md`, `CLAUDE.md`, and `CODEX.md` as routers, not manuals.
- Load only the files needed for the current workflow.
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
- Route discovery controls must connect to service behavior or clearly present as unavailable; do not ship decorative filters that leave results unchanged.

## Lesson Log

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
