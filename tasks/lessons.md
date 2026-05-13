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
